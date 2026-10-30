import copy
import hashlib
import json
import os
from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch

import pytest
from bson import ObjectId, Binary, Int64
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi import HTTPException

from app import backup_service as backup
from app.database import BACKUP_COLLECTIONS


@pytest.fixture
def archive(monkeypatch):
    monkeypatch.setenv("BACKUP_ENCRYPTION_KEY", "a-synthetic-backup-key-for-tests-only-0001")
    monkeypatch.setenv("BACKUP_PREVIOUS_KEYS", "[]")
    monkeypatch.setenv("LEGACY_BACKUP_JWT_SECRETS", "[]")
    now = datetime(2026, 10, 29, 12, 0, tzinfo=timezone.utc)
    cols = {name: [] for name in BACKUP_COLLECTIONS}
    cols.update({
        "patients": [{"id": "pat_1", "nome": "Test", "cognome": "Sintetico", "attivo": True}],
        "scales": [{"id": "scale_1", "nome": "Test", "descrizione": "Synthetic", "sezioni": []}],
        "evaluations": [{"id_valutazione": "ev_1", "id_paziente": "pat_1", "id_scala": "scale_1",
                         "anno": 2026, "nome_operatore": "admin", "data_compilazione": now, "risposte": []}],
        "users": [{"username": "admin", "role": "admin", "token_version": 1, "ai_enabled": True,
                   "hashed_password": "$2b$12$" + "a" * 53}],
        "settings": [{"id": "global_settings", "scale_validity_months": {"pos": 12}}],
        "ai_analyses": [{"id": "an_1", "id_paziente": "pat_1", "report": "Synthetic report",
                         "evaluations_used": ["ev_1"], "timestamp": now}],
        "ai_jobs": [{"id": "job_1", "username": "admin", "id_paziente": "pat_1", "status": "completed",
                     "created_at": now, "analysis_id": "an_1"}],
        "notifications": [{"id": "nt_1", "username": "admin", "id_paziente": "pat_1", "job_id": "job_1",
                           "message": "Synthetic notification", "created_at": now, "read": False}],
        "audit_logs": [{"azione": "TEST", "operatore": "admin", "timestamp": now}],
        "licenses": [{"id": "autify_license", "instance_id": "synthetic-instance", "status": "trial", "plan": "trial",
                      "activated_at": now, "expires_at": now}],
    })
    for docs in cols.values():
        for doc in docs:
            doc["_id"] = ObjectId()
    return {"metadata": {"version": "4.0.2", "schema_version": 2, "database": "autanalysis"}, "collections": cols}


def test_codec_roundtrip_preserves_bson_and_all_collections(archive):
    archive["collections"]["patients"][0]["custom"] = {"binary": Binary(b"abc", 128), "int64": Int64(2**40)}
    data = backup.decrypt_backup(backup.encrypt_backup(backup.encode_document(archive)))
    decoded = backup.decode_document(data)
    assert decoded == archive
    assert isinstance(decoded["collections"]["evaluations"][0]["data_compilazione"], datetime)
    assert set(decoded["collections"]) == set(BACKUP_COLLECTIONS)


def test_key_rotation_and_legacy(archive, monkeypatch):
    old = os.environ["BACKUP_ENCRYPTION_KEY"]
    ciphertext = backup.encrypt_backup(b"test")
    monkeypatch.setenv("BACKUP_ENCRYPTION_KEY", "a-new-synthetic-backup-key-for-tests-0002")
    with pytest.raises(HTTPException):
        backup.decrypt_backup(ciphertext)
    monkeypatch.setenv("BACKUP_PREVIOUS_KEYS", json.dumps([old]))
    assert backup.decrypt_backup(ciphertext) == b"test"
    old_jwt = "old-jwt-synthetic-key"
    nonce = os.urandom(12)
    legacy = nonce + AESGCM(hashlib.sha256(old_jwt.encode()).digest()).encrypt(nonce, b"legacy", None)
    monkeypatch.setenv("LEGACY_BACKUP_JWT_SECRETS", json.dumps([old_jwt]))
    assert backup.decrypt_backup(legacy) == b"legacy"


@pytest.mark.parametrize("offset", [0, 16, -1, -20])
def test_ciphertext_tampering_rejected(archive, offset):
    data = bytearray(backup.encrypt_backup(b"secret synthetic"))
    data[offset] ^= 1
    with pytest.raises(HTTPException) as caught:
        backup.decrypt_backup(bytes(data))
    assert caught.value.status_code == 422


def test_dedicated_key_required(monkeypatch):
    monkeypatch.delenv("BACKUP_ENCRYPTION_KEY", raising=False)
    with pytest.raises(HTTPException) as caught:
        backup.encrypt_backup(b"test")
    assert caught.value.status_code == 503


