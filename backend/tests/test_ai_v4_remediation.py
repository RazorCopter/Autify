import base64
import json
import os
import pytest
from unittest.mock import AsyncMock, patch
from fastapi import HTTPException
from fastapi.testclient import TestClient
import httpx

from app.main import app
from app.auth import create_access_token
from app.ai.crypto import encrypt_secret, decrypt_secret, mask_secret
from app.ai.ssrf import validate_base_url, normalize_base_url
from app.ai.models import AIAttachment, AIGenerationSettings, AISettingsStored
from app.ai.adapters.openai import OpenAIAdapter
from app.ai.adapters.openai_compatible import OpenAICompatibleAdapter
from app.ai.adapters.gemini import GeminiAdapter
from .test_endpoints import MockCollection, setup_mock_db, mock_patients, mock_scales, mock_evaluations, mock_users


# ==============================================================================
# 1. MODEL DISCOVERY TESTS
# ==============================================================================

@pytest.mark.anyio
async def test_openai_compatible_fetch_available_models_success(monkeypatch):
    adapter = OpenAICompatibleAdapter(
        base_url="https://api.openai.com/v1",
        api_key="test-key",
    )

    models_payload = {
        "data": [
            {"id": "model-zeta"},
            {"id": "model-alpha"},
            {"id": "model-beta"},
        ]
    }

    async def mock_get(client_self, url, *args, **kwargs):
        req = httpx.Request("GET", str(url))
        return httpx.Response(200, json=models_payload, request=req)

    monkeypatch.setattr(httpx.AsyncClient, "get", mock_get)

    models = await adapter.fetch_available_models()
    assert models == ["model-alpha", "model-beta", "model-zeta"]


@pytest.mark.anyio
async def test_openai_compatible_fetch_models_fallback_v1(monkeypatch):
    adapter = OpenAICompatibleAdapter(
        base_url="https://gateway.example.com",
        api_key="test-key",
    )

    async def mock_get(client_self, url, *args, **kwargs):
        req = httpx.Request("GET", str(url))
        if str(url) == "https://gateway.example.com/models":
            return httpx.Response(404, text="Not found", request=req)
        elif str(url) == "https://gateway.example.com/v1/models":
            return httpx.Response(200, json={"data": [{"id": "cx/gpt-5.6"}]}, request=req)
        return httpx.Response(404, request=req)

    monkeypatch.setattr(httpx.AsyncClient, "get", mock_get)

    models = await adapter.fetch_available_models()
    assert models == ["cx/gpt-5.6"]


def test_discover_models_admin_endpoint(setup_mock_db):
    admin_token = create_access_token(username="admin", role="admin", ai_enabled=True)
    c = TestClient(app)
    c.headers.update({"Authorization": f"Bearer {admin_token}"})

    with patch.object(OpenAICompatibleAdapter, "fetch_available_models", AsyncMock(return_value=["model-1", "model-2"])):
        res = c.post("/api/admin/ai/openai-compatible/models", json={
            "base_url": "https://api.openai.com/v1",
            "api_key": "custom-key",
        })
        assert res.status_code == 200
        data = res.json()
        assert data["models"] == ["model-1", "model-2"]
        assert data["count"] == 2


# ==============================================================================
# 2. CUSTOM HEADERS ENCRYPTION & MASKING
# ==============================================================================

