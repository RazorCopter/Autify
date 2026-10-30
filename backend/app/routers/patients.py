from ..audit import record
from ..transactions import atomic
from ..database import database
import logging
from fastapi import APIRouter, HTTPException, status, UploadFile, File, Header, Depends, Request, Query
from slowapi import Limiter
from slowapi.util import get_remote_address
from fastapi.responses import StreamingResponse

_limiter = Limiter(key_func=get_remote_address)
_logger = logging.getLogger("autify")
from typing import List, Optional
from bson import ObjectId
import httpx
from ..models import Scale, Evaluation, Patient, PaginatedPatients, AppSettings, Section, Question, Option, DOMINI_POS, AggregatedEvaluation, EvaluationUpdateRequest, AiAnalysis, AiAnalysisCreate, AiAnalysisUpdate, AiAnalysisRequest, AiPdfRequest, UserCreate, UserUpdate, AuditLogCreate, AuditLogResponse
from ..database import evaluations_collection, settings_collection, patients_collection, scales_collection, users_collection, ai_analyses_collection, audit_logs_collection
from ..pdf_generator import generate_evaluation_pdf, generate_ai_analysis_pdf
from ..analytics import compute_psychometric_analysis, compute_direct_scores, build_domain_map, calcola_punteggi_sis
from datetime import datetime, timezone, timedelta
import json
import re
from pydantic import BaseModel
import uuid
import io
import os
import asyncio
from pathlib import Path
from .. import auth as auth_module
from . import _invalidate_dashboard_cache

from ._helpers import (
    verify_auth,
    log_audit,
    _classify_scale,
)

admin_router = APIRouter(dependencies=[Depends(verify_auth)])
public_admin_router = APIRouter()
client_router = APIRouter(dependencies=[Depends(verify_auth)])


# ==========================================
# ADMIN ROUTER (/api/admin)
# ==========================================


def _build_patient_search_condition(search: str) -> dict:
    """Crea una ricerca multi-parola sicura sui campi nome e cognome.

    Ogni parola deve comparire in almeno uno dei due campi, così query come
    "Mario Ro" trovano anche un utente con nome "Mario" e cognome "Rossi".
    """
    terms = [term for term in search.split() if term]
    token_conditions = [
        {
            "$or": [
                {"nome": {"$regex": re.escape(term), "$options": "i"}},
                {"cognome": {"$regex": re.escape(term), "$options": "i"}},
            ]
        }
        for term in terms
    ]

    if len(token_conditions) == 1:
        return token_conditions[0]
    return {"$and": token_conditions}


@admin_router.get("/patients", response_model=PaginatedPatients, tags=["Admin - Patients"])
async def get_patients(
    page: int = Query(default=1, ge=1, description="Numero di pagina (1-based)"),
    page_size: int = Query(default=50, ge=1, le=200, description="Elementi per pagina"),
    search: Optional[str] = Query(default=None, description="Ricerca su nome e cognome"),
    status: Optional[str] = Query(default="active", pattern="^(active|archived|all)$", description="Filtro stato utente"),
    filter: Optional[str] = Query(default=None, pattern="^(scaduti|in_scadenza|incompleti|mai_valutati|coperti|da_completare)$", description="Filtro semantico sullo stato delle scale"),
    validity_pos: int = Query(default=12, ge=1, deprecated=True, description="Compatibilita: ignorato; policy server. Mesi di validità POS/generica"),
    validity_sm: int = Query(default=12, ge=1, deprecated=True, description="Compatibilita: ignorato; policy server. Mesi di validità San Martín"),
    validity_sis: int = Query(default=36, ge=1, deprecated=True, description="Compatibilita: ignorato; policy server. Mesi di validità SIS"),
):
    from ..expiry import project, utc_date
    query = {}
    if status == "active":
        query["attivo"] = {"$ne": False}
    elif status == "archived":
        query["attivo"] = False
    if search and search.strip():
        query.update(_build_patient_search_condition(search))
    # Stable pagination after semantic filtering; no truncated candidate set.
    cursor = patients_collection.find(query).sort([("cognome", 1), ("nome", 1), ("id", 1), ("_id", 1)])
    if filter:
        patients = await cursor.to_list(length=None)
        await project(patients)
        states = ({"coperti", "in_scadenza"} if filter == "coperti" else
                  {"mai_valutati", "incompleti", "scaduti"} if filter == "da_completare" else {filter})
        patients = [p for p in patients if p["stato_valutazioni"] in states]
        total = len(patients)
        patients = patients[(page - 1) * page_size:page * page_size]
    else:
        total = await patients_collection.count_documents(query)
        patients = await cursor.skip((page - 1) * page_size).limit(page_size).to_list(length=page_size)
        await project(patients)
    ids = [p["id"] for p in patients]
    latest = {}
    async for analysis in ai_analyses_collection.find({"id_paziente": {"$in": ids}}, {"id_paziente": 1, "timestamp": 1}):
        date = utc_date(analysis.get("timestamp"))
        pid = analysis["id_paziente"]
        if date and (pid not in latest or date > latest[pid]):
            latest[pid] = date
    for patient in patients:
        date = latest.get(patient["id"])
        patient["ultima_analisi_ia"] = date.isoformat() if date else None
    return PaginatedPatients(items=patients, total=total, page=page, page_size=page_size)

