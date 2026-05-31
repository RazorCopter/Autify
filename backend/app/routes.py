from fastapi import APIRouter, HTTPException, status, UploadFile, File, Header, Depends, Request
from fastapi.responses import StreamingResponse
from typing import List, Optional
from bson import ObjectId
from .models import Scale, Evaluation, Patient, AppSettings, Section, Question, Option, DOMINI_POS, AggregatedEvaluation, EvaluationUpdateRequest, AiAnalysis, AiAnalysisCreate, UserCreate, UserUpdate, UserResponse, AuditLogCreate, AuditLogResponse
from .database import evaluations_collection, settings_collection, patients_collection, scales_collection, users_collection, ai_analyses_collection, audit_logs_collection
from .pdf_generator import generate_evaluation_pdf, generate_ai_analysis_pdf
from .analytics import compute_psychometric_analysis, compute_direct_scores, build_domain_map, calcola_punteggi_sis
from datetime import datetime, timezone
import json
from pydantic import BaseModel
import uuid
import io
import os
import asyncio
from pathlib import Path
from . import auth as auth_module
from . import auth_manager  # backward-compat: usato da auth.py per il log viewer legacy

class LoginRequest(BaseModel):
    username: str
    password: str
    device_id: Optional[str] = "Sconosciuto"

async def verify_auth(request: Request) -> dict:
    """Dependency: verifica JWT o header legacy e restituisce {username, role, ai_enabled}."""
    auth_context = await auth_module.verify_auth(request)

    # Blocca le modifiche di stato per il ruolo Viewer
    if auth_context["role"] == "viewer" and request.method not in ("GET", "HEAD") and \
       request.url.path not in ("/api/admin/evaluations/ai-analysis-pdf", "/api/admin/auth/login"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Azione non consentita per il profilo Viewer (sola lettura)",
        )

    return auth_context

admin_router = APIRouter(dependencies=[Depends(verify_auth)])
public_admin_router = APIRouter()
client_router = APIRouter()

async def log_audit(azione: str, operatore: str, dettagli: str, target_id: Optional[str] = None):
    try:
        log_entry = {
            "azione": azione,
            "operatore": operatore,
            "dettagli": dettagli,
            "target_id": target_id,
            "timestamp": datetime.now(timezone.utc)
        }
        await audit_logs_collection.insert_one(log_entry)
    except Exception as e:
        print(f"Errore nel salvataggio dell'audit log: {e}")

async def _find_evaluation_document(evaluation_id: str):
    """Recupera una valutazione supportando sia il campo applicativo che fallback legacy."""
    string_candidates = [
        {"id_valutazione": evaluation_id},
        {"idValutazione": evaluation_id},
        {"id": evaluation_id},
        {"_id": evaluation_id},
    ]

    eval_doc = await evaluations_collection.find_one({"$or": string_candidates})
    if eval_doc:
        return eval_doc

    if ObjectId.is_valid(evaluation_id):
        eval_doc = await evaluations_collection.find_one({"_id": ObjectId(evaluation_id)})
        if eval_doc:
            return eval_doc

    # Fallback ultra-tollerante per documenti legacy/importati da backup:
    # confronta in memoria i principali campi identificativi come stringhe.
    async for doc in evaluations_collection.find({}):
        doc_identifiers = [
            doc.get("id_valutazione"),
            doc.get("idValutazione"),
            doc.get("id"),
            doc.get("_id"),
        ]
        if any(str(value) == evaluation_id for value in doc_identifiers if value is not None):
            return doc

    return None


def _extract_evaluation_identifier(eval_doc: dict) -> str:
    """Restituisce sempre un identificativo stabile e risolvibile per la valutazione."""
    if eval_doc.get("id_valutazione"):
        return str(eval_doc["id_valutazione"])
    if eval_doc.get("idValutazione"):
        return str(eval_doc["idValutazione"])
    if eval_doc.get("id"):
        return str(eval_doc["id"])
    if eval_doc.get("_id") is not None:
        return str(eval_doc["_id"])
    return ""


def _build_evaluation_selector(eval_doc: dict) -> dict:
    """Costruisce il filtro Mongo più affidabile per aggiornare la valutazione trovata."""
    if eval_doc.get("_id") is not None:
        return {"_id": eval_doc["_id"]}
    if eval_doc.get("id_valutazione"):
        return {"id_valutazione": eval_doc["id_valutazione"]}
    if eval_doc.get("idValutazione"):
        return {"idValutazione": eval_doc["idValutazione"]}
    if eval_doc.get("id"):
        return {"id": eval_doc["id"]}
    return {"id_valutazione": _extract_evaluation_identifier(eval_doc)}


def _normalize_scale_name(value: Optional[str]) -> str:
    val = (value or "").lower().replace(" ", "").replace("-", "")
    for a, b in [("á", "a"), ("à", "a"), ("é", "e"), ("è", "e"), ("í", "i"), ("ì", "i"), ("ó", "o"), ("ò", "o"), ("ú", "u"), ("ù", "u")]:
        val = val.replace(a, b)
    return val


def _load_builtin_san_martin_scale() -> Optional[dict]:
    """Carica il protocollo San Martin bundled per reidratare metadati mancanti."""
    app_dir = Path(__file__).resolve().parent
    candidate_files = [
        app_dir / "ScalaSanMartin.json",
        app_dir / "Scala San Martin.json",
    ]

    for candidate in candidate_files:
        if not candidate.exists():
            continue
        try:
            data = json.loads(candidate.read_text(encoding="utf-8-sig"))
            scala = data.get("scala")
            if scala:
                return scala
        except (OSError, json.JSONDecodeError):
            continue
    return None


def _load_builtin_sis_scale() -> Optional[dict]:
    """Carica il protocollo SIS bundled dal filesystem."""
    app_dir = Path(__file__).resolve().parent
    candidate = app_dir / "ScalaSIS.json"
    if not candidate.exists():
        return None
    try:
        data = json.loads(candidate.read_text(encoding="utf-8-sig"))
        return data.get("scala")
    except (OSError, json.JSONDecodeError):
        return None


