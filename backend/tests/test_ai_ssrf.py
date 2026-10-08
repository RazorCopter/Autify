import os
import pytest
from fastapi import HTTPException
from app.ai.ssrf import validate_base_url, normalize_base_url, is_private_ip

def test_normalize_base_url():
    assert normalize_base_url("https://ia.ghome.it/v1/") == "https://ia.ghome.it/v1"
    assert normalize_base_url("https://ia.ghome.it/v1/chat/completions") == "https://ia.ghome.it/v1"
    assert normalize_base_url("https://ia.ghome.it/v1/responses") == "https://ia.ghome.it/v1"

def test_is_private_ip():
    assert is_private_ip("127.0.0.1") is True
    assert is_private_ip("10.0.0.1") is True
    assert is_private_ip("192.168.1.100") is True
    assert is_private_ip("172.16.0.5") is True
    assert is_private_ip("8.8.8.8") is False
    assert is_private_ip("1.1.1.1") is False

def test_validate_base_url_valid_public():
    url = "https://api.openai.com/v1"
    assert validate_base_url(url) == "https://api.openai.com/v1"

def test_validate_base_url_invalid_schemes():
    with pytest.raises(HTTPException) as exc:
        validate_base_url("ftp://example.com/v1")
    assert "Schema URL non valido" in exc.value.detail

    with pytest.raises(HTTPException) as exc:
        validate_base_url("file:///etc/passwd")
    assert "Schema URL non valido" in exc.value.detail

def test_validate_base_url_rejects_credentials():
    with pytest.raises(HTTPException) as exc:
        validate_base_url("https://user:password@example.com/v1")
    assert "credenziali" in exc.value.detail

def test_validate_base_url_blocks_private_ip_by_default(monkeypatch):
    monkeypatch.delenv("ALLOW_PRIVATE_AI_ENDPOINTS", raising=False)
    with pytest.raises(HTTPException) as exc:
        validate_base_url("http://127.0.0.1:8000/v1")
    assert "non consentito" in exc.value.detail

    with pytest.raises(HTTPException) as exc:
        validate_base_url("http://10.0.1.5:8000/v1")
    assert "non consentito" in exc.value.detail

def test_validate_base_url_allows_private_ip_with_env(monkeypatch):
    monkeypatch.setenv("ALLOW_PRIVATE_AI_ENDPOINTS", "true")
    res = validate_base_url("http://127.0.0.1:8000/v1")
    assert res == "http://127.0.0.1:8000/v1"