def test_custom_headers_encryption_and_masking_roundtrip(setup_mock_db):
    admin_token = create_access_token(username="admin", role="admin", ai_enabled=True)
    c = TestClient(app)
    c.headers.update({"Authorization": f"Bearer {admin_token}"})

    mock_settings_coll = MockCollection("settings", [])
    with patch("app.routers.settings.settings_collection", mock_settings_coll):
        # 1. PATCH custom headers
        patch_res = c.patch("/api/admin/settings/ai", json={
            "openai_compatible": {
                "base_url": "https://api.openai.com/v1",
                "custom_headers": {
                    "X-Api-Secret": "super-confidential-token-12345",
                    "X-Tenant": "tenant-42",
                }
            }
        })
        assert patch_res.status_code == 200

        # DB must contain encrypted headers (enc:v1:), never plaintext
        saved_doc = mock_settings_coll.documents[0]
        db_headers = saved_doc["ai"]["openai_compatible"]["custom_headers"]
        assert db_headers["X-Api-Secret"].startswith("enc:v1:")
        assert "super-confidential" not in db_headers["X-Api-Secret"]
        assert decrypt_secret(db_headers["X-Api-Secret"]) == "super-confidential-token-12345"

        # 2. GET Settings: must return masked metadata
        get_res = c.get("/api/admin/settings/ai")
        assert get_res.status_code == 200
        masked_headers = get_res.json()["openai_compatible"]["custom_headers"]
        assert "super-confidential-token-12345" not in masked_headers["X-Api-Secret"]
        assert masked_headers["X-Api-Secret"].endswith("...") or "..." in masked_headers["X-Api-Secret"]

        # 3. PATCH preserving masked header without re-entering secret
        second_patch = c.patch("/api/admin/settings/ai", json={
            "openai_compatible": {
                "custom_headers": {
                    "X-Api-Secret": masked_headers["X-Api-Secret"],
                    "X-Tenant": "tenant-updated",
                }
            }
        })
        assert second_patch.status_code == 200
        # Secret in DB must remain intact
        updated_db_headers = mock_settings_coll.documents[0]["ai"]["openai_compatible"]["custom_headers"]
        assert decrypt_secret(updated_db_headers["X-Api-Secret"]) == "super-confidential-token-12345"


def test_custom_headers_validation_rejects_crlf_and_host(setup_mock_db):
    admin_token = create_access_token(username="admin", role="admin", ai_enabled=True)
    c = TestClient(app)
    c.headers.update({"Authorization": f"Bearer {admin_token}"})

    # CRLF injection attempt
    res_crlf = c.patch("/api/admin/settings/ai", json={
        "openai_compatible": {
            "custom_headers": {"X-Injected": "val\r\nInjected: true"}
        }
    })
    assert res_crlf.status_code == 422

    # Forbidden Host header override
    res_host = c.patch("/api/admin/settings/ai", json={
        "openai_compatible": {
            "custom_headers": {"Host": "malicious.com"}
        }
    })
    assert res_host.status_code == 422



# ==============================================================================
# 3. VIEWER AI POLICY & PROMPT OVERRIDE TESTS
# ==============================================================================

def test_viewer_ai_policy_enforcement(setup_mock_db):
    mock_coll = MockCollection("settings", [{
        "id": "global_settings",
        "ai": {
            "schema_version": 2,
            "active_provider": "gemini",
            "viewer_ai_enabled": True,
            "gemini": {"model": "gemini-2.5-pro", "api_key_encrypted": encrypt_secret("test-key")},
            "openai": {"model": "gpt-4o"},
            "openai_compatible": {"base_url": "https://api.openai.com/v1"},
        }
    }])

    # 1. Viewer with ai_enabled=True and global viewer_ai_enabled=True -> Can analyze
    viewer_enabled_token = create_access_token(username="viewer_user", role="viewer", ai_enabled=True)
    c = TestClient(app)
    c.headers.update({"Authorization": f"Bearer {viewer_enabled_token}"})

    with patch("app.routers.settings.settings_collection", mock_coll), \
         patch("app.routers.ai.settings_collection", mock_coll), \
         patch("app.routers.ai.get_ai_adapter") as mock_adapter_getter:

        mock_ad = AsyncMock()
        mock_ad.generate.return_value = ("Report generated", {"total_tokens": 10})
        mock_adapter_getter.return_value = mock_ad

        res = c.post("/api/admin/ai/analyze", json={
            "id_paziente": "pat_1",
            "notes": "Note cliniche per analisi",
        })
        assert res.status_code == 200
        assert res.json()["report"] == "Report generated"

        # 2. Viewer trying to override system prompt -> 403 Forbidden
        res_override = c.post("/api/admin/ai/analyze", json={
            "id_paziente": "pat_1",
            "notes": "Note cliniche",
            "system_prompt": "You are a malicious system prompt",
        })
        assert res_override.status_code == 403
        assert "non sono autorizzati a personalizzare il prompt" in res_override.json()["detail"]

    # 3. Viewer with ai_enabled=False -> 403 Forbidden
    viewer_disabled_token = create_access_token(username="viewer_user", role="viewer", ai_enabled=False)
    c.headers.update({"Authorization": f"Bearer {viewer_disabled_token}"})
    with patch("app.routers.settings.settings_collection", mock_coll), \
         patch("app.routers.ai.settings_collection", mock_coll):
        res_no_ai = c.post("/api/admin/ai/analyze", json={
            "id_paziente": "pat_1",
            "notes": "Note cliniche",
        })
        assert res_no_ai.status_code == 403

    # 4. Global viewer_ai_enabled=False -> 403 Forbidden even if user ai_enabled=True
    mock_coll.documents[0]["ai"]["viewer_ai_enabled"] = False
    c.headers.update({"Authorization": f"Bearer {viewer_enabled_token}"})
    with patch("app.routers.settings.settings_collection", mock_coll), \
         patch("app.routers.ai.settings_collection", mock_coll):
        res_glob_disabled = c.post("/api/admin/ai/analyze", json={
            "id_paziente": "pat_1",
            "notes": "Note cliniche",
        })
        assert res_glob_disabled.status_code == 403
        assert "disabilitato a livello globale" in res_glob_disabled.json()["detail"]



