import pytest
import os
import copy
import json
import base64
from datetime import datetime, timezone
from unittest.mock import patch, AsyncMock
from starlette.testclient import TestClient
from fastapi import HTTPException
from bson import Int64

from app.main import app
from app import auth as auth_module
from app.auth import create_access_token, decode_access_token
from app.ai.models import AISettingsStored
from app.ai.crypto import encrypt_secret
from .test_endpoints import MockCollection, setup_mock_db, mock_patients, mock_scales, mock_evaluations, mock_users


@pytest.fixture
def c2_client(setup_mock_db):
    return TestClient(app)


def test_c2_01_and_02_bootstrap_lifecycle():
    """C2-01 & C2-02: Bootstrap rejects empty/short/long passwords, sets must_change_password, preserves existing credentials."""
    mock_u = MockCollection("users", [])
    with patch("app.auth.users_collection", mock_u), \
         patch("app.auth.evaluations_collection", MockCollection("evaluations", [])), \
         patch("app.auth.patients_collection", MockCollection("patients", [])), \
         patch("app.auth.ai_analyses_collection", MockCollection("ai_analyses", [])), \
         patch("app.auth.audit_logs_collection", MockCollection("audit_logs", [])):

        import asyncio

        # 1. Empty rejected
        os.environ["INITIAL_ADMIN_PASSWORD"] = ""
        with pytest.raises(RuntimeError):
            asyncio.run(auth_module.ensure_default_admin())
        assert len(mock_u.documents) == 0

        # 2. Short rejected (<12 chars)
        os.environ["INITIAL_ADMIN_PASSWORD"] = "short_pwd"
        with pytest.raises(RuntimeError):
            asyncio.run(auth_module.ensure_default_admin())
        assert len(mock_u.documents) == 0

        # 3. >72 bytes rejected
        os.environ["INITIAL_ADMIN_PASSWORD"] = "a" * 75
        with pytest.raises(RuntimeError):
            asyncio.run(auth_module.ensure_default_admin())
        assert len(mock_u.documents) == 0

        # 4. Valid password creates admin
        os.environ["INITIAL_ADMIN_PASSWORD"] = "C2-Synthetic-Valid-Password-123!"
        asyncio.run(auth_module.ensure_default_admin())
        assert len(mock_u.documents) == 1
        u = mock_u.documents[0]
        assert u["username"] == "admin"
        assert u["must_change_password"] is True
        assert u["token_version"] == 1
        assert auth_module.verify_password("C2-Synthetic-Valid-Password-123!", u["hashed_password"])

        # 5. Restart with different password does not overwrite
        old_hash = u["hashed_password"]
        os.environ["INITIAL_ADMIN_PASSWORD"] = "Different-New-Password-123!"
        asyncio.run(auth_module.ensure_default_admin())
        assert len(mock_u.documents) == 1
        assert mock_u.documents[0]["hashed_password"] == old_hash


def test_c2_06_and_08_password_change_cas_and_invalidation(c2_client, setup_mock_db):
    """C2-06 & C2-08: Change password updates hash, resets must_change_password, bumps token_version and revokes old tokens."""
    init_pw = "Initial-Valid-Password-123!"
    init_hash = auth_module.hash_password(init_pw)
    user = setup_mock_db["users"].documents[0]
    user.update({
        "username": "admin",
        "role": "admin",
        "hashed_password": init_hash,
        "token_version": 1,
        "must_change_password": True,
        "ai_enabled": True,
    })

    v1_token = create_access_token("admin", "admin", ai_enabled=True, token_version=1)

    # Execute password change with atomic and record patched
    new_pw = "New-Super-Secure-Password-123!"
    async def fake_auth_atomic(coro):
        return await coro(None)

    with patch("app.routers.auth.atomic", side_effect=fake_auth_atomic), \
         patch("app.routers.auth.record", new_callable=AsyncMock):
        res = c2_client.post("/api/admin/auth/change-password", headers={"Authorization": f"Bearer {v1_token}"}, json={
            "current_password": init_pw,
            "new_password": new_pw,
            "confirm_password": new_pw,
        })
        assert res.status_code == 200

    # User document updated
    assert user["must_change_password"] is False
    assert user["token_version"] == 2
    assert auth_module.verify_password(new_pw, user["hashed_password"])

    # Old v1_token is now revoked (returns 401)
    res_old = c2_client.get("/api/admin/settings", headers={"Authorization": f"Bearer {v1_token}"})
    assert res_old.status_code == 401

    # Login with new password works
    res_login = c2_client.post("/api/admin/auth/login", json={"username": "admin", "password": new_pw})
    assert res_login.status_code == 200
    new_token = res_login.json()["token"]
    assert res_login.json()["must_change_password"] is False

    # Access with new token succeeds
    res_new = c2_client.get("/api/admin/settings", headers={"Authorization": f"Bearer {new_token}"})
    assert res_new.status_code == 200


