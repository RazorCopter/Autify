from datetime import datetime, timezone
from unittest.mock import AsyncMock, patch

import pytest

from app.auth import create_access_token
from app.routers import ai as ai_router
from .test_endpoints import (
    MockCollection, client, setup_mock_db,
    mock_patients, mock_scales, mock_evaluations, mock_users,
)


@pytest.mark.anyio
async def test_job_lifecycle_creates_analysis_and_notification():
    jobs = MockCollection("ai_jobs", [{
        "id": "job_1", "username": "admin", "id_paziente": "pat_1",
        "patient_name": "Mario Rossi", "status": "pending",
        "created_at": datetime.now(timezone.utc), "system_prompt": "system",
        "user_prompt": "user", "attachment": None, "evaluations_used": [],
    }])
    analyses = MockCollection("ai_analyses", [])
    notifications = MockCollection("notifications", [])
    adapter = AsyncMock()
    adapter.generate.return_value = ("Relazione completata", {"total_tokens": 10})

    with patch.object(ai_router, "ai_jobs_collection", jobs), \
         patch.object(ai_router, "ai_analyses_collection", analyses), \
         patch.object(ai_router, "notifications_collection", notifications), \
         patch.object(ai_router, "get_or_migrate_ai_settings", new=AsyncMock()) as settings, \
         patch.object(ai_router, "get_ai_adapter", return_value=adapter), \
         patch.object(ai_router, "log_audit", new=AsyncMock()):
        stored = settings.return_value
        stored.active_provider = "gemini"
        stored.gemini.model = "gemini-test"
        await ai_router._process_ai_job("job_1")
        await ai_router._process_ai_job("job_1")

    assert jobs.documents[0]["status"] == "completed"
    assert jobs.documents[0]["analysis_id"].startswith("an_")
    assert len(analyses.documents) == 1
    assert len(notifications.documents) == 1
    assert notifications.documents[0]["message"] == 'Elaborazione IA "Mario Rossi" terminata'
    adapter.generate.assert_awaited_once()


def test_notifications_are_isolated_and_read_updates_badge(client, setup_mock_db):
    now = datetime.now(timezone.utc)
    notifications = MockCollection("notifications", [
        {"id": "nt_admin", "username": "admin", "type": "ai_analysis_completed", "message": "Admin", "read": False, "created_at": now},
        {"id": "nt_other", "username": "other", "type": "ai_analysis_completed", "message": "Other", "read": False, "created_at": now},
    ])
    with patch.object(ai_router, "notifications_collection", notifications):
        response = client.get("/api/admin/notifications")
        assert response.status_code == 200
        assert [item["id"] for item in response.json()] == ["nt_admin"]

        badge = client.get("/api/admin/notifications/unread-count")
        assert badge.json() == {"unread_count": 1}

        forbidden = client.post("/api/admin/notifications/nt_other/read")
        assert forbidden.status_code == 404

        marked = client.post("/api/admin/notifications/nt_admin/read")
        assert marked.status_code == 200
        assert marked.json()["read"] is True
        assert client.get("/api/admin/notifications/unread-count").json() == {"unread_count": 0}


def test_job_detail_is_isolated_by_authenticated_user(client, setup_mock_db):
    jobs = MockCollection("ai_jobs", [{
        "id": "job_other", "username": "other", "id_paziente": "pat_1",
        "patient_name": "Mario Rossi", "status": "pending", "created_at": datetime.now(timezone.utc),
    }])
    with patch.object(ai_router, "ai_jobs_collection", jobs):
        response = client.get("/api/admin/ai/jobs/job_other")
        assert response.status_code == 404