def test_discover_models_forbidden_for_viewer(setup_mock_db):
    viewer_token = create_access_token(username="viewer_user", role="viewer", ai_enabled=True)


# ==============================================================================
# 4. ATTACHMENT CAPABILITY & VALIDATION TESTS
# ==============================================================================

def test_attachment_validation_rejects_invalid_inputs():
    # 1. Non-base64 characters
    with pytest.raises(ValueError):
        AIAttachment(filename="doc.txt", data_base64="not-valid-base64-content!#%")

    # 2. Disallowed extension
    valid_b64 = base64.b64encode(b"hello world").decode("utf-8")
    with pytest.raises(ValueError) as exc:
        AIAttachment(filename="malware.exe", extension="exe", data_base64=valid_b64)
    assert "non consentita" in str(exc.value)

    # 3. Disallowed MIME type
    with pytest.raises(ValueError) as exc:
        AIAttachment(filename="file.bin", mime_type="application/x-dosexec", data_base64=valid_b64)
    assert "non consentito" in str(exc.value)


@pytest.mark.anyio
async def test_adapter_rejects_unsupported_attachments():
    # OpenAI Chat Completions rejects PDF (only image is supported)
    pdf_b64 = base64.b64encode(b"%PDF-1.4 dummy").decode("utf-8")
    pdf_att = AIAttachment(filename="doc.pdf", extension="pdf", mime_type="application/pdf", data_base64=pdf_b64)
    openai_ad = OpenAIAdapter(api_key="test-key")

    with pytest.raises(HTTPException) as exc:
        await openai_ad.generate("sys", "user", attachment=pdf_att)
    assert exc.value.status_code == 400
    assert "supporta solo allegati di tipo immagine" in exc.value.detail

    # OpenAI-Compatible rejects PDF (supports images and text)
    compat_ad = OpenAICompatibleAdapter(base_url="https://api.openai.com/v1", api_key="test-key")
    with pytest.raises(HTTPException) as exc_c:
        await compat_ad.generate("sys", "user", attachment=pdf_att)
    assert exc_c.value.status_code == 400
    assert "non supporta allegati con formato" in exc_c.value.detail


# ==============================================================================
# 5. OPENAI RESPONSES PROTOCOL TESTS
# ==============================================================================

@pytest.mark.anyio
async def test_openai_responses_protocol(monkeypatch):
    adapter = OpenAIAdapter(
        api_key="test-key",
        model="gpt-4o",
        protocol="responses",
    )

    captured_url = []
    captured_payload = []

    async def mock_post(client_self, url, *args, **kwargs):
        captured_url.append(str(url))
        captured_payload.append(kwargs.get("json", {}))
        req = httpx.Request("POST", str(url))
        resp_data = {
            "output": [
                {
                    "type": "message",
                    "content": [{"type": "output_text", "text": "Responses protocol answer"}]
                }
            ],
            "usage": {"input_tokens": 50, "output_tokens": 20, "total_tokens": 70}
        }
        return httpx.Response(200, json=resp_data, request=req)

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    text, usage = await adapter.generate("system instructions", "user query")
    assert text == "Responses protocol answer"
    assert "responses" in captured_url[0]
    assert "input" in captured_payload[0]
    assert usage["total_tokens"] == 70


# ==============================================================================
# 6. SSRF ALLOWLIST TESTS
# ==============================================================================