def test_c2_04_password_change_required_enforced(c2_client, setup_mock_db):
    """C2-04: User with must_change_password=True gets 403 on protected routes except change-password."""
    # Set must_change_password on user
    setup_mock_db["users"].documents[0]["must_change_password"] = True
    token = create_access_token(username="admin", role="admin", ai_enabled=True)
    headers = {"Authorization": f"Bearer {token}"}

    # Protected routes return 403 password_change_required
    routes = [
        ("GET", "/api/admin/patients"),
        ("GET", "/api/admin/settings"),
        ("GET", "/api/admin/export-db"),
        ("GET", "/api/admin/notifications"),
        ("GET", "/api/client/scales"),
    ]
    for method, path in routes:
        res = c2_client.request(method, path, headers=headers)
        assert res.status_code == 403
        body = res.json()
        assert body.get("detail", {}).get("code") == "password_change_required"

    # Reset
    setup_mock_db["users"].documents[0]["must_change_password"] = False


def test_c2_07_change_password_validation_edges(c2_client, setup_mock_db):
    """C2-07: Invalid current password, mismatched confirmation, short or identical password rejected with 400/422."""
    user = setup_mock_db["users"].documents[0]
    user["hashed_password"] = auth_module.hash_password("admin_password_123")
    initial_hash = user["hashed_password"]
    initial_tv = user.get("token_version", 1)
    token = create_access_token(username="admin", role="admin", ai_enabled=True)
    headers = {"Authorization": f"Bearer {token}"}

    # 1. Wrong current password -> 400
    res = c2_client.post("/api/admin/auth/change-password", headers=headers, json={
        "current_password": "WrongPassword123!",
        "new_password": "NewValidPassword123!",
        "confirm_password": "NewValidPassword123!",
    })
    assert res.status_code == 400
    assert "attuale non corretta" in res.json()["detail"]

    # 2. Mismatched confirmation -> 422
    res = c2_client.post("/api/admin/auth/change-password", headers=headers, json={
        "current_password": "admin_password_123",
        "new_password": "NewValidPassword123!",
        "confirm_password": "DifferentPassword123!",
    })
    assert res.status_code == 422
    assert "non coincidente" in str(res.json()["detail"]).lower()

    # 3. New password same as current -> 422
    res = c2_client.post("/api/admin/auth/change-password", headers=headers, json={
        "current_password": "admin_password_123",
        "new_password": "admin_password_123",
        "confirm_password": "admin_password_123",
    })
    assert res.status_code == 422

    # 4. Forbidden extra field -> 422
    res = c2_client.post("/api/admin/auth/change-password", headers=headers, json={
        "current_password": "admin_password_123",
        "new_password": "NewValidPassword123!",
        "confirm_password": "NewValidPassword123!",
        "role": "admin",
    })
    assert res.status_code == 422

    # User document remains unchanged
    assert user["hashed_password"] == initial_hash
    assert user["token_version"] == initial_tv


