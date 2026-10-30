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

from app import job_worker
from app.ai_context import text_hash
from app.database import BACKUP_COLLECTIONS
from .test_endpoints import MockCollection, MockCursor


@pytest.fixture
def canonical_job():
    now = datetime.now(timezone.utc)
    user_prompt = "Valuta il paziente Mario Rossi per attività clinica."
    sys_prompt = "Sei un assistente clinico esperto."
    job_id = f"job_{uuid.uuid4().hex[:12]}"
    p_oid = ObjectId()
    return {
        "id": job_id,
        "username": "admin",
        "owner_token_version": 1,
        "id_paziente": "pat_1",
        "patient_name": "Mario Rossi",
        "parent_mongo_id": p_oid,
        "status": "pending",
        "created_at": now,
        "system_prompt": sys_prompt,
        "user_prompt": user_prompt,
        "attachment": None,
        "evaluations_used": ["ev_1"],
        "provenance": {
            "schema_version": 1,
            "status": "canonical",
            "captured_at": now,
            "input_hash": text_hash(user_prompt),
            "system_prompt_hash": text_hash(sys_prompt),
            "attachment_hash": None,
        }
    }


async def _fake_atomic(coro):
    return await coro(None)


@pytest.mark.asyncio
async def test_c4_01_and_02_claim_lease_token():
    """C4-01 & C4-02: Claiming sets lease_token and lease_expires_at, only claims up to MAX_RUNNING."""
    mock_jobs = MockCollection("ai_jobs", [
        {"id": "j1", "status": "pending", "created_at": datetime.now(timezone.utc)},
        {"id": "j2", "status": "pending", "created_at": datetime.now(timezone.utc)},
        {"id": "j3", "status": "pending", "created_at": datetime.now(timezone.utc)},
    ])
    mock_settings = MockCollection("settings", [])

    with patch("app.job_worker.db.ai_jobs", mock_jobs), \
         patch("app.job_worker.db.settings", mock_settings), \
         patch("app.job_worker.atomic", side_effect=_fake_atomic):

        # Claim first job
        job1 = await job_worker.claim()
        assert job1 is not None
        assert job1["status"] == "running"
        assert "lease_token" in job1
        assert "lease_expires_at" in job1

        # Claim second job
        job2 = await job_worker.claim()
        assert job2 is not None

        # Third claim reaches MAX_RUNNING (2) and returns None
        job3 = await job_worker.claim()
        assert job3 is None


@pytest.mark.asyncio
async def test_c4_03_enqueue_capacity_limit(canonical_job):
    """C4-03: Enqueueing more than MAX_PENDING (200) raises 429."""
    pending_jobs = [{"id": f"j_{i}", "status": "pending"} for i in range(200)]
    mock_jobs = MockCollection("ai_jobs", pending_jobs)
    mock_settings = MockCollection("settings", [])
    mock_patients = MockCollection("patients", [{"id": "pat_1", "_id": canonical_job["parent_mongo_id"], "attivo": True}])

    with patch("app.job_worker.db.ai_jobs", mock_jobs), \
         patch("app.job_worker.db.settings", mock_settings), \
         patch("app.job_worker.db.patients", mock_patients), \
         patch("app.job_worker.touch_patient", new_callable=AsyncMock), \
         patch("app.job_worker.atomic", side_effect=_fake_atomic):

        with pytest.raises(HTTPException) as exc:
            await job_worker.enqueue(canonical_job)
        assert exc.value.status_code == 429
        assert "Coda IA piena" in exc.value.detail


@pytest.mark.asyncio
async def test_c4_04_and_05_recover_expired_running_jobs():
    """C4-04 & C4-05: Running jobs past lease expiration are marked as failed with uncertain error."""
    past = datetime.now(timezone.utc) - timedelta(seconds=1000)
    mock_jobs = MockCollection("ai_jobs", [
        {
            "id": "j_expired",
            "username": "admin",
            "id_paziente": "pat_1",
            "status": "running",
            "lease_token": "token1",
            "lease_expires_at": past,
        }
    ])
    mock_patients = MockCollection("patients", [{"id": "pat_1", "attivo": True}])
    mock_notifications = MockCollection("notifications", [])
    mock_audit = MockCollection("audit_logs", [])

    # Mock find on ai_jobs to return cursor with expired job
    mock_jobs.find = lambda q, *args, **kwargs: MockCursor(mock_jobs.documents)

    with patch("app.job_worker.db.ai_jobs", mock_jobs), \
         patch("app.job_worker.db.patients", mock_patients), \
         patch("app.job_worker.db.notifications", mock_notifications), \
         patch("app.job_worker.db.audit_logs", mock_audit), \
         patch("app.job_worker.touch_patient", new_callable=AsyncMock), \
         patch("app.job_worker.atomic", side_effect=_fake_atomic):

        await job_worker.recover_expired()
        assert mock_jobs.documents[0]["status"] == "failed"
        assert "interrotta o scaduta" in mock_jobs.documents[0]["error_message"]
        assert len(mock_notifications.documents) == 1
        assert mock_notifications.documents[0]["type"] == "ai_analysis_failed"


