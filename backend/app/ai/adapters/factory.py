from typing import Dict, Optional
from fastapi import HTTPException
from ..models import AISettingsStored
from ..crypto import decrypt_secret
from .base import BaseAIAdapter
from .gemini import GeminiAdapter
from .openai import OpenAIAdapter
from .openai_compatible import OpenAICompatibleAdapter

def get_ai_adapter(
    settings: AISettingsStored,
    provider_override: Optional[str] = None,
    api_key_override: Optional[str] = None,
    model_override: Optional[str] = None,
    base_url_override: Optional[str] = None,
    protocol_override: Optional[str] = None,
    custom_headers_override: Optional[Dict[str, str]] = None,
) -> BaseAIAdapter:
    provider = provider_override or settings.active_provider

    if provider == "gemini":
        key = api_key_override if api_key_override is not None else decrypt_secret(settings.gemini.api_key_encrypted)
        model = model_override or settings.gemini.model
        return GeminiAdapter(
            api_key=key,
            model=model,
            generation=settings.generation,
            network=settings.network,
        )

    elif provider == "openai":
        key = api_key_override if api_key_override is not None else decrypt_secret(settings.openai.api_key_encrypted)
        model = model_override or settings.openai.model
        protocol = protocol_override or settings.openai.protocol
        return OpenAIAdapter(
            api_key=key,
            model=model,
            protocol=protocol,
            generation=settings.generation,
            network=settings.network,
        )

    elif provider == "openai_compatible":
        key = api_key_override if api_key_override is not None else decrypt_secret(settings.openai_compatible.api_key_encrypted)
        base_url = base_url_override or settings.openai_compatible.base_url
        model = model_override or settings.openai_compatible.model
        protocol = protocol_override or settings.openai_compatible.protocol
        headers = custom_headers_override if custom_headers_override is not None else settings.openai_compatible.custom_headers
        return OpenAICompatibleAdapter(
            base_url=base_url,
            api_key=key,
            model=model,
            protocol=protocol,
            custom_headers=headers,
            generation=settings.generation,
            network=settings.network,
        )

    raise HTTPException(status_code=400, detail=f"Provider AI '{provider}' non supportato.")
