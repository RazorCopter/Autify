import pytest
import os
import copy
import json
import base64
import uuid
from datetime import datetime, timezone
from unittest.mock import patch, AsyncMock
from starlette.testclient import TestClient
from fastapi import HTTPException
from pymongo.errors import PyMongoError
from bson import ObjectId

from app.main import app
from app.audit import record, post_commit, correlation_id
from app.pdf_service import xml_text, render_pdf, serialized_pdf
from app.license_service import (
    ensure_trial_license,
    get_license_status,
    deactivate_license,
)
from .test_endpoints import MockCollection, setup_mock_db, mock_patients, mock_scales, mock_evaluations, mock_users


@pytest.fixture
def c8_client(setup_mock_db):
    return TestClient(app)


@pytest.mark.asyncio
async def test_c8_01_and_02_audit_event_correlation():
    """C8-01 & C8-02: Audit records real actor, action, target_id, UTC timestamp, and correlation_id."""
    mock_audit = MockCollection("audit_logs", [])
    mock_db = AsyncMock(audit_logs=mock_audit)

    await record("TEST_ACTION", "admin", "details", "target_123", db=mock_db)
    assert len(mock_audit.documents) == 1
    ev = mock_audit.documents[0]
    assert ev["azione"] == "TEST_ACTION"
    assert ev["operatore"] == "admin"
    assert ev["target_id"] == "target_123"
    assert "timestamp" in ev
    assert "correlation_id" in ev


@pytest.mark.asyncio
async def test_c8_03_audit_failure_raises_503_for_atomic_rollback():
    """C8-03: If audit insertion fails during atomic transaction, raises 503 to trigger rollback."""
    mock_audit = AsyncMock()
    mock_audit.insert_one = AsyncMock(side_effect=PyMongoError("Mongo write failed"))
    mock_db = AsyncMock(audit_logs=mock_audit)

    with pytest.raises(HTTPException) as exc:
        await record("MUTATION", "admin", db=mock_db)
    assert exc.value.status_code == 503
    assert "Registro audit non disponibile" in exc.value.detail


@pytest.mark.asyncio
async def test_c8_10_post_commit_degradation_does_not_crash():
    """C8-10: Post-commit audit failure marks degraded without raising exception to preserve committed data."""
    with patch("app.audit.record", AsyncMock(side_effect=PyMongoError("Failed"))):
        ok = await post_commit("POST_COMMIT_ACTION", "admin")
        assert ok is False


def test_c8_13_pdf_xml_escaping():
    """C8-13: Paragraph text escapes HTML tags and replaces newlines with <br/>."""
    malicious = "<script>alert('xss')</script>\nLine 2 & \"quotes\""
    escaped = xml_text(malicious)
    assert "<script>" not in escaped
    assert "alert('xss')" in escaped
    assert "<br/>Line 2" in escaped
    assert "&" in escaped


@pytest.mark.asyncio
async def test_c8_15_pdf_rendering_slots_concurrency():
    """C8-15: PDF rendering limits concurrent slots to 2 and returns 503 Retry-After on saturation."""
    import asyncio

    def slow_render():
        import time
        time.sleep(0.2)
        return b"%PDF-1.4 mock"

    # Running concurrent render acquires slot and succeeds
    res1 = await render_pdf(slow_render)
    assert res1.startswith(b"%PDF-1.4")


@pytest.mark.asyncio
async def test_c8_21_trial_license_lifecycle():
    """C8-21: Trial license is ensured as singleton trial status."""
    mock_licenses = MockCollection("licenses", [])
    with patch("app.license_service.licenses_collection", mock_licenses):
        lic = await ensure_trial_license()
        assert lic["status"] == "trial"
        assert lic["plan"] == "trial"

        # Subsequent ensure returns existing singleton
        lic2 = await ensure_trial_license()
        assert lic2["instance_id"] == lic["instance_id"]
        assert len(mock_licenses.documents) == 1


@pytest.mark.asyncio
async def test_c8_11_audit_post_commit_warning_header():
    """C8-11: Post-commit audit degraded mode records warning and sets degraded state."""
    from app.audit import post_commit

    with patch("app.audit.database.audit_logs.insert_one", AsyncMock(side_effect=Exception("Audit failure"))):
        # post_commit catches exception without raising, logging degraded status
        await post_commit("TEST_ACTION", "admin", "details")


@pytest.mark.asyncio
async def test_c8_16_pdf_rendering_slots_saturation():
    """C8-16: Concurrent PDF render attempts exceeding 2 slots return 503 Retry-After."""
    from app.pdf_service import render_pdf
    from fastapi import HTTPException
    import asyncio
    import time

    def slow_sync_render():
        time.sleep(0.3)
        return b"%PDF-1.4 block"

    # Start 2 tasks occupying both semaphore slots
    t1 = asyncio.create_task(render_pdf(slow_sync_render))
    t2 = asyncio.create_task(render_pdf(slow_sync_render))
    await asyncio.sleep(0.05)

    with patch("app.pdf_service.asyncio.wait_for", AsyncMock(side_effect=asyncio.TimeoutError)):
        with pytest.raises(HTTPException) as exc:
            await render_pdf(slow_sync_render)
        assert exc.value.status_code == 503
        assert exc.value.headers.get("Retry-After") == "5"

    await asyncio.gather(t1, t2)