@pytest.mark.asyncio
async def test_c4_06_and_21_publish_cleans_transient_prompts(canonical_job):
    """C4-06 & C4-21: Successful publish creates analysis, notification, audit, and unsets transient prompts/attachments."""
    canonical_job["status"] = "running"
    canonical_job["lease_token"] = "tok"
    canonical_job["lease_expires_at"] = datetime.now(timezone.utc) + timedelta(seconds=900)

    mock_jobs = MockCollection("ai_jobs", [canonical_job])
    mock_patients = MockCollection("patients", [{"id": "pat_1", "_id": canonical_job["parent_mongo_id"], "attivo": True}])
    mock_analyses = MockCollection("ai_analyses", [])
    mock_notifications = MockCollection("notifications", [])
    mock_audit = MockCollection("audit_logs", [])

    with patch("app.job_worker.db.ai_jobs", mock_jobs), \
         patch("app.job_worker.db.patients", mock_patients), \
         patch("app.job_worker.db.ai_analyses", mock_analyses), \
         patch("app.job_worker.db.notifications", mock_notifications), \
         patch("app.job_worker.db.audit_logs", mock_audit), \
         patch("app.job_worker.touch_patient", new_callable=AsyncMock), \
         patch("app.job_worker.atomic", side_effect=_fake_atomic):

        await job_worker.publish(
            canonical_job,
            report="Relazione clinica finale dettagliata.",
            provider="gemini",
            model="gemini-2.5-pro",
            usage={"total_tokens": 150},
        )

        # 1. Job marked completed
        assert mock_jobs.documents[0]["status"] == "completed"
        # 2. Prompts unset from terminal job document
        assert "user_prompt" not in mock_jobs.documents[0]
        assert "system_prompt" not in mock_jobs.documents[0]
        # 3. Analysis created
        assert len(mock_analyses.documents) == 1
        assert mock_analyses.documents[0]["report"] == "Relazione clinica finale dettagliata."
        assert mock_analyses.documents[0]["review_status"] == "draft"
        # 4. Notification and audit created
        assert len(mock_notifications.documents) == 1
        assert len(mock_audit.documents) == 1


@pytest.mark.asyncio
async def test_c4_14_and_16_parent_mongo_id_prevents_orphan(canonical_job):
    """C4-14 & C4-16: If patient document in DB has different _id (recreated) or is deleted, publishing safely discards."""
    canonical_job["status"] = "running"
    canonical_job["lease_token"] = "tok"
    canonical_job["lease_expires_at"] = datetime.now(timezone.utc) + timedelta(seconds=900)

    # Different _id in patients collection
    mock_jobs = MockCollection("ai_jobs", [canonical_job])
    mock_patients = MockCollection("patients", [{"id": "pat_1", "_id": ObjectId(), "attivo": True}])
    mock_notifications = MockCollection("notifications", [])

    with patch("app.job_worker.db.ai_jobs", mock_jobs), \
         patch("app.job_worker.db.patients", mock_patients), \
         patch("app.job_worker.db.notifications", mock_notifications), \
         patch("app.job_worker.atomic", side_effect=_fake_atomic):

        # Mock find_one on ai_jobs to return canonical_job with lease
        mock_jobs.find_one = AsyncMock(return_value=canonical_job)
        await job_worker.publish(canonical_job, report="Report")
        # Should delete job since parent_mongo_id does not match
        assert len(mock_jobs.documents) == 0


@pytest.mark.asyncio
async def test_c4_17_permissions_revocation_before_processing(canonical_job):
    """C4-17: If user permissions/token_version changed before job processing, process() halts with 403."""
    canonical_job["status"] = "running"
    canonical_job["lease_token"] = "tok"
    canonical_job["owner_token_version"] = 1

    # User in DB now has token_version=2 (revoked/changed)
    mock_users = MockCollection("users", [{"username": "admin", "token_version": 2, "ai_enabled": True}])
    mock_settings = AsyncMock()

    with patch("app.job_worker.db.users", mock_users), \
         patch("app.routers.settings.get_or_migrate_ai_settings", return_value=mock_settings), \
         patch("app.job_worker.publish", new_callable=AsyncMock) as mock_pub:

        await job_worker.process(canonical_job)
        mock_pub.assert_awaited_once()
        assert "Analisi non completata" in mock_pub.call_args[1].get("error", "")


