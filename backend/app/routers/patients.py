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

@admin_router.get("/patients", response_model=PaginatedPatients, tags=["Admin - Patients"])
async def get_patients(
    page: int = Query(default=1, ge=1, description="Numero di pagina (1-based)"),
    page_size: int = Query(default=50, ge=1, le=200, description="Elementi per pagina"),
    search: Optional[str] = Query(default=None, description="Ricerca su nome e cognome"),
    status: Optional[str] = Query(default="active", pattern="^(active|archived|all)$", description="Filtro stato utente"),
    filter: Optional[str] = Query(default=None, pattern="^(scaduti|in_scadenza|incompleti|mai_valutati)$", description="Filtro semantico sullo stato delle scale"),
    validity_pos: int = Query(default=12, ge=1, description="Mesi di validità POS/generica"),
    validity_sm: int = Query(default=12, ge=1, description="Mesi di validità San Martín"),
    validity_sis: int = Query(default=36, ge=1, description="Mesi di validità SIS"),
):
    # Costruzione query filtro stato attivo/archiviato
    query: dict = {}
    if status == "active":
        query["attivo"] = True
    elif status == "archived":
        query["attivo"] = False
    # status == "all" → nessun filtro

    if search and search.strip():
        regex = {"$regex": search.strip(), "$options": "i"}
        query["$or"] = [{"nome": regex}, {"cognome": regex}]

    # ── Filtri semantici server-side ────────────────────────────────────────
    if filter in ("scaduti", "in_scadenza", "incompleti", "mai_valutati"):
        now = datetime.now(timezone.utc)

        # Recupero parametri server-side se presenti
        settings_doc = await settings_collection.find_one({"id": "global_settings"})
        if settings_doc and "scale_validity_months" in settings_doc:
            val_map = settings_doc["scale_validity_months"]
            validity_pos = val_map.get("pos", validity_pos)
            validity_sm = val_map.get("san_martin", validity_sm)
            validity_sis = val_map.get("sis", validity_sis)

        # Calcola le soglie di scadenza per ciascun tipo di scala
        def _cutoff(months: int) -> datetime:
            return now - timedelta(days=months * 30)

        cutoff_pos = _cutoff(validity_pos)
        cutoff_sm = _cutoff(validity_sm)
        cutoff_sis = _cutoff(validity_sis)

        # Campi data delle scale nel documento paziente
        SCALE_FIELDS = [
            ("ultimo_pos_compilato", cutoff_pos),
            ("ultimo_san_martin_compilato", cutoff_sm),
            ("ultimo_sis_compilato", cutoff_sis),
            ("ultimo_ogva_compilato", cutoff_pos),
            ("ultimo_sabs_compilato", cutoff_pos),
            ("ultimo_oso_compilato", cutoff_pos),
        ]

        filter_condition = None

        if filter == "mai_valutati":
            # Tutte le date di scala sono null o mancanti
            filter_condition = {
                "$and": [
                    {"$or": [{f: None}, {f: {"$exists": False}}, {f: ""}]}
                    for f, _ in SCALE_FIELDS
                ]
            }

        elif filter == "incompleti":
            # Almeno una data di scala è null o mancante
            filter_condition = {
                "$or": [
                    {"$or": [{f: None}, {f: {"$exists": False}}, {f: ""}]}
                    for f, _ in SCALE_FIELDS
                ]
            }

        elif filter == "scaduti":
            # Almeno una scala presente è scaduta (data < cutoff)
            scaduti_conditions = []
            for field, cutoff in SCALE_FIELDS:
                # Il campo esiste, non è null, ed è precedente alla soglia
                scaduti_conditions.append({
                    field: {
                        "$nin": [None, ""],
                        "$lt": cutoff.isoformat()
                    }
                })
            filter_condition = {"$or": scaduti_conditions}

        elif filter == "in_scadenza":
            # Almeno una scala presente è in scadenza (cutoff <= data < cutoff + 30gg warning)
            warning_days = 30
            in_scadenza_conditions = []
            for field, cutoff in SCALE_FIELDS:
                warning_cutoff = cutoff + timedelta(days=warning_days)
                in_scadenza_conditions.append({
                    "$and": [
                        {field: {"$ne": None}},
                        {field: {"$ne": ""}},
                        {field: {"$gte": cutoff.isoformat()}},
                        {field: {"$lt": warning_cutoff.isoformat()}},
                    ]
                })
            filter_condition = {"$or": in_scadenza_conditions}

        if filter_condition:
            if "$and" in query:
                query["$and"].append(filter_condition)
            elif query:
                # Trasforma i vincoli esistenti (es. search/status) e la condizione filtro in un unico $and
                existing_parts = []
                for k, v in list(query.items()):
                    existing_parts.append({k: v})
                existing_parts.append(filter_condition)
                query.clear()
                query["$and"] = existing_parts
            else:
                query.update(filter_condition)

    total = await patients_collection.count_documents(query)
    skip = (page - 1) * page_size
    patients = await patients_collection.find(query).skip(skip).limit(page_size).to_list(length=page_size)

    # Recupera le scale per mappare l'ID al nome (1 query)
    scales_list = await scales_collection.find({}).to_list(length=100)
    scale_map = {}
    for s in scales_list:
        nome_lower = s["nome"].lower()
        scale_map[s["id"]] = nome_lower
        mongo_id = s.get("_id")
        if mongo_id:
            scale_map[str(mongo_id)] = nome_lower

    # Raccoglie gli ID dei pazienti della pagina corrente per le query bulk mirate
    pat_ids = [p["id"] for p in patients if p.get("id")]

    # Carica le valutazioni solo per i pazienti della pagina corrente
    all_evals = await evaluations_collection.find(
        {"id_paziente": {"$in": pat_ids}}
    ).sort("data_compilazione", -1).to_list(length=10000)
    evals_by_patient: dict = {}
    for ev in all_evals:
        pid = ev.get("id_paziente")
        if pid:
            evals_by_patient.setdefault(pid, []).append(ev)

    # Carica le ultime analisi IA solo per i pazienti della pagina corrente
    all_analyses = await ai_analyses_collection.find(
        {"id_paziente": {"$in": pat_ids}}
    ).sort("timestamp", -1).to_list(length=2000)
    latest_ia_by_patient: dict = {}
    for an in all_analyses:
        pid = an.get("id_paziente")
        if pid and pid not in latest_ia_by_patient:
            latest_ia_by_patient[pid] = an

    # Arricchisce ciascun utente con le date delle ultime scale compilate
    for pat in patients:
        pat_id = pat["id"]
        pat_dict = pat if isinstance(pat, dict) else pat.__dict__

        pat_dict["ultimo_pos_compilato"] = None
        pat_dict["ultimo_san_martin_compilato"] = None
        pat_dict["ultimo_sis_compilato"] = None
        pat_dict["ultimo_ogva_compilato"] = None
        pat_dict["ultimo_sabs_compilato"] = None
        pat_dict["ultimo_oso_compilato"] = None
        pat_dict["ultima_analisi_ia"] = None

        latest_ai = latest_ia_by_patient.get(pat_id)
        if latest_ai and latest_ai.get("timestamp"):
            ts = latest_ai["timestamp"]
            pat_dict["ultima_analisi_ia"] = ts.isoformat() if isinstance(ts, datetime) else str(ts)

        for ev in evals_by_patient.get(pat_id, []):
            scale_id = ev.get("id_scala")
            scale_id_str = str(scale_id) if scale_id else ""
            scale_name = scale_map.get(scale_id, scale_map.get(scale_id_str, "")).lower()

            data_val = ev.get("data_compilazione")
            data_str = data_val.isoformat() if isinstance(data_val, datetime) else (str(data_val) if data_val else None)

            scale_type = _classify_scale(scale_name, scale_id_str)
            field_map = {
                "pos": "ultimo_pos_compilato",
                "san_martin": "ultimo_san_martin_compilato",
                "sis": "ultimo_sis_compilato",
                "ogva": "ultimo_ogva_compilato",
                "sabs": "ultimo_sabs_compilato",
                "oso": "ultimo_oso_compilato",
            }
            if scale_type in field_map and not pat_dict.get(field_map[scale_type]):
                pat_dict[field_map[scale_type]] = data_str

            if (pat_dict.get("ultimo_pos_compilato") and
                    pat_dict.get("ultimo_san_martin_compilato") and
                    pat_dict.get("ultimo_sis_compilato") and
                    pat_dict.get("ultimo_ogva_compilato") and
                    pat_dict.get("ultimo_sabs_compilato") and
                    pat_dict.get("ultimo_oso_compilato")):
                break

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
    await patients_collection.insert_one(patient_dict)
    _invalidate_dashboard_cache()

    await log_audit(
        "CREAZIONE_UTENTE",
        auth_context["username"],
        f"Creato nuovo utente: {patient.nome} {patient.cognome}",
        patient.id
    )

    return patient

