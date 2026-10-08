import json
import time
from typing import Dict, Optional, Tuple
import httpx
from fastapi import HTTPException
from ..models import AIAttachment, AIGenerationSettings, AINetworkSettings, AIProtocol
from ..ssrf import validate_base_url, normalize_base_url
from .base import BaseAIAdapter

class OpenAICompatibleAdapter(BaseAIAdapter):
    def __init__(
        self,
        base_url: str,
        api_key: Optional[str] = None,
        model: str = "gpt-4o",
        protocol: AIProtocol = "chat_completions",
        custom_headers: Optional[Dict[str, str]] = None,
        generation: Optional[AIGenerationSettings] = None,
        network: Optional[AINetworkSettings] = None,
    ):
        super().__init__(generation, network)
        self.base_url = normalize_base_url(base_url) if base_url else "https://api.openai.com/v1"
        self.api_key = api_key.strip() if api_key and api_key.strip() else None
        self.model = model.strip() if model else "gpt-4o"
        self.protocol = protocol or "chat_completions"
        self.custom_headers = custom_headers or {}

    def _build_headers(self) -> Dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self.custom_headers:
            for k, v in self.custom_headers.items():
                if k.lower() not in ("content-length", "host", "connection", "transfer-encoding"):
                    headers[k] = str(v)
        if self.api_key and "Authorization" not in headers:
            headers["Authorization"] = f"Bearer {self.api_key}"
        return headers

    def _build_endpoint(self) -> str:
        clean = self.base_url.rstrip("/")
        if self.protocol == "responses":
            return f"{clean}/responses"
        return f"{clean}/chat/completions"

    def _parse_compatible_error(self, status_code: int, body: str) -> str:
        try:
            data = json.loads(body)
            err = data.get("error")
            if isinstance(err, dict):
                msg = err.get("message") or err.get("detail")
            elif isinstance(err, str):
                msg = err
            else:
                msg = data.get("detail") or data.get("message")
            if msg:
                return f"Errore Gateway ({status_code}): {msg}"
            return f"Errore Gateway ({status_code}): {body}"
        except Exception:
            return f"Errore Gateway ({status_code}): {body}"

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        attachment: Optional[AIAttachment] = None,
    ) -> Tuple[str, dict]:
        validate_base_url(self.base_url)
        url = self._build_endpoint()
        headers = self._build_headers()

        user_content = user_prompt
        if attachment and attachment.data_base64:
            user_content = f"{user_prompt}\n\n[Allegato: {attachment.filename or 'documento'}]"

        messages = []
        if system_prompt and system_prompt.strip():
            messages.append({"role": "system", "content": system_prompt.strip()})
        messages.append({"role": "user", "content": user_content})

        payload = {
            "model": self.model,
            "messages": messages,
        }
        if self.generation.max_output_tokens:
            payload["max_tokens"] = self.generation.max_output_tokens
        if self.generation.temperature is not None:
            payload["temperature"] = self.generation.temperature
        if self.generation.top_p is not None:
            payload["top_p"] = self.generation.top_p
        if self.generation.reasoning_effort:
            payload["reasoning_effort"] = self.generation.reasoning_effort

        async def _do_req():
            async with httpx.AsyncClient(timeout=float(self.network.timeout_seconds)) as client:
                res = await client.post(url, headers=headers, json=payload)
                if res.status_code != 200:
                    err = self._parse_compatible_error(res.status_code, res.text)
                    raise HTTPException(status_code=502 if res.status_code >= 500 else res.status_code, detail=err)
                return res.json()

        data = await self._execute_with_retry(_do_req)

        try:
            choices = data.get("choices", [])
            text = ""
            if choices:
                first = choices[0]
                if "message" in first and "content" in first["message"]:
                    text = first["message"]["content"]
                elif "text" in first:
                    text = first["text"]
            elif "output_text" in data:
                text = data["output_text"]

            raw_usage = data.get("usage", {})
            usage = {
                "prompt_tokens": raw_usage.get("prompt_tokens"),
                "completion_tokens": raw_usage.get("completion_tokens"),
                "total_tokens": raw_usage.get("total_tokens"),
            }
            return text or "", usage
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Risposta gateway malformata: {e}")

    async def test_connection(self) -> Tuple[bool, float, str]:
        validate_base_url(self.base_url)
        url = self._build_endpoint()
        headers = self._build_headers()
        payload = {
            "model": self.model,
            "messages": [{"role": "user", "content": "Ping"}],
            "max_tokens": 5,
        }
        start = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=float(min(15, self.network.timeout_seconds))) as client:
                res = await client.post(url, headers=headers, json=payload)
                lat = round((time.perf_counter() - start) * 1000, 2)
                if res.status_code == 200:
                    return True, lat, f"Connessione a '{self.base_url}' riuscita ({lat} ms)."
                return False, lat, self._parse_compatible_error(res.status_code, res.text)
        except Exception as e:
            lat = round((time.perf_counter() - start) * 1000, 2)
            return False, lat, f"Errore di connessione al gateway: {str(e)}"

            return f"Errore Gateway ({status_code}): {body}"
        except Exception:
            return f"Errore Gateway ({status_code}): {body}"