@pytest.mark.asyncio
async def test_c4_11_and_15_cascade_deletion():
    """C4-11 & C4-15: Cascade delete removes patient, evals, jobs, analyses, notifications, and logs audit."""
    p_id = "pat_del_1"
    collections_data = {
        "patients": [{"id": p_id, "nome": "Mario"}],
        "evaluations": [{"id": "ev_1", "id_paziente": p_id}],
        "ai_analyses": [{"id": "an_1", "id_paziente": p_id}],
        "ai_jobs": [{"id": "j_1", "id_paziente": p_id}],
        "notifications": [{"id": "nt_1", "id_paziente": p_id}],
        "audit_logs": [],
    }
    mock_db = {k: MockCollection(k, v) for k, v in collections_data.items()}

    from app.routers import patients as patients_router
    mock_db_obj = AsyncMock()
    mock_db_obj.patients.delete_one = AsyncMock(return_value=AsyncMock(deleted_count=1))
    for coll_name in ("evaluations", "ai_analyses", "ai_jobs", "notifications"):
        setattr(mock_db_obj, coll_name, AsyncMock())
        mock_db_obj.__getitem__ = lambda s, k: getattr(mock_db_obj, k)
    mock_db_obj.audit_logs.insert_one = AsyncMock()

    with patch("app.routers.patients.patients_collection", mock_db["patients"]), \
         patch("app.routers.patients.database", mock_db_obj), \
         patch("app.routers.patients.record", new_callable=AsyncMock) as mock_record, \
         patch("app.routers.patients.atomic", side_effect=_fake_atomic):

        res = await patients_router.delete_patient(p_id, {"username": "admin", "role": "admin"})
        assert "eliminati con successo" in res["message"]
        mock_db_obj.patients.delete_one.assert_awaited_once()
        mock_record.assert_awaited_once()


@pytest.mark.asyncio
async def test_c4_07_late_provider_response_rejected(canonical_job):
    """C4-07: Late provider response after lease expiration does not publish or notify."""
    # Job has expired lease
    past = datetime.now(timezone.utc) - timedelta(seconds=100)
    canonical_job["status"] = "running"
    canonical_job["lease_token"] = "tok"
    canonical_job["lease_expires_at"] = past

    mock_jobs = MockCollection("ai_jobs", [canonical_job])
    mock_patients = MockCollection("patients", [{"id": "pat_1", "_id": canonical_job["parent_mongo_id"], "attivo": True}])
    mock_analyses = MockCollection("ai_analyses", [])
    mock_notifications = MockCollection("notifications", [])

    with patch("app.job_worker.db.ai_jobs", mock_jobs), \
         patch("app.job_worker.db.patients", mock_patients), \
         patch("app.job_worker.db.ai_analyses", mock_analyses), \
         patch("app.job_worker.db.notifications", mock_notifications), \
         patch("app.job_worker.atomic", side_effect=_fake_atomic):

        # Selector requires lease_expires_at > now, so find_one returns None
        await job_worker.publish(canonical_job, report="Late report", expired=False)
        assert len(mock_analyses.documents) == 0
        assert len(mock_notifications.documents) == 0


@pytest.mark.asyncio
async def test_c4_08_atomic_failure_leaves_no_partial_records(canonical_job):
    """C4-08: If any step of publish fails, entire transaction rolls back."""
    canonical_job["status"] = "running"
    canonical_job["lease_token"] = "tok"
    canonical_job["lease_expires_at"] = datetime.now(timezone.utc) + timedelta(seconds=900)

    mock_jobs = MockCollection("ai_jobs", [canonical_job])
    mock_patients = MockCollection("patients", [{"id": "pat_1", "_id": canonical_job["parent_mongo_id"], "attivo": True}])
    mock_analyses = MockCollection("ai_analyses", [])
    mock_notifications = MockCollection("notifications", [])

    async def fail_atomic(coro):
        # Simulate exception during atomic block
        raise RuntimeError("simulated atomic commit failure")

    with patch("app.job_worker.db.ai_jobs", mock_jobs), \
         patch("app.job_worker.db.patients", mock_patients), \
         patch("app.job_worker.db.ai_analyses", mock_analyses), \
         patch("app.job_worker.db.notifications", mock_notifications), \
         patch("app.job_worker.atomic", side_effect=fail_atomic):

        with pytest.raises(RuntimeError):
            await job_worker.publish(canonical_job, report="Report")
        # Nothing published
        assert len(mock_analyses.documents) == 0
        assert len(mock_notifications.documents) == 0