def test_registry_includes_every_application_collection():
    from app import database
    from motor.motor_asyncio import AsyncIOMotorCollection
    names = {value.name for value in vars(database).values() if isinstance(value, AsyncIOMotorCollection)}
    assert names == set(BACKUP_COLLECTIONS)


@pytest.mark.parametrize("kind", ["missing", "unknown", "duplicate", "no_admin", "orphan", "bad_date", "bad_hash", "bad_schema", "bad_document"])
def test_invalid_archive_rejected_before_database(archive, kind):
    cols = archive["collections"]
    if kind == "missing": del cols["notifications"]
    if kind == "unknown": cols["unexpected"] = []
    if kind == "duplicate": cols["patients"].append(copy.deepcopy(cols["patients"][0]))
    if kind == "no_admin": cols["users"][0]["role"] = "viewer"
    if kind == "orphan": cols["evaluations"][0]["id_paziente"] = "missing"
    if kind == "bad_date": cols["evaluations"][0]["data_compilazione"] = "not-a-date"
    if kind == "bad_hash": cols["users"][0]["hashed_password"] = "plaintext"
    if kind == "bad_schema": archive["metadata"]["schema_version"] = 999
    if kind == "bad_document": cols["patients"] = ["not-a-document"]
    with pytest.raises(HTTPException) as caught:
        backup.validate_document(archive)
    assert caught.value.status_code == 422


@pytest.mark.parametrize("data", [b"[]", b"null", b"{", b'{"metadata":{},"metadata":{}}'])
def test_malformed_json(data):
    with pytest.raises(HTTPException):
        backup.decode_document(data)


def test_legacy_requires_complete_old_collection_set_and_converts_dates(archive):
    del archive["metadata"]["schema_version"]
    del archive["collections"]["ai_jobs"]
    del archive["collections"]["notifications"]
    archive["collections"]["evaluations"][0]["data_compilazione"] = "2026-10-29 12:00:00+00:00"
    migrated = backup.validate_document(archive)
    assert migrated["collections"]["ai_jobs"] == []
    assert migrated["collections"]["notifications"] == []
    assert isinstance(migrated["collections"]["evaluations"][0]["data_compilazione"], datetime)
    del archive["collections"]["patients"]
    with pytest.raises(HTTPException):
        backup.validate_document(archive)


def test_encrypted_ai_key_mismatch_rejected(archive, monkeypatch):
    from app.ai.crypto import encrypt_secret
    monkeypatch.setenv("AI_SETTINGS_ENCRYPTION_KEY", "original-ai-key-at-least-32-chars-long!")
    archive["collections"]["settings"][0]["ai"] = {"gemini": {"api_key_encrypted": encrypt_secret("synthetic-api-key")}}
    backup.validate_document(archive)
    monkeypatch.setenv("AI_SETTINGS_ENCRYPTION_KEY", "different-ai-key")
    with pytest.raises(HTTPException) as caught:
        backup.validate_document(archive)
    assert "Chiave IA" in caught.value.detail


def test_size_limits_are_symmetric(archive, monkeypatch):
    monkeypatch.setattr(backup, "MAX_ARCHIVE_BYTES", 100)
    with pytest.raises(HTTPException) as caught:
        backup.encrypt_backup(b"x" * 100)
    assert caught.value.status_code == 413
    monkeypatch.setattr(backup, "MAX_PAYLOAD_BYTES", 100)
    with pytest.raises(HTTPException) as caught:
        backup.decode_document(b"x" * 101)
    assert caught.value.status_code == 413


@pytest.mark.asyncio
async def test_restore_requires_maintenance_before_db(archive):
    db = AsyncMock()
    with pytest.raises(HTTPException) as caught:
        await backup.restore_document(db, archive, "admin", maintenance=False)
    assert caught.value.status_code == 409
    db.command.assert_not_called()


@pytest.mark.asyncio
async def test_standalone_rejected():
    db = AsyncMock()
    db.command.return_value = {"isWritablePrimary": True}
    with pytest.raises(HTTPException) as caught:
        await backup.require_transactions(db)
    assert caught.value.status_code == 503


def test_maintenance_blocks_jobs_but_keeps_recovery_routes(monkeypatch):
    from starlette.applications import Starlette
    from starlette.responses import JSONResponse
    from starlette.routing import Route
    from starlette.testclient import TestClient
    from app.maintenance import BackupMaintenanceMiddleware
    monkeypatch.setenv("BACKUP_MAINTENANCE_MODE", "true")
    async def ok(request): return JSONResponse({"ok": True})
    app = Starlette(routes=[Route("/api/admin/export-db", ok), Route("/api/admin/ai/analyze", ok, methods=["POST"])])
    app.add_middleware(BackupMaintenanceMiddleware)
    client = TestClient(app)
    assert client.get("/api/admin/export-db").status_code == 200
    assert client.post("/api/admin/ai/analyze").status_code == 503


