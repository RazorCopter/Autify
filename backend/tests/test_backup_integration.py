"""Run only against an explicitly supplied, disposable local replica set.

C1_TEST_MONGODB_URL=mongodb://127.0.0.1:27091/?directConnection=true
Each test uses its own autify_c1_test_<uuid> database; never autanalysis.
"""
import copy
import asyncio
import os
import uuid
from unittest.mock import AsyncMock

import pytest
import pytest_asyncio
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorCollection
from pymongo.errors import OperationFailure

from app import backup_service as backup
from app.database import BACKUP_COLLECTIONS
from .test_backup_service import archive

pytestmark = pytest.mark.skipif(not os.getenv("C1_TEST_MONGODB_URL"), reason="Disposable replica set not configured")


@pytest_asyncio.fixture
async def db():
    uri = os.environ["C1_TEST_MONGODB_URL"]
    assert uri.startswith("mongodb://127.0.0.1:"), "Integration tests require a local disposable server"
    client = AsyncIOMotorClient(uri, serverSelectionTimeoutMS=5000)
    name = "autify_c1_test_" + uuid.uuid4().hex
    database = client[name]
    try:
        yield database
    finally:
        assert database.name.startswith("autify_c1_test_")
        await client.drop_database(database.name)
        client.close()


async def seed(db, archive):
    for name, docs in archive["collections"].items():
        if docs:
            await db[name].insert_many(copy.deepcopy(docs))


async def dump(db):
    return {name: await db[name].find({}).sort("_id", 1).to_list(None) for name in BACKUP_COLLECTIONS}


@pytest.mark.asyncio
async def test_real_roundtrip_empty_collections_and_session_job_fencing(db, archive):
    await seed(db, archive)
    data = await backup.export_archive(db)
    decoded = backup.decode_document(backup.decrypt_backup(data))
    assert set(decoded["collections"]) == set(BACKUP_COLLECTIONS)
    decoded["collections"]["notifications"] = []
    decoded["collections"]["ai_jobs"][0]["status"] = "running"
    before_id = decoded["collections"]["patients"][0]["_id"]
    result = await backup.restore_document(db, decoded, "admin", maintenance=True)
    assert result["reauthenticate"] is True
    assert await db.notifications.count_documents({}) == 0
    assert (await db.patients.find_one({}))["_id"] == before_id
    assert (await db.users.find_one({}))["token_version"] != 1
    assert (await db.ai_jobs.find_one({}))["status"] == "failed"
    assert await db.audit_logs.count_documents({"target_id": result["restore_id"]}) == 1
    # Export the restored state again: generated token epoch must remain BSON-valid.
    await backup.export_archive(db)


@pytest.mark.asyncio
@pytest.mark.parametrize("failure_collection", BACKUP_COLLECTIONS)
async def test_real_transaction_rolls_back_failure_in_every_collection(db, archive, monkeypatch, failure_collection):
    await seed(db, archive)
    before = await dump(db)
    changed = copy.deepcopy(archive)
    changed["collections"]["patients"][0]["nome"] = "Changed"
    original = AsyncIOMotorCollection.insert_many
    async def fail(self, docs, *args, **kwargs):
        if self.database.name == db.name and self.name == failure_collection and kwargs.get("session"):
            raise OperationFailure("synthetic injected failure", code=2)
        return await original(self, docs, *args, **kwargs)
    monkeypatch.setattr(AsyncIOMotorCollection, "insert_many", fail)
    with pytest.raises(Exception) as caught:
        await backup.restore_document(db, changed, "admin", maintenance=True)
    assert caught.value.status_code == 503
    assert await dump(db) == before


@pytest.mark.asyncio
async def test_real_database_unique_constraint_failure_rolls_back(db, archive):
    await seed(db, archive)
    await db.patients.create_index("nome", unique=True)
    before = await dump(db)
    second = copy.deepcopy(archive["collections"]["patients"][0])
    second.pop("_id")
    second["id"] = "pat_2"
    archive["collections"]["patients"].append(second)
    with pytest.raises(Exception) as caught:
        await backup.restore_document(db, archive, "admin", maintenance=True)
    assert caught.value.status_code == 503
    assert await dump(db) == before


@pytest.mark.asyncio
async def test_restore_into_empty_database(db, archive):
    await backup.restore_document(db, archive, "admin", maintenance=True)
    for name in BACKUP_COLLECTIONS:
        assert await db[name].count_documents({}) >= len(archive["collections"][name])


@pytest.mark.asyncio
async def test_snapshot_export_does_not_mix_concurrent_versions(db, archive, monkeypatch):
    await seed(db, archive)
    original = AsyncIOMotorCollection.find
    def find(self, *args, **kwargs):
        cursor = original(self, *args, **kwargs)
        if self.database.name == db.name and self.name == "patients" and kwargs.get("session"):
            async def concurrent_update():
                async for document in cursor:
                    yield document
                await db.users.update_one({"username": "admin"}, {"$set": {"ai_enabled": False}})
            return concurrent_update()
        return cursor
    monkeypatch.setattr(AsyncIOMotorCollection, "find", find)
    decoded = backup.decode_document(backup.decrypt_backup(await backup.export_archive(db)))
    assert decoded["collections"]["users"][0]["ai_enabled"] is True
    assert (await db.users.find_one({}))["ai_enabled"] is False


