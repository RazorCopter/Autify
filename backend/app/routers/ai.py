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

@admin_router.post("/ai/analyze", tags=["Admin - AI Analyses"])
async def analyze_evaluation(request: AiAnalysisRequest, auth: dict = Depends(verify_auth)):
    """Analizza una valutazione usando Gemini o ChatGPT in base alle impostazioni del server."""
    if not auth.get("ai_enabled", False):
        raise HTTPException(status_code=403, detail="Non sei abilitato all'uso dell'IA")
        
    eval_id = request.id_valutazione
    evaluation = await _find_evaluation_document(eval_id)
    if not evaluation:
        raise HTTPException(status_code=404, detail="Valutazione non trovata")
        
    settings_doc = await settings_collection.find_one({"id": "global_settings"})
    settings = AppSettings(**(settings_doc or {}))
    
    prompt_template = settings.gemini_prompt or "Analizza la seguente valutazione clinica: {data}"
    eval_data = json.dumps(evaluation, default=str, ensure_ascii=False)
    final_prompt = prompt_template.replace("{data}", eval_data)
    
    provider = getattr(settings, "ai_provider", "gemini")
    report_text = ""
    
    async with httpx.AsyncClient() as client:
        if provider == "gemini":
            if not settings.gemini_api_key or settings.gemini_api_key == "***-HIDDEN":
                raise HTTPException(status_code=400, detail="Chiave API Gemini non configurata")
            url = f"https://generativelanguage.googleapis.com/v1beta/models/{settings.gemini_model}:generateContent?key={settings.gemini_api_key}"
            payload = {"contents": [{"parts": [{"text": final_prompt}]}]}
            try:
                resp = await client.post(url, json=payload, timeout=60.0)
                if resp.status_code != 200:
                    raise HTTPException(status_code=502, detail=f"Errore Gemini: {resp.text}")
                resp_data = resp.json()
                report_text = resp_data["candidates"][0]["content"]["parts"][0]["text"]
            except Exception as e:
                raise HTTPException(status_code=502, detail=f"Errore comunicazione Gemini: {e}")
                
        elif provider == "chatgpt":
            if not settings.chatgpt_api_key or settings.chatgpt_api_key == "***-HIDDEN":
                raise HTTPException(status_code=400, detail="Chiave API ChatGPT non configurata")
            url = "https://api.openai.com/v1/chat/completions"
            headers = {
                "Authorization": f"Bearer {settings.chatgpt_api_key}",
                "Content-Type": "application/json"
            }
            payload = {
                "model": settings.chatgpt_model,
                "messages": [{"role": "user", "content": final_prompt}]
            }
            try:
                resp = await client.post(url, headers=headers, json=payload, timeout=60.0)
                if resp.status_code != 200:
                    raise HTTPException(status_code=502, detail=f"Errore ChatGPT: {resp.text}")
                resp_data = resp.json()
                report_text = resp_data["choices"][0]["message"]["content"]
            except Exception as e:
                raise HTTPException(status_code=502, detail=f"Errore comunicazione ChatGPT: {e}")
        else:
            raise HTTPException(status_code=400, detail=f"Provider AI '{provider}' non supportato")
            
    new_analysis = {
        "id": f"an_{uuid.uuid4().hex[:8]}",
        "id_paziente": evaluation["id_paziente"],
        "timestamp": datetime.now(timezone.utc),
        "report": report_text,
        "notes": "",
        "evaluations_used": [eval_id]
    }
    
    await ai_analyses_collection.insert_one(new_analysis)
    
    await log_audit(
        "AI_ANALYSIS", 
        auth["username"], 
        f"Generata analisi AI per valutazione {eval_id}", 
        evaluation["id_paziente"]
    )
    
    return AiAnalysis(**new_analysis)

