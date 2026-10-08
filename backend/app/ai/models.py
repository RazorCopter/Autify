import base64
from typing import Dict, List, Literal, Optional, Union
from pydantic import BaseModel, Field, field_validator

AIProvider = Literal["gemini", "openai", "openai_compatible"]
AIProtocol = Literal["chat_completions", "responses"]
ReasoningEffort = Literal["low", "medium", "high"]

DEFAULT_SYSTEM_PROMPT = """Sei il massimo esperto e consulente di supporto specializzato nei percorsi per l'Autismo e disabilità intellettive/evolutive.
Il tuo compito è analizzare in modo multidimensionale i dati quantitativi e qualitativi estratti dalle scale di valutazione dell'utente.

OBIETTIVO DELL'ANALISI:
1. Valutare l'andamento generale e il profilo dell'utente (punti di forza e aree di supporto nei vari domini).
2. Evidenziare correlazioni significative tra le diverse scale somministrate (es. POS, San Martín, SIS - Supports Intensity Scale).
3. Per la scala SIS, analizzare approfonditamente l'intensità dei bisogni di supporto (Sezione 1 - Domini A-F), le priorità di tutela (Sezione 2) ed i bisogni eccezionali/alert (Sezione 3).
4. Incrociare tutti i dati forniti, incluse le note aggiuntive e gli eventuali allegati documentali.
5. Proporre ipotesi e linee guida per progetti educativi e di supporto customizzati e ritagliati sartorialmente sulle specifiche esigenze dell'utente.
6. Riportare in forma di relazione chiara e coerente quanto emerge dall'incrocio di tutti i dati (scale, note, allegato).

TONO E FORMATTAZIONE:
- Tono: Professionale, rigoroso, empatico, fortemente orientato all'utilità educativa e di supporto.
- Formattazione: Usa il Markdown (titoli, liste puntate, grassetti) per strutturare una relazione elegante, chiara e leggibile.
- NON inserire data di redazione fittizia nel testo generato (viene apposta automaticamente dal sistema)."""

class AIGenerationSettings(BaseModel):
    temperature: Optional[float] = Field(default=None, ge=0.0, le=2.0)
    top_p: Optional[float] = Field(default=None, ge=0.0, le=1.0)
    top_k: Optional[int] = Field(default=None, ge=1, le=100)
    max_output_tokens: Optional[int] = Field(default=4096, ge=128, le=65536)
    reasoning_effort: Optional[ReasoningEffort] = None

class AINetworkSettings(BaseModel):
    timeout_seconds: int = Field(default=300, ge=5, le=600)
    max_retries: int = Field(default=2, ge=0, le=5)

# --- PROVIDER STORED SETTINGS (CON CHIAVI CIFRATE) ---

class GeminiStoredConfig(BaseModel):
    model: str = Field(default="gemini-2.5-pro")
    api_key_encrypted: Optional[str] = None

class OpenAIStoredConfig(BaseModel):
    model: str = Field(default="gpt-4o")
    protocol: AIProtocol = Field(default="chat_completions")
    api_key_encrypted: Optional[str] = None

class OpenAICompatibleStoredConfig(BaseModel):
    base_url: str = Field(default="https://api.openai.com/v1")
    model: str = Field(default="gpt-4o")
    protocol: AIProtocol = Field(default="chat_completions")
    api_key_encrypted: Optional[str] = None
    custom_headers: Dict[str, str] = Field(default_factory=dict)

class AISettingsStored(BaseModel):
    schema_version: int = Field(default=2)
    active_provider: AIProvider = Field(default="gemini")
    viewer_ai_enabled: bool = Field(default=False)
    system_prompt: Optional[str] = Field(default=DEFAULT_SYSTEM_PROMPT)
    generation: AIGenerationSettings = Field(default_factory=AIGenerationSettings)
    network: AINetworkSettings = Field(default_factory=AINetworkSettings)
    gemini: GeminiStoredConfig = Field(default_factory=GeminiStoredConfig)
    openai: OpenAIStoredConfig = Field(default_factory=OpenAIStoredConfig)
    openai_compatible: OpenAICompatibleStoredConfig = Field(default_factory=OpenAICompatibleStoredConfig)

# --- PROVIDER RESPONSE MODELS (MASCHERATI) ---

class SecretFieldStatus(BaseModel):
    configured: bool
    hint: Optional[str] = None

class GeminiProviderResponse(BaseModel):
    model: str
    api_key: SecretFieldStatus

class OpenAIProviderResponse(BaseModel):
    model: str
    protocol: AIProtocol
    api_key: SecretFieldStatus

class OpenAICompatibleResponse(BaseModel):
    base_url: str
    model: str
    protocol: AIProtocol
    api_key: SecretFieldStatus
    custom_headers: Dict[str, str]