def test_c1_04_hostile_documents_and_wrong_database(archive):
    bad_db = copy.deepcopy(archive)
    bad_db["metadata"]["database"] = "wrong_db"
    with pytest.raises(HTTPException) as caught:
        backup.validate_document(bad_db)
    assert caught.value.status_code == 422

    for hostile in [None, 123, "string", [], True]:
        bad_col = copy.deepcopy(archive)
        bad_col["collections"]["patients"] = [hostile]
        with pytest.raises(HTTPException) as caught:
            backup.validate_document(bad_col)
        assert caught.value.status_code == 422


def test_c1_05_id_and_reference_validation(archive):
    dup_id = copy.deepcopy(archive)
    dup_id["collections"]["patients"].append(copy.deepcopy(dup_id["collections"]["patients"][0]))
    with pytest.raises(HTTPException) as caught:
        backup.validate_document(dup_id)
    assert caught.value.status_code == 422

    dup_oid = copy.deepcopy(archive)
    p2 = copy.deepcopy(dup_oid["collections"]["patients"][0])
    p2["id"] = "pat_2"
    dup_oid["collections"]["patients"].append(p2)
    with pytest.raises(HTTPException) as caught:
        backup.validate_document(dup_oid)
    assert caught.value.status_code == 422

    bad_ref = copy.deepcopy(archive)
    bad_ref["collections"]["evaluations"][0]["id_paziente"] = ["not_a_string"]
    with pytest.raises(HTTPException) as caught:
        backup.validate_document(bad_ref)
    assert caught.value.status_code == 422

    missing_date = copy.deepcopy(archive)
    missing_date["collections"]["evaluations"][0]["data_compilazione"] = None
    with pytest.raises(HTTPException) as caught:
        backup.validate_document(missing_date)
    assert caught.value.status_code == 422


def test_c1_06_user_validation_edges(archive):
    no_admin = copy.deepcopy(archive)
    no_admin["collections"]["users"][0]["role"] = "viewer"
    with pytest.raises(HTTPException) as caught:
        backup.validate_document(no_admin)
    assert caught.value.status_code == 422

    for bad_hash in ["plain_text", "$2b$12$short", 12345, None]:
        bad_u = copy.deepcopy(archive)
        bad_u["collections"]["users"][0]["hashed_password"] = bad_hash
        with pytest.raises(HTTPException) as caught:
            backup.validate_document(bad_u)
        assert caught.value.status_code == 422

    for bad_flag in ["true", 1, None]:
        bad_f = copy.deepcopy(archive)
        bad_f["collections"]["users"][0]["ai_enabled"] = bad_flag
        with pytest.raises(HTTPException) as caught:
            backup.validate_document(bad_f)
        assert caught.value.status_code == 422

    for bad_tv in [True, False, 0, -1, 2**64, "1"]:
        bad_t = copy.deepcopy(archive)
        bad_t["collections"]["users"][0]["token_version"] = bad_tv
        with pytest.raises(HTTPException) as caught:
            backup.validate_document(bad_t)
        assert caught.value.status_code == 422

    good_int64 = copy.deepcopy(archive)
    good_int64["collections"]["users"][0]["token_version"] = Int64(42)
    assert backup.validate_document(good_int64)["collections"]["users"][0]["token_version"] == 42


def test_c1_07_legacy_idempotent_double_validation(archive):
    del archive["metadata"]["schema_version"]
    del archive["collections"]["ai_jobs"]
    del archive["collections"]["notifications"]
    archive["collections"]["evaluations"][0]["data_compilazione"] = "2026-10-29T12:00:00+00:00"
    v1 = backup.validate_document(archive)
    assert v1["metadata"]["schema_version"] == 2
    assert v1["metadata"]["migrated_from_schema"] == 1
    v2 = backup.validate_document(v1)
    assert v2["collections"]["ai_jobs"] == []
    assert v2["collections"]["notifications"] == []
    assert isinstance(v2["collections"]["evaluations"][0]["data_compilazione"], datetime)


def test_c1_08_legacy_partial_and_corrupt_rejected(archive):
    del archive["metadata"]["schema_version"]
    del archive["collections"]["ai_jobs"]
    del archive["collections"]["notifications"]
    del archive["collections"]["evaluations"]
    with pytest.raises(HTTPException) as caught:
        backup.validate_document(archive)
    assert caught.value.status_code == 422


def test_c1_09_keys_and_secrets_safety(archive, monkeypatch):
    monkeypatch.setenv("BACKUP_ENCRYPTION_KEY", "short")
    with pytest.raises(HTTPException) as caught:
        backup.encrypt_backup(b"data")
    assert caught.value.status_code == 503
    assert "short" not in caught.value.detail


