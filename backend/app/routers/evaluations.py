from ..pdf_service import render_pdf
from ..audit import record
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
from ..evaluation_contract import resolve_scale, require_answers, scale_snapshot, incomplete_analysis
from ..transactions import atomic, touch_patient
from ..database import database
from pymongo.errors import DuplicateKeyError

from ._helpers import (
    verify_auth,
    log_audit,
    _find_evaluation_document,
    _extract_evaluation_identifier,
    _build_evaluation_selector,
    _hydrate_scale_doc,
    _update_patient_scale_dates,
)

admin_router = APIRouter(dependencies=[Depends(verify_auth)])
public_admin_router = APIRouter()
client_router = APIRouter(dependencies=[Depends(verify_auth)])


# ==========================================
# ADMIN ROUTER (/api/admin)
# ==========================================

@admin_router.get("/evaluations/{id_patient}", response_model=List[Evaluation], tags=["Admin - Evaluations"])
async def get_evaluations(id_patient: str):
    """Storico completo per un utente, per fini analitici."""
    cursor = evaluations_collection.find({"id_paziente": id_patient})
    evaluations = await cursor.to_list(length=None)
    from ..expiry import utc_date
    for ev in evaluations:
        date = utc_date(ev.get("data_compilazione"))
        if date is None:
            raise HTTPException(409, "Storico con data non valida: correggere il documento legacy")
        ev["data_compilazione"] = date
    evaluations.sort(key=lambda ev: (ev["data_compilazione"], str(ev.get("_id", ""))), reverse=True)
    return evaluations


@admin_router.get("/patients/{patient_id}/evaluation-scales", response_model=List[Scale], tags=["Admin - Evaluations"])
async def historical_scales(patient_id: str):
    current = await scales_collection.find({}).to_list(length=None)
    result = {s["id"]: s for s in current}
    async for ev in evaluations_collection.find({"id_paziente": patient_id}).sort("data_compilazione", -1):
        if ev["id_scala"] not in result:
            result[ev["id_scala"]] = await resolve_scale(ev)
    return list(result.values())

@admin_router.get("/evaluations/{evaluation_id}/pdf", tags=["Admin - Evaluations"])
async def download_evaluation_pdf(
    evaluation_id: str,
):
    """Genera e scarica il PDF della valutazione con grafico a barre."""
    eval_doc = await _find_evaluation_document(evaluation_id)
    if not eval_doc:
        raise HTTPException(
            status_code=404,
            detail=f"Valutazione non trovata per id '{evaluation_id}'",
        )

    patient_doc = await patients_collection.find_one({"id": eval_doc["id_paziente"]})
    scale_doc = await resolve_scale(eval_doc)

    analysis = compute_psychometric_analysis(
        risposte=eval_doc.get("risposte", []),
        scale_doc=scale_doc or {},
    )

    domain_map = build_domain_map(scale_doc or {})
    if not domain_map:
        domain_map = DOMINI_POS
    domains = [] if analysis.get("validation_message") else compute_direct_scores(eval_doc.get("risposte", []), domain_map, scale_doc)

    pdf_bytes = await render_pdf(
        generate_evaluation_pdf,
        eval_doc,
        patient_doc or {},
        scale_doc or {},
        domains,
        analysis,
    )

    filename = f"valutazione_{evaluation_id[:8]}.pdf"
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
@admin_router.post("/evaluations/ai-analysis-pdf", tags=["Admin - Evaluations"])
async def download_ai_analysis_pdf(request: AiPdfRequest):
    pdf_bytes = await render_pdf(generate_ai_analysis_pdf, request.patient,
                                       "BOZZA - testo fornito dal client, provenienza non attestata\n\n" + request.report)
    filename = f"analisi_ai_{request.patient.get('cognome', 'paziente')}.pdf"
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@admin_router.get("/evaluations/{evaluation_id}/analysis", tags=["Admin - Evaluations"])
async def get_evaluation_analysis(evaluation_id: str):
    """Restituisce l'analisi psicometrica completa di una valutazione."""
    eval_doc = await _find_evaluation_document(evaluation_id)
    if not eval_doc:
        raise HTTPException(
            status_code=404,
            detail=f"Valutazione non trovata per id '{evaluation_id}'",
        )
    scale_doc = await resolve_scale(eval_doc)
    if not scale_doc:
        raise HTTPException(status_code=404, detail="Scala associata non trovata")

    analysis = compute_psychometric_analysis(
        risposte=eval_doc.get("risposte", []),
        scale_doc=scale_doc,
    )
    analysis["id_valutazione"] = _extract_evaluation_identifier(eval_doc) or evaluation_id
    analysis["id_paziente"] = eval_doc.get("id_paziente", "")
    analysis["id_scala"] = eval_doc.get("id_scala", "")
    return analysis


