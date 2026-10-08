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
from pydantic import BaseModel
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
        evaluations_used=payload.evaluations_used
    )
    analysis_dict = analysis.model_dump()
    # Pydantic datetime conversion support for motor/mongodb insertion
    if isinstance(analysis_dict.get("timestamp"), datetime) and analysis_dict["timestamp"].tzinfo is None:
        analysis_dict["timestamp"] = analysis_dict["timestamp"].replace(tzinfo=timezone.utc)
    await ai_analyses_collection.insert_one(analysis_dict)
    
    operatore = auth_context.get("username", "Operatore Sconosciuto")
    cognome = patient.get("cognome", "")
    nome = patient.get("nome", "")
    utente_info = f" per {cognome} {nome}" if (cognome or nome) else ""
    
    await log_audit(
        "GENERAZIONE_REPORT_IA",
        operatore,
        f"{operatore} ha generato la Relazione IA{utente_info}".strip(),
        id_patient
    )
    
    return analysis

@admin_router.put("/patients/ai-analyses/{id_analysis}", tags=["Admin - AI Analyses"])
async def update_ai_analysis(id_analysis: str, payload: AiAnalysisUpdate, auth_context: dict = Depends(verify_auth)):
    existing = await ai_analyses_collection.find_one({"id": id_analysis})
    if not existing:
        raise HTTPException(status_code=404, detail="Analisi IA non trovata")
    
    update_data = {}
    if payload.notes is not None:
        update_data["notes"] = payload.notes
        
    if update_data:
        await ai_analyses_collection.update_one({"id": id_analysis}, {"$set": update_data})
        
        id_patient = existing.get("id_paziente")
        utente_info = ""
        if id_patient:
            patient = await patients_collection.find_one({"id": id_patient})
            if patient:
                cognome = patient.get("cognome", "")
                nome = patient.get("nome", "")
                if cognome or nome:
                    utente_info = f" per {cognome} {nome}"
                    
        operatore = auth_context.get("username", "Operatore Sconosciuto")
        nota_nuova = payload.notes or ""
        await log_audit(
            "MODIFICA_REPORT_IA",
            operatore,
            f"{operatore} ha modificato la nota della Relazione IA{utente_info} in: {nota_nuova}".strip(),
            id_patient
        )
        
    return {"message": "Analisi IA aggiornata con successo"}

@admin_router.delete("/patients/ai-analyses/{id_analysis}", tags=["Admin - AI Analyses"])
async def delete_ai_analysis(id_analysis: str, auth_context: dict = Depends(verify_auth)):
    existing = await ai_analyses_collection.find_one({"id": id_analysis})
    if not existing:
        raise HTTPException(status_code=404, detail="Analisi IA non trovata")
        
    id_patient = existing.get("id_paziente")
    utente_info = ""
    if id_patient:
        patient = await patients_collection.find_one({"id": id_patient})
        if patient:
            cognome = patient.get("cognome", "")
            nome = patient.get("nome", "")
            if cognome or nome:
                utente_info = f" per {cognome} {nome}"

    result = await ai_analyses_collection.delete_one({"id": id_analysis})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Analisi IA non trovata")
        
    operatore = auth_context.get("username", "Operatore Sconosciuto")
    await log_audit(
        "CANCELLAZIONE_REPORT_IA",
        operatore,
        f"{operatore} ha eliminato la Relazione IA{utente_info}".strip(),
        id_patient
    )
    return {"message": "Analisi IA eliminata con successo"}

