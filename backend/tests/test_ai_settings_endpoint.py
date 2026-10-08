from unittest.mock import patch
from app.ai.crypto import encrypt_secret
from .test_endpoints import MockCollection, client, setup_mock_db, mock_patients, mock_scales, mock_evaluations, mock_users


def test_get_and_patch_ai_settings_endpoint(client, setup_mock_db):
    """Verifica GET e PATCH /api/admin/settings/ai con protezione chiavi e preservazione."""

    initial_doc = {
        "id": "global_settings",
        "ai": {
            "schema_version": 2,
            "active_provider": "gemini",
            "viewer_ai_enabled": False,
            "gemini": {
                "model": "gemini-2.5-pro",
                "api_key_encrypted": encrypt_secret("initial-gemini-secret-12345"),
            },
            "openai": {
                "model": "gpt-4o",
                "protocol": "chat_completions",
                "api_key_encrypted": None,
            },
            "openai_compatible": {
                "base_url": "https://api.openai.com/v1",
                "model": "gpt-4o",
                "protocol": "chat_completions",
                "custom_headers": {},
                "api_key_encrypted": None,
            }
        }
    }

    mock_settings_coll = MockCollection("settings", [initial_doc])

    with patch("app.routers.settings.settings_collection", mock_settings_coll):
        # 1. GET Settings AI
        res = client.get("/api/admin/settings/ai")
        assert res.status_code == 200
        data = res.json()
        assert data["active_provider"] == "gemini"
        assert data["gemini"]["model"] == "gemini-2.5-pro"
        assert data["gemini"]["api_key"]["configured"] is True
        assert "initial-gemini-secret" not in data["gemini"]["api_key"]["hint"]
        assert data["openai"]["api_key"]["configured"] is False

        # 2. PATCH parziale: cambia solo OpenAI Compatible senza toccare Gemini
        patch_payload = {
            "active_provider": "openai_compatible",
            "openai_compatible": {
                "base_url": "https://ia.ghome.it/v1",
                "model": "cx/gpt-5.6-sol-high",
                "api_key": "omni-super-secret",
                "custom_headers": {"X-Custom": "custom-val"}
            }
        }
        res_patch = client.patch("/api/admin/settings/ai", json=patch_payload)
        assert res_patch.status_code == 200
        patch_data = res_patch.json()
        assert patch_data["active_provider"] == "openai_compatible"
        assert patch_data["openai_compatible"]["base_url"] == "https://ia.ghome.it/v1"
        assert patch_data["openai_compatible"]["model"] == "cx/gpt-5.6-sol-high"
        assert patch_data["openai_compatible"]["api_key"]["configured"] is True
        # La chiave Gemini deve essere stata preservata intatta
        assert patch_data["gemini"]["api_key"]["configured"] is True

        # 3. PATCH per cancellare esplicitamente la chiave Gemini
        res_clear = client.patch("/api/admin/settings/ai", json={
            "gemini": {"clear_api_key": True}
        })
        assert res_clear.status_code == 200
        assert res_clear.json()["gemini"]["api_key"]["configured"] is False
