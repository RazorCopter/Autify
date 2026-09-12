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
    """
    Ritorna statistiche aggregate pre-calcolate per la Dashboard direzionale:
    - Totale utenze attive
    - Stato copertura (Coperti vs Scaduti/Da valutare) negli ultimi 6 mesi (180 giorni)
    - Distribuzione valutazioni per tipo di scala
    - Trend degli ultimi 6 mesi (valutazioni mensili per scala)
    - Lista degli ultimi alert (max 5) di pazienti da rivalutare urgentemente
    Risultato in cache per 5 minuti (P-01).
    """
    if _dashboard_cache["data"] is not None and (_time.time() - _dashboard_cache["ts"]) < _DASHBOARD_CACHE_TTL:
        return _dashboard_cache["data"]

    try:
        def parse_eval_date(ev_doc):
            d = ev_doc.get("data_compilazione")
            if not d:
                return datetime.min.replace(tzinfo=timezone.utc)
            if isinstance(d, str):
                try:
                    res = datetime.fromisoformat(d.replace('Z', '+00:00'))
                except ValueError:
                    m_ymd = re.match(r"^(\d{4})[-\/](\d{1,2})[-\/](\d{1,2})", d)
                    if m_ymd:
                        try:
                            res = datetime(int(m_ymd.group(1)), int(m_ymd.group(2)), int(m_ymd.group(3)), tzinfo=timezone.utc)
                        except ValueError:
                            res = datetime.min.replace(tzinfo=timezone.utc)
                    else:
                        m_dmy = re.match(r"^(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})", d)
                        if m_dmy:
                            try:
                                res = datetime(int(m_dmy.group(3)), int(m_dmy.group(2)), int(m_dmy.group(1)), tzinfo=timezone.utc)
                            except ValueError:
                                res = datetime.min.replace(tzinfo=timezone.utc)
                        else:
                            res = datetime.min.replace(tzinfo=timezone.utc)
            elif isinstance(d, datetime):
                res = d
            else:
                res = datetime.min.replace(tzinfo=timezone.utc)
            if res.tzinfo is None:
                res = res.replace(tzinfo=timezone.utc)
            return res

        # 1. Recupero di tutti i pazienti e di tutte le scale per mappare i nomi
        MAX_PATIENTS_LIMIT = 5000
        MAX_EVALS_LIMIT = 10000

        patients_cursor = patients_collection.find({})
        patients = await patients_cursor.to_list(length=MAX_PATIENTS_LIMIT)
        is_truncated = len(patients) >= MAX_PATIENTS_LIMIT
        
        active_patient_ids = set()
        pazienti_attivi = [p for p in patients if p.get("attivo", True)]
        for pat in pazienti_attivi:
            p_id = pat.get("id")
            if p_id:
                active_patient_ids.add(str(p_id))
            p_id2 = pat.get("_id")
            if p_id2:
                active_patient_ids.add(str(p_id2))
        
        scales_cursor = scales_collection.find({})
        scales_list = await scales_cursor.to_list(length=100)
        
        scale_names = {}
        for s in scales_list:
            s_nome = s.get("nome") or "Scala senza nome"
            s_id = s.get("id")
            if s_id:
                scale_names[str(s_id)] = s_nome
            s_id2 = s.get("_id")
            if s_id2:
                scale_names[str(s_id2)] = s_nome
                
        # 2. Recupero di tutte le valutazioni
        evaluations_cursor = evaluations_collection.find({})
        evaluations = await evaluations_cursor.to_list(length=MAX_EVALS_LIMIT)
        if len(evaluations) >= MAX_EVALS_LIMIT:
            is_truncated = True
        
        now = datetime.now(timezone.utc)
        
        # 3. Raggruppamento valutazioni per utente (saltando orfane e normalizzando gli ID a stringa)
        evals_by_patient = {}
        for ev in evaluations:
            pat_id = ev.get("id_paziente")
            if not pat_id:
                continue
            pat_id_str = str(pat_id)
            if pat_id_str not in active_patient_ids:
                continue
            if pat_id_str not in evals_by_patient:
                evals_by_patient[pat_id_str] = []
            evals_by_patient[pat_id_str].append(ev)
            
        # 4. Calcolo dello stato di copertura di ciascun utente (POS e San Martin valutati individualmente)
        pos_attivi = 0
        san_martin_attivi = 0
        sis_attivi = 0
        pos_scaduti = 0
        san_martin_scaduti = 0
        sis_scaduti = 0
        alert_candidates = []
        total_scaduti_global = 0
        total_in_scadenza_global = 0
        total_mai_valutati_global = 0
        total_incompleti_global = 0
        
        # Inizializza i dati per il Forecast a 8 settimane (W1 - W8).
        # "routine" non è calcolabile senza un modulo di pianificazione: impostato a 0.
        forecast_dati = []
        for w in range(1, 9):
            forecast_dati.append({
                "settimana": f"W{w}",
                "routine": 0,
                "criticita": 0
            })
        
        for pat in pazienti_attivi:
            p_id = pat.get("id")
            p_id2 = pat.get("_id")
            
            p_id_str = str(p_id) if p_id else None
            p_id2_str = str(p_id2) if p_id2 else None
            
            pat_display_id = p_id_str or p_id2_str
            if not pat_display_id:
                continue
                
            # Recupera le valutazioni dell'utente provando entrambe le chiavi stringa
            pat_evals = []
            if p_id_str and p_id_str in evals_by_patient:
                pat_evals = evals_by_patient[p_id_str]
            elif p_id2_str and p_id2_str in evals_by_patient:
                pat_evals = evals_by_patient[p_id2_str]
            
            # Dividi le valutazioni in POS, San Martín e SIS
            pat_pos_evals = []
            pat_sm_evals = []
            pat_sis_evals = []
            
            for ev in pat_evals:
                scale_id = ev.get("id_scala")
                scale_id_str = str(scale_id) if scale_id else ""
                scale_name = scale_names.get(scale_id_str) or scale_names.get(str(scale_id)) or scale_id_str or ""
                scale_name = scale_name.lower()
                scale_type = _classify_scale(scale_name, scale_id_str)
                if scale_type == "pos":
                    pat_pos_evals.append(ev)
                elif scale_type == "san_martin":
                    pat_sm_evals.append(ev)
                elif scale_type == "sis":
                    pat_sis_evals.append(ev)
            
            # --- Valuta POS ---
            has_valid_pos = False
            latest_pos_date = None
            if pat_pos_evals:
                sorted_pos = sorted(pat_pos_evals, key=parse_eval_date, reverse=True)
                latest_pos = sorted_pos[0]
                latest_pos_date = parse_eval_date(latest_pos)
                days_since_pos = (now - latest_pos_date).days
                if days_since_pos <= 180:
                    has_valid_pos = True
                    pos_attivi += 1
                else:
                    pos_scaduti += 1
            else:
                pos_scaduti += 1
                
            # --- Valuta San Martín ---
            has_valid_sm = False
            latest_sm_date = None
            if pat_sm_evals:
                sorted_sm = sorted(pat_sm_evals, key=parse_eval_date, reverse=True)
                latest_sm = sorted_sm[0]
                latest_sm_date = parse_eval_date(latest_sm)
                days_since_sm = (now - latest_sm_date).days
                if days_since_sm <= 180:
                    has_valid_sm = True
                    san_martin_attivi += 1
                else:
                    san_martin_scaduti += 1
            else:
                san_martin_scaduti += 1
                
            # --- Valuta SIS ---
            has_valid_sis = False
            latest_sis_date = None
            if pat_sis_evals:
                sorted_sis = sorted(pat_sis_evals, key=parse_eval_date, reverse=True)
                latest_sis = sorted_sis[0]
                latest_sis_date = parse_eval_date(latest_sis)
                days_since_sis = (now - latest_sis_date).days
                if days_since_sis <= 365:
                    has_valid_sis = True
                    sis_attivi += 1
                else:
                    sis_scaduti += 1
            else:
                sis_scaduti += 1
                
            # Generazione alert puntuali per singola scala (se non valida o in scadenza)
            # POS
            if not pat_pos_evals:
                alert_candidates.append({
                    "paziente_id": pat_display_id,
                    "paziente_nome": pat.get("nome", ""),
                    "paziente_cognome": pat.get("cognome", ""),
                    "ultima_valutazione_data": None,
                    "giorni_da_ultima_valutazione": 9999,
                    "stato": "mai_valutato",
                    "scala_nome": "POS"
                })
            else:
                days_since_pos = (now - latest_pos_date).days
                if days_since_pos > 180:
                    alert_candidates.append({
                        "paziente_id": pat_display_id,
                        "paziente_nome": pat.get("nome", ""),
                        "paziente_cognome": pat.get("cognome", ""),
                        "ultima_valutazione_data": latest_pos_date.isoformat(),
                        "giorni_da_ultima_valutazione": days_since_pos,
                        "stato": "scaduto",
                        "scala_nome": "POS"
                    })
                elif days_since_pos > 150:
                    alert_candidates.append({
                        "paziente_id": pat_display_id,
                        "paziente_nome": pat.get("nome", ""),
                        "paziente_cognome": pat.get("cognome", ""),
                        "ultima_valutazione_data": latest_pos_date.isoformat(),
                        "giorni_da_ultima_valutazione": days_since_pos,
                        "stato": "in_scadenza",
                        "scala_nome": "POS"
                    })

            # San Martín
            if not pat_sm_evals:
                alert_candidates.append({
                    "paziente_id": pat_display_id,
                    "paziente_nome": pat.get("nome", ""),
                    "paziente_cognome": pat.get("cognome", ""),
                    "ultima_valutazione_data": None,
                    "giorni_da_ultima_valutazione": 9999,
                    "stato": "mai_valutato",
                    "scala_nome": "San Martín"
                })
            else:
                days_since_sm = (now - latest_sm_date).days
                if days_since_sm > 180:
                    alert_candidates.append({
                        "paziente_id": pat_display_id,
                        "paziente_nome": pat.get("nome", ""),
                        "paziente_cognome": pat.get("cognome", ""),
                        "ultima_valutazione_data": latest_sm_date.isoformat(),
                        "giorni_da_ultima_valutazione": days_since_sm,
                        "stato": "scaduto",
                        "scala_nome": "San Martín"
                    })
                elif days_since_sm > 150:
                    alert_candidates.append({
                        "paziente_id": pat_display_id,
                        "paziente_nome": pat.get("nome", ""),
                        "paziente_cognome": pat.get("cognome", ""),
                        "ultima_valutazione_data": latest_sm_date.isoformat(),
                        "giorni_da_ultima_valutazione": days_since_sm,
                        "stato": "in_scadenza",
                        "scala_nome": "San Martín"
                    })

            # SIS
            if not pat_sis_evals:
                alert_candidates.append({
                    "paziente_id": pat_display_id,
                    "paziente_nome": pat.get("nome", ""),
                    "paziente_cognome": pat.get("cognome", ""),
                    "ultima_valutazione_data": None,
                    "giorni_da_ultima_valutazione": 9999,
                    "stato": "mai_valutato",
                    "scala_nome": "SIS"
                })
            else:
                days_since_sis = (now - latest_sis_date).days
                if days_since_sis > 365:
                    alert_candidates.append({
                        "paziente_id": pat_display_id,
                        "paziente_nome": pat.get("nome", ""),
                        "paziente_cognome": pat.get("cognome", ""),
                        "ultima_valutazione_data": latest_sis_date.isoformat(),
                        "giorni_da_ultima_valutazione": days_since_sis,
                        "stato": "scaduto",
                        "scala_nome": "SIS"
                    })
                elif days_since_sis > 335:
                    alert_candidates.append({
                        "paziente_id": pat_display_id,
                        "paziente_nome": pat.get("nome", ""),
                        "paziente_cognome": pat.get("cognome", ""),
                        "ultima_valutazione_data": latest_sis_date.isoformat(),
                        "giorni_da_ultima_valutazione": days_since_sis,
                        "stato": "in_scadenza",
                        "scala_nome": "SIS"
                    })

            # --- Calcolo Metriche Globali dell'Utente (AlertBar) ---
            is_scaduta = False
            is_in_scadenza = False
            
            if pat_pos_evals and latest_pos_date:
                days_since_pos = (now - latest_pos_date).days
                if days_since_pos > 180:
                    is_scaduta = True
                elif days_since_pos > 150:
                    is_in_scadenza = True
                    
            if pat_sm_evals and latest_sm_date:
                days_since_sm = (now - latest_sm_date).days
                if days_since_sm > 180:
                    is_scaduta = True
                elif days_since_sm > 150:
                    is_in_scadenza = True
                    
            if pat_sis_evals and latest_sis_date:
                days_since_sis = (now - latest_sis_date).days
                if days_since_sis > 365:
                    is_scaduta = True
                elif days_since_sis > 335:
                    is_in_scadenza = True
                    
            if len(pat_evals) == 0:
                total_mai_valutati_global += 1
            else:
                if not pat_pos_evals or not pat_sm_evals or not pat_sis_evals:
                    total_incompleti_global += 1
                elif is_scaduta:
                    total_scaduti_global += 1
                elif is_in_scadenza:
                    total_in_scadenza_global += 1

            # --- Calcolo Forecast a 8 settimane ---
            # routine  = scala valida ma in scadenza entro 8 sett. (0 < days_left < 56)
            # criticita = scala già scaduta (days_left <= 0) → sempre W0
            for (pat_evals, latest_date, soglia) in [
                (pat_pos_evals, latest_pos_date, 180),
                (pat_sm_evals, latest_sm_date, 180),
                (pat_sis_evals, latest_sis_date, 365),
            ]:
                if pat_evals and latest_date:
                    exp = latest_date + timedelta(days=soglia)
                    days_left = (exp - now).days
                    if 0 < days_left < 56:
                        w_idx = days_left // 7
                        forecast_dati[w_idx]["routine"] += 1
                    elif days_left <= 0:
                        forecast_dati[0]["criticita"] += 1

        # Calcolo percentuale di copertura
        totale_pazienti = len(patients)
        totale_pazienti_attivi = len(pazienti_attivi)
        coperti_count = pos_attivi + san_martin_attivi + sis_attivi
        scaduti_count = pos_scaduti + san_martin_scaduti + sis_scaduti
        max_scale_teoriche = 3 * totale_pazienti_attivi
        copertura_percentuale = (coperti_count / max_scale_teoriche * 100) if max_scale_teoriche > 0 else 0.0
        
        # 5. Ordina gli alert: prima chi non ne ha mai fatte o scadute da più tempo, poi in scadenza
        alert_candidates.sort(
            key=lambda x: (
                0 if x.get("stato") in ("scaduto", "mai_valutato") else 1,
                -x.get("giorni_da_ultima_valutazione", 0)
            )
        )
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
                distribuzione_raw[scale_id_str].add(pat_id_str)
            
        totale_valutazioni = sum(len(patients) for patients in distribuzione_raw.values())
        distribuzione_scale = []
        for scale_id, patients_set in distribuzione_raw.items():
            count = len(patients_set)
            scala_nome = scale_names.get(scale_id) or scale_id or "Scala sconosciuta"
            distribuzione_scale.append({
                "scala_id": scale_id,
                "scala_nome": scala_nome,
                "count": count,
                "percentuale": round((count / totale_pazienti * 100), 1) if totale_pazienti > 0 else 0.0
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
        _dashboard_cache["data"] = result
        _dashboard_cache["ts"] = _time.time()
        return result
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