@admin_router.get("/evaluations/{patient_id}/{scale_id}",
                  response_model=List[AggregatedEvaluation],
                  tags=["Admin - Evaluations"])
async def get_aggregated_evaluation(patient_id: str, scale_id: str):
    """Recupera lo storico valutazioni per utente+scala ordinato per data decrescente."""
    cursor = evaluations_collection.find(
        {"id_paziente": patient_id, "id_scala": scale_id}
    ).sort("data_compilazione", -1)
    eval_docs = await cursor.to_list(length=None)
    if not eval_docs:
        raise HTTPException(status_code=404, detail="Nessuna valutazione trovata")

    from ..expiry import utc_date
    for ev in eval_docs:
        date = utc_date(ev.get("data_compilazione"))
        if date is None:
            raise HTTPException(409, "Storico con data non valida: correggere il documento legacy")
        ev["data_compilazione"] = date
    eval_docs.sort(key=lambda ev: (ev["data_compilazione"], str(ev.get("_id", ""))), reverse=True)
    history = []
    for eval_doc in eval_docs:
        scale_doc = await resolve_scale(eval_doc)
        domain_map = build_domain_map(scale_doc or {})
        if not domain_map:
            domain_map = DOMINI_POS
        invalid = incomplete_analysis(eval_doc.get("risposte", []), scale_doc)
        domains = [] if invalid else compute_direct_scores(eval_doc.get("risposte", []), domain_map, scale_doc=scale_doc)
        history.append(
            AggregatedEvaluation(
                id_valutazione=_extract_evaluation_identifier(eval_doc),
                id_paziente=eval_doc["id_paziente"],
                id_scala=eval_doc["id_scala"],
                anno=eval_doc["anno"],
                data_compilazione=(
                    eval_doc["data_compilazione"].replace(tzinfo=timezone.utc)
                    if isinstance(eval_doc["data_compilazione"], datetime) and eval_doc["data_compilazione"].tzinfo is None
                    else eval_doc["data_compilazione"]
                ),
                nome_operatore=eval_doc["nome_operatore"],
                nome_intervistato=eval_doc.get("nome_intervistato"),
                demographics=eval_doc.get("demographics"),
                snapshot_scala=scale_doc,
                domini=domains,
                risposte=eval_doc.get("risposte", []),
            )
        )
    return history


@admin_router.put("/evaluations/{evaluation_id}",
                  response_model=AggregatedEvaluation,
                  tags=["Admin - Evaluations"])