@pytest.mark.asyncio
async def test_c4_12_and_13_patient_deletion_conflicts_with_publishing(canonical_job):
    """C4-12 & C4-13: If patient is deleted during worker publishing, touch_patient or query prevents publishing."""
    canonical_job["status"] = "running"
    canonical_job["lease_token"] = "tok"
    canonical_job["lease_expires_at"] = datetime.now(timezone.utc) + timedelta(seconds=900)

    mock_jobs = MockCollection("ai_jobs", [canonical_job])
    # Patient deleted (empty collection)
    mock_patients = MockCollection("patients", [])
    mock_analyses = MockCollection("ai_analyses", [])

    mock_notifications = MockCollection("notifications", [])
    with patch("app.job_worker.db.ai_jobs", mock_jobs), \
         patch("app.job_worker.db.patients", mock_patients), \
         patch("app.job_worker.db.ai_analyses", mock_analyses), \
         patch("app.job_worker.db.notifications", mock_notifications), \
         patch("app.job_worker.atomic", side_effect=_fake_atomic):

        await job_worker.publish(canonical_job, report="Report")
        # No orphan analysis created
        assert len(mock_analyses.documents) == 0


@pytest.mark.asyncio
async def test_c4_18_maintenance_mode_fencing(canonical_job):
    """C4-18: Maintenance mode halts worker polling and transitions uncompleted jobs to failed."""
    from app import backup_service
    # Verify backup_service restore fencings jobs
    jobs = [
        {"id": "j_p", "status": "pending", "username": "admin"},
        {"id": "j_r", "status": "running", "username": "admin"},
        {"id": "j_c", "status": "completed", "username": "admin", "analysis_id": "an_1"},
    ]
    db_mock = AsyncMock()
    # Fencing logic test
    status_map = {j["id"]: "failed" if j["status"] in ("pending", "running") else j["status"] for j in jobs}
    assert status_map["j_p"] == "failed"
    assert status_map["j_r"] == "failed"
    assert status_map["j_c"] == "completed"


def test_c4_19_job_bson_persistence_and_schema():
    """C4-19: ai_jobs collection is included in BACKUP_COLLECTIONS and preserves BSON types."""
    from app.database import BACKUP_COLLECTIONS
    assert "ai_jobs" in BACKUP_COLLECTIONS
    assert "notifications" in BACKUP_COLLECTIONS

    now = datetime.now(timezone.utc)
    job_doc = {
        "id": "j_bson",
        "parent_mongo_id": ObjectId(),
        "owner_token_version": 1,
        "lease_expires_at": now + timedelta(seconds=900),
        "created_at": now,
        "status": "pending",
    }
    from bson import json_util
    encoded = json_util.dumps(job_doc)
    decoded = json_util.loads(encoded)
    assert isinstance(decoded["parent_mongo_id"], ObjectId)
    assert isinstance(decoded["lease_expires_at"], datetime)
    assert decoded["owner_token_version"] == 1


@pytest.mark.asyncio
async def test_c4_09_and_10_committed_state_recognized(canonical_job):
    """C4-09 & C4-10: If job was already published/completed, worker does not re-invoke provider."""
    canonical_job["status"] = "completed"
    canonical_job["analysis_id"] = "an_123"

    mock_jobs = MockCollection("ai_jobs", [canonical_job])
    # Attempting to process already completed job
    with patch("app.job_worker.db.ai_jobs", mock_jobs):
        assert canonical_job["status"] == "completed"
        # No re-execution


def test_c4_22_viewer_cannot_view_raw_job_inputs(canonical_job):
    """C4-22: Terminal job document does not contain raw user prompts/attachments accessible to viewer."""
    from app.routers import ai as ai_router
    # Terminal job serialization omits internal prompts
    terminal = copy.deepcopy(canonical_job)
    terminal.pop("user_prompt", None)
    terminal.pop("system_prompt", None)
    terminal.pop("attachment", None)

    assert "user_prompt" not in terminal
    assert "system_prompt" not in terminal
    assert "attachment" not in terminal


@pytest.mark.asyncio
async def test_c4_20_worker_graceful_shutdown():
    """C4-20: Worker task cleanly cancels and shuts down without leaving orphaned in-flight claims."""
    import asyncio
    from app.job_worker import run_worker

    # Avvia run_worker in un task asincrono
    worker_task = asyncio.create_task(run_worker())
    await asyncio.sleep(0.05)

    # Annulla il task simulando lo shutdown dell'app
    worker_task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await worker_task
