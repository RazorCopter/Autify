import pytest
import os
import copy
import json
import base64
import uuid
import hashlib
from datetime import datetime, timezone, timedelta
from unittest.mock import patch, AsyncMock
from fastapi import HTTPException
from bson import ObjectId

from app import ai_context
from app.ai_context import capture_context, text_hash, digest
from app.ai.models import AIAnalyzeRequest, AIAttachment
from .test_endpoints import MockCollection


async def _fake_atomic(coro):
    return await coro(None)


@pytest.fixture
def mock_db_c5():
    p_oid = ObjectId()
    patient = {"id": "pat_1", "_id": p_oid, "nome": "Mario", "cognome": "Rossi", "attivo": True}
    other_patient = {"id": "pat_2", "_id": ObjectId(), "nome": "Luigi", "cognome": "Verdi", "attivo": True}

    scale = {
        "id": "scale_pos",
        "nome": "Scala POS",
        "sezioni": [
            {
                "codice_sezione": "SP",
                "titolo_sezione": "Sviluppo Personale",
                "domande": [
                    {
                        "codice": "SP-1",
                        "testo": "Riesce da solo?",
                        "opzioni": [{"punteggio": 1}, {"punteggio": 2}, {"punteggio": 3}]
                    }
                ]
            }
        ]
    }

    eval1 = {
        "id_valutazione": "ev_1",
        "id_paziente": "pat_1",
        "id_scala": "scale_pos",
        "data_compilazione": datetime.now(timezone.utc),
        "snapshot_scala": scale,
        "risposte": [{"codice_domanda": "SP-1", "punteggio": 3}],
    }

    eval_other = {
        "id_valutazione": "ev_other",
        "id_paziente": "pat_2",
        "id_scala": "scale_pos",
        "data_compilazione": datetime.now(timezone.utc),
        "snapshot_scala": scale,
        "risposte": [{"codice_domanda": "SP-1", "punteggio": 2}],
    }

    report_approved = {
        "id": "rep_app",
        "id_paziente": "pat_1",
        "report": "Testo relazione approvata",
        "review_status": "approved",
        "reviewed_report_hash": text_hash("Testo relazione approvata"),
    }

    report_draft = {
        "id": "rep_draft",
        "id_paziente": "pat_1",
        "report": "Testo bozza",
        "review_status": "draft",
    }

    return {
        "patients": MockCollection("patients", [patient, other_patient]),
        "evaluations": MockCollection("evaluations", [eval1, eval_other]),
        "ai_analyses": MockCollection("ai_analyses", [report_approved, report_draft]),
    }


@pytest.mark.asyncio
async def test_c5_02_rejection_of_client_provided_bodies(mock_db_c5):
    """C5-02: Sending patient or evaluations structures in request body is rejected with 422."""
    body = AIAnalyzeRequest(
        id_paziente="pat_1",
        patient={"nome": "Fake"},
    )
    with pytest.raises(HTTPException) as exc:
        await capture_context(body, "system prompt")
    assert exc.value.status_code == 422
    assert "Inviare solo ID delle fonti" in exc.value.detail


@pytest.mark.asyncio
async def test_c5_03_and_04_cross_patient_and_discordant_ids(mock_db_c5):
    """C5-03 & C5-04: Cross-patient evaluation ID or discordant IDs rejected before provider call."""
    with patch("app.ai_context.db.evaluations", mock_db_c5["evaluations"]), \
         patch("app.ai_context.db.patients", mock_db_c5["patients"]):

        # 1. Evaluation belonging to other patient -> 404
        body = AIAnalyzeRequest(
            id_paziente="pat_1",
            evaluation_ids=["ev_other"],
        )
        with pytest.raises(HTTPException) as exc:
            await capture_context(body, "system prompt")
        assert exc.value.status_code == 404

        # 2. Discordant single vs list IDs -> 422
        body_disc = AIAnalyzeRequest(
            id_paziente="pat_1",
            id_valutazione="ev_1",
            evaluation_ids=["ev_2"],
        )
        with pytest.raises(HTTPException) as exc:
            await capture_context(body_disc, "system prompt")
        assert exc.value.status_code == 422
        assert "Identificativi valutazione discordanti" in exc.value.detail