def _hydrate_scale_doc(scale_doc: Optional[dict]) -> dict:
    """
    Ripristina i metadati psicometrici per le scale San Martin importate
    prima del supporto a `scoring_tables`.
    """
    if not scale_doc:
        return {}

    if scale_doc.get("scoring_tables"):
        return scale_doc

    normalized_id = _normalize_scale_name(scale_doc.get("id"))
    normalized_name = _normalize_scale_name(scale_doc.get("nome"))
    is_san_martin = "sanmartin" in normalized_id or "sanmartin" in normalized_name

    if not is_san_martin:
        return scale_doc

    builtin_scale = _load_builtin_san_martin_scale()
    if not builtin_scale:
        return scale_doc

    enriched_scale = dict(scale_doc)
    for key, value in builtin_scale.items():
        if key not in enriched_scale:
            enriched_scale[key] = value
    return enriched_scale

# ==========================================
# ADMIN ROUTER (/api/admin)
# ==========================================

@public_admin_router.post("/auth/login", tags=["Admin - Auth"])
async def auth_login(payload: LoginRequest, request: Request):
    """
    Endpoint pubblico di login. Verifica username+password con bcrypt,
    restituisce un JWT con role e ai_enabled.
    """
    user_doc = await users_collection.find_one({"username": payload.username.lower()})
    if not user_doc:
        raise HTTPException(status_code=401, detail="Credenziali non valide")

    if not auth_module.verify_password(payload.password, user_doc["hashed_password"]):
        raise HTTPException(status_code=401, detail="Credenziali non valide")

    role = user_doc.get("role", "viewer")
    ai_enabled = user_doc.get("ai_enabled", False)

    # Log accesso operatore (mantiene il log su file per backward-compat ed estende a tutti)
    client_ip = request.client.host if request.client else "Sconosciuto"
    x_forwarded_for = request.headers.get("X-Forwarded-For")
    if x_forwarded_for:
        client_ip = x_forwarded_for.split(",")[0].strip()
    auth_manager.log_viewer_connection(
        username=user_doc["username"],
        role=role,
        ip_address=client_ip,
        device_name=payload.device_id
    )

    token = auth_module.create_access_token(
        username=user_doc["username"],
        role=role,
        ai_enabled=ai_enabled,
    )
    return {
        "token": token,
        "role": role,
        "ai_enabled": ai_enabled,
        "username": user_doc["username"],
    }

@admin_router.get("/auth/logs", tags=["Admin - Auth"])
async def get_viewer_logs(auth: dict = Depends(verify_auth)):
    if auth["role"] != "admin":
        raise HTTPException(status_code=403, detail="Solo l'admin può leggere i log di connessione")
    return auth_manager.get_viewer_logs()

# ── Stats Globali (Dashboard) ────────────────────────────────────────────────

@admin_router.get("/stats", tags=["Admin - Stats"])
async def get_global_stats(auth: dict = Depends(verify_auth)):
    """Restituisce le statistiche aggregate globali per la Dashboard (Fase 1)."""
    # 1. Totali
    active_users = await patients_collection.count_documents({"attivo": True})
    total_evals = await evaluations_collection.count_documents({})
    
    # 2. Copertura Scale (mock logica o base)
    # Per semplicità, consideriamo coperti quelli che hanno 'ultimo_sis_compilato' ecc.
    # ma facciamo una stima veloce dal DB.
    patients = await patients_collection.find({"attivo": True}).to_list(1000)
    
    coperti_count = 0
    scaduti_count = 0
    pos_mancanti = 0
    sis_mancanti = 0
    san_martin_mancanti = 0
    ultimi_alert = []
    
    now = datetime.now(timezone.utc)
    
    for p in patients:
        # Molto semplice: se ha almeno una valutazione recente (es. ultimo anno) è coperto
        # Assumiamo per ora una logica random o calcolata sui dati reali
        has_sis = p.get("ultimo_sis_compilato") is not None
        has_pos = p.get("ultimo_pos_compilato") is not None
        
        if has_sis or has_pos:
            coperti_count += 1
        else:
            scaduti_count += 1
            if not has_sis: sis_mancanti += 1
            if not has_pos: pos_mancanti += 1
            
            # Genera alert per non valutati
            ultimi_alert.append({
                "paziente_nome": p.get("nome", ""),
                "paziente_cognome": p.get("cognome", ""),
                "stato": "mai_valutato",
                "giorni_da_ultima_valutazione": 0,
                "scala_nome": "SIS/POS"
            })
            
    coperti_percentuale = (coperti_count / active_users * 100) if active_users > 0 else 0
    
    # Prendi solo i primi 10 alert
    ultimi_alert = ultimi_alert[:10]

    # 3. Trend Somministrazioni (ultimi 6 mesi base)
    trend_somministrazioni = [
        {"mese": "Gen", "count": 2},
        {"mese": "Feb", "count": 5},
        {"mese": "Mar", "count": 3},
        {"mese": "Apr", "count": 8},
        {"mese": "Mag", "count": 4},
        {"mese": "Giu", "count": 7},
    ] # Mock data for now, ideally group by month from DB
    
    # 4. Distribuzione Scale
    distribuzione_scale = [
        {"nome": "SIS", "count": 15, "colore": "#3B82F6"},
        {"nome": "POS", "count": 8, "colore": "#10B981"}
    ]

    return {
        "totale_utenze_attive": active_users,
        "totale_valutazioni_eseguite": total_evals,
        "copertura_scale": {
            "coperti_count": coperti_count,
            "scaduti_count": scaduti_count,
            "coperti_percentuale": round(coperti_percentuale, 1),
            "pos_mancanti": pos_mancanti,
            "san_martin_mancanti": san_martin_mancanti,
            "sis_mancanti": sis_mancanti
        },
        "ultimi_alert": ultimi_alert,
        "trend_somministrazioni": trend_somministrazioni,
        "distribuzione_scale": distribuzione_scale
    }