@pytest.mark.asyncio
async def test_foreign_commercial_license_rejected_without_writes(db, archive):
    await seed(db, archive)
    await db.licenses.update_one({}, {"$set": {"plan": "lifetime", "instance_id": "other", "license_token": "synthetic"}})
    before = await dump(db)
    with pytest.raises(Exception) as caught:
        await backup.restore_document(db, archive, "admin", maintenance=True)
    assert caught.value.status_code == 409
    assert await dump(db) == before


@pytest.mark.asyncio
async def test_cancelled_restore_aborts_real_transaction(db, archive, monkeypatch):
    await seed(db, archive)
    before = await dump(db)
    original = AsyncIOMotorCollection.insert_many
    async def cancel(self, docs, *args, **kwargs):
        if self.database.name == db.name and self.name == "notifications" and kwargs.get("session"):
            raise asyncio.CancelledError()
        return await original(self, docs, *args, **kwargs)
    monkeypatch.setattr(AsyncIOMotorCollection, "insert_many", cancel)
    with pytest.raises(asyncio.CancelledError):
        await backup.restore_document(db, archive, "admin", maintenance=True)
    assert await dump(db) == before


@pytest.mark.asyncio
async def test_http_encrypted_export_restore_and_error_messages(db, archive, monkeypatch):
    import httpx
    from fastapi import FastAPI
    from app.routers import backup as router
    from app.maintenance import BackupMaintenanceMiddleware
    await seed(db, archive)
    monkeypatch.setattr(router, "database", db)
    monkeypatch.setenv("BACKUP_MAINTENANCE_MODE", "true")
    monkeypatch.setattr(router, "log_audit", AsyncMock())
    app = FastAPI()
    app.include_router(router.admin_router, prefix="/api/admin")
    async def admin(): return {"role": "admin", "username": "admin"}
    app.dependency_overrides[router.verify_auth] = admin
    app.add_middleware(BackupMaintenanceMiddleware)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        exported = await client.get("/api/admin/export-db")
        assert exported.status_code == 200
        assert exported.headers["cache-control"] == "no-store"
        assert exported.content.startswith(backup.MAGIC)
        restored = await client.post("/api/admin/import-db", files={"file": ("backup.enc", exported.content)})
        assert restored.status_code == 200, restored.text
        assert restored.json()["reauthenticate"]
        rejected = await client.post("/api/admin/import-db", files={"file": ("backup.enc", b"bad")})
        assert rejected.status_code == 422


@pytest.mark.asyncio
async def test_final_audit_write_failure_also_rolls_back(db, archive, monkeypatch):
    await seed(db, archive)
    before = await dump(db)
    original = AsyncIOMotorCollection.insert_one
    async def fail(self, doc, *args, **kwargs):
        if self.database.name == db.name and doc.get("azione") == "IMPORT_DATABASE":
            raise OperationFailure("synthetic audit failure", code=2)
        return await original(self, doc, *args, **kwargs)
    monkeypatch.setattr(AsyncIOMotorCollection, "insert_one", fail)
    with pytest.raises(Exception) as caught:
        await backup.restore_document(db, archive, "admin", maintenance=True)
    assert caught.value.status_code == 503
    assert await dump(db) == before


@pytest.mark.asyncio
async def test_unknown_collection_prevents_incomplete_export(db, archive):
    await seed(db, archive)
    await db.unregistered.insert_one({"synthetic": True})
    with pytest.raises(Exception) as caught:
        await backup.export_archive(db)
    assert caught.value.status_code == 409


@pytest.mark.asyncio
async def test_c1_15_destination_indexes_preserved_after_restore(db, archive):
    await seed(db, archive)
    await db.patients.create_index("codice_fiscale")
    await backup.restore_document(db, archive, "admin", maintenance=True)
    indexes = [idx["name"] for idx in await db.patients.list_indexes().to_list(None)]
    assert "codice_fiscale_1" in indexes


@pytest.mark.asyncio
async def test_c1_21_job_status_matrix_on_restore(db, archive):
    now = archive["collections"]["ai_jobs"][0]["created_at"]
    jobs = [
        {"id": "j_p", "username": "admin", "status": "pending", "created_at": now},
        {"id": "j_r", "username": "admin", "status": "running", "created_at": now},
        {"id": "j_c", "username": "admin", "status": "completed", "created_at": now, "analysis_id": "an_1"},
        {"id": "j_f", "username": "admin", "status": "failed", "created_at": now},
    ]
    archive["collections"]["ai_jobs"] = jobs
    # Update notifications reference to valid job
    archive["collections"]["notifications"][0]["job_id"] = "j_c"
    await backup.restore_document(db, archive, "admin", maintenance=True)
    by_id = {j["id"]: j["status"] async for j in db.ai_jobs.find({})}
    assert by_id["j_p"] == "failed"
    assert by_id["j_r"] == "failed"
    assert by_id["j_c"] == "completed"
    assert by_id["j_f"] == "failed"


@pytest.mark.asyncio
async def test_c1_22_same_license_and_trial_scenarios(db, archive):
    # Same license identity allowed
    await seed(db, archive)
    await backup.restore_document(db, archive, "admin", maintenance=True)
    # Destination trial allowed to receive commercial
    await db.licenses.update_one({}, {"$set": {"plan": "trial", "instance_id": "inst_trial", "license_token": None}})
    archive_commercial = copy.deepcopy(archive)
    archive_commercial["collections"]["licenses"][0].update({"plan": "1M", "instance_id": "inst_comm", "license_token": "token123"})
    await backup.restore_document(db, archive_commercial, "admin", maintenance=True)
    assert (await db.licenses.find_one({}))["plan"] == "1M"
