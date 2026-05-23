from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime, timezone
import uuid

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
    ultimo_pos_compilato: Optional[str] = None
    ultimo_san_martin_compilato: Optional[str] = None

# --- MODELLI SETTINGS (Config Models) ---

class AppSettings(BaseModel):
    id: str = "global_settings"
    gemini_api_key: Optional[str] = None
    gemini_model: Optional[str] = "gemini-2.5-pro"

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


class Answer(BaseModel):
    codice_domanda: str
    punteggio: int
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
