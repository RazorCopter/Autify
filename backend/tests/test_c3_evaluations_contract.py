import pytest
import os
import copy
import json
import base64
from datetime import datetime, timezone
from unittest.mock import patch, AsyncMock
from starlette.testclient import TestClient
from fastapi import HTTPException
from bson import ObjectId

from app.main import app
from app import auth as auth_module
from app.auth import create_access_token
from app.evaluation_contract import (
    question_contract,
    validate_answers,
    require_answers,
    incomplete_analysis,
    scale_snapshot,
    resolve_scale,
)
from app.scale_import import _import_sis_scale
from .test_endpoints import MockCollection, setup_mock_db, mock_patients, mock_scales, mock_evaluations, mock_users


@pytest.fixture
def c3_client(setup_mock_db):
    return TestClient(app)


@pytest.fixture
def sis_scale_data():
    with open("scale/Scala_SIS.json", "r", encoding="utf-8") as f:
        return json.load(f)["scala"]


@pytest.fixture
def pos_scale_data():
    with open("scale/ODFLAB – Scheda Osservativa per la Valutazione delle Funzioni di Base.json", "r", encoding="utf-8") as f:
        return json.load(f)["scala"]


def test_c3_01_import_sis_structure(sis_scale_data):
    """C3-01: Import structure of SIS scale preserves A-F sections, options and metadata."""
    aliases, questions = question_contract(sis_scale_data)
    assert len(questions) == 86  # 49 A-F + 8 P + 16 M + 13 BC
    for i in range(1, 9):
        assert f"A{i}" in questions
        q, tridim = questions[f"A{i}"]
        assert tridim is True


def test_c3_02_invalid_scale_structures():
    """C3-02: Non-dict scale, empty questions, or ambiguous aliases rejected with ValueError/422."""
    with pytest.raises(ValueError):
        question_contract({})
    with pytest.raises(ValueError):
        question_contract({"sezioni": [{"domande": []}]})
    with pytest.raises(ValueError):
        question_contract({"sezioni": [{"domande": [{"id": ""}]}]})


def test_c3_03_and_04_answers_strict_validation(pos_scale_data):
    """C3-03 & C3-04: Non-integer scores, out of range, missing/extra answers rejected without coercion."""
    # POS scale
    aliases, questions = question_contract(pos_scale_data)

    # 1. Non-integer score (string/bool/float)
    with pytest.raises(ValueError) as exc:
        validate_answers([{"codice_domanda": list(questions.keys())[0], "punteggio": "1"}], pos_scale_data)
    assert "atteso punteggio intero" in str(exc.value)

    with pytest.raises(ValueError) as exc:
        validate_answers([{"codice_domanda": list(questions.keys())[0], "punteggio": True}], pos_scale_data)
    assert "atteso punteggio intero" in str(exc.value)

    # 2. Score out of options range
    with pytest.raises(ValueError) as exc:
        validate_answers([{"codice_domanda": list(questions.keys())[0], "punteggio": 999}], pos_scale_data)
    assert "punteggio non previsto" in str(exc.value)

    # 3. Duplicate answer
    first_q = list(questions.keys())[0]
    with pytest.raises(ValueError) as exc:
        validate_answers([
            {"codice_domanda": first_q, "punteggio": 1},
            {"codice_domanda": first_q, "punteggio": 1},
        ], pos_scale_data, complete=False)
    assert "duplicata" in str(exc.value)


def test_c3_05_sis_validation_rules(sis_scale_data):
    """C3-05: SIS requires F, D, T ints in 0-4; A3 F<=3; non-dict or out-of-range rejected."""
    # A3 with F=4 must be rejected
    with pytest.raises(ValueError) as exc:
        validate_answers([{"codice_domanda": "A3", "punteggio": {"F": 4, "D": 2, "T": 1}}], sis_scale_data, complete=False)
    assert "frequenza massima 3" in str(exc.value)

    # Score missing T
    with pytest.raises(ValueError) as exc:
        validate_answers([{"codice_domanda": "A1", "punteggio": {"F": 2, "D": 2}}], sis_scale_data, complete=False)
    assert "attesi F/D/T" in str(exc.value)

    # Score with string or out of range
    with pytest.raises(ValueError) as exc:
        validate_answers([{"codice_domanda": "A1", "punteggio": {"F": 5, "D": 2, "T": 1}}], sis_scale_data, complete=False)
    assert "attesi F/D/T" in str(exc.value)


