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
import time as _time
from . import _invalidate_dashboard_cache, _dashboard_cache, _DASHBOARD_CACHE_TTL

from ._helpers import (
    verify_auth,
    _classify_scale,
)

admin_router = APIRouter(dependencies=[Depends(verify_auth)])
public_admin_router = APIRouter()
client_router = APIRouter(dependencies=[Depends(verify_auth)])


# ==========================================
# ADMIN ROUTER (/api/admin)
# ==========================================

@admin_router.get("/dashboard-stats", tags=["Admin - Dashboard"])
async def get_dashboard_stats():
    """Live statistics using the same projection as /patients (no stale status cache)."""
    from ..expiry import project, utc_date, ROME
    try:
        now = datetime.now(ROME)
        def parse_eval_date(ev_doc):
            date = utc_date(ev_doc.get("data_compilazione"))
            return date.astimezone(ROME) if date else datetime.min.replace(tzinfo=timezone.utc)
        patients = await patients_collection.find({}).to_list(length=None)
        pazienti_attivi = [p for p in patients if p.get("attivo", True)]
        policy = await project(pazienti_attivi, now)
        active_patient_ids = {str(key) for p in pazienti_attivi for key in (p.get("id"), p.get("_id")) if key is not None}
        scales_list = await scales_collection.find({}).to_list(length=None)
        scale_names = {str(key): s.get("nome", "Scala senza nome") for s in scales_list for key in (s.get("id"), s.get("_id")) if key is not None}
        evaluations = await evaluations_collection.find({}, {"id_paziente": 1, "id_scala": 1, "data_compilazione": 1}).to_list(length=None)
        canonical_patients = {str(key): p["id"] for p in pazienti_attivi for key in (p.get("id"), p.get("_id")) if key is not None}
        is_truncated = False
        totals = {k: 0 for k in ("mai_valutati", "incompleti", "scaduti", "in_scadenza", "coperti")}
        covered = {k: 0 for k in policy["scale_validity_months"]}
        alert_candidates = []
        forecast_dati = [{"settimana": f"W{w}", "routine": 0, "criticita": 0} for w in range(1, 9)]
        for pat in pazienti_attivi:
            totals[pat["stato_valutazioni"]] += 1
            for kind, state in pat["stato_scale"].items():
                if state["stato"] in ("valida", "in_scadenza"):
                    covered[kind] += 1
                if kind not in policy["required_scale_types"]:
                    continue
                days = state["giorni_residui"]
                if days is not None:
                    if days < 0:
                        forecast_dati[0]["criticita"] += 1
                    elif days < 56:
                        forecast_dati[days // 7]["routine"] += 1
                if state["stato"] != "valida":
                    date = utc_date(state["data"])
                    alert_candidates.append({
                        "paziente_id": pat["id"], "paziente_nome": pat.get("nome", ""),
                        "paziente_cognome": pat.get("cognome", ""),
                        "ultima_valutazione_data": state["data"],
                        "giorni_da_ultima_valutazione": (now - date).days if date else 9999,
                        "stato": {"mai_valutati": "mai_valutato", "incompleti": "incompleto", "scaduti": "scaduto"}.get(pat["stato_valutazioni"], pat["stato_valutazioni"]),
                        "stato_scala": state["stato"],
                        "scala_nome": kind.upper().replace("_", " "),
                    })
        totale_pazienti = len(patients)
        totale_pazienti_attivi = len(pazienti_attivi)
        pos_attivi, san_martin_attivi, sis_attivi = (covered[k] for k in ("pos", "san_martin", "sis"))
        pos_scaduti, san_martin_scaduti, sis_scaduti = (totale_pazienti_attivi - covered[k] for k in ("pos", "san_martin", "sis"))
        coperti_count = sum(covered[k] for k in policy["required_scale_types"])
        denominator = len(policy["required_scale_types"]) * totale_pazienti_attivi
        scaduti_count = denominator - coperti_count
        copertura_percentuale = 100 * coperti_count / denominator if denominator else 0
        total_scaduti_global = totals["scaduti"]
        total_in_scadenza_global = totals["in_scadenza"]
        total_mai_valutati_global = totals["mai_valutati"]
        total_incompleti_global = totals["incompleti"]
        alert_candidates.sort(key=lambda a: (a["stato"] == "in_scadenza", -a["giorni_da_ultima_valutazione"], a["paziente_id"], a["scala_nome"]))
        ultimi_alert = alert_candidates[:10]

        # 6. Distribuzione per tipo di scala (saltando orfane o non valide)
        distribuzione_raw = {}
        for ev in evaluations:
            pat_id = ev.get("id_paziente")
            if not pat_id:
                continue
            pat_id_str = str(pat_id)
            if pat_id_str not in active_patient_ids:
                continue
            scale_id = ev.get("id_scala")
            if scale_id:
                scale_id_str = str(scale_id)
                if scale_id_str not in distribuzione_raw:
                    distribuzione_raw[scale_id_str] = set()
                distribuzione_raw[scale_id_str].add(canonical_patients[pat_id_str])
            
        totale_valutazioni = sum(1 for ev in evaluations if str(ev.get("id_paziente")) in active_patient_ids)
        distribuzione_scale = []
        for scale_id, patients_set in distribuzione_raw.items():
            count = len(patients_set)
            scala_nome = scale_names.get(scale_id) or scale_id or "Scala sconosciuta"
            distribuzione_scale.append({
                "scala_id": scale_id,
                "scala_nome": scala_nome,
                "count": count,
                "percentuale": round((count / totale_pazienti_attivi * 100), 1) if totale_pazienti_attivi > 0 else 0.0
            })
            
        # 7. Trend degli ultimi 6 mesi (BarChart dati delle somministrazioni mensili)
        trend_dati = []
        for i in range(5, -1, -1):
            offset_months = i
            target_year = now.year
            target_month = now.month - offset_months
            while target_month <= 0:
                target_month += 12
                target_year -= 1
                
            mesi_it = {
                1: "Gen", 2: "Feb", 3: "Mar", 4: "Apr", 5: "Mag", 6: "Giu",
                7: "Lug", 8: "Ago", 9: "Set", 10: "Ott", 11: "Nov", 12: "Dic"
            }
            nome_mese = f"{mesi_it[target_month]} {target_year}"
            
            # Filtra valutazioni fatte in questo anno/mese (escludendo orfane)
            count_mese = 0
            dettaglio_scale = {}
            for ev in evaluations:
                pat_id = ev.get("id_paziente")
                if not pat_id:
                    continue
                pat_id_str = str(pat_id)
                if pat_id_str not in active_patient_ids:
                    continue
                
                ev_date = parse_eval_date(ev)
                if ev_date.year == target_year and ev_date.month == target_month:
                    count_mese += 1
                    scale_id = ev.get("id_scala")
                    scale_id_str = str(scale_id) if scale_id else "unknown"
                    scala_nome = scale_names.get(scale_id_str) or scale_id_str or "Scala sconosciuta"
                    dettaglio_scale[scala_nome] = dettaglio_scale.get(scala_nome, 0) + 1
                    
            trend_dati.append({
                "mese": nome_mese,
                "anno": target_year,
                "num_mese": target_month,
                "count": count_mese,
                "dettaglio_scale": dettaglio_scale
            })
            
        # 8. Statistiche Demografiche
        demographics = {
            "sesso": {"M": 0, "F": 0, "Altro/Non specificato": 0},
            "fasce_eta": {"0-18": 0, "19-35": 0, "36-50": 0, "51+": 0, "Non specificata": 0}
        }
        
        for pat in pazienti_attivi:
            sesso = pat.get("sesso") or "Altro/Non specificato"
            if sesso.upper() == "M":
                demographics["sesso"]["M"] += 1
            elif sesso.upper() == "F":
                demographics["sesso"]["F"] += 1
            else:
                demographics["sesso"]["Altro/Non specificato"] += 1
                
            data_nascita = pat.get("data_nascita") or pat.get("dataNascita")
            eta_fascia = "Non specificata"
            if data_nascita:
                try:
                    if "/" in data_nascita:
                        d, m, y = data_nascita.split("/")
                        birth = datetime(int(y), int(m), int(d))
                    elif "-" in data_nascita:
                        parts = data_nascita.split("-")
                        if len(parts[0]) == 4:
                            birth = datetime(int(parts[0]), int(parts[1]), int(parts[2][:2]))
                        else:
                            birth = datetime(int(parts[2][:4]), int(parts[1]), int(parts[0]))
                    else:
                        birth = None
                        
                    if birth:
                        age = now.year - birth.year - ((now.month, now.day) < (birth.month, birth.day))
                        if age <= 18:
                            eta_fascia = "0-18"
                        elif age <= 35:
                            eta_fascia = "19-35"
                        elif age <= 50:
                            eta_fascia = "36-50"
                        else:
                            eta_fascia = "51+"
                except Exception:
                    pass
            demographics["fasce_eta"][eta_fascia] += 1
            
        result = {
            "expiry_policy": policy,
            "calculated_at": now.isoformat(),
            "coverage_denominator": denominator,
            "utenze_coperte": totals["coperti"] + totals["in_scadenza"],
            "utenze_da_completare": totals["mai_valutati"] + totals["incompleti"] + totals["scaduti"],
            "coverage_unit": "coppie utente attivo / scala richiesta",
            "totale_utenze": totale_pazienti,
            "totale_utenze_attive": totale_pazienti_attivi,
            "totale_valutazioni_eseguite": totale_valutazioni,
            "copertura_scale": {
                "coperti_percentuale": round(copertura_percentuale, 1),
                "coperti_count": coperti_count,
                "scaduti_count": scaduti_count,
                "pos_mancanti": pos_scaduti,
                "san_martin_mancanti": san_martin_scaduti,
                "sis_mancanti": sis_scaduti,
                "pos_attivi": pos_attivi,
                "san_martin_attivi": san_martin_attivi,
                "sis_attivi": sis_attivi
            },
            "alert_stats": {
                "totale_scaduti": total_scaduti_global,
                "totale_in_scadenza": total_in_scadenza_global,
                "totale_mai_valutati": total_mai_valutati_global,
                "totale_incompleti": total_incompleti_global
            },
            "distribuzione_scale": distribuzione_scale,
            "trend_somministrazioni": trend_dati,
            "forecast_somministrazioni": forecast_dati,
            "ultimi_alert": ultimi_alert,
            "demographics": demographics,
            "is_truncated": is_truncated,
        }
        return result
    except HTTPException:
        raise
    except Exception as e:
        _logger.exception("Errore durante il calcolo delle statistiche della dashboard: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Impossibile calcolare le statistiche della dashboard. Riprova più tardi.",
        )


@admin_router.delete("/dashboard-stats/cache", tags=["Admin - Dashboard"])
async def invalidate_dashboard_cache(_current_user: dict = Depends(verify_auth)):
    """Invalida la cache delle statistiche dashboard (utile dopo import dati)."""
    _dashboard_cache["data"] = None
    _dashboard_cache["ts"] = 0.0
    return {"message": "Cache dashboard invalidata"}
