from ..security import safe_csv_cell
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
from ..database import evaluations_collection, settings_collection, patients_collection, scales_collection, users_collection, ai_analyses_collection, audit_logs_collection, licenses_collection
from ..pdf_generator import generate_evaluation_pdf, generate_ai_analysis_pdf
from ..analytics import compute_psychometric_analysis, compute_direct_scores, build_domain_map, calcola_punteggi_sis
from datetime import datetime, timezone, timedelta
import json
import re
import hashlib
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
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

from ..backup_service import (
    MAX_ARCHIVE_BYTES, decode_document, decrypt_backup, encrypt_backup,
    export_archive, restore_document,
)
from ..database import database
from ..maintenance import maintenance_enabled
from ..license_service import require_valid_license
from pymongo.errors import PyMongoError


@admin_router.get("/export-db", tags=["Admin - Database"])
async def export_database(auth: dict = Depends(verify_auth)):
    if auth["role"] != "admin":
        raise HTTPException(403, "Solo l'admin può esportare il database")
    try:
        encrypted = await export_archive(database)
    except PyMongoError as exc:
        raise HTTPException(503, "Database non disponibile per un backup consistente. Nessun file generato.") from exc
    filename = f"autify_backup_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.enc"
    await log_audit("EXPORT_DATABASE", auth["username"], f"Backup completo cifrato: {filename}")
    return StreamingResponse(io.BytesIO(encrypted), media_type="application/octet-stream",
                             headers={"Content-Disposition": f'attachment; filename="{filename}"',
                                      "Cache-Control": "no-store"})


@admin_router.post("/import-db", tags=["Admin - Database"])
async def import_database(file: UploadFile = File(...), auth: dict = Depends(verify_auth)):
    if auth["role"] != "admin":
        raise HTTPException(403, "Solo l'admin può importare il database")
    filename = (file.filename or "").lower()
    if not filename.endswith((".json", ".enc")):
        raise HTTPException(400, "Il file deve essere .json o .enc")
    content = await file.read(MAX_ARCHIVE_BYTES + 1)
    if len(content) > MAX_ARCHIVE_BYTES:
        raise HTTPException(413, "Il backup supera il limite di 64 MiB.")
    payload = decrypt_backup(content) if filename.endswith(".enc") else content
    document = decode_document(payload)
    try:
        result = await restore_document(database, document, auth["username"], maintenance=maintenance_enabled())
    except PyMongoError as exc:
        raise HTTPException(503, "Database non disponibile: ripristino non avviato.") from exc
    _invalidate_dashboard_cache()
    return result


@admin_router.get("/export-patients-csv", tags=["Admin - Database"], dependencies=[Depends(require_valid_license)])
async def export_patients_csv(auth: dict = Depends(verify_auth)):
    """Esporta la lista utenti e il loro stato documentale in formato CSV per Excel.
    Usa un generator asincrono (P-02): la risposta inizia subito, senza caricare
    tutto il CSV in RAM prima dell'invio.
    """
    if auth.get("role") != "admin":
        raise HTTPException(403, "Esportazione dati riservata agli amministratori")
    import csv
    from io import StringIO

    from ..expiry import project

    def _sanitize_csv_cell(val):
        if val is None:
            return ""
        s = str(val)
        if s and s[0] in ("=", "+", "-", "@", "\t", "\r"):
            return "'" + s
        return s

    def _row_for_patient(pat):
        raw = [pat.get("nome", ""), pat.get("cognome", ""), pat.get("sesso", ""),
               pat.get("data_nascita", pat.get("dataNascita", ""))] + [
               pat.get(f"ultimo_{kind}_compilato", "") for kind in
               ("ogva", "sabs", "oso", "pos", "san_martin", "sis")]
        return [_sanitize_csv_cell(v) for v in raw]

    async def _csv_generator():
        buf = StringIO()
        writer = csv.writer(buf, delimiter=";")
        # BOM per Excel UTF-8
        buf.write("﻿")
        writer.writerow(["Nome", "Cognome", "Sesso", "Data di Nascita",
                         "Ultimo OGVA", "Ultimo SABS", "Ultimo OSO",
                         "Ultimo POS", "Ultimo San Martin", "Ultima SIS"])
        yield buf.getvalue().encode("utf-8")

        batch = []
        async for pat in patients_collection.find({}).sort([("cognome", 1), ("nome", 1), ("id", 1), ("_id", 1)]):
            batch.append(pat)
            if len(batch) == 100:
                await project(batch)
                for item in batch:
                    buf.seek(0); buf.truncate(0)
                    writer.writerow([safe_csv_cell(value) for value in _row_for_patient(item)])
                    yield buf.getvalue().encode("utf-8")
                batch = []
        if batch:
            await project(batch)
            for item in batch:
                buf.seek(0); buf.truncate(0)
                writer.writerow([safe_csv_cell(value) for value in _row_for_patient(item)])
                yield buf.getvalue().encode("utf-8")

    await log_audit("EXPORT_CSV", auth["username"], "Avviata esportazione CSV anagrafica riservata agli amministratori")
    filename = f"autify_utenti_{datetime.now(timezone.utc).strftime('%Y%m%d')}.csv"
    return StreamingResponse(
        _csv_generator(),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"', "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"},
    )


