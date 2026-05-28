from pydantic import BaseModel, Field, field_validator
from typing import List, Optional, Union
from datetime import datetime, timezone
import uuid

# --- MODELLI UTENZE (Auth & RBAC) ---

class UserCreate(BaseModel):
    """Payload per la creazione di un nuovo operatore."""
    username: str = Field(..., min_length=3, max_length=50, description="Nome utente (min 3 caratteri, nessuno spazio)")
    password: str = Field(..., min_length=4, max_length=128)
    confirm_password: str
    role: str = Field(default="viewer", pattern="^(admin|viewer)$")
    ai_enabled: bool = False

    @field_validator("username")
    @classmethod
    def username_no_spaces(cls, v: str) -> str:
        if " " in v:
            raise ValueError("Lo username non può contenere spazi")
        return v.lower()

    @field_validator("confirm_password")
    @classmethod
    def passwords_match(cls, v: str, info) -> str:
        if "password" in info.data and v != info.data["password"]:
            raise ValueError("Le password non coincidono")
        return v


class UserUpdate(BaseModel):
    """Payload per la modifica di un operatore esistente."""
    password: Optional[str] = Field(None, min_length=4, max_length=128)
    confirm_password: Optional[str] = None
    role: Optional[str] = Field(None, pattern="^(admin|viewer)$")
    ai_enabled: Optional[bool] = None

    @field_validator("confirm_password")
    @classmethod
    def passwords_match(cls, v: Optional[str], info) -> Optional[str]:
        if v is not None and "password" in info.data and info.data["password"] is not None:
            if v != info.data["password"]:
                raise ValueError("Le password non coincidono")
        return v


class UserResponse(BaseModel):
    """Risposta pubblica — non espone mai hashed_password."""
    username: str
    role: str
    ai_enabled: bool
    is_default: bool
    created_at: datetime
    updated_at: datetime

# --- MODELLI ANAGRAFICA (User Models) ---

class Patient(BaseModel):
    id: str = Field(default_factory=lambda: f"pat_{uuid.uuid4().hex[:8]}")
    nome: str
    cognome: str
    altezza: Optional[int] = None
    peso: Optional[float] = None
    data_nascita: Optional[str] = None
    sesso: Optional[str] = None
    note: Optional[str] = None
    attivo: bool = True
    ultimo_pos_compilato: Optional[str] = None
    ultimo_san_martin_compilato: Optional[str] = None
    ultimo_sis_compilato: Optional[str] = None

# --- MODELLI SETTINGS (Config Models) ---

class AppSettings(BaseModel):
    id: str = "global_settings"
    gemini_api_key: Optional[str] = None
    gemini_model: Optional[str] = "gemini-2.5-pro"
    gemini_prompt: Optional[str] = None
    viewer_ai_enabled: Optional[bool] = False

# --- MODELLI SCALA (Scale Models) ---

class Option(BaseModel):
    testo_risposta: str
    punteggio: int
    descrizione: Optional[str] = None   # Testo descrittivo esteso

class Question(BaseModel):
    id_domanda: str
    codice: Optional[str] = None
    testo_domanda: str
    note: Optional[str] = None           # Avvertenze / contesto clinico
    opzioni: List[Option] = []

class Section(BaseModel):
    codice_sezione: Optional[str] = None # es. "SP"
    titolo_sezione: str
    descrizione_sezione: Optional[str] = None
    domande: List[Question]

class Scale(BaseModel):
    id: str
    nome: str
    descrizione: str
    sezioni: List[Section]


# --- MODELLI RISPOSTA (flessibile per POS/SanMartín e SIS) ---

class SISItemResponse(BaseModel):
    """Risposta tridimensionale per un item SIS (sottoscale A-F e sezione 2)."""
    F: int = Field(..., ge=0, le=4, description="Frequenza (0-4)")
    D: int = Field(..., ge=0, le=4, description="Durata quotidiana (0-4)")
    T: int = Field(..., ge=0, le=4, description="Tipo di sostegno (0-4)")

class Answer(BaseModel):
    """
    Modello di risposta flessibile.

    - Per POS / San Martín: punteggio è un int (es. 3)
    - Per SIS (sottoscale A-F e sezione 2): punteggio è un dict {"F": 2, "D": 3, "T": 1}
    - Per SIS (sezione 3 medica/comportamentale): punteggio è un int (0, 1 o 2)
    """
    codice_domanda: str
    punteggio: Union[int, dict] = 0
    nota: Optional[str] = None

class Evaluation(BaseModel):
    id_valutazione: str = Field(default_factory=lambda: str(uuid.uuid4()))
    id_paziente: str
    anno: int
    id_scala: str
    data_compilazione: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    nome_operatore: str
    nome_intervistato: Optional[str] = None
    demographics: Optional[dict] = None
    risposte: List[Answer]

# --- MODELLI AGGREGAZIONE E PDF ---

DOMINI_POS = {
    "SP": "Sviluppo Personale",
    "AD": "Autodeterminazione",
    "RI": "Risorse Inclusive",
    "IS": "Relazioni Interpersonali",
    "D":  "Diritti",
    "BE": "Benessere Emotivo",
    "BF": "Benessere Fisico",
    "BM": "Benessere Materiale",
}

class DomainScore(BaseModel):
    codice: str
    etichetta: str
    punteggio_totale: int
    num_domande: int

class AggregatedEvaluation(BaseModel):
    id_valutazione: str
    id_paziente: str
    id_scala: str
    anno: int
    data_compilazione: datetime
    nome_operatore: str
    nome_intervistato: Optional[str] = None
    demographics: Optional[dict] = None
    domini: List[DomainScore]
    risposte: List[Answer]

class EvaluationUpdateRequest(BaseModel):
    risposte: List[Answer]
    nome_operatore: Optional[str] = None
    nome_intervistato: Optional[str] = None
    demographics: Optional[dict] = None

# --- MODELLI STORICO ANALISI IA (AI History Models) ---

class AiAnalysis(BaseModel):
    id: str = Field(default_factory=lambda: f"an_{uuid.uuid4().hex[:8]}")
    id_paziente: str
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    report: str
    notes: Optional[str] = None
    evaluations_used: List[str] = []

class AiAnalysisCreate(BaseModel):
    report: str
    notes: Optional[str] = None
    evaluations_used: List[str] = []

# --- MODELLI OUTPUT SIS ---

class SISDomainResult(BaseModel):
    """Risultato calcolato per un singolo dominio SIS (A-F)."""
    codice: str
    etichetta: str
    punteggio_grezzo: int
    punteggio_standard: Optional[int] = None
    percentile: Optional[int] = None
    num_domande: int = 0

class SISSezione3Detail(BaseModel):
    """Dettaglio alert per sezione 3 (medica o comportamentale)."""
    alert: bool = False
    count_parziale: int = 0
    count_estensivo: int = 0
    totale: int = 0
    items_segnalati: List[dict] = []

class SISSupplementaryResult(BaseModel):
    """Risultati delle sezioni supplementari SIS."""
    sezione_2_top4: List[dict] = []
    alert_medico: bool = False
    alert_comportamentale: bool = False
    dettaglio_medico: SISSezione3Detail = SISSezione3Detail()
    dettaglio_comportamentale: SISSezione3Detail = SISSezione3Detail()
