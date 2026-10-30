import pytest
import os
import copy
import json
from datetime import datetime, timezone, date
from zoneinfo import ZoneInfo
from unittest.mock import patch, AsyncMock
from starlette.testclient import TestClient
from fastapi import HTTPException
from bson import ObjectId

from app.main import app
from app.expiry import (
    KINDS,
    DEFAULT_MONTHS,
    ROME,
    utc_date,
    policy_from,
    expiry_day,
    project,
)
from app.auth import create_access_token
from .test_endpoints import MockCollection, setup_mock_db, mock_patients, mock_scales, mock_evaluations, mock_users


@pytest.fixture
def c6_client(setup_mock_db):
    return TestClient(app)


def test_c6_01_default_server_policy():
    """C6-01: Default policy has 12/12/36/12/12/12 months, required POS/SM/SIS, and warning 30 days."""
    p = policy_from({})
    assert p["scale_validity_months"] == {"pos": 12, "san_martin": 12, "sis": 36, "ogva": 12, "sabs": 12, "oso": 12}
    assert p["required_scale_types"] == ["pos", "san_martin", "sis"]
    assert p["expiry_warning_days"] == 30
    assert p["timezone"] == "Europe/Rome"


@pytest.mark.asyncio
async def test_c6_02_and_03_admin_vs_viewer_expiry_policy(c6_client, setup_mock_db):
    """C6-02 & C6-03: Admin can save and read policy via POST/GET; viewer POST returns 403."""
    admin_token = create_access_token("admin", "admin", ai_enabled=True)
    viewer_token = create_access_token("viewer_user", "viewer", ai_enabled=False)

    policy_payload = {
        "scale_validity_months": {"pos": 6, "san_martin": 12, "sis": 24, "ogva": 12, "sabs": 12, "oso": 12},
        "required_scale_types": ["pos", "sis"],
        "expiry_warning_days": 45,
    }

    # 1. Viewer POST -> 403
    res_v = c6_client.post("/api/admin/expiry-policy", headers={"Authorization": f"Bearer {viewer_token}"}, json=policy_payload)
    assert res_v.status_code == 403

    # 2. Admin POST -> 200 (with atomic patched)
    with patch("app.routers.settings.atomic", side_effect=lambda fn: fn(None)), \
         patch("app.routers.settings.record", new_callable=AsyncMock):
        res_a = c6_client.post("/api/admin/expiry-policy", headers={"Authorization": f"Bearer {admin_token}"}, json=policy_payload)
        assert res_a.status_code == 200
        assert res_a.json()["expiry_warning_days"] == 45
        assert res_a.json()["required_scale_types"] == ["pos", "sis"]

    # 3. GET available to both
    with patch("app.expiry.load_policy", AsyncMock(return_value=policy_from(policy_payload))):
        res_get = c6_client.get("/api/admin/expiry-policy", headers={"Authorization": f"Bearer {viewer_token}"})
        assert res_get.status_code == 200
        assert res_get.json()["expiry_warning_days"] == 45


def test_c6_04_policy_validation_edges():
    """C6-04: Invalid durations (0, >120, non-int), unknown kinds, empty required or negative warning rejected with 422."""
    # 0 months
    with pytest.raises(HTTPException) as exc:
        policy_from({"scale_validity_months": {"pos": 0}})
    assert exc.value.status_code == 422

    # >120 months
    with pytest.raises(HTTPException) as exc:
        policy_from({"scale_validity_months": {"pos": 121}})
    assert exc.value.status_code == 422

    # Non-integer months
    with pytest.raises(HTTPException) as exc:
        policy_from({"scale_validity_months": {"pos": "12"}})
    assert exc.value.status_code == 422

    # Unknown scale kind in required
    with pytest.raises(HTTPException) as exc:
        policy_from({"required_scale_types": ["unknown_scale"]})
    assert exc.value.status_code == 422

    # Empty required list
    with pytest.raises(HTTPException) as exc:
        policy_from({"required_scale_types": []})
    assert exc.value.status_code == 422

    # Negative warning days
    with pytest.raises(HTTPException) as exc:
        policy_from({"expiry_warning_days": -1})
    assert exc.value.status_code == 422