@admin_router.put("/patients/{id}", response_model=Patient, tags=["Admin - Patients"])
async def update_patient(id: str, patient: Patient, auth_context: dict = Depends(verify_auth)):
    if patient.id != id:
        raise HTTPException(status_code=400, detail="L'ID nel corpo della richiesta non coincide con l'ID nel path")
    patient_dict = patient.model_dump()
    result = await patients_collection.replace_one({"id": id}, patient_dict)
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Utente non trovato")
        
    await log_audit(
        "MODIFICA_UTENTE", 
        auth_context["username"], 
        f"Aggiornata anagrafica utente: {patient.nome} {patient.cognome}", 
        id
    )
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
            
    # Elimina a cascata tutte le valutazioni e le analisi IA associate all'utente prima di rimuoverlo
    await evaluations_collection.delete_many({"id_paziente": id})
    await ai_analyses_collection.delete_many({"id_paziente": id})
    
    result = await patients_collection.delete_one({"id": id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Utente non trovato")
    _invalidate_dashboard_cache()

    await log_audit(
        "CANCELLAZIONE_UTENTE", 
        auth_context["username"], 
        f"Eliminato utente{utente_nome}, relative valutazioni e analisi IA".strip(), 
        id
    )
        
    return {"message": "Utente, relative valutazioni e analisi IA eliminati con successo"}

@client_router.get("/patients", response_model=List[Patient], tags=["Client - Patients"])
@_limiter.limit("30/minute")
async def get_client_patients(request: Request):
    """Recupero pazienti per la selezione prima del wizard"""
    cursor = patients_collection.find({})
    patients = await cursor.to_list(length=1000)
    # The frontend only needs id, nome, cognome. Patient model has them.
    return patients