# ── CRUD Utenze ─────────────────────────────────────────────────────────────

@admin_router.get("/users", tags=["Admin - Users"])
async def get_users(auth: dict = Depends(verify_auth)):
    """Restituisce la lista di tutti gli operatori (solo admin)."""
    if auth["role"] != "admin":
        raise HTTPException(status_code=403, detail="Solo l'admin può gestire le utenze")
    cursor = users_collection.find({}, {"hashed_password": 0, "_id": 0})
    return await cursor.to_list(length=200)

@public_admin_router.post("/users", tags=["Admin - Users"], status_code=status.HTTP_201_CREATED)
async def create_user(payload: UserCreate, request: Request):
    """Crea un nuovo operatore. Solo admin. Accetta sia JWT che legacy header."""
    auth = await auth_module.verify_auth(request)
    if auth["role"] != "admin":
        raise HTTPException(status_code=403, detail="Solo l'admin può creare utenze")

    existing = await users_collection.find_one({"username": payload.username})
    if existing:
        raise HTTPException(status_code=409, detail=f"Username '{payload.username}' già in uso")

    now = datetime.now(timezone.utc)
    await users_collection.insert_one({
        "username": payload.username,
        "hashed_password": auth_module.hash_password(payload.password),
        "role": payload.role,
        "ai_enabled": payload.ai_enabled,
        "is_default": False,
        "created_at": now,
        "updated_at": now,
    })
    return {"message": f"Utente '{payload.username}' creato con successo"}

@admin_router.put("/users/{username}", tags=["Admin - Users"])
async def update_user(username: str, payload: UserUpdate, auth: dict = Depends(verify_auth)):
    """Modifica un operatore esistente. Solo admin."""
    if auth["role"] != "admin":
        raise HTTPException(status_code=403, detail="Solo l'admin può modificare le utenze")

    user_doc = await users_collection.find_one({"username": username})
    if not user_doc:
        raise HTTPException(status_code=404, detail=f"Utente '{username}' non trovato")

    update_data: dict = {"updated_at": datetime.now(timezone.utc)}

    if payload.password:
        update_data["hashed_password"] = auth_module.hash_password(payload.password)
    if payload.role is not None:
        if user_doc.get("is_default") and payload.role != "admin":
            raise HTTPException(status_code=400, detail="L'utente admin di sistema deve mantenere il ruolo Admin")
        update_data["role"] = payload.role
    if payload.ai_enabled is not None:
        update_data["ai_enabled"] = payload.ai_enabled

    await users_collection.update_one({"username": username}, {"$set": update_data})
    return {"message": f"Utente '{username}' aggiornato con successo"}

@admin_router.delete("/users/{username}", tags=["Admin - Users"])
async def delete_user(username: str, auth: dict = Depends(verify_auth)):
    """Elimina un operatore. Blocca l'eliminazione dell'utente di sistema e l'auto-cancellazione."""
    if auth["role"] != "admin":
        raise HTTPException(status_code=403, detail="Solo l'admin può eliminare le utenze")

    if auth["username"] == username:
        raise HTTPException(status_code=400, detail="Non puoi eliminare il tuo stesso account")

    user_doc = await users_collection.find_one({"username": username})
    if not user_doc:
        raise HTTPException(status_code=404, detail=f"Utente '{username}' non trovato")
    if user_doc.get("is_default"):
        raise HTTPException(status_code=400, detail="L'utente admin di sistema non può essere eliminato")

    await users_collection.delete_one({"username": username})
    return {"message": f"Utente '{username}' eliminato con successo"}


@admin_router.get("/patients", response_model=List[Patient], tags=["Admin - Patients"])
async def get_patients():
    # Migrazione automatica dei vecchi documenti sprovvisti del campo 'attivo'
    await patients_collection.update_many({"attivo": {"$exists": False}}, {"$set": {"attivo": True}})

    cursor = patients_collection.find({})
    patients = await cursor.to_list(length=1000)
    
    # Recupera tutte le scale per mappare l'ID al nome
    scales_cursor = scales_collection.find({})
    scales_list = await scales_cursor.to_list(length=100)
    scale_map = {}
    for s in scales_list:
        nome_lower = s["nome"].lower()
        scale_map[s["id"]] = nome_lower
        mongo_id = s.get("_id")
        if mongo_id:
            scale_map[str(mongo_id)] = nome_lower
        
    # Arricchisce ciascun utente con le date delle ultime scale compilate
    for pat in patients:
        pat_id = pat["id"]
        
        # Recupera tutte le valutazioni per questo utente, ordinate per data decrescente
        evals_cursor = evaluations_collection.find({"id_paziente": pat_id}).sort("data_compilazione", -1)
        evals = await evals_cursor.to_list(length=100)
        
        # Inizializziamo i campi come None (o stringhe vuote)
        pat_dict = pat if isinstance(pat, dict) else pat.__dict__
        pat_dict["ultimo_pos_compilato"] = None
        pat_dict["ultimo_san_martin_compilato"] = None
        pat_dict["ultimo_sis_compilato"] = None
        pat_dict["ultima_analisi_ia"] = None
        
        # Recupera la data dell'ultima analisi IA per questo utente
        latest_ai = await ai_analyses_collection.find_one(
            {"id_paziente": pat_id},
            sort=[("timestamp", -1)]
        )
        if latest_ai and latest_ai.get("timestamp"):
            ts = latest_ai["timestamp"]
            if isinstance(ts, datetime):
                pat_dict["ultima_analisi_ia"] = ts.isoformat()
            else:
                pat_dict["ultima_analisi_ia"] = str(ts)
        
        for ev in evals:
            scale_id = ev.get("id_scala")
            scale_id_str = str(scale_id) if scale_id else ""
            scale_name = scale_map.get(scale_id, scale_map.get(scale_id_str, "")).lower()
            
            data_val = ev.get("data_compilazione")
            data_str = None
            if data_val:
                if isinstance(data_val, datetime):
                    data_str = data_val.isoformat()
                else:
                    data_str = str(data_val)
            
            # Se la scala è POS ed è la prima che incontriamo (l'ultima compilata cronologicamente)
            if not pat_dict.get("ultimo_pos_compilato") and ("pos" in scale_name or "pos" in scale_id_str.lower()):
                pat_dict["ultimo_pos_compilato"] = data_str
                
            # Se la scala è San Martín ed è la prima che incontriamo
            scale_name_clean = scale_name.replace('í', 'i').replace('ì', 'i')
            if not pat_dict.get("ultimo_san_martin_compilato") and ("martin" in scale_name_clean or "martin" in scale_id_str.lower()):
                pat_dict["ultimo_san_martin_compilato"] = data_str

            # Se la scala è SIS ed è la prima che incontriamo
            if not pat_dict.get("ultimo_sis_compilato") and ("sis" in scale_name or "sis" in scale_id_str.lower()):
                pat_dict["ultimo_sis_compilato"] = data_str
                
            # Se abbiamo trovato tutte e tre, possiamo interrompere la ricerca per questo utente
            if (pat_dict.get("ultimo_pos_compilato") and 
                pat_dict.get("ultimo_san_martin_compilato") and
                pat_dict.get("ultimo_sis_compilato")):
                break
                
    return patients