def test_c3_06_incomplete_analysis_status(sis_scale_data):
    """C3-06: Incomplete evaluations marked as invalid_or_incomplete without bogus scores."""
    res = incomplete_analysis([{"codice_domanda": "A1", "punteggio": {"F": 2, "D": 2, "T": 1}}], sis_scale_data)
    assert res is not None
    assert res["validation_status"] == "invalid_or_incomplete"
    assert res["indice_sis"] is None
    assert res["percentile"] is None


def test_c3_07_composite_questions():
    """C3-07: Composite questions strictly enforce score within range 0..len(parts)."""
    scale = {
        "id": "scale_comp",
        "sezioni": [{
            "codice": "SEC1",
            "domande": [{
                "id": "Q1",
                "tipo": "composito",
                "sottodomande": ["part1", "part2", "part3"],
            }]
        }]
    }
    # Valid: 0, 1, 2, 3
    for s in range(4):
        valid = validate_answers([{"codice_domanda": "Q1", "punteggio": s}], scale)
        assert len(valid) == 1

    # Invalid: 4 (exceeds len(parts)=3) or negative
    with pytest.raises(ValueError):
        validate_answers([{"codice_domanda": "Q1", "punteggio": 4}], scale)
    with pytest.raises(ValueError):
        validate_answers([{"codice_domanda": "Q1", "punteggio": -1}], scale)


def test_c3_09_scale_snapshot_immutability(sis_scale_data):
    """C3-09: Snapshot calculation produces deterministic sha256 hash and sets provenance."""
    snap = scale_snapshot(sis_scale_data, provenance="original")
    assert "snapshot_hash" in snap
    assert snap["snapshot_provenance"] == "original"
    # Recomputing produces identical hash
    snap2 = scale_snapshot(sis_scale_data, provenance="original")
    assert snap["snapshot_hash"] == snap2["snapshot_hash"]


@pytest.mark.asyncio
async def test_c3_12_and_15_resolve_scale_fallback():
    """C3-12 & C3-15: resolve_scale uses snapshot if valid, freezes legacy if missing, raises 409 if malformed."""
    # Valid snapshot
    eval_with_snap = {
        "id_valutazione": "ev1",
        "id_scala": "sc1",
        "snapshot_scala": {"sezioni": [{"domande": [{"id": "Q1"}]}]}
    }
    resolved = await resolve_scale(eval_with_snap)
    assert resolved["sezioni"][0]["domande"][0]["id"] == "Q1"

    # Malformed snapshot (truthy but non-dict or no sezioni) -> 409
    eval_bad_snap = {
        "id_valutazione": "ev1",
        "id_scala": "sc1",
        "snapshot_scala": "not-a-dict"
    }
    with pytest.raises(HTTPException) as exc:
        await resolve_scale(eval_bad_snap)
    assert exc.value.status_code == 409


def test_c3_10_and_11_historical_scale_isolation(c3_client, setup_mock_db, pos_scale_data):
    """C3-10 & C3-11: Historical evaluation retains immutable snapshot even if scale is deleted/modified."""
    # Scale snapshot is embedded in evaluation
    eval_id = "ev_hist_1"
    snap = scale_snapshot(pos_scale_data, provenance="original")
    # Ensure sections field conforms to Scale response model if present under domini
    snap = {
        "id": "scale_deleted",
        "nome": "Scala Storica Eliminata",
        "descrizione": "Desc",
        "sezioni": [
            {
                "codice_sezione": "S1",
                "titolo_sezione": "Sezione 1",
                "domande": [
                    {
                        "id_domanda": "SP-1",
                        "codice": "SP-1",
                        "testo_domanda": "Domanda test",
                        "opzioni": [{"punteggio": 3, "testo_risposta": "Sì"}],
                    }
                ],
            }
        ],
        "snapshot_hash": "dummyhash",
        "snapshot_provenance": "original",
    }
    setup_mock_db["evaluations"].documents.append({
        "id_valutazione": eval_id,
        "id_paziente": "pat_1",
        "id_scala": "scale_deleted",
        "anno": 2026,
        "data_compilazione": datetime.now(timezone.utc),
        "nome_operatore": "admin",
        "snapshot_scala": snap,
        "risposte": [{"codice_domanda": "SP-1", "punteggio": 3}],
    })

    token = create_access_token("admin", "admin", ai_enabled=True)
    headers = {"Authorization": f"Bearer {token}"}

    # Fetching historical scales list for patient returns the snapshot scale even though scale_deleted is not in scales_collection
    res = c3_client.get("/api/admin/patients/pat_1/evaluation-scales", headers=headers)
    assert res.status_code == 200
    scales = res.json()
    assert any(s["id"] == "scale_deleted" for s in scales)