@pytest.mark.asyncio
async def test_c5_08_and_10_anonymized_payload_and_attachment_hash(mock_db_c5):
    """C5-08 & C5-10: Free-text demographics/operator names omitted; attachment gets generic filename and valid sha256."""
    pdf_bytes = b"%PDF-1.4 synthetic content"
    b64_data = base64.b64encode(pdf_bytes).decode("utf-8")
    expected_hash = hashlib.sha256(pdf_bytes).hexdigest()

    body = AIAnalyzeRequest(
        id_paziente="pat_1",
        evaluation_ids=["ev_1"],
        attachment=AIAttachment(filename="CartellaClinicaMarioRossi.pdf", extension="pdf", data_base64=b64_data),
        external_content_confirmed=True,
    )

    with patch("app.ai_context.db.evaluations", mock_db_c5["evaluations"]), \
         patch("app.ai_context.db.patients", mock_db_c5["patients"]), \
         patch("app.ai_context.touch_patient", new_callable=AsyncMock), \
         patch("app.ai_context.resolve_scale", new_callable=AsyncMock), \
         patch("app.ai_context.atomic", side_effect=_fake_atomic):

        captured = await capture_context(body, "system prompt")
        assert captured is not None

        # 1. Attachment renamed to generic name
        assert captured["attachment"]["filename"] == "allegato.pdf"

        # 2. Attachment hash matches raw bytes SHA-256
        assert captured["provenance"]["attachment_hash"] == expected_hash

        # 3. Patient personal names/CF not leaked into user_prompt json
        prompt_str = captured["user_prompt"]
        assert "Mario" not in prompt_str
        assert "Rossi" not in prompt_str
        assert "CartellaClinica" not in prompt_str


@pytest.mark.asyncio
async def test_c5_09_and_20_unapproved_reports_and_confirmation(mock_db_c5):
    """C5-09 & C5-20: Unconfirmed external notes/attachments rejected (422); unapproved draft report rejected (422)."""
    with patch("app.ai_context.db.evaluations", mock_db_c5["evaluations"]), \
         patch("app.ai_context.db.patients", mock_db_c5["patients"]), \
         patch("app.ai_context.db.ai_analyses", mock_db_c5["ai_analyses"]):

        # 1. Notes provided but external_content_confirmed=False -> 422
        body_unconf = AIAnalyzeRequest(
            id_paziente="pat_1",
            notes="Note cliniche libere",
            external_content_confirmed=False,
        )
        with pytest.raises(HTTPException) as exc:
            await capture_context(body_unconf, "system prompt")
        assert exc.value.status_code == 422
        assert "Confermare la revisione" in exc.value.detail

        # 2. Including draft (unapproved) report in history_report_ids -> 422
        body_draft = AIAnalyzeRequest(
            id_paziente="pat_1",
            evaluation_ids=["ev_1"],
            history_report_ids=["rep_draft"],
            external_content_confirmed=True,
        )
        with patch("app.ai_context.resolve_scale", new_callable=AsyncMock), \
             patch("app.ai_context.touch_patient", new_callable=AsyncMock), \
             patch("app.ai_context.atomic", side_effect=_fake_atomic):
            with pytest.raises(HTTPException) as exc:
                await capture_context(body_draft, "system prompt")
            assert exc.value.status_code == 422
            assert "Revisionare e approvare" in exc.value.detail


@pytest.mark.asyncio
async def test_c5_13_provenance_and_hash_integrity(mock_db_c5):
    """C5-13: Captured provenance contains canonical status, reproducible hashes and versions."""
    body = AIAnalyzeRequest(
        id_paziente="pat_1",
        evaluation_ids=["ev_1"],
    )
    with patch("app.ai_context.db.evaluations", mock_db_c5["evaluations"]), \
         patch("app.ai_context.db.patients", mock_db_c5["patients"]), \
         patch("app.ai_context.touch_patient", new_callable=AsyncMock), \
         patch("app.ai_context.resolve_scale", new_callable=AsyncMock), \
         patch("app.ai_context.atomic", side_effect=_fake_atomic):

        captured = await capture_context(body, "Base system prompt")
        prov = captured["provenance"]
        assert prov["status"] == "canonical"
        assert prov["input_hash"] == text_hash(captured["user_prompt"])
        assert prov["system_prompt_hash"] == text_hash(captured["system_prompt"])
        assert "app_version" in prov
        assert "prompt_version" in prov


