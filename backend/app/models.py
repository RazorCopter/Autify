from pydantic import BaseModel, Field
from typing import List, Optional
from datetime import datetime
import uuid

# --- MODELLI ANAGRAFICA (User Models) ---

class User(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    nome: str
    cognome: str
    data_nascita: str
    codice_fiscale: str
    note: Optional[str] = None

# --- MODELLI SETTINGS (Config Models) ---

class AppSettings(BaseModel):
    id: str = "global_settings"
    gemini_api_key: Optional[str] = None

# --- MODELLI SCALA (Scale Models) ---

class Question(BaseModel):
    id_domanda: str
    testo_domanda: str
    tipo_risposta: str = "rating_1_to_5"

class Section(BaseModel):
    titolo_sezione: str
    domande: List[Question]

class Scale(BaseModel):
    id: str
    nome: str
    descrizione: str
    sezioni: List[Section]


# --- MODELLI VALUTAZIONE (Evaluation Models) ---

class Answer(BaseModel):
    id_domanda: str
    valore_risposta: int
    note_opzionali: Optional[str] = None

class Evaluation(BaseModel):
    id_valutazione: str = Field(default_factory=lambda: str(uuid.uuid4()))
    id_paziente: str
    anno: int
    id_scala: str
    data_compilazione: datetime = Field(default_factory=datetime.utcnow)
    nome_operatore: str
    risposte: List[Answer]
