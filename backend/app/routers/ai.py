from ..pdf_service import render_pdf
from ..audit import record
from ..ai_context import text_hash
from ..job_worker import enqueue
from ..transactions import atomic, touch_patient
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
from ..database import evaluations_collection, settings_collection, patients_collection, scales_collection, users_collection, ai_analyses_collection, audit_logs_collection, ai_jobs_collection, notifications_collection
from ..pdf_generator import generate_evaluation_pdf, generate_ai_analysis_pdf
from ..analytics import compute_psychometric_analysis, compute_direct_scores, build_domain_map, calcola_punteggi_sis
from datetime import datetime, timezone, timedelta
import json
import re
from pydantic import BaseModel, Field
import uuid
import io
import os
import asyncio
from pathlib import Path
from .. import auth as auth_module
from ..ai import (
    AISettingsStored,
    AITestConnectionRequest,
    AITestConnectionResponse,
    AIDiscoverModelsRequest,
    AIDiscoverModelsResponse,
    AIAnalyzeRequest,
    AIAnalyzeResponse,
    AIAttachment,
    AIJobDetail,
    AINotification,
    AINotificationUnreadCount,
    DEFAULT_SYSTEM_PROMPT,
    decrypt_secret,
    resolve_secret,
    resolve_custom_headers,
)
from ..ai.adapters import get_ai_adapter
from ..ai.adapters.openai_compatible import OpenAICompatibleAdapter
from .settings import get_or_migrate_ai_settings


from ._helpers import (
    verify_auth,
    log_audit,
    _find_evaluation_document,
)

admin_router = APIRouter(dependencies=[Depends(verify_auth)])
public_admin_router = APIRouter()
client_router = APIRouter(dependencies=[Depends(verify_auth)])


# ==========================================
# ADMIN ROUTER (/api/admin)
# ==========================================

@admin_router.get("/patients/{id_patient}/ai-analyses", response_model=List[AiAnalysis], tags=["Admin - AI Analyses"])
async def get_patient_ai_analyses(id_patient: str):
    cursor = ai_analyses_collection.find({"id_paziente": id_patient}).sort("timestamp", -1)
    analyses = await cursor.to_list(length=100)
    for a in analyses:
        a["report_hash"] = text_hash(a["report"])
        if a.get("review_status") == "approved" and a.get("reviewed_report_hash") != a["report_hash"]:
            a["review_status"] = "draft"
        if "timestamp" in a and isinstance(a["timestamp"], datetime) and a["timestamp"].tzinfo is None:
            a["timestamp"] = a["timestamp"].replace(tzinfo=timezone.utc)
    return analyses

@admin_router.post("/patients/{id_patient}/ai-analyses", response_model=AiAnalysis, status_code=status.HTTP_201_CREATED, tags=["Admin - AI Analyses"])
async def save_patient_ai_analysis(id_patient: str, payload: AiAnalysisCreate, auth_context: dict = Depends(verify_auth)):
    patient = await patients_collection.find_one({"id": id_patient})
    if not patient:
        raise HTTPException(status_code=404, detail="Utente non trovato")
    
    analysis = AiAnalysis(
        id_paziente=id_patient,
        report=payload.report,
        notes=payload.notes,
        evaluations_used=payload.evaluations_used,
        review_status="draft", provenance={"status": "manual_unverified"},
        report_hash=text_hash(payload.report),
    )
    analysis_dict = analysis.model_dump()
    # Pydantic datetime conversion support for motor/mongodb insertion
    if isinstance(analysis_dict.get("timestamp"), datetime) and analysis_dict["timestamp"].tzinfo is None:
        analysis_dict["timestamp"] = analysis_dict["timestamp"].replace(tzinfo=timezone.utc)
    async def persist_manual(session):
        await touch_patient(id_patient, session, active=True, expected_id=patient["_id"])
        for ident in payload.evaluations_used:
            if not await database.evaluations.find_one({"id_valutazione": ident, "id_paziente": id_patient}, session=session):
                raise HTTPException(422, "Riferimento valutazione non disponibile per questo utente")
        await database.ai_analyses.insert_one(dict(analysis_dict), session=session)
        await record("SALVATAGGIO_REPORT_IA", auth_context["username"], "Bozza manuale salvata senza testo nel registro", analysis.id,
                     session=session, target_version=analysis.report_hash)
    await atomic(persist_manual)
    
    return analysis