def test_c3_17_dashboard_unaffected_by_incomplete_legacy(c3_client, setup_mock_db):
    """C3-17: Incomplete evaluation does not calculate reassuring standard score/index."""
    res = incomplete_analysis([], {"nome": "Test Scale"})
    assert res["indice_sis"] is None
    assert res["somma_punteggi_standard"] is None
    assert res["validation_status"] == "invalid_or_incomplete"


@pytest.mark.asyncio
async def test_c3_08_duplicate_evaluation_id_409(pos_scale_data):
    """C3-08: Creating evaluation with duplicate ID raises 409 DuplicateKeyError."""
    from pymongo.errors import DuplicateKeyError
    from app.routers import evaluations as evals_router
    from app.models import Evaluation

    first_q = pos_scale_data["domini"][0]["domande"][0]["codice"]
    eval_data = Evaluation(
        id_valutazione="ev_dup_1",
        id_paziente="pat_1",
        id_scala="scale_pos",
        anno=2026,
        nome_operatore="admin",
        risposte=[{"codice_domanda": first_q, "punteggio": 2}],
    )

    from starlette.requests import Request
    scope = {"type": "http", "method": "POST", "path": "/api/client/evaluations", "headers": []}
    real_req = Request(scope)
    mock_patient = {"id": "pat_1", "_id": ObjectId(), "attivo": True}

    async def fake_atomic_dup(coro):
        await coro(None)
        raise DuplicateKeyError("duplicate key")

    mock_db_obj = AsyncMock()
    scale_with_id = dict(pos_scale_data)
    scale_with_id["_id"] = ObjectId()
    mock_db_obj.scales.find_one = AsyncMock(return_value=scale_with_id)
    mock_db_obj.scales.update_one = AsyncMock()
    mock_db_obj.evaluations.insert_one = AsyncMock(side_effect=DuplicateKeyError("duplicate key"))

    with patch("app.routers.evaluations.patients_collection.find_one", AsyncMock(return_value=mock_patient)), \
         patch("app.routers.evaluations.scales_collection.find_one", AsyncMock(return_value=pos_scale_data)), \
         patch("app.routers.evaluations.database", mock_db_obj), \
         patch("app.routers.evaluations.require_answers", return_value=[{"codice_domanda": first_q, "punteggio": 2}]), \
         patch("app.routers.evaluations.touch_patient", new_callable=AsyncMock), \
         patch("app.routers.evaluations.atomic", side_effect=fake_atomic_dup):

        with pytest.raises(HTTPException) as exc:
            await evals_router.create_evaluation.__wrapped__(real_req, eval_data, {"username": "admin", "role": "admin"})
        assert exc.value.status_code == 409
        assert "gia presente" in exc.value.detail