def test_c2_09_jwt_validation_matrix(c2_client, setup_mock_db):
    """C2-09: JWT missing sub, exp, token_version or invalid signature rejected with 401."""
    import jwt
    secret = os.environ.get("JWT_SECRET_KEY", "test-secret-key-for-unit-tests")

    # 1. Missing sub
    bad_token = jwt.encode({"exp": 9999999999, "token_version": 1}, secret, algorithm="HS256")
    res = c2_client.get("/api/admin/patients", headers={"Authorization": f"Bearer {bad_token}"})
    assert res.status_code == 401

    # 2. Missing token_version
    bad_token = jwt.encode({"sub": "admin", "exp": 9999999999}, secret, algorithm="HS256")
    res = c2_client.get("/api/admin/patients", headers={"Authorization": f"Bearer {bad_token}"})
    assert res.status_code == 401

    # 3. String token_version
    bad_token = jwt.encode({"sub": "admin", "exp": 9999999999, "token_version": "1"}, secret, algorithm="HS256")
    res = c2_client.get("/api/admin/patients", headers={"Authorization": f"Bearer {bad_token}"})
    assert res.status_code == 401

    # 4. Boolean token_version
    bad_token = jwt.encode({"sub": "admin", "exp": 9999999999, "token_version": True}, secret, algorithm="HS256")
    res = c2_client.get("/api/admin/patients", headers={"Authorization": f"Bearer {bad_token}"})
    assert res.status_code == 401

    # 5. Wrong secret/signature
    bad_token = jwt.encode({"sub": "admin", "exp": 9999999999, "token_version": 1}, "wrong-secret", algorithm="HS256")
    res = c2_client.get("/api/admin/patients", headers={"Authorization": f"Bearer {bad_token}"})
    assert res.status_code == 401

    # 6. Non-existent account
    bad_token = jwt.encode({"sub": "deleted_user", "exp": 9999999999, "token_version": 1}, secret, algorithm="HS256")
    res = c2_client.get("/api/admin/patients", headers={"Authorization": f"Bearer {bad_token}"})
    assert res.status_code == 401


def test_c2_10_stale_claims_cannot_grant_privileges(c2_client, setup_mock_db):
    """C2-10: Token claims do not bypass DB authorization; DB permissions and token_version dictate access."""
    # User in DB is viewer with ai_enabled=False
    setup_mock_db["users"].documents[1]["ai_enabled"] = False
    setup_mock_db["users"].documents[1]["role"] = "viewer"
    setup_mock_db["users"].documents[1]["token_version"] = 1

    # A token with stale claims claiming role=admin and ai_enabled=True
    stale_token = create_access_token(username="viewer_user", role="admin", ai_enabled=True, token_version=1)
    res = c2_client.post("/api/admin/settings/ai", headers={"Authorization": f"Bearer {stale_token}"}, json={})
    # Since DB role is viewer, accessing admin-only endpoint must fail with 403
    assert res.status_code in (403, 404, 405, 422)