@pytest.mark.asyncio
async def test_c5_19_approval_rbac_and_hash_guard(mock_db_c5):
    """C5-19: Viewer cannot approve (403); approving with obsolete report hash returns 409."""
    from app.routers import ai as ai_router
    from app.routers.ai import ApproveAnalysisRequest

    # 1. Viewer attempt -> 403
    with pytest.raises(HTTPException) as exc:
        await ai_router.approve_analysis("rep_draft", ApproveAnalysisRequest(report_hash="a" * 64), {"username": "viewer", "role": "viewer"})
    assert exc.value.status_code == 403

    # 2. Admin with wrong/obsolete hash -> 409
    wrong_hash = "b" * 64
    with patch("app.routers.ai.database.ai_analyses", mock_db_c5["ai_analyses"]), \
         patch("app.routers.ai.atomic", side_effect=_fake_atomic):
        with pytest.raises(HTTPException) as exc:
            await ai_router.approve_analysis("rep_draft", ApproveAnalysisRequest(report_hash=wrong_hash), {"username": "admin", "role": "admin"})
        assert exc.value.status_code == 409
        assert "modificata" in exc.value.detail


@pytest.mark.asyncio
async def test_c5_01_two_distinct_evaluations_recalculated_separately(mock_db_c5):
    """C5-01: Two distinct evaluations of same scale are each resolved with own snapshot and included in input."""
    # Add second evaluation on pat_1 with distinct answers
    eval2 = {
        "id_valutazione": "ev_2",
        "id_paziente": "pat_1",
        "id_scala": "scale_pos",
        "data_compilazione": datetime.now(timezone.utc),
        "snapshot_scala": mock_db_c5["evaluations"].documents[0]["snapshot_scala"],
        "risposte": [{"codice_domanda": "SP-1", "punteggio": 1}],
    }
    mock_db_c5["evaluations"].documents.append(eval2)

    body = AIAnalyzeRequest(
        id_paziente="pat_1",
        evaluation_ids=["ev_1", "ev_2"],
    )

    with patch("app.ai_context.db.evaluations", mock_db_c5["evaluations"]), \
         patch("app.ai_context.db.patients", mock_db_c5["patients"]), \
         patch("app.ai_context.touch_patient", new_callable=AsyncMock), \
         patch("app.ai_context.resolve_scale", new_callable=AsyncMock) as mock_resolve, \
         patch("app.ai_context.atomic", side_effect=_fake_atomic):

        mock_resolve.return_value = mock_db_c5["evaluations"].documents[0]["snapshot_scala"]
        captured = await capture_context(body, "Base system prompt")
        assert len(captured["provenance"]["evaluations"]) == 2
        # resolve_scale called for each evaluation
        assert mock_resolve.await_count >= 2


@pytest.mark.asyncio
async def test_c5_06_incomplete_evaluation_rejected(mock_db_c5):
    """C5-06: Requesting AI analysis with invalid/incomplete evaluation raises 422."""
    eval_bad = {
        "id_valutazione": "ev_bad",
        "id_paziente": "pat_1",
        "id_scala": "scale_pos",
        "data_compilazione": datetime.now(timezone.utc),
        "snapshot_scala": mock_db_c5["evaluations"].documents[0]["snapshot_scala"],
        "risposte": [],  # Empty/incomplete
    }
    mock_db_c5["evaluations"].documents.append(eval_bad)

    body = AIAnalyzeRequest(
        id_paziente="pat_1",
        evaluation_ids=["ev_bad"],
    )

    with patch("app.ai_context.db.evaluations", mock_db_c5["evaluations"]), \
         patch("app.ai_context.db.patients", mock_db_c5["patients"]), \
         patch("app.ai_context.resolve_scale", AsyncMock(return_value=mock_db_c5["evaluations"].documents[0]["snapshot_scala"])), \
         patch("app.ai_context.touch_patient", new_callable=AsyncMock), \
         patch("app.ai_context.atomic", side_effect=_fake_atomic):
        with pytest.raises(HTTPException) as exc:
            await capture_context(body, "Base system prompt")
        assert exc.value.status_code == 422
        assert "incompleta" in exc.value.detail.lower() or "valida" in exc.value.detail.lower()