@admin_router.post("/patients", response_model=Patient, status_code=status.HTTP_201_CREATED, tags=["Admin - Patients"])
async def create_patient(patient: Patient, auth_context: dict = Depends(verify_auth)):
    patient_dict = patient.model_dump()
    if not patient_dict.get("id"):
        patient_dict.pop("id", None)
        patient = Patient(**patient_dict)
        patient_dict = patient.model_dump()
    else:
        existing = await patients_collection.find_one({"id": patient.id})
        if existing:
            raise HTTPException(status_code=400, detail="Utente con questo ID già esistente")
    async def persist(session):
        await database.patients.insert_one(patient_dict, session=session)
        await record("CREAZIONE_UTENTE", auth_context["username"], "Creata anagrafica", patient.id, session=session)
    await atomic(persist)
    _invalidate_dashboard_cache()

    return patient

@admin_router.put("/patients/{id}", response_model=Patient, tags=["Admin - Patients"])
async def update_patient(id: str, patient: Patient, auth_context: dict = Depends(verify_auth)):
    if patient.id != id:
        raise HTTPException(status_code=400, detail="L'ID nel corpo della richiesta non coincide con l'ID nel path")
    patient_dict = patient.model_dump()
    async def persist(session):
        result = await database.patients.update_one({"id": id}, {"$set": patient_dict, "$inc": {"write_revision": 1}}, session=session)
        if result.matched_count == 0:
            raise HTTPException(404, "Utente non trovato")
        await record("MODIFICA_UTENTE", auth_context["username"], "Aggiornata anagrafica", id, session=session)
    await atomic(persist)
    _invalidate_dashboard_cache()

    return patient

@admin_router.delete("/patients/{id}", tags=["Admin - Patients"])
async def delete_patient(id: str, auth_context: dict = Depends(verify_auth)):
    patient_doc = await patients_collection.find_one({"id": id})
    utente_nome = ""
    if patient_doc:
        cognome = patient_doc.get("cognome", "")
        nome = patient_doc.get("nome", "")
        if cognome or nome:
            utente_nome = f" {cognome} {nome}"
            
    async def remove(session):
        result = await database.patients.delete_one({"id": id}, session=session)
        if result.deleted_count == 0:
            raise HTTPException(404, "Utente non trovato")
        for collection in ("evaluations", "ai_analyses", "ai_jobs", "notifications"):
            await database[collection].delete_many({"id_paziente": id}, session=session)
        await record("CANCELLAZIONE_UTENTE", auth_context["username"], "Eliminata anagrafica e dati collegati inclusi job e notifiche", id, session=session)
    await atomic(remove)
    _invalidate_dashboard_cache()

    return {"message": "Utente, relative valutazioni e analisi IA eliminati con successo"}

@client_router.get("/patients", response_model=List[Patient], tags=["Client - Patients"])
@_limiter.limit("30/minute")
async def get_client_patients(request: Request):
    """Recupero pazienti per la selezione prima del wizard"""
    cursor = patients_collection.find({})
    patients = await cursor.to_list(length=None)
    # The frontend only needs id, nome, cognome. Patient model has them.
    return patients