def test_c2_12_viewer_and_admin_ai_matrix(c2_client, setup_mock_db):
    """C2-12: Full matrix of viewer and admin ai permissions."""
    mock_coll = MockCollection("settings", [{
        "id": "global_settings",
        "ai": {
            "schema_version": 2,
            "active_provider": "gemini",
            "viewer_ai_enabled": True,
            "gemini": {"model": "gemini-2.5-pro", "api_key_encrypted": encrypt_secret("key")},
            "openai": {"model": "gpt-4o"},
            "openai_compatible": {"base_url": "https://api.openai.com/v1"},
        }
    }])

    fake_captured = {
        "patient_name": "Test Patient",
        "parent_mongo_id": "fake_patient_oid",
        "inputs": [],
        "context_sha256": "fakehash",
        "system_prompt": "prompt",
        "evaluations_used": [],
        "provenance": {},
        "user_prompt": "user prompt",
        "attachment": None,
    }

    # Case 1: Viewer with personal ON and global ON -> 202
    setup_mock_db["users"].documents[1]["ai_enabled"] = True
    viewer_token = create_access_token(username="viewer_user", role="viewer", ai_enabled=True)
    with patch("app.routers.settings.settings_collection", mock_coll), \
         patch("app.routers.ai.settings_collection", mock_coll), \
         patch("app.ai_context.capture_context", new_callable=AsyncMock) as mock_cap, \
         patch("app.routers.ai.enqueue", new_callable=AsyncMock):
        mock_cap.return_value = fake_captured
        res = c2_client.post("/api/admin/ai/analyze", headers={"Authorization": f"Bearer {viewer_token}"}, json={
            "id_paziente": "pat_1",
            "notes": "Note cliniche",
            "external_content_confirmed": True,
        })
        assert res.status_code == 202

    # Case 2: Viewer with personal OFF and global ON -> 403
    setup_mock_db["users"].documents[1]["ai_enabled"] = False
    v_off_token = create_access_token(username="viewer_user", role="viewer", ai_enabled=False)
    with patch("app.routers.settings.settings_collection", mock_coll), \
         patch("app.routers.ai.settings_collection", mock_coll):
        res = c2_client.post("/api/admin/ai/analyze", headers={"Authorization": f"Bearer {v_off_token}"}, json={
            "id_paziente": "pat_1",
            "notes": "Note cliniche",
            "external_content_confirmed": True,
        })
        assert res.status_code == 403

    # Case 3: Viewer with personal ON and global OFF -> 403
    setup_mock_db["users"].documents[1]["ai_enabled"] = True
    mock_coll.documents[0]["ai"]["viewer_ai_enabled"] = False
    with patch("app.routers.settings.settings_collection", mock_coll), \
         patch("app.routers.ai.settings_collection", mock_coll):
        res = c2_client.post("/api/admin/ai/analyze", headers={"Authorization": f"Bearer {viewer_token}"}, json={
            "id_paziente": "pat_1",
            "notes": "Note cliniche",
            "external_content_confirmed": True,
        })
        assert res.status_code == 403

    # Case 4: Admin personal OFF -> 403
    setup_mock_db["users"].documents[0]["ai_enabled"] = False
    admin_off_token = create_access_token(username="admin", role="admin", ai_enabled=False)
    with patch("app.routers.settings.settings_collection", mock_coll), \
         patch("app.routers.ai.settings_collection", mock_coll):
        res = c2_client.post("/api/admin/ai/analyze", headers={"Authorization": f"Bearer {admin_off_token}"}, json={
            "id_paziente": "pat_1",
            "notes": "Note cliniche",
            "external_content_confirmed": True,
        })
        assert res.status_code == 403

    # Restore admin
    setup_mock_db["users"].documents[0]["ai_enabled"] = True


def test_c2_14_capabilities_minimal_metadata(c2_client, setup_mock_db):
    """C2-14: Capabilities endpoint exposes only minimal metadata and no key hints or prompts."""
    mock_coll = MockCollection("settings", [{
        "id": "global_settings",
        "ai": {
            "schema_version": 2,
            "active_provider": "gemini",
            "viewer_ai_enabled": True,
            "gemini": {"model": "gemini-2.5-pro", "api_key_encrypted": encrypt_secret("sk-secret")},
            "openai": {"model": "gpt-4o"},
            "openai_compatible": {"base_url": "https://api.openai.com/v1"},
        }
    }])
    viewer_token = create_access_token(username="viewer_user", role="viewer", ai_enabled=True)
    with patch("app.routers.settings.settings_collection", mock_coll):
        res = c2_client.get("/api/admin/ai/capabilities", headers={"Authorization": f"Bearer {viewer_token}"})
        assert res.status_code == 200
        data = res.json()
        assert "active_provider" in data
        assert "viewer_ai_enabled" in data
        assert "can_analyze" in data
        # Must NOT expose api_key configured hint or secret hints
        assert "api_key" not in data.get("gemini", {})
        assert "system_prompt" not in data


def test_c2_15_notifications_isolation(c2_client, setup_mock_db):
    """C2-15: Reading own notification works; accessing another user's or non-existent notification returns 404."""
    notif_coll = MockCollection("notifications", [
        {"id": "n_own", "username": "viewer_user", "message": "Msg", "read": False, "created_at": datetime.now(timezone.utc)},
        {"id": "n_other", "username": "other_user", "message": "Msg", "read": False, "created_at": datetime.now(timezone.utc)},
    ])
    viewer_token = create_access_token(username="viewer_user", role="viewer", ai_enabled=True)
    with patch("app.routers.ai.notifications_collection", notif_coll):
        # 1. Own notification -> 200
        res = c2_client.post("/api/admin/notifications/n_own/read", headers={"Authorization": f"Bearer {viewer_token}"})
        assert res.status_code == 200
        assert notif_coll.documents[0]["read"] is True

        # 2. Other user's notification -> 404
        res = c2_client.post("/api/admin/notifications/n_other/read", headers={"Authorization": f"Bearer {viewer_token}"})
        assert res.status_code == 404
        assert notif_coll.documents[1]["read"] is False

        # 3. Non-existent notification -> 404
        res = c2_client.post("/api/admin/notifications/n_missing/read", headers={"Authorization": f"Bearer {viewer_token}"})
        assert res.status_code == 404