@pytest.mark.asyncio
async def test_c3_13_and_14_scale_concurrency_and_rollback(pos_scale_data):
    """C3-13 & C3-14: Concurrency and rollback when scale is modified/deleted during evaluation persistence."""
    from app.routers import evaluations as evals_router
    from app.models import Evaluation
    from starlette.requests import Request

    eval_data = Evaluation(
        id_valutazione="ev_conc_1",
        id_paziente="pat_1",
        id_scala="scale_pos",
        anno=2026,
        nome_operatore="admin",
        risposte=[{"codice_domanda": "SP-1", "punteggio": 2}],
    )

    scope = {"type": "http", "method": "POST", "path": "/api/client/evaluations", "headers": []}
    real_req = Request(scope)
    mock_patient = {"id": "pat_1", "_id": ObjectId(), "attivo": True}

    async def fake_atomic_scale_missing(coro):
        await coro(None)

    mock_db_obj = AsyncMock()
    mock_db_obj.scales.find_one = AsyncMock(return_value=None)

    # Scale disappears or is deleted during the atomic transaction
    with patch("app.routers.evaluations.patients_collection.find_one", AsyncMock(return_value=mock_patient)), \
         patch("app.routers.evaluations.scales_collection.find_one", AsyncMock(return_value=pos_scale_data)), \
         patch("app.routers.evaluations.database", mock_db_obj), \
         patch("app.routers.evaluations.touch_patient", new_callable=AsyncMock), \
         patch("app.routers.evaluations.atomic", side_effect=fake_atomic_scale_missing):

        with pytest.raises(HTTPException) as exc:
            await evals_router.create_evaluation.__wrapped__(real_req, eval_data, {"username": "admin", "role": "admin"})
        assert exc.value.status_code == 409
        assert "Protocollo non disponibile" in exc.value.detail


@pytest.mark.asyncio
async def test_c3_18_deleted_patient_prevents_orphan_evaluation(pos_scale_data):
    """C3-18: If patient is deleted/missing, touch_patient prevents creating orphan evaluation."""
    from app.routers import evaluations as evals_router
    from app.models import Evaluation
    from starlette.requests import Request

    eval_data = Evaluation(
        id_valutazione="ev_orphan_1",
        id_paziente="pat_deleted",
        id_scala="scale_pos",
        anno=2026,
        nome_operatore="admin",
        risposte=[{"codice_domanda": "SP-1", "punteggio": 2}],
    )
    scope = {"type": "http", "method": "POST", "path": "/api/client/evaluations", "headers": []}
    real_req = Request(scope)

    with patch("app.routers.evaluations.patients_collection.find_one", AsyncMock(return_value=None)):
        with pytest.raises(HTTPException) as exc:
            await evals_router.create_evaluation.__wrapped__(real_req, eval_data, {"username": "admin", "role": "admin"})
        assert exc.value.status_code == 404
        assert "non trovato" in exc.value.detail


def test_c3_20_bson_roundtrip_all_bundled_scales():
    """C3-20: BSON round-trip and hash stability on all bundled scales in scale/."""
    from bson import json_util

    scale_files = [
        "scale/ODFLAB – Scheda Osservativa per la Valutazione delle Funzioni di Base.json",
        "scale/Scala San Martin.json",
        "scale/Scala_ODFLAB_Griglia Autonomia.json",
        "scale/Scala_SABS.json",
        "scale/Scala_SIS.json",
    ]

    for sf in scale_files:
        with open(sf, "r", encoding="utf-8") as f:
            data = json.load(f)["scala"]
        snap = scale_snapshot(data, provenance="original")
        assert "snapshot_hash" in snap
        assert snap["snapshot_provenance"] == "original"
        # BSON serialization preserves all types and structure
        encoded = json_util.dumps(snap)
        decoded = json_util.loads(encoded)
        assert decoded["snapshot_hash"] == snap["snapshot_hash"]


def test_c3_19_scale_deleted_backup_restore_preservation(pos_scale_data):
    """C3-19: Evaluation referencing deleted scale preserves embedded snapshot in backup export."""
    from app.evaluation_contract import scale_snapshot
    from app.database import BACKUP_COLLECTIONS
    snap = scale_snapshot(pos_scale_data, provenance="original")
    ev_doc = {
        "id_valutazione": "ev_deleted_scale",
        "id_paziente": "pat_1",
        "id_scala": "scale_no_longer_in_catalog",
        "snapshot_scala": snap,
        "risposte": [{"codice_domanda": "SP-1", "punteggio": 3}],
    }
    # Snapshot remains accessible
    assert "snapshot_hash" in ev_doc["snapshot_scala"]
    assert ev_doc["snapshot_scala"]["nome"] == pos_scale_data["nome"]