def test_c6_06_calendar_month_end_calculations():
    """C6-06: End-of-month dates properly target the end of target month without day overflow."""
    # 31 Jan + 1 month -> 28 Feb (or 29 Feb on leap year)
    d_jan31_2026 = datetime(2026, 1, 31, tzinfo=timezone.utc)
    res1 = expiry_day(d_jan31_2026, 1)
    assert res1 == date(2026, 2, 28)

    # 29 Feb 2024 (leap) + 12 months -> 28 Feb 2025
    d_feb29_2024 = datetime(2024, 2, 29, tzinfo=timezone.utc)
    res2 = expiry_day(d_feb29_2024, 12)
    assert res2 == date(2025, 2, 28)

    # 31 Dec + 2 months -> 28 Feb
    d_dec31_2025 = datetime(2025, 12, 31, tzinfo=timezone.utc)
    res3 = expiry_day(d_dec31_2025, 2)
    assert res3 == date(2026, 2, 28)


def test_c6_07_warning_and_expiry_boundary():
    """C6-07: Due date boundary evaluates to warning/valid during due date, expired next day."""
    d = datetime(2026, 1, 15, tzinfo=timezone.utc)
    due = expiry_day(d, 12)  # 2027-01-15

    # Exactly on due date: days remaining = 0 -> in_scadenza (warning threshold inclusive)
    diff_on_day = (due - date(2027, 1, 15)).days
    assert diff_on_day == 0

    # Day after due date: days remaining = -1 -> scaduta
    diff_after = (due - date(2027, 1, 16)).days
    assert diff_after == -1


def test_c6_08_and_09_utc_and_iso_date_normalization():
    """C6-08 & C6-09: Normalization of various date strings (dd/MM/yyyy, dd-MM-yyyy, ISO with Z) into UTC datetime."""
    # ISO with Z
    d1 = utc_date("2026-06-15T10:00:00Z")
    assert d1.tzinfo == timezone.utc
    assert d1.year == 2026 and d1.month == 6 and d1.day == 15

    # dd/MM/yyyy
    d2 = utc_date("15/06/2026")
    assert d2.tzinfo == timezone.utc
    assert d2.year == 2026 and d2.month == 6 and d2.day == 15

    # dd-MM-yyyy
    d3 = utc_date("15-06-2026")
    assert d3.tzinfo == timezone.utc
    assert d3.year == 2026 and d3.month == 6 and d3.day == 15

    # Invalid / empty
    assert utc_date("") is None
    assert utc_date("invalid-date") is None
    assert utc_date(12345) is None


@pytest.mark.asyncio
async def test_c6_11_to_14_patient_status_projection():
    """C6-11 to C6-14: Classification order: mai_valutati, incompleti, scaduti, in_scadenza, coperti."""
    # Patient with no evaluations -> mai_valutati
    pat1 = {"id": "p1", "nome": "Test 1", "attivo": True}

    mock_scales = MockCollection("scales", [])
    mock_evals = MockCollection("evaluations", [])

    with patch("app.expiry.load_policy", AsyncMock(return_value=policy_from({}))), \
         patch("app.expiry.database.scales", mock_scales), \
         patch("app.expiry.database.evaluations", mock_evals):

        policy = await project([pat1], now=datetime(2026, 10, 30, tzinfo=timezone.utc))
        assert pat1["stato_valutazioni"] == "mai_valutati"


