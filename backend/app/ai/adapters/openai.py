import json
import time
from typing import Optional, Tuple
import httpx
from fastapi import HTTPException
from ..models import AIAttachment, AIGenerationSettings, AINetworkSettings, AIProtocol
from .base import BaseAIAdapter

class OpenAIAdapter(BaseAIAdapter):
    def __init__(
        self,
        api_key: Optional[str],
        model: str = "gpt-4o",
        protocol: AIProtocol = "chat_completions",
        generation: Optional[AIGenerationSettings] = None,
        network: Optional[AINetworkSettings] = None,
    ):
        super().__init__(generation, network)
        self.api_key = api_key
        self.model = model.strip() if model else "gpt-4o"
        self.protocol = protocol or "chat_completions"

    def _is_reasoning_model(self) -> bool:
        low = self.model.lower()
        return any(low.startswith(p) for p in ("o1", "o3", "o4")) or "reasoning" in low

    def _parse_openai_error(self, status_code: int, body: str) -> str:
        try:
            data = json.loads(body)
            error = data.get("error", {})
            msg = error.get("message", "")
            code = error.get("code", "")
            if status_code == 401 or code == "invalid_api_key":
                return "Chiave API OpenAI non valida o revocata."
            if status_code == 429 or code == "insufficient_quota":
                return "Credito esaurito o limite richieste (Rate Limit/Quota) superato su OpenAI."
            if status_code == 404 or code == "model_not_found":
                return f"Modello OpenAI '{self.model}' non trovato per questo account."
            return f"Errore OpenAI ({status_code}): {msg or body}"
        except Exception:
            return f"Errore OpenAI ({status_code}): {body}"

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        attachment: Optional[AIAttachment] = None,
    ) -> Tuple[str, dict]:
        if not self.api_key:
            raise HTTPException(status_code=400, detail="Chiave API OpenAI non configurata.")

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        user_content = user_prompt
        if attachment and attachment.data_base64:
            mime = (attachment.mime_type or "").lower()
            ext = (attachment.extension or "").lower()
            if not mime and ext:
                if ext in ("png", "jpg", "jpeg", "webp", "gif"):
                    mime = f"image/{'jpeg' if ext in ('jpg', 'jpeg') else ext}"
            if not (mime.startswith("image/") or ext in ("png", "jpg", "jpeg", "webp", "gif")):
                raise HTTPException(
                    status_code=400,
                    detail=f"Il provider OpenAI supporta solo allegati di tipo immagine (PNG, JPEG, WEBP, GIF). Il formato '{mime or ext}' non è supportato.",
                )
            effective_mime = mime if mime.startswith("image/") else "image/jpeg"
            user_content = [
                {"type": "text", "text": user_prompt},
                {"type": "image_url", "image_url": {"url": f"data:{effective_mime};base64,{attachment.data_base64}"}},
            ]

        is_reasoning = self._is_reasoning_model()
        messages = []
        if system_prompt and system_prompt.strip():
            messages.append({"role": "system", "content": system_prompt.strip()})
        messages.append({"role": "user", "content": user_content})

        if self.protocol == "responses":
            url = "https://api.openai.com/v1/responses"
            payload = {"model": self.model, "input": messages}
            if self.generation.max_output_tokens:
                payload["max_output_tokens"] = self.generation.max_output_tokens
            if self.generation.temperature is not None and not is_reasoning:
                payload["temperature"] = self.generation.temperature
        else:
            url = "https://api.openai.com/v1/chat/completions"
            payload = {"model": self.model, "messages": messages}
            if is_reasoning:
                if self.generation.max_output_tokens:
                    payload["max_completion_tokens"] = self.generation.max_output_tokens
                if self.generation.reasoning_effort:
                    payload["reasoning_effort"] = self.generation.reasoning_effort
            else:
                if self.generation.max_output_tokens:
                    payload["max_tokens"] = self.generation.max_output_tokens
                if self.generation.temperature is not None:
                    payload["temperature"] = self.generation.temperature
                if self.generation.top_p is not None:
                    payload["top_p"] = self.generation.top_p

        async def _do_req():
            async with httpx.AsyncClient(timeout=float(self.network.timeout_seconds), follow_redirects=False) as client:
                res = await client.post(url, headers=headers, json=payload)
                if res.status_code != 200:
                    err = self._parse_openai_error(res.status_code, res.text)
                    raise HTTPException(status_code=502 if res.status_code >= 500 else res.status_code, detail=err)
                return res.json()

        data = await self._execute_with_retry(_do_req)
        try:
            text = ""
            choices = data.get("choices", [])
            if choices:
                text = choices[0]["message"]["content"]
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
            raise HTTPException(status_code=502, detail=f"Risposta OpenAI malformata: {e}")

    async def test_connection(self) -> Tuple[bool, float, str]:
        if not self.api_key:
            return False, 0.0, "Chiave API OpenAI non configurata."

        headers = {"Authorization": f"Bearer {self.api_key}"}
        if self.protocol == "responses":
            url = "https://api.openai.com/v1/responses"
            payload = {
                "model": self.model,
                "input": [{"role": "user", "content": "Ping"}],
                "max_output_tokens": 5,
            }
        else:
            url = "https://api.openai.com/v1/chat/completions"
            payload = {
                "model": self.model,
                "messages": [{"role": "user", "content": "Ping"}],
                "max_tokens": 5,
            }
            if self._is_reasoning_model():
                payload.pop("max_tokens", None)
                payload["max_completion_tokens"] = 5

        start = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=float(min(15, self.network.timeout_seconds)), follow_redirects=False) as client:
                res = await client.post(url, headers=headers, json=payload)
                lat = round((time.perf_counter() - start) * 1000, 2)
                if res.status_code == 200:
                    return True, lat, f"Connessione a OpenAI riuscita ({lat} ms)."
                return False, lat, self._parse_openai_error(res.status_code, res.text)
        except Exception as e:
            lat = round((time.perf_counter() - start) * 1000, 2)
            return False, lat, f"Errore di connessione a OpenAI: {str(e)}"