def test_ssrf_allowlist_enforcement(monkeypatch):
    monkeypatch.setenv("ALLOWED_AI_HOSTS", "api.openai.com,together.xyz,ia.ghome.it")

    # Allowed exact and subdomain
    assert validate_base_url("https://api.openai.com/v1") == "https://api.openai.com/v1"
    assert validate_base_url("https://sub.together.xyz/v1") == "https://sub.together.xyz/v1"
    assert validate_base_url("https://ia.ghome.it/v1") == "https://ia.ghome.it/v1"

    # Blocked host
    with pytest.raises(HTTPException) as exc:
        validate_base_url("https://malicious-host.com/v1")
    assert "whitelist" in exc.value.detail.lower() or "allowed_ai_hosts" in exc.value.detail.lower()


# ==============================================================================
# 5. MASKED CREDENTIALS RESOLUTION & AT-REST MIGRATION & AUDIT TESTS
# ==============================================================================

def test_masked_credentials_resolved_in_test_connection_and_discovery(setup_mock_db, monkeypatch):
    admin_token = create_access_token(username="admin", role="admin", ai_enabled=True)
    c = TestClient(app)
    c.headers.update({"Authorization": f"Bearer {admin_token}"})

    real_key = "sk-super-secret-key-12345678"
    real_header = "super-secret-header-token-888"

    stored_ai = AISettingsStored()
    stored_ai.active_provider = "openai_compatible"
    stored_ai.openai_compatible.base_url = "https://api.openai.com/v1"
    stored_ai.openai_compatible.api_key_encrypted = encrypt_secret(real_key)
    stored_ai.openai_compatible.custom_headers = {
        "X-Secret-Token": encrypt_secret(real_header),
    }

    mock_settings_coll = MockCollection("settings", [{
        "id": "global_settings",
        "ai": stored_ai.model_dump(),
    }])
    mock_audit_coll = MockCollection("audit_logs", [])

    recorded_headers = {}

    async def mock_post(client_self, url, *args, **kwargs):
        headers = kwargs.get("headers", {})
        recorded_headers.update(dict(headers))
        req = httpx.Request("POST", str(url))
        resp_json = {
            "choices": [{"message": {"content": "ok"}}],
            "usage": {"total_tokens": 10},
        }
        return httpx.Response(200, json=resp_json, request=req)

    async def mock_get(client_self, url, *args, **kwargs):
        headers = kwargs.get("headers", {})
        recorded_headers.update(dict(headers))
        req = httpx.Request("GET", str(url))
        resp_json = {"data": [{"id": "model-xyz"}]}
        return httpx.Response(200, json=resp_json, request=req)

    monkeypatch.setattr("httpx.AsyncClient.post", mock_post)
    monkeypatch.setattr("httpx.AsyncClient.get", mock_get)

    with patch("app.routers.settings.settings_collection", mock_settings_coll), \
         patch("app.routers.ai.settings_collection", mock_settings_coll), \
         patch("app.routers._helpers.audit_logs_collection", mock_audit_coll), \
         patch("app.routers.ai.audit_logs_collection", mock_audit_coll):

        # 1. Test connection with masked API key and masked custom header
        conn_res = c.post("/api/admin/ai/test-connection", json={
            "provider": "openai_compatible",
            "api_key": mask_secret(real_key),  # Masked!
            "custom_headers": {
                "X-Secret-Token": mask_secret(real_header),  # Masked!
            },
        })
        assert conn_res.status_code == 200
        assert conn_res.json()["success"] is True

        # Assert upstream request received the DECRYPTED secrets, not masks!
        assert recorded_headers.get("Authorization") == f"Bearer {real_key}"
        assert recorded_headers.get("X-Secret-Token") == real_header

        # 2. Model discovery with masked API key and masked custom header
        recorded_headers.clear()
        disc_res = c.post("/api/admin/ai/openai-compatible/models", json={
            "api_key": "***",  # Masked wildcard!
            "custom_headers": {
                "X-Secret-Token": "...",  # Masked ellipsis!
            },
        })
        assert disc_res.status_code == 200
        assert disc_res.json()["models"] == ["model-xyz"]

        # Assert upstream request received the DECRYPTED secrets!
        assert recorded_headers.get("Authorization") == f"Bearer {real_key}"
        assert recorded_headers.get("X-Secret-Token") == real_header

        # Assert audit logs were written for both actions
        audit_actions = [doc.get("azione") for doc in mock_audit_coll.documents]
        assert "AI_TEST_CONNECTION" in audit_actions
        assert "AI_DISCOVER_MODELS" in audit_actions


