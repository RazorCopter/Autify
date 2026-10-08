import base64
import json
import time
from typing import Dict, List, Optional, Tuple
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
            mime = (attachment.mime_type or "").lower()
            ext = (attachment.extension or "").lower()
            if not mime and ext:
                if ext in ("png", "jpg", "jpeg", "webp", "gif"):
                    mime = f"image/{'jpeg' if ext in ('jpg', 'jpeg') else ext}"
                elif ext in ("txt", "csv"):
                    mime = "text/plain" if ext == "txt" else "text/csv"

            if mime.startswith("image/") or ext in ("png", "jpg", "jpeg", "webp", "gif"):
                effective_mime = mime if mime.startswith("image/") else "image/jpeg"
                user_content = [
                    {"type": "text", "text": user_prompt},
                    {"type": "image_url", "image_url": {"url": f"data:{effective_mime};base64,{attachment.data_base64}"}},
                ]
            elif mime in ("text/plain", "text/csv") or ext in ("txt", "csv"):
                try:
                    decoded_bytes = base64.b64decode(attachment.data_base64)
                    decoded_text = decoded_bytes.decode("utf-8", errors="replace")
                    user_content = f"{user_prompt}\n\n[Allegato: {attachment.filename or 'documento'}]\n{decoded_text}"
                except Exception:
                    raise HTTPException(status_code=400, detail="Impossibile decodificare l'allegato di testo Base64.")
            else:
                raise HTTPException(
                    status_code=400,
                    detail=f"Il provider OpenAI-Compatible non supporta allegati con formato '{mime or ext}'. Sono supportate immagini (PNG, JPEG, WEBP, GIF) e testo (TXT, CSV).",
                )

        messages = []
        if system_prompt and system_prompt.strip():
            messages.append({"role": "system", "content": system_prompt.strip()})
        messages.append({"role": "user", "content": user_content})

        if self.protocol == "responses":
            payload = {
                "model": self.model,
                "input": messages,
            }
            if self.generation.max_output_tokens:
                payload["max_output_tokens"] = self.generation.max_output_tokens
            if self.generation.temperature is not None:
                payload["temperature"] = self.generation.temperature
        else:
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
            async with httpx.AsyncClient(timeout=float(self.network.timeout_seconds), follow_redirects=False) as client:
                res = await client.post(url, headers=headers, json=payload)
                if res.status_code != 200:
                    err = self._parse_compatible_error(res.status_code, res.text)
                    raise HTTPException(status_code=502 if res.status_code >= 500 else res.status_code, detail=err)
                return res.json()

        data = await self._execute_with_retry(_do_req)

        try:
            text = ""
            choices = data.get("choices", [])
            if choices:
                first = choices[0]
                if "message" in first and "content" in first["message"]:
                    text = first["message"]["content"]
                elif "text" in first:
                    text = first["text"]
            elif "output" in data and isinstance(data["output"], list):
                for item in data["output"]:
                    if isinstance(item, dict):
                        if item.get("type") == "message":
                            for c in item.get("content", []):
                                if isinstance(c, dict) and c.get("text"):
                                    text += c["text"]
                        elif "text" in item:
                            text += item["text"]
            elif "output_text" in data:
                text = data["output_text"]

            raw_usage = data.get("usage", {})
            prompt_tok = raw_usage.get("prompt_tokens") or raw_usage.get("input_tokens")
            comp_tok = raw_usage.get("completion_tokens") or raw_usage.get("output_tokens")
            tot_tok = raw_usage.get("total_tokens") or ((prompt_tok or 0) + (comp_tok or 0) if prompt_tok is not None else None)

            usage = {
                "prompt_tokens": prompt_tok,
                "completion_tokens": comp_tok,
                "total_tokens": tot_tok,
            }
            return text or "", usage
        except Exception as e:
            raise HTTPException(status_code=502, detail=f"Risposta gateway malformata: {e}")

    async def test_connection(self) -> Tuple[bool, float, str]:
        validate_base_url(self.base_url)
        url = self._build_endpoint()
        headers = self._build_headers()
        if self.protocol == "responses":
            payload = {
                "model": self.model,
                "input": [{"role": "user", "content": "Ping"}],
                "max_output_tokens": 5,
            }
        else:
            payload = {
                "model": self.model,
                "messages": [{"role": "user", "content": "Ping"}],
                "max_tokens": 5,
            }
        start = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=float(min(15, self.network.timeout_seconds)), follow_redirects=False) as client:
                res = await client.post(url, headers=headers, json=payload)
                lat = round((time.perf_counter() - start) * 1000, 2)
                if res.status_code == 200:
                    return True, lat, f"Connessione a '{self.base_url}' riuscita ({lat} ms)."
                return False, lat, self._parse_compatible_error(res.status_code, res.text)
        except Exception as e:
            lat = round((time.perf_counter() - start) * 1000, 2)
            return False, lat, f"Errore di connessione al gateway: {str(e)}"

    async def fetch_available_models(self) -> List[str]:
        validate_base_url(self.base_url)
        clean = self.base_url.rstrip("/")
        models_url = f"{clean}/models"
        headers = self._build_headers()

        async with httpx.AsyncClient(timeout=float(min(15, self.network.timeout_seconds)), follow_redirects=False) as client:
            try:
                res = await client.get(models_url, headers=headers)
                if res.status_code == 404 and not clean.endswith("/v1"):
                    res = await client.get(f"{clean}/v1/models", headers=headers)
            except Exception as e:
                raise HTTPException(status_code=502, detail=f"Errore di connessione al gateway per recupero modelli: {str(e)}")

            if res.status_code != 200:
                err = self._parse_compatible_error(res.status_code, res.text)
                raise HTTPException(
                    status_code=502 if res.status_code >= 500 else res.status_code,
                    detail=f"Impossibile recuperare i modelli: {err}",
                )

            if len(res.content) > 5 * 1024 * 1024:
                raise HTTPException(status_code=502, detail="La risposta dei modelli upstream eccede la dimensione massima consentita (5MB).")

            try:
                data = res.json()
            except Exception as e:
                raise HTTPException(status_code=502, detail=f"Risposta JSON non valida dall'endpoint /models: {str(e)}")

            raw_items = []
            if isinstance(data, dict):
                if "data" in data and isinstance(data["data"], list):
                    raw_items = data["data"]
                elif "models" in data and isinstance(data["models"], list):
                    raw_items = data["models"]
            elif isinstance(data, list):
                raw_items = data

            models: List[str] = []
            for item in raw_items:
                if isinstance(item, dict):
                    mid = item.get("id") or item.get("name")
                    if mid and str(mid).strip():
                        models.append(str(mid).strip())
                elif isinstance(item, str) and item.strip():
                    models.append(item.strip())

            return sorted(list(set(models)))
