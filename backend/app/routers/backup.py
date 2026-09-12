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

async def _collect_collection(name: str, collection) -> list:
    """Raccoglie tutti i documenti di una collezione, convertendo ObjectId in stringa."""
    docs = []
    async for doc in collection.find({}):
        doc.pop('_id', None)
        docs.append(doc)
    return docs

@admin_router.get("/export-db", tags=["Admin - Database"])
async def export_database(auth: dict = Depends(verify_auth)):
    """Esporta l'intero database in un unico file JSON."""
    if auth["role"] != "admin":
        raise HTTPException(status_code=403, detail="Solo l'admin può esportare il database")

    _version_file = Path(__file__).resolve().parents[2] / "VERSION"
    _version = _version_file.read_text(encoding="utf-8").strip() if _version_file.exists() else "unknown"

    db_dump = {
        "metadata": {
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "version": _version,
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
    await log_audit(
        "EXPORT_DATABASE",
        auth["username"],
        f"Esportato backup completo del database ({filename})"
    )
    return StreamingResponse(
        io.BytesIO(json_bytes),
        media_type="application/json",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@admin_router.post("/import-db", tags=["Admin - Database"])
async def import_database(file: UploadFile = File(...), auth: dict = Depends(verify_auth)):
    """Importa l'intero database da un file JSON di backup."""
    if auth["role"] != "admin":
        raise HTTPException(status_code=403, detail="Solo l'admin può importare il database")

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

    metadata = data.get("metadata")
    if not isinstance(metadata, dict) or "version" not in metadata:
        raise HTTPException(status_code=422, detail="Formato backup non valido: header 'metadata' mancante o corrotto")

    collections_data = data.get("collections")
    if not isinstance(collections_data, dict) or not collections_data:
        raise HTTPException(status_code=422, detail="Formato backup non valido: 'collections' deve essere un oggetto non vuoto")

    mapping = {
        "patients": patients_collection,
        "evaluations": evaluations_collection,
        "scales": scales_collection,
        "users": users_collection,
        "settings": settings_collection,
        "ai_analyses": ai_analyses_collection,
        "audit_logs": audit_logs_collection,
    }

    # Pre-validazione completa PRIMA di eseguire qualsiasi cancellazione distruttiva (DATA-01)
    valid_collections_to_import = {}
    for coll_name, docs in collections_data.items():
        if coll_name not in mapping:
            continue
        if not isinstance(docs, list):
            raise HTTPException(
                status_code=422,
                detail=f"Collezione '{coll_name}' non valida: attesa una lista di documenti"
            )
        for idx, doc in enumerate(docs):
            if not isinstance(doc, dict):
                raise HTTPException(
                    status_code=422,
                    detail=f"Documento #{idx} nella collezione '{coll_name}' non è un oggetto JSON valido"
                )
        if docs:
            valid_collections_to_import[coll_name] = docs

    if not valid_collections_to_import:
        raise HTTPException(
            status_code=422,
            detail="Nessuna collezione riconosciuta con documenti validi da ripristinare"
        )

    # Se viene ripristinata la collezione utenti, verifica che contenga almeno un admin
    if "users" in valid_collections_to_import:
        has_admin = any(u.get("role") == "admin" for u in valid_collections_to_import["users"])
        if not has_admin:
            raise HTTPException(
                status_code=422,
                detail="Il backup della collezione 'users' deve contenere almeno un utente con ruolo 'admin'"
            )

    imported_counts = {}
    for coll_name, docs in valid_collections_to_import.items():
        coll = mapping[coll_name]
        await coll.delete_many({})
        await coll.insert_many(docs)
        imported_counts[coll_name] = len(docs)

    _invalidate_dashboard_cache()

    await log_audit(
        "IMPORT_DATABASE",
        auth["username"],
        f"Ripristinato backup database: {imported_counts}"
    )

    return {
        "message": "Database importato con successo",
        "collections": imported_counts,
    }


@admin_router.get("/export-patients-csv", tags=["Admin - Database"])
async def export_patients_csv():
    """Esporta la lista utenti e il loro stato documentale in formato CSV per Excel.
    Usa un generator asincrono (P-02): la risposta inizia subito, senza caricare
    tutto il CSV in RAM prima dell'invio.
    """
    import csv
    from io import StringIO

    # Scale in memoria (≤100 documenti, trascurabili)
    scales_list = await scales_collection.find({}).to_list(length=100)
    scale_map: dict = {}
    for s in scales_list:
        nome_lower = s.get("nome", "").lower()
        if s.get("id"):
            scale_map[s["id"]] = nome_lower
        if s.get("_id"):
            scale_map[str(s["_id"])] = nome_lower

    # Valutazioni raggruppate per paziente: 1 bulk query con solo i campi necessari
    # (id_paziente, id_scala, data_compilazione) per minimizzare il payload RAM.
    evals_projection = {"id_paziente": 1, "id_scala": 1, "data_compilazione": 1, "_id": 0}
    evals_cursor = evaluations_collection.find({}, evals_projection).sort("data_compilazione", -1)
    evals_by_patient: dict = {}
    async for ev in evals_cursor:
        pid = ev.get("id_paziente")
        if pid:
            evals_by_patient.setdefault(pid, []).append(ev)

    def _row_for_patient(pat: dict) -> list:
        pat_id = pat.get("id")
        evals = evals_by_patient.get(pat_id, [])

        ultimo_pos = ultimo_sm = ultima_sis = ultimo_ogva = ultimo_sabs = ultimo_oso = None

        for ev in evals:
            scale_id = ev.get("id_scala")
            scale_id_str = str(scale_id) if scale_id else ""
            scale_name = scale_map.get(scale_id, scale_map.get(scale_id_str, "")).lower()
            data_val = ev.get("data_compilazione")
            data_str = data_val.isoformat() if isinstance(data_val, datetime) else (str(data_val) if data_val else "")

            scale_type = _classify_scale(scale_name, scale_id_str)
            if not ultimo_pos and scale_type == "pos":
                ultimo_pos = data_str
            elif not ultimo_sm and scale_type == "san_martin":
                ultimo_sm = data_str
            elif not ultima_sis and scale_type == "sis":
                ultima_sis = data_str
            elif not ultimo_ogva and scale_type == "ogva":
                ultimo_ogva = data_str
            elif not ultimo_sabs and scale_type == "sabs":
                ultimo_sabs = data_str
            elif not ultimo_oso and scale_type == "oso":
                ultimo_oso = data_str
            if ultimo_pos and ultimo_sm and ultima_sis and ultimo_ogva and ultimo_sabs and ultimo_oso:
                break

        # Fallback ai campi denormalizzati nel documento paziente
        ultimo_pos = ultimo_pos or pat.get("ultimo_pos_compilato", pat.get("ultimoPosCompilato", ""))
        ultimo_sm = ultimo_sm or pat.get("ultimo_san_martin_compilato", pat.get("ultimoSanMartinCompilato", ""))
        ultima_sis = ultima_sis or pat.get("ultimo_sis_compilato", pat.get("ultimaSisCompilata", ""))
        ultimo_ogva = ultimo_ogva or pat.get("ultimo_ogva_compilato", "")
        ultimo_sabs = ultimo_sabs or pat.get("ultimo_sabs_compilato", "")
        ultimo_oso = ultimo_oso or pat.get("ultimo_oso_compilato", "")

        return [
            pat.get("nome", ""), pat.get("cognome", ""),
            pat.get("sesso", ""), pat.get("data_nascita", pat.get("dataNascita", "")),
            ultimo_ogva, ultimo_sabs, ultimo_oso,
            ultimo_pos, ultimo_sm, ultima_sis,
        ]

    async def _csv_generator():
        buf = StringIO()
        writer = csv.writer(buf, delimiter=";")
        # BOM per Excel UTF-8
        buf.write("﻿")
        writer.writerow(["Nome", "Cognome", "Sesso", "Data di Nascita",
                         "Ultimo OGVA", "Ultimo SABS", "Ultimo OSO",
                         "Ultimo POS", "Ultimo San Martin", "Ultima SIS"])
        yield buf.getvalue().encode("utf-8")

        async for pat in patients_collection.find({}):
            buf.seek(0); buf.truncate(0)
            writer.writerow(_row_for_patient(pat))
            yield buf.getvalue().encode("utf-8")

    filename = f"autify_utenti_{datetime.now(timezone.utc).strftime('%Y%m%d')}.csv"
    return StreamingResponse(
        _csv_generator(),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