class ApproveAnalysisRequest(BaseModel):
    report_hash: str = Field(pattern=r"^[a-f0-9]{64}$")


@admin_router.post("/patients/ai-analyses/{id_analysis}/approve", tags=["Admin - AI Analyses"])
async def approve_analysis(id_analysis: str, payload: ApproveAnalysisRequest, auth: dict = Depends(verify_auth)):
    if auth["role"] != "admin":
        raise HTTPException(403, "Solo un amministratore puo approvare la relazione revisionata")
    async def approve(session):
        report = await database.ai_analyses.find_one({"id": id_analysis}, session=session)
        if not report:
            raise HTTPException(404, "Relazione non trovata")
        if text_hash(report["report"]) != payload.report_hash:
            raise HTTPException(409, "Relazione modificata: rileggere prima di approvare")
        await touch_patient(report["id_paziente"], session)
        now = datetime.now(timezone.utc)
        await database.ai_analyses.update_one({"_id": report["_id"]}, {"$set": {
            "review_status": "approved", "reviewed_by": auth["username"], "reviewed_at": now,
            "reviewed_report_hash": payload.report_hash,
        }}, session=session)
        await record("APPROVAZIONE_REPORT_IA", auth["username"], "Revisione educativa esplicita della relazione", id_analysis,
                     session=session, target_version=payload.report_hash)
    await atomic(approve)
    return {"message": "Relazione approvata"}


@admin_router.get("/patients/ai-analyses/{id_analysis}/pdf", tags=["Admin - AI Analyses"])
async def saved_analysis_pdf(id_analysis: str):
    report = await database.ai_analyses.find_one({"id": id_analysis})
    if not report:
        raise HTTPException(404, "Relazione non trovata")
    parent = await database.patients.find_one({"id": report["id_paziente"]})
    if not parent:
        raise HTTPException(404, "Utente non trovato")
    approved = report.get("review_status") == "approved" and report.get("reviewed_report_hash") == text_hash(report["report"])
    label = "Relazione revisionata e approvata" if approved else "BOZZA - da sottoporre a revisione educativa"
    provenance = report.get("provenance") or {}
    sources = ", ".join(report.get("evaluations_used", [])) or "nessuna valutazione selezionata"
    header = f"{label}\n\nFonti: {sources}\n\nProvenienza: {provenance.get('status', 'legacy_non_attestata')}\n\n"
    pdf = await render_pdf(generate_ai_analysis_pdf, parent, header + report["report"])
    return StreamingResponse(io.BytesIO(pdf), media_type="application/pdf",
                             headers={"Content-Disposition": 'attachment; filename="relazione.pdf"', "Cache-Control": "no-store"})


@admin_router.put("/patients/ai-analyses/{id_analysis}", tags=["Admin - AI Analyses"])
async def update_ai_analysis(id_analysis: str, payload: AiAnalysisUpdate, auth_context: dict = Depends(verify_auth)):
    existing = await ai_analyses_collection.find_one({"id": id_analysis})
    if not existing:
        raise HTTPException(status_code=404, detail="Analisi IA non trovata")
    
    update_data = {}
    if payload.notes is not None:
        update_data["notes"] = payload.notes
        
    if update_data:
        async def persist(session):
            await touch_patient(existing["id_paziente"], session)
            result = await database.ai_analyses.update_one({"_id": existing["_id"]}, {"$set": update_data}, session=session)
            if not result.matched_count:
                raise HTTPException(409, "Relazione eliminata durante la modifica")
            await record("MODIFICA_REPORT_IA", auth_context["username"], "Nota della relazione aggiornata; testo non registrato", id_analysis, session=session)
        await atomic(persist)
    return {"message": "Analisi IA aggiornata con successo"}

@admin_router.delete("/patients/ai-analyses/{id_analysis}", tags=["Admin - AI Analyses"])
async def delete_ai_analysis(id_analysis: str, auth_context: dict = Depends(verify_auth)):
    existing = await ai_analyses_collection.find_one({"id": id_analysis})
    if not existing:
        raise HTTPException(status_code=404, detail="Analisi IA non trovata")
        
    async def remove(session):
        result = await database.ai_analyses.delete_one({"_id": existing["_id"]}, session=session)
        if not result.deleted_count:
            raise HTTPException(409, "Relazione gia eliminata")
        await record("CANCELLAZIONE_REPORT_IA", auth_context["username"], "Relazione eliminata senza testo nel registro", id_analysis, session=session)
    await atomic(remove)
    return {"message": "Analisi IA eliminata con successo"}

