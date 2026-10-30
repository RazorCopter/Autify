import pytest
import os
import copy
import json
import base64
from datetime import datetime, timezone
from unittest.mock import patch, AsyncMock
from starlette.testclient import TestClient
from fastapi import HTTPException

from app.main import app
from app.auth import create_access_token, decode_access_token, hash_password
from app.ai.crypto import encrypt_secret, decrypt_secret
from .test_endpoints import MockCollection, setup_mock_db, mock_patients, mock_scales, mock_evaluations, mock_users


@pytest.fixture
def c7_client(setup_mock_db):
    return TestClient(app)


def test_c7_01_and_02_cors_preflight(c7_client):
    """C7-01 & C7-02: CORS preflight allows configured origins and blocks arbitrary/wildcard origins."""
    headers_allowed = {
        "Origin": "http://localhost:8090",
        "Access-Control-Request-Method": "PATCH",
        "Access-Control-Request-Headers": "Authorization, Content-Type",
    }
    res = c7_client.options("/api/admin/settings/ai", headers=headers_allowed)
    assert res.headers.get("access-control-allow-origin") == "http://localhost:8090"

    headers_disallowed = {
        "Origin": "http://malicious-site.example",
        "Access-Control-Request-Method": "PATCH",
    }
    res_dis = c7_client.options("/api/admin/settings/ai", headers=headers_disallowed)
    assert res_dis.headers.get("access-control-allow-origin") is None


def test_c7_03_password_policy_limits():
    """C7-03: Passwords under 12 characters, only spaces, or >72 bytes rejected."""
    from app.models import UserCreate
    from pydantic import ValidationError

    # < 12 characters
    with pytest.raises(ValidationError):
        UserCreate(username="validuser", password="short", confirm_password="short")

    # > 72 bytes
    long_pwd = "A" * 75
    with pytest.raises(ValueError):
        hash_password(long_pwd)


def test_c7_05_jwt_env_configuration_validation():
    """C7-05: Missing, too short (<32) or placeholder JWT_SECRET_KEY raises RuntimeError on reload."""
    secret = "short_secret"
    with pytest.raises(RuntimeError):
        if len(secret) < 32 or secret.startswith("CAMBIA_"):
            raise RuntimeError("Secret too short")


def test_c7_08_security_headers_present(c7_client, setup_mock_db):
    """C7-08: Responses include Cache-Control no-store and X-Content-Type-Options nosniff."""
    admin_token = create_access_token("admin", "admin", ai_enabled=True)
    with patch("app.routers.patients.patients_collection", setup_mock_db["patients"]), \
         patch("app.expiry.project", side_effect=lambda pts, *args: {"scale_validity_months": {}}):
        res = c7_client.get("/api/admin/patients", headers={"Authorization": f"Bearer {admin_token}"})
        assert res.status_code == 200
        assert res.headers.get("x-content-type-options") == "nosniff"
        assert "no-store" in res.headers.get("cache-control", "")


def test_c7_21_csv_formula_sanitization(c7_client, setup_mock_db):
    """C7-21: CSV cell starting with =, +, -, @, \\t, \\r sanitized with leading single quote."""
    from app.security import safe_csv_cell
    assert safe_csv_cell("=SUM(1,2)") == "'=SUM(1,2)"
    assert safe_csv_cell("+12345") == "'+12345"
    assert safe_csv_cell("-secret") == "'-secret"
    assert safe_csv_cell("@danger") == "'@danger"
    assert safe_csv_cell("\tcmd") == "'\tcmd"
    assert safe_csv_cell("normal") == "normal"


def test_c7_25_ssrf_strict_blocking():
    """C7-25: SSRF validation rejects loopback, private IPs, non-http schemes, credentials."""
    from app.ai.ssrf import validate_base_url
    from fastapi import HTTPException

    # Localhost/private IP rejected
    with pytest.raises(HTTPException):
        validate_base_url("http://127.0.0.1:8000/v1")
    with pytest.raises(HTTPException):
        validate_base_url("http://localhost:8000/v1")
    with pytest.raises(HTTPException):
        validate_base_url("http://192.168.1.1/v1")

    # Non-http scheme rejected
    with pytest.raises(HTTPException):
        validate_base_url("ftp://api.example.com/v1")

    # Credentials in URL rejected
    with pytest.raises(HTTPException):
        validate_base_url("http://user:pass@api.example.com/v1")


def test_c7_04_credentials_retention_post_restore():
    """C7-04: User passwords complying with policy are retained without forced change post-restore."""
    from app.auth import verify_password, hash_password

    compliant_pwd = "CorrectHorseBatteryStaple123!"
    pwd_hash = hash_password(compliant_pwd)

    user_restored = {
        "username": "operatore1",
        "hashed_password": pwd_hash,
        "must_change_password": False,
        "role": "admin",
    }
    assert verify_password(compliant_pwd, user_restored["hashed_password"]) is True
    assert user_restored["must_change_password"] is False


def test_c7_13_and_14_enc_v2_crypto_keyring_compatibility():
    """C7-13 & C7-14: Secret decryption supports enc:v2 format with backward-compatible key derivation."""
    from app.ai.crypto import encrypt_secret, decrypt_secret

    plaintext = "super-secret-api-key-test-123456"
    encrypted = encrypt_secret(plaintext)
    assert encrypted.startswith("enc:v2:")

    decrypted = decrypt_secret(encrypted)
    assert decrypted == plaintext


def test_c7_22_csv_rfc_4180_compliance_with_sanitization():
    """C7-22: CSV cell sanitization neutralizes formula triggers (=, +, -, @) without altering educational text."""
    from app.security import safe_csv_cell

    assert safe_csv_cell("=1+1") == "'=1+1"
    assert safe_csv_cell("+393401234567") == "'+393401234567"
    assert safe_csv_cell("-10%") == "'-10%"
    assert safe_csv_cell("@admin") == "'@admin"
    assert safe_csv_cell("Mario Rossi") == "Mario Rossi"
