import abc
import asyncio
import random
import time
from typing import Optional, Tuple
import httpx
from fastapi import HTTPException
from ..models import AIAttachment, AIGenerationSettings, AINetworkSettings

class BaseAIAdapter(abc.ABC):
    def __init__(
        self,
        generation: Optional[AIGenerationSettings] = None,
        network: Optional[AINetworkSettings] = None,
    ):
        self.generation = generation or AIGenerationSettings()
        self.network = network or AINetworkSettings()

    @abc.abstractmethod
    async def generate(
        self,
        system_prompt: str,
        user_prompt: str,
        attachment: Optional[AIAttachment] = None,
    ) -> Tuple[str, dict]:
        """Esegue la generazione del report IA. Ritorna (testo_report, info_usage)."""
        pass

    @abc.abstractmethod
    async def test_connection(self) -> Tuple[bool, float, str]:
        """Verifica la connessione al provider. Ritorna (success, latency_ms, messaggio)."""
        pass

    async def _execute_with_retry(self, request_fn):
        """
        Esegue la funzione di richiesta HTTP gestendo retry con backoff esponenziale
        e jitter solo su errori transitori (429, 502, 503, 504, timeout).
        Errori permanenti (400, 401, 403, 404) sollevano immediatamente eccezione.
        """
        retries = max(0, self.network.max_retries)
        delay = 1.0
        last_error = None

        for attempt in range(retries + 1):
            try:
                return await request_fn()
            except (httpx.TimeoutException, httpx.NetworkError) as e:
                last_error = e
                if attempt == retries:
                    raise HTTPException(
                        status_code=504,
                        detail=f"Timeout o errore di rete dopo {retries} tentativi: {str(e)}"
                    )
            except HTTPException as e:
                # Retry solo su 429 e 502/503/504
                if e.status_code in (429, 502, 503, 504) and attempt < retries:
                    last_error = e
                else:
                    raise e

            # Calcolo backoff con jitter
            jitter = random.uniform(0.1, 0.4)
            await asyncio.sleep(delay + jitter)
            delay *= 2.0

        if last_error:
            raise last_error