def _build_educational_prompt(
    patient: Optional[dict],
    evaluations: List[dict],
    notes: Optional[str] = None,
    history_reports: Optional[List[dict]] = None,
) -> str:
    lines = [
        "IMPORTANTE: NON INSERIRE NESSUNA DATA (es. 'Data di redazione', 'Data odierna') nel testo generato.",
        "La data viene applicata automaticamente dal sistema nell'intestazione del documento.\n",
    ]
    if patient:
        lines.append("PROFILO UTENTE:")
        lines.append(f"- Nome: {patient.get('nome', '')} {patient.get('cognome', '')}".strip())
        if patient.get("codice_fiscale"):
            lines.append(f"- Codice Fiscale: {patient['codice_fiscale']}")
        if patient.get("data_nascita"):
            lines.append(f"- Data di Nascita: {str(patient['data_nascita']).split('T')[0]}")
        if patient.get("note"):
            lines.append(f"- Note Generali Anagrafica: {patient['note']}")
        lines.append("")

    if evaluations:
        lines.append("CRONOLOGIA E DETTAGLIO VALUTAZIONI:")
        for idx, ev in enumerate(evaluations, 1):
            scale_id = ev.get("id_scala", "Scala")
            data_comp = str(ev.get("data_compilazione", "")).split("T")[0]
            lines.append(f"[{idx}] Valutazione: {scale_id} | Data Compilazione: {data_comp}")
            domini = ev.get("domini") or []
            if domini:
                lines.append("    Punteggi di Dominio:")
                for d in domini:
                    if isinstance(d, dict):
                        cod = d.get("codice", "")
                        lbl = d.get("etichetta", cod)
                        pts = d.get("punteggio") or d.get("punteggio_totale") or d.get("punteggio_grezzo")
                        lines.append(f"      * [{cod}] {lbl}: {pts}")
            analysis = ev.get("analysis") or ev.get("snapshot_scala")
            if analysis and isinstance(analysis, dict):
                lines.append("    Indici Analitici / Sintesi:")
                for k, v in analysis.items():
                    if k not in ("domini", "items_segnalati"):
                        lines.append(f"      * {k}: {v}")
            lines.append("")

    if history_reports:
        lines.append("STORICO ANALISI E SINTESI PRECEDENTI DELL'UTENTE:")
        for hr in history_reports:
            ts = str(hr.get("timestamp", "")).split("T")[0]
            rep = hr.get("report") or hr.get("notes") or ""
            lines.append(f"--- Sintesi del {ts} ---\n{rep}\n")

    if notes and notes.strip():
        lines.append(f"NOTE AGGIUNTIVE FORNITE DALL'OPERATORE:\n{notes.strip()}\n")

    lines.append("Procedi con l'analisi multidimensionale globale incrociando tutti i dati clinici forniti.")
    return "\n".join(lines)

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