async def update_evaluation(evaluation_id: str, payload: EvaluationUpdateRequest, auth: dict = Depends(verify_auth)):
    """Modifica inline punteggi/note di una valutazione, restituisce i dati riaggregati."""
    existing = await _find_evaluation_document(evaluation_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Valutazione non trovata")

    scale_doc = await resolve_scale(existing)
    new_risposte = require_answers([r.model_dump() for r in payload.risposte], scale_doc)
    update_data = {"risposte": new_risposte}
    if payload.nome_operatore is not None:
        update_data["nome_operatore"] = payload.nome_operatore
        existing["nome_operatore"] = payload.nome_operatore
    if payload.nome_intervistato is not None:
        update_data["nome_intervistato"] = payload.nome_intervistato
        existing["nome_intervistato"] = payload.nome_intervistato
    if payload.demographics is not None:
        update_data["demographics"] = payload.demographics
        existing["demographics"] = payload.demographics
        
    async def persist_update(session):
        await touch_patient(existing["id_paziente"], session)
        result = await database.evaluations.update_one(
            _build_evaluation_selector(existing), {"$set": update_data}, session=session)
        if not result.matched_count:
            raise HTTPException(409, "Valutazione eliminata durante la modifica")
        await record("MODIFICA_VALUTAZIONE", auth["username"], "Risposte e metadati aggiornati", evaluation_id,
                     session=session, target_version=scale_doc.get("snapshot_hash"))
    await atomic(persist_update)
    _invalidate_dashboard_cache()
    existing["risposte"] = new_risposte

    domain_map = build_domain_map(scale_doc or {})
    if not domain_map:
        domain_map = DOMINI_POS
    domains = compute_direct_scores(new_risposte, domain_map, scale_doc=scale_doc)
    return AggregatedEvaluation(
        id_valutazione=_extract_evaluation_identifier(existing),
        id_paziente=existing["id_paziente"],
        id_scala=existing["id_scala"],
        anno=existing["anno"],
        data_compilazione=existing["data_compilazione"],
        nome_operatore=existing["nome_operatore"],
        nome_intervistato=existing.get("nome_intervistato"),
        demographics=existing.get("demographics"),
        snapshot_scala=scale_doc,
        domini=domains,
        risposte=new_risposte,
    )

@admin_router.delete("/evaluations/{evaluation_id}", tags=["Admin - Evaluations"])
async def delete_evaluation(evaluation_id: str, auth: dict = Depends(verify_auth)):
    """Elimina definitivamente una singola valutazione dal database."""
    eval_doc = await _find_evaluation_document(evaluation_id)
    if not eval_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Valutazione non trovata")

    patient_id = eval_doc.get("id_paziente")
    selector = _build_evaluation_selector(eval_doc)
    async def remove(session):
        await touch_patient(patient_id, session)
        result = await database.evaluations.delete_one(selector, session=session)
        if result.deleted_count != 1:
            raise HTTPException(409, "Valutazione gia eliminata o modificata")
        await record("CANCELLAZIONE_VALUTAZIONE", auth["username"], "Valutazione eliminata; provenienza delle relazioni conservata", evaluation_id, session=session)
    await atomic(remove)
    _invalidate_dashboard_cache()
    # C6 reads source evaluations; denormalized dates are only a compatibility cache.

    return {"status": "success", "message": "Valutazione eliminata con successo"}


# ==========================================
# CLIENT ROUTER (/api/client)
# ==========================================

@client_router.post("/evaluations", response_model=Evaluation, status_code=status.HTTP_201_CREATED, tags=["Client - Evaluations"])
@_limiter.limit("20/minute")
async def create_evaluation(request: Request, evaluation: Evaluation, auth_context: dict = Depends(verify_auth)):
    """Salva una nuova valutazione compilata nel database dopo aver validato paziente, scala e risposte."""
    # 1. Validazione esistenza utente (SCORE-01, Task 10.1)
    id_paziente = evaluation.id_paziente
    patient_doc = await patients_collection.find_one({"id": id_paziente})
    if not patient_doc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Utente con ID '{id_paziente}' non trovato"
        )

    # 2. Validazione esistenza scala (SCORE-01, Task 10.1)
    id_scala = evaluation.id_scala
    scale_doc = await scales_collection.find_one({"id": id_scala})
    if not scale_doc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Scala con ID '{id_scala}' non trovata"
        )

    eval_dict = evaluation.model_dump()
    if not eval_dict.get("data_compilazione"):
        eval_dict["data_compilazione"] = datetime.now(timezone.utc)
    # Imposta l'operatore autenticato dal token JWT
    operatore_autenticato = auth_context.get("username") or "Operatore Sconosciuto"
    eval_dict["nome_operatore"] = operatore_autenticato
    submitted_answers = list(eval_dict["risposte"])
    
    async def persist(session):
        await touch_patient(id_paziente, session, active=True, expected_id=patient_doc["_id"])
        current_scale = await database.scales.find_one({"id": id_scala}, session=session)
        if not current_scale:
            raise HTTPException(409, "Protocollo non disponibile")
        await database.scales.update_one({"_id": current_scale["_id"]}, {"$inc": {"write_revision": 1}}, session=session)
        eval_dict["snapshot_scala"] = scale_snapshot(current_scale)
        eval_dict["risposte"] = require_answers(submitted_answers, current_scale)
        result = await database.evaluations.insert_one(dict(eval_dict), session=session)
        await record("COMPILAZIONE_SCALA", operatore_autenticato, "Valutazione completa acquisita con snapshot", eval_dict["id_valutazione"],
                     session=session, target_version=eval_dict["snapshot_scala"].get("snapshot_hash"))
        return result
    try:
        await atomic(persist)
    except DuplicateKeyError as exc:
        raise HTTPException(409, "Identificativo valutazione gia presente") from exc
    evaluation = Evaluation(**eval_dict)
    _invalidate_dashboard_cache()

    # Mantiene aggiornati i campi ultimo_*_compilato sul paziente (FUN-01, Task 8.2)
    try:
        await _update_patient_scale_dates(id_paziente)
    except Exception:
        _logger.warning("Cache date non aggiornata dopo salvataggio; proiezione C6 usa le valutazioni sorgente")
        
    return evaluation