@admin_router.post("/ai/test-connection", response_model=AITestConnectionResponse, tags=["Admin - AI"])
@_limiter.limit("15/minute")
async def test_ai_connection(
    request: Request,
    req: AITestConnectionRequest,
    auth: dict = Depends(verify_auth),
):
    if auth.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Solo gli amministratori possono testare i provider IA")

    stored = await get_or_migrate_ai_settings()
    target_provider = req.provider or stored.active_provider

    adapter = get_ai_adapter(
        settings=stored,
        provider_override=req.provider,
        api_key_override=req.api_key,
        model_override=req.model,
        base_url_override=req.base_url,
        protocol_override=req.protocol,
        custom_headers_override=req.custom_headers,
    )

    success, latency_ms, message = await adapter.test_connection()
    target_model = req.model or (
        stored.gemini.model if target_provider == "gemini"
        else stored.openai.model if target_provider == "openai"
        else stored.openai_compatible.model
    )

    operatore = auth.get("username", "operatore")
    await log_audit(
        "AI_TEST_CONNECTION",
        operatore,
        f"Provider: {target_provider}, Model: {target_model}, Esito: {'OK' if success else 'KO'} ({latency_ms}ms)",
        None,
    )

    return AITestConnectionResponse(
        success=success,
        provider=target_provider,
        model=target_model,
        latency_ms=latency_ms,
        message=message,
    )

@admin_router.post("/ai/openai-compatible/models", response_model=AIDiscoverModelsResponse, tags=["Admin - AI"])
@_limiter.limit("15/minute")
async def discover_openai_compatible_models(
    request: Request,
    req: AIDiscoverModelsRequest,
    auth: dict = Depends(verify_auth),
):
    if auth.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Solo gli amministratori possono scoprire i modelli IA")

    stored = await get_or_migrate_ai_settings()

    target_base_url = req.base_url or stored.openai_compatible.base_url
    target_api_key = resolve_secret(req.api_key, stored.openai_compatible.api_key_encrypted)
    target_headers = resolve_custom_headers(req.custom_headers, stored.openai_compatible.custom_headers)

    adapter = OpenAICompatibleAdapter(
        base_url=target_base_url,
        api_key=target_api_key,
        custom_headers=target_headers,
        generation=stored.generation,
        network=stored.network,
    )

    models = await adapter.fetch_available_models()

    operatore = auth.get("username", "operatore")
    await log_audit(
        "AI_DISCOVER_MODELS",
        operatore,
        f"Base URL: {target_base_url}, Modelli trovati: {len(models)}",
        None,
    )

    return AIDiscoverModelsResponse(models=models, count=len(models))

def _iso(value) -> Optional[str]:
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).isoformat()
    return value


def _public_job(document: dict) -> dict:
    return {
        "id": document["id"],
        "job_id": document["id"],
        "username": document["username"],
        "id_paziente": document.get("id_paziente"),
        "patient_name": document.get("patient_name"),
        "status": document["status"],
        "created_at": _iso(document["created_at"]),
        "started_at": _iso(document.get("started_at")),
        "completed_at": _iso(document.get("completed_at")),
        "error_message": document.get("error_message"),
        "analysis_id": document.get("analysis_id"),
        "report_preview": document.get("report_preview"),
    }


def _public_notification(document: dict) -> dict:
    return {
        "id": document["id"],
        "username": document["username"],
        "type": document.get("type", "ai_analysis_completed"),
        "title": document.get("title", "Elaborazione IA"),
        "message": document["message"],
        "job_id": document.get("job_id"),
        "analysis_id": document.get("analysis_id"),
        "id_paziente": document.get("id_paziente"),
        "patient_name": document.get("patient_name"),
        "read": document.get("read", False),
        "created_at": _iso(document["created_at"]),
    }


