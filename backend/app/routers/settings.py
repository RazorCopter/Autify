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
    AISettingsResponse,
    AISettingsPatch,
    GeminiProviderResponse,
    OpenAIProviderResponse,
    OpenAICompatibleResponse,
    SecretFieldStatus,
    encrypt_secret,
    decrypt_secret,
    mask_secret,
    is_masked_or_empty,
    validate_base_url,
)


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

@admin_router.get("/scales", response_model=List[Scale], tags=["Admin - Configuration"])
async def get_admin_scales():
    """Restituisce l'elenco completo delle scale e dei protocolli caricati."""
    cursor = scales_collection.find({})
    scales = await cursor.to_list(length=100)
    return scales

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

            tipo_q = d.get("tipo") or "likert"
            sottodomande_q = d.get("sottodomande")

            domande.append(Question(
                id_domanda=f"q_{uuid.uuid4().hex[:8]}",
                codice=codice_q,
                testo_domanda=testo_q,
                note=note_q,
                tipo=tipo_q,
                sottodomande=sottodomande_q,
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
    if scale.id != id:
        raise HTTPException(status_code=400, detail="L'ID nel corpo della richiesta non coincide con l'ID nel path")
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


@admin_router.post("/settings", tags=["Admin - Configuration"])
async def update_settings(settings: AppSettings):
    settings_dict = settings.model_dump()
    existing = await settings_collection.find_one({"id": settings.id})

    # Preserva o inizializza il sotto-documento AI
    if existing and "ai" in existing and isinstance(existing["ai"], dict):
        settings_dict["ai"] = existing["ai"]
    elif "ai" not in settings_dict or not settings_dict["ai"]:
        settings_dict["ai"] = AISettingsStored().model_dump()

    # Se il payload legacy include chiavi non mascherate, sincronizza ai.gemini e ai.openai
    if settings_dict.get("gemini_api_key") and settings_dict.get("gemini_api_key") != "***-HIDDEN":
        settings_dict["ai"]["gemini"]["api_key_encrypted"] = encrypt_secret(settings_dict["gemini_api_key"])
    if settings_dict.get("chatgpt_api_key") and settings_dict.get("chatgpt_api_key") != "***-HIDDEN":
        settings_dict["ai"]["openai"]["api_key_encrypted"] = encrypt_secret(settings_dict["chatgpt_api_key"])

    # Rimuovi categoricamente le credenziali in chiaro dal dizionario prima del salvataggio
    settings_dict.pop("gemini_api_key", None)
    settings_dict.pop("chatgpt_api_key", None)

    await settings_collection.replace_one({"id": settings.id}, settings_dict, upsert=True)
    # Assicura il purge a livello DB nel caso in cui fossero presenti campi residui
    await settings_collection.update_one(
        {"id": settings.id},
        {"$unset": {"gemini_api_key": "", "chatgpt_api_key": ""}}
    )
    return {"message": "Impostazioni salvate con successo"}

@admin_router.get("/settings", response_model=AppSettings, tags=["Admin - Configuration"])
async def get_settings(auth: dict = Depends(verify_auth)):
    doc = await settings_collection.find_one({"id": "global_settings"})
    if doc:
        settings = AppSettings(**doc)
        # Non restituire mai le credenziali in chiaro né il sotto-documento AI cifrato
        settings.gemini_api_key = None
        settings.chatgpt_api_key = None
        settings.ai = None
        return settings
    return AppSettings()


def stored_to_ai_response(stored: AISettingsStored) -> AISettingsResponse:
    gem_key = decrypt_secret(stored.gemini.api_key_encrypted)
    oai_key = decrypt_secret(stored.openai.api_key_encrypted)
    oac_key = decrypt_secret(stored.openai_compatible.api_key_encrypted)

    masked_headers = {}
    if stored.openai_compatible.custom_headers:
        for k, v in stored.openai_compatible.custom_headers.items():
            plain_v = decrypt_secret(v)
            masked_headers[k] = mask_secret(plain_v) or "***"

    return AISettingsResponse(
        schema_version=stored.schema_version,
        active_provider=stored.active_provider,
        viewer_ai_enabled=stored.viewer_ai_enabled,
        system_prompt=stored.system_prompt,
        generation=stored.generation,
        network=stored.network,
        gemini=GeminiProviderResponse(
            model=stored.gemini.model,
            api_key=SecretFieldStatus(
                configured=bool(gem_key),
                hint=mask_secret(gem_key) if gem_key else None,
            ),
        ),
        openai=OpenAIProviderResponse(
            model=stored.openai.model,
            protocol=stored.openai.protocol,
            api_key=SecretFieldStatus(
                configured=bool(oai_key),
                hint=mask_secret(oai_key) if oai_key else None,
            ),
        ),
        openai_compatible=OpenAICompatibleResponse(
            base_url=stored.openai_compatible.base_url,
            model=stored.openai_compatible.model,
            protocol=stored.openai_compatible.protocol,
            api_key=SecretFieldStatus(
                configured=bool(oac_key),
                hint=mask_secret(oac_key) if oac_key else None,
            ),
            custom_headers=masked_headers,
        ),
    )

async def get_or_migrate_ai_settings() -> AISettingsStored:
    doc = await settings_collection.find_one({"id": "global_settings"})
    if not doc:
        return AISettingsStored()

    needs_purge = False
    unset_fields = {}
    for legacy_key in ("gemini_api_key", "chatgpt_api_key"):
        if legacy_key in doc:
            needs_purge = True
            unset_fields[legacy_key] = ""

    if "ai" in doc and isinstance(doc["ai"], dict):
        try:
            stored = AISettingsStored.model_validate(doc["ai"])
            needs_save = False

            # Migrazione at-rest per segreti preesistenti non ancora cifrati
            if stored.gemini.api_key_encrypted and not stored.gemini.api_key_encrypted.startswith("enc:v1:"):
                stored.gemini.api_key_encrypted = encrypt_secret(stored.gemini.api_key_encrypted)
                needs_save = True

            if stored.openai.api_key_encrypted and not stored.openai.api_key_encrypted.startswith("enc:v1:"):
                stored.openai.api_key_encrypted = encrypt_secret(stored.openai.api_key_encrypted)
                needs_save = True

            if stored.openai_compatible.api_key_encrypted and not stored.openai_compatible.api_key_encrypted.startswith("enc:v1:"):
                stored.openai_compatible.api_key_encrypted = encrypt_secret(stored.openai_compatible.api_key_encrypted)
                needs_save = True

            if stored.openai_compatible.custom_headers:
                migrated_headers = {}
                for k, v in stored.openai_compatible.custom_headers.items():
                    if v and not v.startswith("enc:v1:"):
                        migrated_headers[k] = encrypt_secret(v)
                        needs_save = True
                    else:
                        migrated_headers[k] = v
                stored.openai_compatible.custom_headers = migrated_headers

            if needs_save:
                await settings_collection.update_one(
                    {"id": "global_settings"},
                    {"$set": {"ai": stored.model_dump()}}
                )

            if needs_purge:
                await settings_collection.update_one({"id": "global_settings"}, {"$unset": unset_fields})
            return stored
        except Exception:
            pass

    legacy = AppSettings(**doc)
    stored = legacy.to_ai_stored()
    update_doc = {"$set": {"ai": stored.model_dump()}}
    if needs_purge:
        update_doc["$unset"] = unset_fields
    await settings_collection.update_one({"id": "global_settings"}, update_doc, upsert=True)
    return stored

@admin_router.get("/settings/ai", response_model=AISettingsResponse, tags=["Admin - AI"])
async def get_ai_settings_endpoint(auth: dict = Depends(verify_auth)):
    if auth.get("role") != "admin" and not auth.get("ai_enabled", False):
        raise HTTPException(status_code=403, detail="Accesso alle impostazioni IA non autorizzato")
    stored = await get_or_migrate_ai_settings()
    return stored_to_ai_response(stored)

@admin_router.patch("/settings/ai", response_model=AISettingsResponse, tags=["Admin - AI"])
async def patch_ai_settings_endpoint(patch: AISettingsPatch, auth: dict = Depends(verify_auth)):
    if auth.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Solo gli amministratori possono modificare le impostazioni IA")

    stored = await get_or_migrate_ai_settings()

    if patch.active_provider is not None:
        stored.active_provider = patch.active_provider
    if patch.viewer_ai_enabled is not None:
        stored.viewer_ai_enabled = patch.viewer_ai_enabled
    if patch.system_prompt is not None:
        stored.system_prompt = patch.system_prompt
    if patch.generation is not None:
        stored.generation = patch.generation
    if patch.network is not None:
        stored.network = patch.network

    if patch.gemini is not None:
        if patch.gemini.model:
            stored.gemini.model = patch.gemini.model
        if patch.gemini.clear_api_key:
            stored.gemini.api_key_encrypted = None
        elif patch.gemini.api_key and patch.gemini.api_key.strip():
            cur_plain = decrypt_secret(stored.gemini.api_key_encrypted)
            if not is_masked_or_empty(patch.gemini.api_key, cur_plain):
                stored.gemini.api_key_encrypted = encrypt_secret(patch.gemini.api_key)

    if patch.openai is not None:
        if patch.openai.model:
            stored.openai.model = patch.openai.model
        if patch.openai.protocol:
            stored.openai.protocol = patch.openai.protocol
        if patch.openai.clear_api_key:
            stored.openai.api_key_encrypted = None
        elif patch.openai.api_key and patch.openai.api_key.strip():
            cur_plain = decrypt_secret(stored.openai.api_key_encrypted)
            if not is_masked_or_empty(patch.openai.api_key, cur_plain):
                stored.openai.api_key_encrypted = encrypt_secret(patch.openai.api_key)

    if patch.openai_compatible is not None:
        if patch.openai_compatible.base_url:
            validate_base_url(patch.openai_compatible.base_url)
            stored.openai_compatible.base_url = patch.openai_compatible.base_url
        if patch.openai_compatible.model:
            stored.openai_compatible.model = patch.openai_compatible.model
        if patch.openai_compatible.protocol:
            stored.openai_compatible.protocol = patch.openai_compatible.protocol
        if patch.openai_compatible.custom_headers is not None:
            updated_headers = {}
            current_encrypted = stored.openai_compatible.custom_headers or {}
            for k, v in patch.openai_compatible.custom_headers.items():
                if not k or not str(k).strip():
                    continue
                k_clean = str(k).strip()
                v_clean = str(v).strip()
                if k_clean in current_encrypted:
                    cur_plain = decrypt_secret(current_encrypted[k_clean])
                    if is_masked_or_empty(v_clean, cur_plain):
                        updated_headers[k_clean] = current_encrypted[k_clean]
                        continue
                updated_headers[k_clean] = encrypt_secret(v_clean) or ""
            stored.openai_compatible.custom_headers = updated_headers
        if patch.openai_compatible.clear_api_key:
            stored.openai_compatible.api_key_encrypted = None
        elif patch.openai_compatible.api_key and patch.openai_compatible.api_key.strip():
            cur_plain = decrypt_secret(stored.openai_compatible.api_key_encrypted)
            if not is_masked_or_empty(patch.openai_compatible.api_key, cur_plain):
                stored.openai_compatible.api_key_encrypted = encrypt_secret(patch.openai_compatible.api_key)

    existing = await settings_collection.find_one({"id": "global_settings"}) or {"id": "global_settings"}
    existing["ai"] = stored.model_dump()
    existing["ai_provider"] = stored.active_provider
    existing["viewer_ai_enabled"] = stored.viewer_ai_enabled
    existing["gemini_model"] = stored.gemini.model
    existing["gemini_prompt"] = stored.system_prompt
    existing["chatgpt_model"] = stored.openai.model
    existing.pop("gemini_api_key", None)
    existing.pop("chatgpt_api_key", None)

    await settings_collection.replace_one({"id": "global_settings"}, existing, upsert=True)
    await settings_collection.update_one(
        {"id": "global_settings"},
        {"$unset": {"gemini_api_key": "", "chatgpt_api_key": ""}}
    )

    operatore = auth.get("username", "operatore")
    await log_audit(
        "MODIFICA_IMPOSTAZIONI_IA",
        operatore,
        f"Aggiornate impostazioni AI (provider: {stored.active_provider}, viewer: {stored.viewer_ai_enabled})",
        None,
    )

    return stored_to_ai_response(stored)

