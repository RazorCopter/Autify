from ..audit import record
from ..transactions import atomic
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
from pydantic import BaseModel, Field, ConfigDict
from pymongo import ReturnDocument
import uuid
import io
import os
import asyncio
from pathlib import Path
from .. import auth as auth_module

class LoginRequest(BaseModel):
    username: str
    password: str
    device_id: Optional[str] = "Sconosciuto"


class ChangePasswordRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=12, max_length=128)
    confirm_password: str = Field(min_length=12, max_length=128)

from ._helpers import (
    verify_auth,
    log_audit,
)

admin_router = APIRouter(dependencies=[Depends(verify_auth)])
public_admin_router = APIRouter()
client_router = APIRouter(dependencies=[Depends(verify_auth)])


# ==========================================
# ADMIN ROUTER (/api/admin)
# ==========================================

@public_admin_router.post("/auth/login", tags=["Admin - Auth"])
@_limiter.limit("10/minute")
async def auth_login(request: Request, payload: LoginRequest):
    """
    Endpoint pubblico di login. Verifica username+password con bcrypt,
    restituisce un JWT con role e ai_enabled.
    """
    user_doc = await users_collection.find_one({"username": payload.username.lower()})
    if not user_doc:
        raise HTTPException(status_code=401, detail="Credenziali non valide")

    if not auth_module.verify_password(payload.password, user_doc["hashed_password"]):
        raise HTTPException(status_code=401, detail="Credenziali non valide")

    # Also covers old backups restored after startup without the mandatory flag.
    if user_doc["username"] == "admin" and payload.password == "admin":
        await users_collection.update_one(
            {"username": "admin", "hashed_password": user_doc["hashed_password"]},
            {"$set": {"must_change_password": True}},
        )
        user_doc["must_change_password"] = True

    role = user_doc.get("role", "viewer")
    ai_enabled = user_doc.get("ai_enabled", False)
    token_version = user_doc.get("token_version", 1)

    token = auth_module.create_access_token(
        username=user_doc["username"],
        role=role,
        ai_enabled=ai_enabled,
        token_version=token_version,
    )
    await log_audit(
        "LOGIN_OPERATORE",
        user_doc["username"],
        f"Accesso operatore '{user_doc['username']}' con ruolo '{role}'"
    )
    return {
        "token": token,
        "role": role,
        "ai_enabled": ai_enabled,
        "username": user_doc["username"],
        "must_change_password": user_doc.get("must_change_password", False),
    }

# ── CRUD Utenze ─────────────────────────────────────────────────────────────

@admin_router.post("/auth/change-password", tags=["Admin - Auth"])
@_limiter.limit("10/minute")
async def change_own_password(request: Request, payload: ChangePasswordRequest,
                              auth: dict = Depends(verify_auth)):
    if (payload.new_password != payload.confirm_password
            or len(payload.new_password.encode("utf-8")) > 72
            or not payload.new_password.strip()):
        raise HTTPException(422, "Conferma non coincidente o password oltre 72 byte.")
    user = await users_collection.find_one({"username": auth["username"]})
    if not user or not auth_module.verify_password(payload.current_password, user.get("hashed_password", "")):
        raise HTTPException(400, "Password attuale non corretta.")
    if auth_module.verify_password(payload.new_password, user["hashed_password"]):
        raise HTTPException(422, "La nuova password deve essere diversa dalla precedente.")
    # Compare-and-swap prevents two concurrent changes or an admin reset racing
    # with this request from silently replacing newer credentials/permissions.
    async def change(session):
        updated = await users_collection.find_one_and_update(
            {"username": auth["username"], "hashed_password": user["hashed_password"],
             "token_version": auth["token_version"]},
            {"$set": {"hashed_password": auth_module.hash_password(payload.new_password),
                      "must_change_password": False, "updated_at": datetime.now(timezone.utc)},
             "$inc": {"token_version": 1}},
            return_document=ReturnDocument.AFTER, session=session,
        )
        if not updated:
            raise HTTPException(409, "Account modificato nel frattempo. Effettua nuovamente il login.")
        await record("CAMBIO_PASSWORD", auth["username"], "Password personale aggiornata; sessioni revocate", auth["username"], session=session)
    await atomic(change)
    return {"message": "Password aggiornata. Effettua nuovamente il login.", "reauthenticate": True}


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
    document = {
        "username": payload.username, "hashed_password": auth_module.hash_password(payload.password),
        "role": payload.role, "ai_enabled": payload.ai_enabled, "is_default": False,
        "token_version": 1, "created_at": now, "updated_at": now,
    }
    async def persist(session):
        await users_collection.insert_one(document, session=session)
        await record("CREAZIONE_OPERATORE", auth["username"], "Creato account operatore", payload.username, session=session)
    await atomic(persist)
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
    should_increment_token = False

    if payload.password:
        update_data["hashed_password"] = auth_module.hash_password(payload.password)
        update_data["must_change_password"] = False
        should_increment_token = True
    if payload.role is not None:
        if user_doc.get("is_default") and payload.role != "admin":
            raise HTTPException(status_code=400, detail="L'utente admin di sistema deve mantenere il ruolo Admin")
        update_data["role"] = payload.role
        should_increment_token = True
    if payload.ai_enabled is not None:
        update_data["ai_enabled"] = payload.ai_enabled
        should_increment_token = True

    update_query: dict = {"$set": update_data}
    if should_increment_token:
        update_query["$inc"] = {"token_version": 1}

    async def persist(session):
        result = await users_collection.update_one({"_id": user_doc["_id"]}, update_query, session=session)
        if not result.matched_count:
            raise HTTPException(409, "Account modificato o eliminato durante l'operazione")
        await record("MODIFICA_OPERATORE", auth["username"], "Aggiornato account e autorizzazioni", username, session=session)
    await atomic(persist)
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

    async def persist(session):
        result = await users_collection.delete_one({"_id": user_doc["_id"]}, session=session)
        if not result.deleted_count:
            raise HTTPException(409, "Account gia eliminato")
        await record("ELIMINAZIONE_OPERATORE", auth["username"], "Eliminato account operatore", username, session=session)
    await atomic(persist)
    return {"message": f"Utente '{username}' eliminato con successo"}