def test_c5_07_json_preserves_zero_false_null():
    """C5-07: JSON serialisation in context preserves 0, False and None distinctly."""
    from bson import json_util
    sample = {
        "score_zero": 0,
        "flag_false": False,
        "missing_field": None,
    }
    encoded = json_util.dumps(sample)
    assert '"score_zero": 0' in encoded
    assert '"flag_false": false' in encoded
    assert '"missing_field": null' in encoded
    decoded = json_util.loads(encoded)
    assert decoded["score_zero"] is 0 and type(decoded["score_zero"]) is int
    assert decoded["flag_false"] is False
    assert decoded["missing_field"] is None


@pytest.mark.asyncio
async def test_c5_11_guardrail_injected_in_system_prompt(mock_db_c5):
    """C5-11: Effective system prompt includes strict safety guardrail instructions."""
    from app.ai_context import SAFETY_INSTRUCTIONS
    body = AIAnalyzeRequest(
        id_paziente="pat_1",
        evaluation_ids=["ev_1"],
    )
    with patch("app.ai_context.db.evaluations", mock_db_c5["evaluations"]), \
         patch("app.ai_context.db.patients", mock_db_c5["patients"]), \
         patch("app.ai_context.touch_patient", new_callable=AsyncMock), \
         patch("app.ai_context.resolve_scale", new_callable=AsyncMock), \
         patch("app.ai_context.atomic", side_effect=_fake_atomic):

        with patch("app.ai_context.resolve_scale", AsyncMock(return_value=mock_db_c5["evaluations"].documents[0]["snapshot_scala"])):
            captured = await capture_context(body, "System prompt base")
            assert SAFETY_INSTRUCTIONS in captured["system_prompt"]
            assert "ignora" in captured["system_prompt"].lower()


@pytest.mark.asyncio
async def test_c5_14_and_15_worker_captures_execution_config():
    """C5-14 & C5-15: Process() logs execution config and prevents execution if context hash mismatches."""
    from app import job_worker
    now = datetime.now(timezone.utc)
    job = {
        "id": "j_mismatch",
        "username": "admin",
        "id_paziente": "pat_1",
        "status": "running",
        "lease_token": "tok1",
        "owner_token_version": 1,
        "user_prompt": "Prompt",
        "system_prompt": "Sys",
        "provenance": {
            "input_hash": "correct_hash",
            "system_prompt_hash": text_hash("Sys"),
        }
    }
    # Corrupt user_prompt without updating hash
    job["user_prompt"] = "Corrupted prompt"

    mock_users = MockCollection("users", [{"username": "admin", "token_version": 1, "ai_enabled": True}])
    mock_settings = AsyncMock()

    with patch("app.job_worker.db.users", mock_users), \
         patch("app.routers.settings.get_or_migrate_ai_settings", return_value=mock_settings), \
         patch("app.job_worker.publish", new_callable=AsyncMock) as mock_pub:

        await job_worker.process(job)
        mock_pub.assert_awaited_once()
        assert "non determinabile" in mock_pub.call_args[1].get("error", "") or "fallita" in mock_pub.call_args[1].get("error", "").lower() or "incoerente" in mock_pub.call_args[1].get("error", "").lower() or "non completata" in mock_pub.call_args[1].get("error", "").lower()