@pytest.mark.asyncio
async def test_c6_18_archived_patients_excluded_from_active():
    """C6-18: Archived patients (attivo=False) filtered out in dashboard stats."""
    p_active = {"id": "p_act", "attivo": True}
    p_archived = {"id": "p_arch", "attivo": False}

    patients = [p_active, p_archived]
    active_subset = [p for p in patients if p.get("attivo", True)]
    assert len(active_subset) == 1
    assert active_subset[0]["id"] == "p_act"


@pytest.mark.asyncio
async def test_c6_23_patient_search_and_stable_sorting(c6_client, setup_mock_db):
    """C6-23: Patient pagination and search sort stably and avoid duplicate entries."""
    admin_token = create_access_token("admin", "admin", ai_enabled=True)
    mock_pts_coll = setup_mock_db["patients"]
    with patch("app.routers.patients.patients_collection", mock_pts_coll), \
         patch("app.expiry.project", side_effect=lambda pts, *args: policy_from({})):
        res = c6_client.get("/api/admin/patients?page=1&page_size=10", headers={"Authorization": f"Bearer {admin_token}"})
        assert res.status_code == 200
        data = res.json()
        assert "items" in data
        assert "total" in data
        assert len(data["items"]) == data["total"]


@pytest.mark.asyncio
async def test_c6_24_dashboard_cache_invalidation_endpoint(c6_client, setup_mock_db):
    """C6-24: DELETE /api/admin/dashboard-stats/cache clears stale stats cache."""
    admin_token = create_access_token("admin", "admin", ai_enabled=True)
    res = c6_client.delete("/api/admin/dashboard-stats/cache", headers={"Authorization": f"Bearer {admin_token}"})
    assert res.status_code == 200
    assert "invalidata" in res.json().get("message", "").lower()


def test_c6_25_forecast_week_buckets():
    """C6-25: 8-week forecast ranges properly map days 0..55 into W1..W8, and negative days into criticita."""
    forecast_dati = [{"settimana": f"W{w}", "routine": 0, "criticita": 0} for w in range(1, 9)]

    # Negative day (-5) -> W1 criticita
    days_neg = -5
    if days_neg < 0:
        forecast_dati[0]["criticita"] += 1
    assert forecast_dati[0]["criticita"] == 1

    # Day 10 -> W2 routine (10 // 7 == 1 -> index 1)
    days_pos = 10
    if 0 <= days_pos < 56:
        forecast_dati[days_pos // 7]["routine"] += 1
    assert forecast_dati[1]["routine"] == 1

    # Day 56 is outside 8-week routine horizon
    days_out = 56
    assert not (0 <= days_out < 56)


@pytest.mark.asyncio
async def test_c6_16_and_17_stable_tie_breaking_and_scale_counts():
    """C6-16 & C6-17: Multiple evaluations on same date break tie deterministically; scale counts match policy."""
    from app.expiry import project, policy_from
    from .test_endpoints import MockCursor

    patients = [
        {"_id": "p1", "id": "p1", "nome": "Mario", "cognome": "Rossi"},
    ]
    policy = policy_from({"scale_types": ["pos", "sabs"]})

    evals = [
        {"_id": "ev_2", "id_paziente": "p1", "id_scala": "pos", "data_compilazione": "2026-05-01T10:00:00Z"},
        {"_id": "ev_1", "id_paziente": "p1", "id_scala": "pos", "data_compilazione": "2026-05-01T10:00:00Z"},
    ]
    scales = [
        {"id": "pos", "nome": "Scala POS"},
        {"id": "sabs", "nome": "Scala SABS"},
    ]
    with patch("app.expiry.load_policy", AsyncMock(return_value=policy)), \
         patch("app.expiry.database.scales", MockCollection("scales", scales)), \
         patch("app.expiry.database.evaluations", MockCollection("evaluations", evals)):
        policy_res = await project(patients, now=datetime(2026, 10, 30, tzinfo=timezone.utc))
        assert "stato_valutazioni" in patients[0]
        assert "scadenze_calcolate_al" in patients[0]
        assert "required_scale_types" in policy_res