async def _process_ai_job(job_id: str) -> None:
    """Esegue esattamente una volta il job persistito, reclamandolo atomicamente."""
    claimed = await ai_jobs_collection.find_one_and_update(
        {"id": job_id, "status": "pending"},
        {"$set": {"status": "running", "started_at": datetime.now(timezone.utc)}},
        return_document=True,
    )
    if not claimed:
        return

    try:
        stored = await get_or_migrate_ai_settings()
        adapter = get_ai_adapter(settings=stored)
        report_text, usage = await adapter.generate(
            system_prompt=claimed["system_prompt"],
            user_prompt=claimed["user_prompt"],
            attachment=AIAttachment.model_validate(claimed["attachment"]) if claimed.get("attachment") else None,
        )
        now = datetime.now(timezone.utc)
        analysis_id = f"an_{uuid.uuid4().hex[:8]}"
        model = (
            stored.gemini.model if stored.active_provider == "gemini"
            else stored.openai.model if stored.active_provider == "openai"
            else stored.openai_compatible.model
        )
        await ai_analyses_collection.insert_one({
            "id": analysis_id,
            "id_paziente": claimed.get("id_paziente") or "sconosciuto",
            "timestamp": now,
            "report": report_text,
            "notes": "",
            "evaluations_used": claimed.get("evaluations_used", []),
            "provider": stored.active_provider,
            "model": model,
            "usage": usage,
            "owner_username": claimed["username"],
        })
        await ai_jobs_collection.update_one(
            {"id": job_id, "status": "running"},
            {"$set": {
                "status": "completed", "completed_at": now,
                "analysis_id": analysis_id, "error_message": None,
                "report_preview": report_text[:240],
            }},
        )
        patient_name = claimed.get("patient_name") or "Utente"
        await notifications_collection.insert_one({
            "id": f"nt_{uuid.uuid4().hex[:12]}",
            "username": claimed["username"],
            "type": "ai_analysis_completed",
            "title": "Elaborazione IA completata",
            "message": f'Elaborazione IA "{patient_name}" terminata',
            "job_id": job_id,
            "analysis_id": analysis_id,
            "id_paziente": claimed.get("id_paziente"),
            "patient_name": patient_name,
            "read": False,
            "created_at": now,
        })
        await log_audit(
            "AI_ANALYSIS", claimed["username"],
            f"{claimed['username']} ha generato analisi IA ({stored.active_provider})",
            claimed.get("id_paziente") or "globale",
        )
    except Exception as exc:
        _logger.exception("Job IA %s fallito", job_id)
        now = datetime.now(timezone.utc)
        safe_error = str(exc)[:500] or "Errore sconosciuto durante l'elaborazione IA"
        await ai_jobs_collection.update_one(
            {"id": job_id, "status": "running"},
            {"$set": {"status": "failed", "completed_at": now, "error_message": safe_error}},
        )
        patient_name = claimed.get("patient_name") or "Utente"
        await notifications_collection.insert_one({
            "id": f"nt_{uuid.uuid4().hex[:12]}",
            "username": claimed["username"],
            "type": "ai_analysis_failed",
            "title": "Elaborazione IA non riuscita",
            "message": f'Elaborazione IA "{patient_name}" non riuscita',
            "job_id": job_id,
            "id_paziente": claimed.get("id_paziente"),
            "patient_name": patient_name,
            "read": False,
            "created_at": now,
        })


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
    if auth.get("role") == "viewer" and body.system_prompt:
        raise HTTPException(status_code=403, detail="I profili Viewer non sono autorizzati a personalizzare il prompt di sistema")

    patient_id = body.id_paziente
    evaluations_used = list(body.evaluation_ids or [])
    patient_data = body.patient
    evaluations_data = list(body.evaluations or [])
    if body.id_valutazione and not evaluations_data:
        eval_doc = await _find_evaluation_document(body.id_valutazione)
        if not eval_doc:
            raise HTTPException(status_code=404, detail="Valutazione non trovata")
        evaluations_data.append(eval_doc)
        if body.id_valutazione not in evaluations_used:
            evaluations_used.append(body.id_valutazione)
        patient_id = patient_id or eval_doc.get("id_paziente")
    if patient_id and not patient_data:
        patient_data = await patients_collection.find_one({"id": patient_id})
    if not patient_id and patient_data:
        patient_id = patient_data.get("id")
    if not evaluations_data and not (body.notes and body.notes.strip()) and not body.attachment:
        raise HTTPException(status_code=400, detail="Nessun dato fornito per l'analisi (valutazioni, note o allegato)")

    username = auth.get("username", "operatore")
    patient_name = " ".join(filter(None, [
        (patient_data or {}).get("nome"), (patient_data or {}).get("cognome")
    ])).strip() or "Utente"
    created_at = datetime.now(timezone.utc)
    job_id = f"job_{uuid.uuid4().hex[:12]}"
    await ai_jobs_collection.insert_one({
        "id": job_id,
        "username": username,
        "id_paziente": patient_id,
        "patient_name": patient_name,
        "status": "pending",
        "created_at": created_at,
        "started_at": None,
        "completed_at": None,
        "error_message": None,
        "analysis_id": None,
        "evaluations_used": evaluations_used,
        "user_prompt": _build_educational_prompt(patient_data, evaluations_data, body.notes, body.history_reports),
        "system_prompt": (body.system_prompt if auth.get("role") != "viewer" else None) or stored.system_prompt or DEFAULT_SYSTEM_PROMPT,
        "attachment": body.attachment.model_dump() if body.attachment else None,
    })
    asyncio.create_task(_process_ai_job(job_id))
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