@admin_router.get("/scales", response_model=List[Scale], tags=["Admin - Configuration"])
async def get_admin_scales():
    """Restituisce l'elenco completo delle scale e dei protocolli caricati."""
    cursor = scales_collection.find({})
    scales = await cursor.to_list(length=100)
    return scales

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
    
    await log_audit(
        "CREAZIONE_UTENTE", 
        auth_context["username"], 
        f"Creato nuovo utente: {patient.nome} {patient.cognome}", 
        patient.id
    )
    
    return patient

@admin_router.put("/patients/{id}", response_model=Patient, tags=["Admin - Patients"])
async def update_patient(id: str, patient: Patient, auth_context: dict = Depends(verify_auth)):
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
            
    # Elimina a cascata tutte le valutazioni associate all'utente prima di rimuoverlo
    await evaluations_collection.delete_many({"id_paziente": id})
    
    result = await patients_collection.delete_one({"id": id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Utente non trovato")
        
    await log_audit(
        "CANCELLAZIONE_UTENTE", 
        auth_context["username"], 
        f"Eliminato utente{utente_nome} e relative valutazioni".strip(), 
        id
    )
        
    return {"message": "Utente e le relative valutazioni eliminati con successo"}

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

class AiAnalysisUpdate(BaseModel):
    notes: Optional[str] = None

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

@admin_router.get("/evaluations/{id_patient}", response_model=List[Evaluation], tags=["Admin - Evaluations"])
async def get_evaluations(id_patient: str):
    """Storico completo per un utente, per fini analitici."""
    cursor = evaluations_collection.find({"id_paziente": id_patient})
    evaluations = await cursor.to_list(length=1000)
    return evaluations

async def _import_sis_scale(scala_data: dict, scale_id: str, nome: str, descrizione: str) -> dict:
    """
    Importa una scala SIS con la sua struttura specializzata.

    La scala SIS ha un formato diverso dalle scale standard (POS, San Martín):
    - Usa 'sottoscale' invece di 'domini'
    - Ogni item ha risposta tridimensionale (F, D, T) invece di opzioni multiple
    - Include sezioni supplementari (protezione, medica, comportamentale)
    - Include tabelle di conversione specifiche
    """
    info = scala_data.get("info", {})
    if info:
        scale_id = info.get("id", scale_id)
        nome = info.get("nome", nome)
        descrizione = info.get("sottotitolo", descrizione)

    sezioni: list[Section] = []

    # Sottoscale A-F → sezioni con domande (senza opzioni, dato che la risposta è F/D/T)
    for sottoscala in scala_data.get("sottoscale", []):
        codice = sottoscala.get("codice", "")
        nome_sez = sottoscala.get("nome", codice)
        domande: list[Question] = []
        for d in sottoscala.get("domande", []):
            domande.append(Question(
                id_domanda=d.get("id", f"q_{uuid.uuid4().hex[:8]}"),
                codice=d.get("id"),
                testo_domanda=d.get("testo", ""),
                note=d.get("note"),
                opzioni=[],
            ))
        sezioni.append(Section(
            codice_sezione=codice,
            titolo_sezione=nome_sez,
            descrizione_sezione=None,
            domande=domande,
        ))

    # Sezione 2: Protezione e tutela
    sez2 = scala_data.get("sezione_2_protezione_tutela", {})
    if sez2 and sez2.get("item"):
        domande_sez2: list[Question] = []
        for item in sez2["item"]:
            domande_sez2.append(Question(
                id_domanda=item.get("id", f"q_{uuid.uuid4().hex[:8]}"),
                codice=item.get("id"),
                testo_domanda=item.get("testo", ""),
                opzioni=[],
            ))
        sezioni.append(Section(
            codice_sezione="SEZ2",
            titolo_sezione=sez2.get("titolo", "Scala supplementare di protezione e tutela legale"),
            descrizione_sezione=sez2.get("note"),
            domande=domande_sez2,
        ))

    # Sezione 3 Medica
    sez3m = scala_data.get("sezione_3_medica", {})
    if sez3m and sez3m.get("item"):
        domande_med: list[Question] = []
        for item in sez3m["item"]:
            domande_med.append(Question(
                id_domanda=item.get("id", f"q_{uuid.uuid4().hex[:8]}"),
                codice=item.get("id"),
                testo_domanda=item.get("testo", ""),
                opzioni=[
                    Option(punteggio=0, testo_risposta="Assente"),
                    Option(punteggio=1, testo_risposta="Parziale"),
                    Option(punteggio=2, testo_risposta="Estensivo"),
                ],
            ))
        sezioni.append(Section(
            codice_sezione="SEZ3M",
            titolo_sezione=sez3m.get("titolo", "Bisogni di sostegno non ordinari di tipo medico"),
            descrizione_sezione=sez3m.get("note"),
            domande=domande_med,
        ))

    # Sezione 3 Comportamentale
    sez3c = scala_data.get("sezione_3_comportamentale", {})
    if sez3c and sez3c.get("item"):
        domande_comp: list[Question] = []
        for item in sez3c["item"]:
            domande_comp.append(Question(
                id_domanda=item.get("id", f"q_{uuid.uuid4().hex[:8]}"),
                codice=item.get("id"),
                testo_domanda=item.get("testo", ""),
                opzioni=[
                    Option(punteggio=0, testo_risposta="Assente"),
                    Option(punteggio=1, testo_risposta="Parziale"),
                    Option(punteggio=2, testo_risposta="Estensivo"),
                ],
            ))
        sezioni.append(Section(
            codice_sezione="SEZ3C",
            titolo_sezione=sez3c.get("titolo", "Bisogni di sostegno non ordinari di tipo comportamentale"),
            descrizione_sezione=sez3c.get("note"),
            domande=domande_comp,
        ))

    if not sezioni:
        raise HTTPException(status_code=422, detail="Il JSON SIS non contiene sottoscale o sezioni")

    scale = Scale(id=scale_id, nome=nome, descrizione=descrizione, sezioni=sezioni)
    scale_dict = scale.model_dump()

    # Preserva TUTTI i metadati extra del JSON SIS per il motore di calcolo
    extra_metadata = {
        key: value
        for key, value in scala_data.items()
        if key not in {"id", "nome", "descrizione", "domini"}
    }
    scale_dict.update(extra_metadata)
    scale_dict["tipo_scala"] = "sis"

    await scales_collection.replace_one({"id": scale_id}, scale_dict, upsert=True)

    total_questions = sum(len(s.domande) for s in sezioni)
    return {
        "message": "Scala SIS importata con successo",
        "id": scale_id,
        "nome": nome,
        "sezioni": len(sezioni),
        "domande_totali": total_questions,
        "tipo": "SIS (Supports Intensity Scale)",
    }


@admin_router.post("/import-scale", tags=["Admin - Configuration"])
async def import_scale(file: UploadFile = File(...)):
    """
    Importa una scala multidimensionale da un file JSON strutturato.

    Formato atteso:
    {
      "scala": {
        "id": "pos_2024",          // opzionale, generato se assente
        "nome": "Scala POS",
        "descrizione": "...",      // opzionale
        "domini": [
          {
            "codice": "SP",
            "nome": "Sviluppo Personale",
            "descrizione": "...",  // opzionale
            "domande": [
              {
                "codice": "SP-1",
                "testo": "...",
                "note": "...",     // opzionale
                "opzioni": [
                  { "punteggio": 3, "etichetta": "Riesce da solo", "descrizione": "..." }
                ]
              }
            ]
          }
        ]
      }
    }
    """
    if not (file.filename or '').lower().endswith('.json'):
        raise HTTPException(status_code=400, detail="Il file deve essere un JSON (.json)")

    MAX_FILE_SIZE = 5 * 1024 * 1024
    content = await file.read(MAX_FILE_SIZE + 1)
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail="Il file supera la dimensione massima consentita di 5MB")

    try:
        data = json.loads(content.decode('utf-8-sig'))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise HTTPException(status_code=422, detail=f"JSON non valido: {exc}")

    scala_data = data.get("scala")
    if not scala_data:
        raise HTTPException(status_code=422, detail="Campo 'scala' mancante nel JSON")

    # ── ID e metadati radice ──────────────────────────────────────────────
    scale_id = scala_data.get("id") or f"scale_{uuid.uuid4().hex[:8]}"
    nome = scala_data.get("nome") or "Scala senza nome"
    descrizione = scala_data.get("descrizione") or \
        f"Importata il {datetime.now(timezone.utc).strftime('%Y-%m-%d')}"

    # ── Scala SIS: importazione con struttura dedicata ─────────────────
    if (scala_data.get("sottoscale") or 
        scala_data.get("info", {}).get("id", "").lower().startswith("sis") or
        "sis" in scale_id.lower()):
        return await _import_sis_scale(scala_data, scale_id, nome, descrizione)

    # ── Costruzione sezioni (scale standard: POS, San Martín) ─────────
    sezioni: list[Section] = []

    for dominio in scala_data.get("domini", []):
        codice_dom = dominio.get("codice") or ""
        nome_dom = dominio.get("nome") or dominio.get("titolo_sezione") or codice_dom
        desc_dom = dominio.get("descrizione")

        domande: list[Question] = []
        for d in dominio.get("domande", []):
            codice_q = d.get("codice")
            testo_q = d.get("testo") or d.get("testo_domanda") or ""
            note_q = d.get("note")

            opzioni: list[Option] = []
            for o in d.get("opzioni", []):
                opzioni.append(Option(
                    punteggio=int(o.get("punteggio", 0)),
                    testo_risposta=o.get("etichetta") or o.get("testo_risposta") or "",
                    descrizione=o.get("descrizione"),
                ))

            # Ordina opzioni per punteggio decrescente (3→1) per consistenza UI
            opzioni.sort(key=lambda x: x.punteggio, reverse=True)

            domande.append(Question(
                id_domanda=f"q_{uuid.uuid4().hex[:8]}",
                codice=codice_q,
                testo_domanda=testo_q,
                note=note_q,
                opzioni=opzioni,
            ))

        sezioni.append(Section(
            codice_sezione=codice_dom,
            titolo_sezione=nome_dom,
            descrizione_sezione=desc_dom,
            domande=domande,
        ))

    if not sezioni:
        raise HTTPException(status_code=422, detail="Il JSON non contiene domini/sezioni")

    scale = Scale(
        id=scale_id,
        nome=nome,
        descrizione=descrizione,
        sezioni=sezioni,
    )

    scale_dict = scale.model_dump()
    extra_metadata = {
        key: value
        for key, value in scala_data.items()
        if key not in {"id", "nome", "descrizione", "domini"}
    }
    scale_dict.update(extra_metadata)

    await scales_collection.replace_one(
        {"id": scale_id}, scale_dict, upsert=True
    )

    total_questions = sum(len(s.domande) for s in sezioni)
    return {
        "message": "Scala importata con successo",
        "id": scale_id,
        "nome": nome,
        "sezioni": len(sezioni),
        "domande_totali": total_questions,
    }


@admin_router.put("/scales/{id}", response_model=Scale, tags=["Admin - Configuration"])
async def update_scale(id: str, scale: Scale):
    scale_dict = scale.model_dump()
    existing = await scales_collection.find_one({"id": id})
    if existing:
        # Mantiene qualsiasi metadato extra già salvato nel documento Mongo.
        preserved_metadata = {
            key: value
            for key, value in existing.items()
            if key not in {"_id", "id", "nome", "descrizione", "sezioni"}
        }
        scale_dict.update(preserved_metadata)
    result = await scales_collection.replace_one({"id": id}, scale_dict)
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Protocollo non trovato")
    return scale

@admin_router.delete("/scales/{id}", tags=["Admin - Configuration"])
async def delete_scale(id: str):
    result = await scales_collection.delete_one({"id": id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Protocollo non trovato")
    return {"message": "Protocollo eliminato con successo"}


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
    scale_doc = _hydrate_scale_doc(
        await scales_collection.find_one({"id": eval_doc["id_scala"]})
    )

    analysis = compute_psychometric_analysis(
        risposte=eval_doc.get("risposte", []),
        scale_doc=scale_doc or {},
    )

    domain_map = build_domain_map(scale_doc or {})
    if not domain_map:
        domain_map = DOMINI_POS
    domains = compute_direct_scores(eval_doc.get("risposte", []), domain_map, scale_doc)

    pdf_bytes = await asyncio.to_thread(
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
class AiPdfRequest(BaseModel):
    patient: dict
    report: str

@admin_router.post("/evaluations/ai-analysis-pdf", tags=["Admin - Evaluations"])
async def download_ai_analysis_pdf(request: AiPdfRequest):
    pdf_bytes = await asyncio.to_thread(generate_ai_analysis_pdf, request.patient, request.report)
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
    scale_doc = _hydrate_scale_doc(
        await scales_collection.find_one({"id": eval_doc["id_scala"]})
    )
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
    eval_docs = await cursor.to_list(length=1000)
    if not eval_docs:
        raise HTTPException(status_code=404, detail="Nessuna valutazione trovata")

    history = []
    for eval_doc in eval_docs:
        scale_doc = _hydrate_scale_doc(
            await scales_collection.find_one({"id": eval_doc["id_scala"]})
        )
        domain_map = build_domain_map(scale_doc or {})
        if not domain_map:
            domain_map = DOMINI_POS
        domains = compute_direct_scores(eval_doc.get("risposte", []), domain_map, scale_doc=scale_doc)
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
                domini=domains,
                risposte=eval_doc.get("risposte", []),
            )
        )
    return history


@admin_router.put("/evaluations/{evaluation_id}",
                  response_model=AggregatedEvaluation,
                  tags=["Admin - Evaluations"])
async def update_evaluation(evaluation_id: str, payload: EvaluationUpdateRequest):
    """Modifica inline punteggi/note di una valutazione, restituisce i dati riaggregati."""
    existing = await _find_evaluation_document(evaluation_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Valutazione non trovata")

    new_risposte = [r.model_dump() for r in payload.risposte]
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
        
    await evaluations_collection.update_one(
        _build_evaluation_selector(existing),
        {"$set": update_data}
    )
    existing["risposte"] = new_risposte
    scale_doc = _hydrate_scale_doc(
        await scales_collection.find_one({"id": existing["id_scala"]})
    )
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
        domini=domains,
        risposte=new_risposte,
    )

@admin_router.post("/settings", tags=["Admin - Configuration"])
async def update_settings(settings: AppSettings):
    settings_dict = settings.model_dump()
    
    # Se il frontend invia la chiave mascherata, recuperiamo quella vera dal DB
    if settings_dict.get("gemini_api_key") == "***-HIDDEN":
        existing = await settings_collection.find_one({"id": settings.id})
        if existing:
            settings_dict["gemini_api_key"] = existing.get("gemini_api_key")
        else:
            settings_dict["gemini_api_key"] = None
            
    await settings_collection.replace_one({"id": settings.id}, settings_dict, upsert=True)
    return {"message": "Impostazioni salvate con successo"}

@admin_router.get("/settings", response_model=AppSettings, tags=["Admin - Configuration"])
async def get_settings(auth: dict = Depends(verify_auth)):
    doc = await settings_collection.find_one({"id": "global_settings"})
    if doc:
        settings = AppSettings(**doc)
        # Nasconde la API Key ai viewer che non hanno ai_enabled
        if settings.gemini_api_key and auth["role"] == "viewer":
            if not auth.get("ai_enabled", False):
                settings.gemini_api_key = "***-HIDDEN"
        return settings
    return AppSettings()


@admin_router.get("/dashboard-stats", tags=["Admin - Dashboard"])
async def get_dashboard_stats():
    """
    Ritorna statistiche aggregate pre-calcolate per la Dashboard direzionale:
    - Totale utenze attive
    - Stato copertura (Coperti vs Scaduti/Da valutare) negli ultimi 6 mesi (180 giorni)
    - Distribuzione valutazioni per tipo di scala
    - Trend degli ultimi 6 mesi (valutazioni mensili per scala)
    - Lista degli ultimi alert (max 5) di pazienti da rivalutare urgentemente
    """
    try:
        import re
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
        patients_cursor = patients_collection.find({})
        patients = await patients_cursor.to_list(length=2000)
        
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
        evaluations = await evaluations_cursor.to_list(length=5000)
        
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
        
        for pat in patients:
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
                scale_name_clean = scale_name.replace('í', 'i').replace('ì', 'i')
                
                if "pos" in scale_name or "pos" in scale_id_str.lower():
                    pat_pos_evals.append(ev)
                elif "martin" in scale_name_clean or "martin" in scale_id_str.lower():
                    pat_sm_evals.append(ev)
                elif "sis" in scale_name or "sis" in scale_id_str.lower():
                    pat_sis_evals.append(ev)
            
            # --- Valuta POS ---
            has_valid_pos = False
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
                
            # Alert candidates: se non ha POS valida o non ha San Martín valida o non ha SIS valida
            if not has_valid_pos or not has_valid_sm or not has_valid_sis:
                if not pat_evals:
                    alert_candidates.append({
                        "paziente_id": pat_display_id,
                        "paziente_nome": pat.get("nome", ""),
                        "paziente_cognome": pat.get("cognome", ""),
                        "ultima_valutazione_data": None,
                        "giorni_da_ultima_valutazione": 9999,
                        "stato": "mai_valutato",
                        "scala_nome": "Nessuna scala somministrata"
                    })
                else:
                    sorted_evals = sorted(pat_evals, key=parse_eval_date, reverse=True)
                    latest_ev = sorted_evals[0]
                    latest_date = parse_eval_date(latest_ev)
                    days_since = (now - latest_date).days
                    scale_id = latest_ev.get("id_scala")
                    scale_id_str = str(scale_id) if scale_id else ""
                    scala_nome = scale_names.get(scale_id_str) or scale_names.get(str(scale_id)) or scale_id_str or "Scala sconosciuta"
                    alert_candidates.append({
                        "paziente_id": pat_display_id,
                        "paziente_nome": pat.get("nome", ""),
                        "paziente_cognome": pat.get("cognome", ""),
                        "ultima_valutazione_data": latest_date.isoformat(),
                        "giorni_da_ultima_valutazione": days_since,
                        "stato": "scaduto",
                        "scala_nome": scala_nome
                    })

        # Calcolo percentuale di copertura
        totale_pazienti = len(patients)
        totale_pazienti_attivi = len(pazienti_attivi)
        coperti_count = pos_attivi + san_martin_attivi + sis_attivi
        scaduti_count = pos_scaduti + san_martin_scaduti + sis_scaduti
        max_scale_teoriche = 3 * totale_pazienti_attivi
        copertura_percentuale = (coperti_count / max_scale_teoriche * 100) if max_scale_teoriche > 0 else 0.0
        
        # 5. Ordina gli alert: prima chi non ne ha mai fatte, poi chi ha valutazioni scadute da più tempo
        alert_candidates.sort(key=lambda x: x.get("giorni_da_ultima_valutazione", 0), reverse=True)
        ultimi_alert = alert_candidates[:5]
        
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
            
        return {
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
            "distribuzione_scale": distribuzione_scale,
            "trend_somministrazioni": trend_dati,
            "ultimi_alert": ultimi_alert,
            "demographics": demographics
        }
    except Exception as e:
        import traceback
        tb_str = traceback.format_exc()
        print("CRITICAL ERROR in get_dashboard_stats:")
        print(tb_str)
        return {
            "totale_utenze_attive": 0,
            "totale_valutazioni_eseguite": 0,
            "copertura_scale": {
                "coperti_percentuale": 0.0,
                "coperti_count": 0,
                "scaduti_count": 0,
                "pos_mancanti": 0,
                "san_martin_mancanti": 0,
                "sis_mancanti": 0,
                "pos_attivi": 0,
                "san_martin_attivi": 0,
                "sis_attivi": 0
            },
            "distribuzione_scale": [],
            "trend_somministrazioni": [],
            "ultimi_alert": [],
            "error_traceback": tb_str
        }


# ─── DATABASE EXPORT / IMPORT ────────────────────────────────────────────────

async def _collect_collection(name: str, collection) -> list:
    """Raccoglie tutti i documenti di una collezione, convertendo ObjectId in stringa."""
    docs = []
    async for doc in collection.find({}):
        doc.pop('_id', None)
        docs.append(doc)
    return docs


@admin_router.get("/export-db", tags=["Admin - Database"])
async def export_database():
    """Esporta l'intero database in un unico file JSON."""
    db_dump = {
        "metadata": {
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "version": "2.18.8",
        },
        "collections": {
            "patients": await _collect_collection("patients", patients_collection),
            "evaluations": await _collect_collection("evaluations", evaluations_collection),
            "scales": await _collect_collection("scales", scales_collection),
            "users": await _collect_collection("users", users_collection),
            "settings": await _collect_collection("settings", settings_collection),
            "ai_analyses": await _collect_collection("ai_analyses", ai_analyses_collection),
            "audit_logs": await _collect_collection("audit_logs", audit_logs_collection),
        }
    }
    json_bytes = json.dumps(db_dump, ensure_ascii=False, indent=2, default=str).encode('utf-8')

    filename = f"autify_backup_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
    return StreamingResponse(
        io.BytesIO(json_bytes),
        media_type="application/json",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@admin_router.post("/import-db", tags=["Admin - Database"])
async def import_database(file: UploadFile = File(...)):
    """Importa l'intero database da un file JSON di backup."""
    if not (file.filename or '').lower().endswith('.json'):
        raise HTTPException(status_code=400, detail="Il file deve essere un JSON (.json)")

    MAX_FILE_SIZE = 5 * 1024 * 1024
    content = await file.read(MAX_FILE_SIZE + 1)
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail="Il file supera la dimensione massima consentita di 5MB")

    try:
        data = json.loads(content.decode('utf-8-sig'))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise HTTPException(status_code=422, detail=f"JSON non valido: {exc}")

    collections_data = data.get("collections")
    if not collections_data:
        raise HTTPException(status_code=422, detail="Formato backup non valido: 'collections' mancante")

    mapping = {
        "patients": patients_collection,
        "evaluations": evaluations_collection,
        "scales": scales_collection,
        "users": users_collection,
        "settings": settings_collection,
        "ai_analyses": ai_analyses_collection,
    }

    imported_counts = {}
    for coll_name, coll in mapping.items():
        docs = collections_data.get(coll_name, [])
        if docs:
            await coll.delete_many({})
            await coll.insert_many(docs)
            imported_counts[coll_name] = len(docs)

    return {
        "message": "Database importato con successo",
        "collections": imported_counts,
    }


@admin_router.get("/export-patients-csv", tags=["Admin - Database"])
async def export_patients_csv():
    """Esporta la lista utenti e il loro stato documentale in formato CSV per Excel."""
    import csv
    from io import StringIO
    
    patients_cursor = patients_collection.find({})
    patients = await patients_cursor.to_list(length=2000)
    
    output = StringIO()
    # Aggiungi il BOM (Byte Order Mark) per far riconoscere a Excel il formato UTF-8 automaticamente
    output.write('\ufeff')
    writer = csv.writer(output, delimiter=';')
    writer.writerow(["Nome", "Cognome", "Sesso", "Data di Nascita", "Ultimo POS", "Ultimo San Martin", "Ultima SIS"])
    
    for pat in patients:
        nome = pat.get("nome", "")
        cognome = pat.get("cognome", "")
        sesso = pat.get("sesso", "")
        data_nascita = pat.get("dataNascita", "")
        ultimo_pos = pat.get("ultimoPosCompilato", "")
        ultimo_sm = pat.get("ultimoSanMartinCompilato", "")
        ultima_sis = pat.get("ultimaSisCompilata", "")
        
        writer.writerow([nome, cognome, sesso, data_nascita, ultimo_pos, ultimo_sm, ultima_sis])
        
    csv_bytes = output.getvalue().encode('utf-8')
    filename = f"autify_utenti_{datetime.now(timezone.utc).strftime('%Y%m%d')}.csv"
    
    return StreamingResponse(
        io.BytesIO(csv_bytes),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'}
    )


@admin_router.delete("/evaluations/{evaluation_id}", tags=["Admin - Evaluations"])
async def delete_evaluation(evaluation_id: str):
    """Elimina definitivamente una singola valutazione dal database."""
    eval_doc = await evaluations_collection.find_one({"id_valutazione": evaluation_id})
    if not eval_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Valutazione non trovata")
    
    result = await evaluations_collection.delete_one({"id_valutazione": evaluation_id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Errore nell'eliminazione della valutazione")
        
    return {"status": "success", "message": "Valutazione eliminata con successo"}


# ==========================================
# CLIENT ROUTER (/api/client)
# ==========================================

@client_router.get("/scales", response_model=List[Scale], tags=["Client - Scales"])
async def get_scales():
    """Restituisce l'elenco delle scale disponibili per il data entry"""
    cursor = scales_collection.find({})
    scales = await cursor.to_list(length=100)
    return scales

@client_router.get("/scales/{scale_id}", response_model=Scale, tags=["Client - Scales"])
async def get_scale_by_id(scale_id: str):
    """Restituisce i dettagli completi di una singola scala"""
    scale = await scales_collection.find_one({"id": scale_id})
    if not scale:
        raise HTTPException(status_code=404, detail="Scala non trovata")
    return scale

@client_router.post("/evaluations", response_model=Evaluation, status_code=status.HTTP_201_CREATED, tags=["Client - Evaluations"])
async def create_evaluation(evaluation: Evaluation):
    """Salva una nuova valutazione compilata nel database"""
    eval_dict = evaluation.model_dump()
    if not eval_dict.get("data_compilazione"):
        eval_dict["data_compilazione"] = datetime.now(timezone.utc)
    evaluation = Evaluation(**eval_dict)
    result = await evaluations_collection.insert_one(eval_dict)
    
    if not result.inserted_id:
        raise HTTPException(status_code=500, detail="Errore nel salvataggio della valutazione")
        
    # Salva il log di audit
    operatore = eval_dict.get("nome_operatore", "Operatore Sconosciuto")
    id_paziente = eval_dict.get("id_paziente")
    id_scala = eval_dict.get("id_scala", "")
    
    utente_info = ""
    if id_paziente:
        utente_doc = await patients_collection.find_one({"id": id_paziente})
        if utente_doc:
            cognome = utente_doc.get("cognome", "")
            nome = utente_doc.get("nome", "")
            if cognome or nome:
                utente_info = f" per {cognome} {nome}"
                
    await log_audit(
        "COMPILAZIONE_SCALA", 
        operatore, 
        f"{operatore} ha compilato la Scala {id_scala}{utente_info}".strip(), 
        id_paziente
    )
        
    return evaluation

@admin_router.get("/audit-logs", response_model=List[AuditLogResponse], tags=["Admin - Audit"])
async def get_audit_logs(limit: int = 200):
    """Recupera gli ultimi log di attività (tracciabilità educativa)"""
    cursor = audit_logs_collection.find({}).sort("timestamp", -1)
    logs_raw = await cursor.to_list(length=limit)
    
    logs = []
    for log in logs_raw:
        log["_id"] = str(log["_id"])
        logs.append(log)
        
    return logs

@client_router.get("/patients", response_model=List[Patient], tags=["Client - Patients"])
async def get_client_patients():
    """Recupero pazienti per la selezione prima del wizard"""
    cursor = patients_collection.find({})
    patients = await cursor.to_list(length=1000)
    # The frontend only needs id, nome, cognome. Patient model has them.
    return patients