def test_legacy_settings_endpoint_does_not_leak_ai_document(setup_mock_db):
    admin_token = create_access_token(username="admin", role="admin", ai_enabled=True)
    c = TestClient(app)
    c.headers.update({"Authorization": f"Bearer {admin_token}"})

    mock_settings_coll = MockCollection("settings", [{
        "id": "global_settings",
        "gemini_api_key": "legacy-plain-key",
        "chatgpt_api_key": "legacy-plain-chatgpt",
        "ai": {
            "schema_version": 2,
            "openai_compatible": {
                "api_key_encrypted": encrypt_secret("confidential-secret"),
                "custom_headers": {"X-Secret": encrypt_secret("secret-val")},
            },
        },
    }])

    with patch("app.routers.settings.settings_collection", mock_settings_coll):
        res = c.get("/api/admin/settings")
        assert res.status_code == 200
        data = res.json()
        assert data.get("gemini_api_key") is None
        assert data.get("chatgpt_api_key") is None
        assert data.get("ai") is None


@pytest.mark.anyio
async def test_get_or_migrate_encrypts_unencrypted_secrets_at_rest():
    from app.routers.settings import get_or_migrate_ai_settings

    # Simulate existing DB document with plain unencrypted credentials
    mock_settings_coll = MockCollection("settings", [{
        "id": "global_settings",
        "ai": {
            "schema_version": 2,
            "active_provider": "gemini",
            "gemini": {
                "model": "gemini-2.5-pro",
                "api_key_encrypted": "plain-unencrypted-gemini-key",
            },
            "openai": {
                "model": "gpt-4o",
                "api_key_encrypted": "plain-unencrypted-openai-key",
            },
            "openai_compatible": {
                "base_url": "https://api.openai.com/v1",
                "model": "gpt-4o",
                "api_key_encrypted": "plain-unencrypted-compat-key",
                "custom_headers": {
                    "X-Header-Secret": "plain-unencrypted-header-secret",
                },
            },
        },
    }])

    with patch("app.routers.settings.settings_collection", mock_settings_coll):
        stored = await get_or_migrate_ai_settings()

        # In-memory returned object must have valid decrypted values
        assert decrypt_secret(stored.gemini.api_key_encrypted) == "plain-unencrypted-gemini-key"
        assert decrypt_secret(stored.openai.api_key_encrypted) == "plain-unencrypted-openai-key"
        assert decrypt_secret(stored.openai_compatible.api_key_encrypted) == "plain-unencrypted-compat-key"
        assert decrypt_secret(stored.openai_compatible.custom_headers["X-Header-Secret"]) == "plain-unencrypted-header-secret"

        # Database document MUST have been updated with enc:v1: tokens
        db_doc = mock_settings_coll.documents[0]["ai"]
        assert db_doc["gemini"]["api_key_encrypted"].startswith("enc:v1:")
        assert db_doc["openai"]["api_key_encrypted"].startswith("enc:v1:")
        assert db_doc["openai_compatible"]["api_key_encrypted"].startswith("enc:v1:")
        assert db_doc["openai_compatible"]["custom_headers"]["X-Header-Secret"].startswith("enc:v1:")


def test_patch_with_masked_api_key_does_not_overwrite(setup_mock_db):
    admin_token = create_access_token(username="admin", role="admin", ai_enabled=True)
    c = TestClient(app)
    c.headers.update({"Authorization": f"Bearer {admin_token}"})

    original_plain = "sk-original-secret-key-12345678"
    stored_ai = AISettingsStored()
    stored_ai.gemini.api_key_encrypted = encrypt_secret(original_plain)

    mock_settings_coll = MockCollection("settings", [{
        "id": "global_settings",
        "ai": stored_ai.model_dump(),
    }])

    with patch("app.routers.settings.settings_collection", mock_settings_coll):
        # PATCH with masked API key hint
        patch_res = c.patch("/api/admin/settings/ai", json={
            "gemini": {
                "api_key": mask_secret(original_plain),
            }
        })
        assert patch_res.status_code == 200

        # DB must still have the original secret decrypted properly
        db_key = mock_settings_coll.documents[0]["ai"]["gemini"]["api_key_encrypted"]
        assert decrypt_secret(db_key) == original_plain