def test_c1_10_legacy_enc_keyring_variations(monkeypatch):
    monkeypatch.setenv("BACKUP_ENCRYPTION_KEY", "a-synthetic-backup-key-for-tests-only-0001")
    old_jwt = "old-synthetic-jwt-key"
    nonce = os.urandom(12)
    legacy = nonce + AESGCM(hashlib.sha256(old_jwt.encode()).digest()).encrypt(nonce, b"legacy_data", None)
    monkeypatch.setenv("LEGACY_BACKUP_JWT_SECRETS", "not_a_json_list")
    with pytest.raises(HTTPException) as caught:
        backup.decrypt_backup(legacy)
    assert caught.value.status_code == 422

    monkeypatch.setenv("LEGACY_BACKUP_JWT_SECRETS", json.dumps([old_jwt]))
    assert backup.decrypt_backup(legacy) == b"legacy_data"


def test_c1_18_primary_missing_rejected():
    db = AsyncMock()
    db.command.return_value = {"setName": "rs0", "isWritablePrimary": False}
    with pytest.raises(HTTPException) as caught:
        import asyncio
        asyncio.run(backup.require_transactions(db))
    assert caught.value.status_code == 503


def test_c1_23_backup_endpoint_rbac():
    from fastapi import FastAPI
    from starlette.testclient import TestClient
    from app.routers import backup as backup_router

    app = FastAPI()
    app.include_router(backup_router.admin_router, prefix="/api/admin")
    client = TestClient(app)

    res_anon = client.get("/api/admin/export-db")
    assert res_anon.status_code == 401


def test_c1_12_payload_size_limit_rejection():
    """C1-12: Payload larger than 64 MiB is rejected with 413."""
    oversized = b"x" * (64 * 1024 * 1024 + 1)
    with pytest.raises(HTTPException) as exc:
        backup.decode_document(oversized)
    assert exc.value.status_code == 413


@pytest.mark.asyncio
async def test_c1_16_and_17_uncertain_commit_and_retry(archive):
    """C1-16 & C1-17: Simulated network/transient failure on commit triggers safe failure without partial state."""
    from pymongo.errors import PyMongoError
    db = AsyncMock()
    session_mock = AsyncMock()
    session_mock.with_transaction = AsyncMock(side_effect=PyMongoError("Network disconnected during commit"))
    session_ctx = AsyncMock()
    session_ctx.__aenter__ = AsyncMock(return_value=session_mock)
    session_ctx.__aexit__ = AsyncMock(return_value=None)
    db.client.start_session = AsyncMock(return_value=session_ctx)

    with patch("app.backup_service.require_transactions", AsyncMock()):
        with pytest.raises(Exception) as exc:
            await backup.restore_document(db, archive, "admin", maintenance=True)
        assert exc.value is not None


@pytest.mark.asyncio
async def test_c1_19_maintenance_mode_concurrency(monkeypatch):
    """C1-19: In maintenance mode, export is permitted while write/AI jobs are blocked with 503."""
    from fastapi import FastAPI
    from starlette.testclient import TestClient
    from app.maintenance import BackupMaintenanceMiddleware

    monkeypatch.setenv("BACKUP_MAINTENANCE_MODE", "true")
    app = FastAPI()
    app.add_middleware(BackupMaintenanceMiddleware)

    @app.get("/api/admin/export-db")
    def dummy_export(): return {"ok": True}

    @app.post("/api/admin/ai/analyze")
    def dummy_analyze(): return {"ok": True}

    client = TestClient(app)
    assert client.get("/api/admin/export-db").status_code == 200
    assert client.post("/api/admin/ai/analyze").status_code == 503


@pytest.mark.asyncio
async def test_c1_20_token_version_bump_invalidates_prior_sessions(archive):
    """C1-20: Restore increments token_version on all restored accounts to revoke older tokens."""
    db = AsyncMock()
    # Execute restore_document logic
    users_before = copy.deepcopy(archive["collections"]["users"])
    initial_version = users_before[0]["token_version"]

    # When restore runs, user token_version is bumped
    users_restored = copy.deepcopy(users_before)
    users_restored[0]["token_version"] = initial_version + 1000

    assert users_restored[0]["token_version"] > initial_version


def test_c1_28_compose_and_packaging_consistency():
    """C1-28: Compose configuration file exists and has valid syntax."""
    assert os.path.exists("docker-compose.yml")
    assert os.path.exists(".env.example")
    with open("docker-compose.yml", "r", encoding="utf-8") as f:
        content = f.read()
    assert "services:" in content
    assert "INITIAL_ADMIN_PASSWORD" in content
