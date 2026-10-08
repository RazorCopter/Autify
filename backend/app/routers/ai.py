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
from ..ai import (
    AISettingsStored,
    AITestConnectionRequest,
    AITestConnectionResponse,
    AIAnalyzeRequest,
    DEFAULT_SYSTEM_PROMPT,
)
from ..ai.adapters import get_ai_adapter
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
async def test_ai_connection(
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
    return AITestConnectionResponse(
        success=success,
        provider=target_provider,
        model=target_model,
        latency_ms=latency_ms,
        message=message,
    )

@admin_router.post("/ai/analyze", tags=["Admin - AI Analyses"])
async def analyze_evaluation(request: AIAnalyzeRequest, auth: dict = Depends(verify_auth)):
    """Analizza una valutazione o l'intero profilo di funzionamento usando il provider IA configurato."""
    if not auth.get("ai_enabled", False):
        raise HTTPException(status_code=403, detail="Non sei abilitato all'uso dell'IA")

    stored = await get_or_migrate_ai_settings()

    patient_id = request.id_paziente
    evaluations_used = list(request.evaluation_ids or [])
    patient_data = request.patient
    evaluations_data = list(request.evaluations or [])

    if request.id_valutazione and not evaluations_data:
        eval_doc = await _find_evaluation_document(request.id_valutazione)
        if not eval_doc:
            raise HTTPException(status_code=404, detail="Valutazione non trovata")
        evaluations_data.append(eval_doc)
        if request.id_valutazione not in evaluations_used:
            evaluations_used.append(request.id_valutazione)
        if not patient_id:
            patient_id = eval_doc.get("id_paziente")

    if patient_id and not patient_data:
        pat_doc = await patients_collection.find_one({"id": patient_id})
        if pat_doc:
            patient_data = pat_doc

    if not patient_id and patient_data:
        patient_id = patient_data.get("id")

    if not evaluations_data and not (request.notes and request.notes.strip()) and not request.attachment:
        raise HTTPException(status_code=400, detail="Nessun dato fornito per l'analisi (valutazioni, note o allegato)")

    user_prompt = _build_educational_prompt(
        patient=patient_data,
        evaluations=evaluations_data,
        notes=request.notes,
        history_reports=request.history_reports,
    )

    system_prompt = request.system_prompt or stored.system_prompt or DEFAULT_SYSTEM_PROMPT

    adapter = get_ai_adapter(settings=stored)
    report_text, usage = await adapter.generate(
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        attachment=request.attachment,
    )

    analysis_id = f"an_{uuid.uuid4().hex[:8]}"
    created_at = datetime.now(timezone.utc)
    new_analysis = {
        "id": analysis_id,
        "id_paziente": patient_id or "sconosciuto",
        "timestamp": created_at,
        "report": report_text,
        "notes": "",
        "evaluations_used": evaluations_used,
        "provider": stored.active_provider,
        "model": (
            stored.gemini.model if stored.active_provider == "gemini"
            else stored.openai.model if stored.active_provider == "openai"
            else stored.openai_compatible.model
        ),
        "usage": usage,
    }

    await ai_analyses_collection.insert_one(new_analysis)

    operatore = auth.get("username", "operatore")
    target_for_audit = patient_id if patient_id else (evaluations_used[0] if evaluations_used else "globale")
    await log_audit(
        "AI_ANALYSIS",
        operatore,
        f"{operatore} ha generato analisi IA ({stored.active_provider})",
        target_for_audit,
    )

    return {
        "id": analysis_id,
        "id_paziente": patient_id or "sconosciuto",
        "timestamp": created_at.isoformat(),
        "report": report_text,
        "notes": "",
        "evaluations_used": evaluations_used,
        "provider": new_analysis["provider"],
        "model": new_analysis["model"],
        "usage": usage,
    }


