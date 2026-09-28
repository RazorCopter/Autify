import os
from datetime import timedelta
from unittest.mock import AsyncMock

import pytest
import httpx

os.environ.setdefault("LICENSE_SHARED_SECRET", "test-shared-secret-with-more-than-32-characters")

from app import license_service


class _HealthResponse:
    status_code = 200


class _HealthClient:
    def __init__(self, *args, **kwargs):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def get(self, url):
        assert url == "https://licenze.example.test/health"
        return _HealthResponse()


@pytest.mark.anyio
async def test_license_server_info_reports_reachable(monkeypatch):
    monkeypatch.setenv("LICENSE_SERVER_URL", "https://licenze.example.test/")
    monkeypatch.setattr(license_service.httpx, "AsyncClient", _HealthClient)

    result = await license_service.get_license_server_info()

    assert result == {
        "license_server_url": "https://licenze.example.test",
        "configured": True,
        "reachable": True,
    }


@pytest.mark.anyio
async def test_license_server_info_handles_unreachable_server(monkeypatch):
    class UnreachableClient(_HealthClient):
        async def get(self, url):
            raise httpx.ConnectError("offline")

    monkeypatch.setenv("LICENSE_SERVER_URL", "https://licenze.example.test")
    monkeypatch.setattr(license_service.httpx, "AsyncClient", UnreachableClient)

    result = await license_service.get_license_server_info()

    assert result["configured"] is True
    assert result["reachable"] is False


@pytest.fixture
def collection(monkeypatch):
    mock = AsyncMock()
    monkeypatch.setattr(license_service, "licenses_collection", mock)
    return mock


@pytest.mark.anyio
async def test_trial_is_created_once(collection, monkeypatch):
    collection.find_one.side_effect = [None, {"id": license_service.LICENSE_ID}]
    monkeypatch.setattr(license_service.uuid, "uuid4", lambda: "instance-id")
    created = await license_service.ensure_trial_license()
    assert created["status"] == "trial"
    assert created["expires_at"] - created["activated_at"] == timedelta(days=15)
    collection.insert_one.assert_awaited_once()


def test_serialize_maps_expired_and_rounds_remaining_days(monkeypatch):
    now = license_service.utcnow()
    monkeypatch.setattr(license_service, "utcnow", lambda: now)
    result = license_service._serialize(
        {"status": "active", "plan": "1M", "expires_at": now + timedelta(seconds=1)}
    )
    assert result["status"] == "active"
    assert result["days_remaining"] == 1

    expired = license_service._serialize(
        {"status": "active", "plan": "1M", "expires_at": now - timedelta(seconds=1)}
    )
    assert expired["status"] == "expired"
    assert expired["valid"] is False


@pytest.mark.anyio
async def test_remote_revocation_is_preserved(collection, monkeypatch):
    now = license_service.utcnow()
    document = {
        "id": license_service.LICENSE_ID,
        "instance_id": "instance-id",
        "license_token": "token",
        "status": "active",
        "plan": "12M",
        "expires_at": now + timedelta(days=30),
        "last_validated_at": now - timedelta(days=2),
    }
    collection.find_one.return_value = document
    monkeypatch.setattr(
        license_service,
        "_license_server_call",
        AsyncMock(return_value={"valid": False, "reason": "revoked", "plan": "12M"}),
    )
    result = await license_service.get_license_status(force_remote=True)
    assert result["status"] == "revoked"
    assert result["valid"] is False


@pytest.mark.anyio
async def test_offline_grace_and_expiry(collection, monkeypatch):
    now = license_service.utcnow()
    document = {
        "id": license_service.LICENSE_ID,
        "instance_id": "instance-id",
        "license_token": "token",
        "status": "active",
        "plan": "12M",
        "expires_at": now + timedelta(days=30),
        "last_validated_at": now - timedelta(hours=1),
    }
    collection.find_one.return_value = document
    monkeypatch.setattr(
        license_service, "_license_server_call", AsyncMock(side_effect=RuntimeError("offline"))
    )
    grace = await license_service.get_license_status(force_remote=True)
    assert grace["valid"] is True
    assert grace["offline"] is True

    collection.find_one.return_value = {
        **document,
        "last_validated_at": now - timedelta(hours=license_service.OFFLINE_GRACE_HOURS + 1),
    }
    expired = await license_service.get_license_status(force_remote=True)
    assert expired["valid"] is False
    assert expired["status"] == "validation_required"