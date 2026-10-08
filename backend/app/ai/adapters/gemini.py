import json
import time
from typing import Optional, Tuple
import httpx
from fastapi import HTTPException
from ..models import AIAttachment, AIGenerationSettings, AINetworkSettings
from .base import BaseAIAdapter

class GeminiAdapter(BaseAIAdapter):
    def __init__(
        self,
        api_key: Optional[str],
        model: str = "gemini-2.5-pro",
        generation: Optional[AIGenerationSettings] = None,
        network: Optional[AINetworkSettings] = None,
    ):
        super().__init__(generation, network)
        self.api_key = api_key
        self.model = model.strip() if model else "gemini-2.5-pro"

    def _parse_gemini_error(self, status_code: int, body: str) -> str:
        try:
            data = json.loads(body)
            error = data.get("error", {})
            msg = error.get("message", "")
            status = error.get("status", "")

            if "spending cap" in msg.lower() or (status == "RESOURCE_EXHAUSTED" and "budget" in msg.lower()):
                return "Limite di spesa mensile superato su Google AI Studio (Monthly Spending Cap)."
            if status == "RESOURCE_EXHAUSTED" or status_code == 429:
                return "Limite temporaneo superato (Quota/Rate Limit Gemini). Riprova tra poco."
            if status_code in (401, 403) or "API_KEY_INVALID" in msg:
                return "Chiave API Gemini non valida o priva di autorizzazioni."
            if "not found" in msg.lower() or status == "NOT_FOUND":
                return f"Modello Gemini '{self.model}' non trovato per questa API key."
            return f"Errore Gemini ({status_code}): {msg or body}"
        except Exception:
            return f"Errore Gemini ({status_code}): {body}"

    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        attachment: Optional[AIAttachment] = None,
    ) -> Tuple[str, dict]:
        if not self.api_key:
            raise HTTPException(status_code=400, detail="Chiave API Gemini non configurata.")

        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent?key={self.api_key}"

        parts = [{"text": user_prompt}]
        if attachment and attachment.data_base64:
            mime = (attachment.mime_type or "").lower()
            ext = (attachment.extension or "").lower()
            if not mime and ext:
                if ext == "pdf":
                    mime = "application/pdf"
                elif ext in ("txt", "csv"):
                    mime = "text/plain" if ext == "txt" else "text/csv"
                elif ext in ("png", "jpg", "jpeg", "webp", "heic", "heif"):
                    mime = f"image/{'jpeg' if ext in ('jpg', 'jpeg') else ext}"

            allowed_gemini = (
                "application/pdf", "image/png", "image/jpeg", "image/webp",
                "image/heic", "image/heif", "text/plain", "text/csv"
            )
            if mime not in allowed_gemini:
                raise HTTPException(
                    status_code=400,
                    detail=f"Il provider Gemini non supporta allegati di tipo '{mime or ext}'. Sono supportati PDF, TXT, CSV e immagini (PNG, JPEG, WEBP, HEIC).",
                )
            parts.append({"inlineData": {"mimeType": mime, "data": attachment.data_base64}})

        payload = {"contents": [{"parts": parts}]}
        if system_prompt and system_prompt.strip():
            payload["system_instruction"] = {"parts": [{"text": system_prompt.strip()}]}

        gen_config = {}
        if self.generation.temperature is not None:
            gen_config["temperature"] = self.generation.temperature
        if self.generation.top_p is not None:
            gen_config["topP"] = self.generation.top_p
        if self.generation.top_k is not None:
            gen_config["topK"] = self.generation.top_k
        if self.generation.max_output_tokens:
            gen_config["maxOutputTokens"] = self.generation.max_output_tokens
        if gen_config:
            payload["generationConfig"] = gen_config

        async def _do_req():
            async with httpx.AsyncClient(timeout=float(self.network.timeout_seconds), follow_redirects=False) as client:
                res = await client.post(url, json=payload)
                if res.status_code != 200:
                    err = self._parse_gemini_error(res.status_code, res.text)
                    raise HTTPException(status_code=502 if res.status_code >= 500 else res.status_code, detail=err)
                return res.json()

        data = await self._execute_with_retry(_do_req)

        try:
            candidate = data["candidates"][0]
            text = candidate["content"]["parts"][0]["text"]
            usage_meta = data.get("usageMetadata", {})
            usage = {
                "prompt_tokens": usage_meta.get("promptTokenCount"),
                "completion_tokens": usage_meta.get("candidatesTokenCount"),
                "total_tokens": usage_meta.get("totalTokenCount"),
            }
            return text, usage
        except (KeyError, IndexError) as e:
            raise HTTPException(status_code=502, detail=f"Risposta Gemini malformata: {e}")

    async def test_connection(self) -> Tuple[bool, float, str]:
        if not self.api_key:
            return False, 0.0, "Chiave API Gemini non configurata."

        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent?key={self.api_key}"
        payload = {
            "contents": [{"parts": [{"text": "Ping"}]}],
            "generationConfig": {"maxOutputTokens": 5}
        }
        start = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=float(min(15, self.network.timeout_seconds)), follow_redirects=False) as client:
                res = await client.post(url, json=payload)
                lat = round((time.perf_counter() - start) * 1000, 2)
                if res.status_code == 200:
                    return True, lat, f"Connessione a Gemini riuscita ({lat} ms)."
                return False, lat, self._parse_gemini_error(res.status_code, res.text)
        except Exception as e:
            lat = round((time.perf_counter() - start) * 1000, 2)
            return False, lat, f"Errore di connessione a Gemini: {str(e)}"