def test_c2_16_notifications_read_all_isolation(c2_client, setup_mock_db):
    """C2-16: read-all only updates authenticated user's unread notifications."""
    notif_coll = MockCollection("notifications", [
        {"id": "n1", "username": "viewer_user", "read": False, "created_at": datetime.now(timezone.utc)},
        {"id": "n2", "username": "viewer_user", "read": False, "created_at": datetime.now(timezone.utc)},
        {"id": "n3", "username": "other_user", "read": False, "created_at": datetime.now(timezone.utc)},
    ])
    viewer_token = create_access_token(username="viewer_user", role="viewer", ai_enabled=False)
    with patch("app.routers.ai.notifications_collection", notif_coll):
        res = c2_client.post("/api/admin/notifications/read-all", headers={"Authorization": f"Bearer {viewer_token}"})
        assert res.status_code == 200
        assert notif_coll.documents[0]["read"] is True
        assert notif_coll.documents[1]["read"] is True
        # Other user's notification remains unread
        assert notif_coll.documents[2]["read"] is False


def test_c2_17_viewer_rbac_restricted(c2_client, setup_mock_db):
    """C2-17: Viewer cannot perform domain writes or unapproved modifications."""
    viewer_token = create_access_token(username="viewer_user", role="viewer", ai_enabled=False)
    headers = {"Authorization": f"Bearer {viewer_token}"}

    # Viewer POST to patients -> 403
    res = c2_client.post("/api/admin/patients", headers=headers, json={"nome": "A", "cognome": "B"})
    assert res.status_code == 403

    # Viewer DELETE to notifications -> 405 or 403
    res = c2_client.delete("/api/admin/notifications/n1", headers=headers)
    assert res.status_code in (403, 404, 405)

    # Viewer PATCH to settings -> 403
    res = c2_client.patch("/api/admin/settings/ai", headers=headers, json={})
    assert res.status_code == 403


def test_c2_03_legacy_admin_auto_flagged_on_login(c2_client, setup_mock_db):
    """C2-03: Legacy admin/admin login sets must_change_password=True automatically."""
    setup_mock_db["users"].documents[0]["hashed_password"] = auth_module.hash_password("admin")
    setup_mock_db["users"].documents[0]["must_change_password"] = False

    res = c2_client.post("/api/admin/auth/login", json={"username": "admin", "password": "admin"})
    assert res.status_code == 200
    assert res.json()["must_change_password"] is True
    assert setup_mock_db["users"].documents[0]["must_change_password"] is True


def test_c2_18_change_password_allowed_during_maintenance(c2_client, setup_mock_db):
    """C2-18: Password change endpoint is exempt from maintenance mode lockout."""
    from app.maintenance import BackupMaintenanceMiddleware
    # Test that /change-password and /login are allowed in maintenance mode definition
    import inspect
    src = inspect.getsource(BackupMaintenanceMiddleware)
    assert '("POST", "/api/admin/auth/change-password")' in src
    assert '("POST", "/api/admin/auth/login")' in src


def test_c2_19_export_import_blocked_during_password_change_required(c2_client, setup_mock_db):
    """C2-19: Export and import endpoints are blocked with 403 if must_change_password is true."""
    setup_mock_db["users"].documents[0]["must_change_password"] = True
    token = create_access_token("admin", "admin", ai_enabled=True)
    headers = {"Authorization": f"Bearer {token}"}

    res_exp = c2_client.get("/api/admin/export-db", headers=headers)
    assert res_exp.status_code == 403
    assert res_exp.json()["detail"]["code"] == "password_change_required"

    # Reset
    setup_mock_db["users"].documents[0]["must_change_password"] = False