@admin_router.post("/ai/analyze", response_model=AIAnalyzeResponse, status_code=status.HTTP_202_ACCEPTED, tags=["Admin - AI Analyses"])
@_limiter.limit("20/minute")
async def analyze_evaluation(
    request: Request,
    body: AIAnalyzeRequest,
    auth: dict = Depends(verify_auth),
):
    """Valida la richiesta, persiste il job e restituisce immediatamente HTTP 202."""
    if not auth.get("ai_enabled", False):
        raise HTTPException(status_code=403, detail="Non sei abilitato all'uso dell'IA")

    stored = await get_or_migrate_ai_settings()
    if auth.get("role") == "viewer" and not stored.viewer_ai_enabled:
        raise HTTPException(status_code=403, detail="L'uso dell'IA per i profili Viewer è disabilitato a livello globale")
    if auth.get("role") == "viewer" and body.system_prompt is not None:
        raise HTTPException(status_code=403, detail="I profili Viewer non sono autorizzati a personalizzare il prompt di sistema")

    from ..ai_context import capture_context
    captured = await capture_context(body, (body.system_prompt if auth["role"] == "admin" else None)
                                     or stored.system_prompt or DEFAULT_SYSTEM_PROMPT)
    patient_id = body.id_paziente
    patient_name = captured["patient_name"] or "Utente"
    username = auth["username"]
    created_at = datetime.now(timezone.utc)
    job_id = f"job_{uuid.uuid4().hex[:12]}"
    await enqueue({
        "id": job_id,
        "username": username,
        "owner_token_version": auth["token_version"],
        "parent_mongo_id": captured["parent_mongo_id"],
        "id_paziente": patient_id,
        "patient_name": patient_name,
        "status": "pending",
        "created_at": created_at,
        "started_at": None,
        "completed_at": None,
        "error_message": None,
        "analysis_id": None,
        "evaluations_used": captured["evaluations_used"],
        "provenance": captured["provenance"],
        "user_prompt": captured["user_prompt"],
        "system_prompt": captured["system_prompt"],
        "attachment": captured["attachment"],
    })
    return AIAnalyzeResponse(
        id=job_id, job_id=job_id, status="pending", id_paziente=patient_id,
        patient_name=patient_name, created_at=created_at.isoformat(),
        message="Elaborazione IA avviata in background",
    )


@admin_router.get("/ai/jobs", response_model=List[AIJobDetail], tags=["Admin - AI Jobs"])
async def list_ai_jobs(limit: int = Query(30, ge=1, le=100), auth: dict = Depends(verify_auth)):
    documents = await ai_jobs_collection.find({"username": auth["username"]}).sort("created_at", -1).limit(limit).to_list(length=limit)
    return [_public_job(document) for document in documents]


@admin_router.get("/ai/jobs/{job_id}", response_model=AIJobDetail, tags=["Admin - AI Jobs"])
async def get_ai_job(job_id: str, auth: dict = Depends(verify_auth)):
    document = await ai_jobs_collection.find_one({"id": job_id, "username": auth["username"]})
    if not document:
        raise HTTPException(status_code=404, detail="Job IA non trovato")
    return _public_job(document)


@admin_router.get("/notifications", response_model=List[AINotification], tags=["Admin - Notifications"])
async def list_notifications(limit: int = Query(50, ge=1, le=100), auth: dict = Depends(verify_auth)):
    documents = await notifications_collection.find({"username": auth["username"]}).sort("created_at", -1).limit(limit).to_list(length=limit)
    return [_public_notification(document) for document in documents]


@admin_router.get("/notifications/unread-count", response_model=AINotificationUnreadCount, tags=["Admin - Notifications"])
async def unread_notification_count(auth: dict = Depends(verify_auth)):
    count = await notifications_collection.count_documents({"username": auth["username"], "read": False})
    return AINotificationUnreadCount(unread_count=count)


@admin_router.post("/notifications/{notification_id}/read", response_model=AINotification, tags=["Admin - Notifications"])
async def mark_notification_read(notification_id: str, auth: dict = Depends(verify_auth)):
    document = await notifications_collection.find_one_and_update(
        {"id": notification_id, "username": auth["username"]},
        {"$set": {"read": True, "read_at": datetime.now(timezone.utc)}},
        return_document=True,
    )
    if not document:
        raise HTTPException(status_code=404, detail="Notifica non trovata")
    return _public_notification(document)


@admin_router.post("/notifications/read-all", tags=["Admin - Notifications"])
async def mark_all_notifications_read(auth: dict = Depends(verify_auth)):
    result = await notifications_collection.update_many(
        {"username": auth["username"], "read": False},
        {"$set": {"read": True, "read_at": datetime.now(timezone.utc)}},
    )
    return {"updated": result.modified_count}