class AISettingsResponse(BaseModel):
    schema_version: int = 2
    active_provider: AIProvider
    viewer_ai_enabled: bool
    system_prompt: Optional[str]
    generation: AIGenerationSettings
    network: AINetworkSettings
    gemini: GeminiProviderResponse
    openai: OpenAIProviderResponse
    openai_compatible: OpenAICompatibleResponse

# --- PROVIDER PATCH MODELS ---

class GeminiProviderPatch(BaseModel):
    model: Optional[str] = None
    api_key: Optional[str] = None
    clear_api_key: Optional[bool] = False

    @field_validator("model")
    @classmethod
    def check_model_not_empty(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.strip():
            raise ValueError("Il modello Gemini non può essere una stringa vuota.")
        return v.strip() if v else None

class OpenAIProviderPatch(BaseModel):
    model: Optional[str] = None
    protocol: Optional[AIProtocol] = None
    api_key: Optional[str] = None
    clear_api_key: Optional[bool] = False

    @field_validator("model")
    @classmethod
    def check_model_not_empty(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.strip():
            raise ValueError("Il modello OpenAI non può essere una stringa vuota.")
        return v.strip() if v else None

def _validate_headers_dict(headers: Optional[Dict[str, str]]) -> Optional[Dict[str, str]]:
    if headers is None:
        return None
    cleaned = {}
    for k, v in headers.items():
        if not k or not str(k).strip():
            continue
        key = str(k).strip()
        val = str(v).strip()
        if any(c in key or c in val for c in ("\r", "\n")):
            raise ValueError("Gli header HTTP non possono contenere caratteri newline (CRLF).")
        if key.lower() in ("host", "content-length", "connection", "transfer-encoding"):
            raise ValueError(f"L'header '{key}' non può essere personalizzato per motivi di sicurezza.")
        cleaned[key] = val
    return cleaned

class OpenAICompatiblePatch(BaseModel):
    base_url: Optional[str] = None
    model: Optional[str] = None
    protocol: Optional[AIProtocol] = None
    api_key: Optional[str] = None
    custom_headers: Optional[Dict[str, str]] = None
    clear_api_key: Optional[bool] = False

    @field_validator("model")
    @classmethod
    def check_model_not_empty(cls, v: Optional[str]) -> Optional[str]:
        if v is not None and not v.strip():
            raise ValueError("Il modello OpenAI-Compatible non può essere una stringa vuota.")
        return v.strip() if v else None

    @field_validator("custom_headers")
    @classmethod
    def check_custom_headers(cls, v: Optional[Dict[str, str]]) -> Optional[Dict[str, str]]:
        return _validate_headers_dict(v)

class AISettingsPatch(BaseModel):
    active_provider: Optional[AIProvider] = None
    viewer_ai_enabled: Optional[bool] = None
    system_prompt: Optional[str] = None
    generation: Optional[AIGenerationSettings] = None
    network: Optional[AINetworkSettings] = None
    gemini: Optional[GeminiProviderPatch] = None
    openai: Optional[OpenAIProviderPatch] = None
    openai_compatible: Optional[OpenAICompatiblePatch] = None

# --- TEST CONNECTION, DISCOVERY & ANALYZE MODELS ---

class AITestConnectionRequest(BaseModel):
    provider: Optional[AIProvider] = None
    model: Optional[str] = None
    api_key: Optional[str] = None
    base_url: Optional[str] = None
    protocol: Optional[AIProtocol] = None
    custom_headers: Optional[Dict[str, str]] = None

    @field_validator("custom_headers")
    @classmethod
    def check_custom_headers(cls, v: Optional[Dict[str, str]]) -> Optional[Dict[str, str]]:
        return _validate_headers_dict(v)

class AITestConnectionResponse(BaseModel):
    success: bool
    provider: str
    model: str
    latency_ms: Optional[float] = None
    message: str

class AIDiscoverModelsRequest(BaseModel):
    base_url: Optional[str] = None
    api_key: Optional[str] = None
    custom_headers: Optional[Dict[str, str]] = None

    @field_validator("custom_headers")
    @classmethod
    def check_custom_headers(cls, v: Optional[Dict[str, str]]) -> Optional[Dict[str, str]]:
        return _validate_headers_dict(v)

class AIDiscoverModelsResponse(BaseModel):
    models: List[str]
    count: int

MAX_ATTACHMENT_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB

ALLOWED_ATTACHMENT_MIME_TYPES = {
    "image/png",
    "image/jpeg",
    "image/webp",
    "image/gif",
    "image/heic",
    "image/heif",
    "application/pdf",
    "text/plain",
    "text/csv",
}

ALLOWED_ATTACHMENT_EXTENSIONS = {
    "png", "jpg", "jpeg", "webp", "gif", "heic", "heif", "pdf", "txt", "csv"
}

class AIAttachment(BaseModel):
    filename: Optional[str] = None
    extension: Optional[str] = None
    mime_type: Optional[str] = None
    data_base64: str

    @field_validator("filename")
    @classmethod
    def validate_filename(cls, v: Optional[str]) -> Optional[str]:
        if not v:
            return None
        clean = v.replace("\\", "/").split("/")[-1].strip()
        return clean[:255] if clean else None

    @field_validator("extension")
    @classmethod
    def validate_extension(cls, v: Optional[str]) -> Optional[str]:
        if not v:
            return None
        clean = v.strip().lower().lstrip(".")
        if clean and clean not in ALLOWED_ATTACHMENT_EXTENSIONS:
            raise ValueError(f"Estensione allegato non consentita: .{clean}")
        return clean

    @field_validator("mime_type")
    @classmethod
    def validate_mime_type(cls, v: Optional[str]) -> Optional[str]:
        if not v:
            return None
        clean = v.strip().lower()
        if clean and clean not in ALLOWED_ATTACHMENT_MIME_TYPES:
            raise ValueError(f"MIME type allegato non consentito: {clean}")
        return clean

    @field_validator("data_base64")
    @classmethod
    def validate_data_base64(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("Il contenuto base64 dell'allegato non può essere vuoto.")
        raw = v.strip()
        if len(raw) > 16 * 1024 * 1024:
            raise ValueError("La dimensione dell'allegato supera il limite consentito di 10MB.")
        try:
            decoded = base64.b64decode(raw, validate=True)
        except Exception:
            raise ValueError("Il campo data_base64 non contiene una codifica Base64 valida.")
        if len(decoded) > MAX_ATTACHMENT_SIZE_BYTES:
            raise ValueError("La dimensione del file decodificato supera il limite massimo di 10MB.")
        return raw

class AIAnalyzeRequest(BaseModel):
    id_valutazione: Optional[str] = None
    id_paziente: Optional[str] = None
    patient: Optional[dict] = None
    evaluations: Optional[List[dict]] = None
    evaluation_ids: Optional[List[str]] = None
    history_reports: Optional[List[dict]] = None
    notes: Optional[str] = None
    attachment: Optional[AIAttachment] = None
    system_prompt: Optional[str] = None

    @field_validator("notes")
    @classmethod
    def validate_notes(cls, v: Optional[str]) -> Optional[str]:
        if v and len(v) > 20000:
            raise ValueError("Le note aggiuntive superano la lunghezza massima consentita (20000 caratteri).")
        return v

    @field_validator("system_prompt")
    @classmethod
    def validate_system_prompt(cls, v: Optional[str]) -> Optional[str]:
        if v and len(v) > 10000:
            raise ValueError("Il prompt di sistema supera la lunghezza massima consentita (10000 caratteri).")
        return v

    @field_validator("evaluations")
    @classmethod
    def validate_evaluations(cls, v: Optional[List[dict]]) -> Optional[List[dict]]:
        if v and len(v) > 100:
            raise ValueError("Numero massimo di valutazioni superato (max 100).")
        return v

    @field_validator("history_reports")
    @classmethod
    def validate_history_reports(cls, v: Optional[List[dict]]) -> Optional[List[dict]]:
        if v and len(v) > 50:
            raise ValueError("Numero massimo di relazioni storiche superato (max 50).")
        return v

class AIAnalyzeResponse(BaseModel):
    id: str
    job_id: Optional[str] = None
    status: Optional[str] = "pending"
    id_paziente: Optional[str] = None
    patient_name: Optional[str] = None
    message: Optional[str] = "Elaborazione IA avviata in background"
    report: Optional[str] = ""
    notes: Optional[str] = ""
    evaluations_used: List[str] = Field(default_factory=list)
    provider: Optional[str] = None
    model: Optional[str] = None
    usage: Optional[dict] = None
    timestamp: Optional[str] = None
    prompt_tokens: Optional[int] = None
    completion_tokens: Optional[int] = None
    total_tokens: Optional[int] = None
    created_at: Optional[str] = None


class AIJobDetail(BaseModel):
    id: str
    job_id: str
    username: str
    id_paziente: Optional[str] = None
    patient_name: Optional[str] = None
    status: str
    created_at: str
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    error_message: Optional[str] = None
    analysis_id: Optional[str] = None
    report_preview: Optional[str] = None


class AINotification(BaseModel):
    id: str
    username: str
    type: str = "ai_analysis_completed"
    title: str = "Elaborazione IA"
    message: str
    job_id: Optional[str] = None
    analysis_id: Optional[str] = None
    id_paziente: Optional[str] = None
    patient_name: Optional[str] = None
    read: bool = False
    created_at: str


class AINotificationUnreadCount(BaseModel):
    unread_count: int