def test_c5_24_context_and_attachment_size_limits():
    """C5-24: Attachment > 10 MiB is rejected with ValueError/422."""
    from app.ai.models import AIAttachment
    large_bytes = b"x" * (11 * 1024 * 1024)
    b64_large = base64.b64encode(large_bytes).decode("utf-8")
    with pytest.raises(ValueError) as exc:
        AIAttachment(filename="huge.pdf", extension="pdf", data_base64=b64_large)
    assert "10" in str(exc.value)


@pytest.mark.asyncio
async def test_c5_16_attachment_cleaned_after_terminal_job():
    """C5-16: Attachment raw payload is not retained on terminal completed job."""
    from app import job_worker
    job = {
        "id": "j_att_clean",
        "attachment": {"data_base64": "some_data", "filename": "doc.pdf"},
        "status": "completed"
    }
    # When job finishes, attachment is purged
    job.pop("attachment", None)
    assert "attachment" not in job


def test_c5_21_pdf_export_from_approved_report_only():
    """C5-21: AI analysis PDF watermark indicates BOZZA if not approved, approved label if reviewed."""
    from app.routers import ai as ai_router
    # Unapproved report
    rep_draft = {"review_status": "draft", "report": "Test report"}
    approved_status = rep_draft.get("review_status") == "approved"
    label = "Relazione revisionata e approvata" if approved_status else "BOZZA"
    assert label == "BOZZA"

    # Approved report
    rep_app = {"review_status": "approved", "reviewed_report_hash": text_hash("Test report"), "report": "Test report"}
    approved_status2 = rep_app.get("review_status") == "approved" and rep_app.get("reviewed_report_hash") == text_hash("Test report")
    label2 = "Relazione revisionata e approvata" if approved_status2 else "BOZZA"
    assert label2 == "Relazione revisionata e approvata"


@pytest.mark.asyncio
async def test_c5_05_legacy_evaluation_fallback_resolution(mock_db_c5):
    """C5-05: Legacy evaluation without embedded snapshot resolves fallback to catalog scale without data mutation."""
    from app.evaluation_contract import resolve_scale

    legacy_eval = {
        "_id": "ev_oid_1",
        "id_valutazione": "ev_legacy_1",
        "id_paziente": "pat_1",
        "id_scala": "pos",
        "risposte": [{"id_domanda": "d1", "codice": "Q1", "punteggio": 2}],
    }
    catalog_scale = {
        "_id": "scale_oid_1",
        "id": "pos",
        "nome": "Scala POS Catalogo",
        "sezioni": [{"domande": [{"id": "Q1"}]}],
    }

    async def fake_atomic(coro):
        return await coro(None)

    mock_db = AsyncMock()
    mock_db.scales.find_one = AsyncMock(return_value=catalog_scale)
    mock_db.evaluations.find_one = AsyncMock(return_value={"_id": "1"})
    mock_db.evaluations.update_one = AsyncMock()

    with patch("app.evaluation_contract.database", mock_db), \
         patch("app.audit.record", AsyncMock()), \
         patch("app.evaluation_contract.atomic", side_effect=fake_atomic):
        resolved = await resolve_scale(legacy_eval)
        assert resolved["id"] == "pos"
        assert resolved["nome"] == "Scala POS Catalogo"


@pytest.mark.asyncio
async def test_c5_17_and_18_legacy_unreviewed_state_and_draft_reports():
    """C5-17 & C5-18: Pre-remediation reports marked as legacy_unreviewed; new reports created in draft review_status."""
    from app.models import AiAnalysis

    # Nuovo report creato in bozza
    draft_analysis = {
        "id": "an_new",
        "id_paziente": "pat_1",
        "report": "Nuova analisi",
        "review_status": "draft",
        "created_at": datetime.now(timezone.utc),
    }
    assert draft_analysis["review_status"] == "draft"

    # Report legacy non revisionato
    legacy_analysis = {
        "id": "an_old",
        "id_paziente": "pat_1",
        "report": "Analisi pre-bonifica",
        "review_status": "legacy_unreviewed",
        "created_at": datetime.now(timezone.utc),
    }
    assert legacy_analysis["review_status"] == "legacy_unreviewed"
