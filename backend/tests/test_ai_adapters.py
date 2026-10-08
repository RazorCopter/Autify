import json
import pytest
import httpx
from fastapi import HTTPException
from app.ai.adapters.gemini import GeminiAdapter
from app.ai.adapters.openai import OpenAIAdapter
from app.ai.adapters.openai_compatible import OpenAICompatibleAdapter
from app.ai.adapters.factory import get_ai_adapter
from app.ai.models import AISettingsStored, AIGenerationSettings, AINetworkSettings, AIAttachment
from app.ai.crypto import encrypt_secret

@pytest.mark.anyio
async def test_gemini_adapter_generate_success(monkeypatch):
    adapter = GeminiAdapter(api_key="test-key", model="gemini-2.5-pro")

    gemini_resp = {
        "candidates": [
            {"content": {"parts": [{"text": "Analisi clinica completata con successo."}]}}
        ],
        "usageMetadata": {
            "promptTokenCount": 150,
            "candidatesTokenCount": 80,
            "totalTokenCount": 230,
        }
    }

    async def mock_post(client_self, url, *args, **kwargs):
        req = httpx.Request("POST", str(url))
        return httpx.Response(200, json=gemini_resp, request=req)

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    text, usage = await adapter.generate(
        system_prompt="Sei un esperto",
        user_prompt="Analizza i dati utente",
    )
    assert "Analisi clinica" in text
    assert usage["total_tokens"] == 230

@pytest.mark.anyio
async def test_gemini_adapter_spending_cap_error(monkeypatch):
    adapter = GeminiAdapter(api_key="test-key", model="gemini-2.5-pro")

    error_body = {
        "error": {
            "code": 429,
            "message": "Resource has been exhausted (e.g. check quota or monthly spending cap).",
            "status": "RESOURCE_EXHAUSTED"
        }
    }

    async def mock_post(client_self, url, *args, **kwargs):
        req = httpx.Request("POST", str(url))
        return httpx.Response(429, json=error_body, request=req)

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    with pytest.raises(HTTPException) as exc:
        await adapter.generate("sys", "user")
    assert "spending cap" in exc.value.detail.lower() or "limite" in exc.value.detail.lower()

@pytest.mark.anyio
async def test_openai_adapter_generate_success(monkeypatch):
    adapter = OpenAIAdapter(
        api_key="sk-test-key",
        model="gpt-4o",
        generation=AIGenerationSettings(temperature=0.7, max_output_tokens=2048)
    )

    openai_resp = {
        "choices": [
            {"message": {"role": "assistant", "content": "Report OpenAI sintetico."}}
        ],
        "usage": {
            "prompt_tokens": 100,
            "completion_tokens": 50,
            "total_tokens": 150,
        }
    }

    captured_payload = {}
    async def mock_post(client_self, url, *args, **kwargs):
        captured_payload.update(kwargs.get("json", {}))
        req = httpx.Request("POST", str(url))
        return httpx.Response(200, json=openai_resp, request=req)

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    text, usage = await adapter.generate("System", "User")
    assert text == "Report OpenAI sintetico."
    assert captured_payload["temperature"] == 0.7
    assert captured_payload["max_tokens"] == 2048
    assert usage["total_tokens"] == 150

@pytest.mark.anyio
async def test_openai_compatible_adapter(monkeypatch):
    monkeypatch.setenv("ALLOW_PRIVATE_AI_ENDPOINTS", "true")
    adapter = OpenAICompatibleAdapter(
        base_url="https://ia.ghome.it/v1",
        api_key="omni-secret-key",
        model="cx/gpt-5.6-sol-high",
        custom_headers={"X-Tenant-ID": "clinic-01"},
    )

    gateway_resp = {
        "choices": [
            {"message": {"content": "Report da OmniRoute gateway."}}
        ],
        "usage": {"total_tokens": 99}
    }

    captured_headers = {}
    async def mock_post(client_self, url, *args, **kwargs):
        captured_headers.update(kwargs.get("headers", {}))
        req = httpx.Request("POST", str(url))
        return httpx.Response(200, json=gateway_resp, request=req)

    monkeypatch.setattr(httpx.AsyncClient, "post", mock_post)

    text, usage = await adapter.generate("System", "User")
    assert text == "Report da OmniRoute gateway."
    assert captured_headers.get("X-Tenant-ID") == "clinic-01"
    assert "Bearer omni-secret-key" in captured_headers.get("Authorization", "")

def test_adapter_factory():
    stored = AISettingsStored(
        active_provider="gemini",
    )
    stored.gemini.api_key_encrypted = encrypt_secret("gemini-secret-1234")
    stored.gemini.model = "gemini-2.5-flash"

    adapter = get_ai_adapter(stored)
    assert isinstance(adapter, GeminiAdapter)
    assert adapter.api_key == "gemini-secret-1234"
    assert adapter.model == "gemini-2.5-flash"
