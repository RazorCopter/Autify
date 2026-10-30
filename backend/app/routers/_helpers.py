import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from bson import ObjectId
from fastapi import HTTPException, Request, status

from .. import auth as auth_module
from ..database import (
    ai_analyses_collection,
    audit_logs_collection,
    evaluations_collection,
    patients_collection,
    scales_collection,
    settings_collection,
    users_collection,
)
from ..models import AuditLogCreate

_logger = logging.getLogger("autify")


async def verify_auth(request: Request) -> dict:
    """Dependency: verifica JWT o header legacy e restituisce {username, role, ai_enabled}."""
    auth_context = await auth_module.verify_auth(request)

    # These handlers always restrict updates to the authenticated owner.
    own_notification_read = request.method == "POST" and (
        request.url.path == "/api/admin/notifications/read-all"
        or (request.url.path.startswith("/api/admin/notifications/")
            and request.url.path.endswith("/read")
            and len(request.url.path.split("/")) == 6)
    )

    # Blocca le modifiche di stato per il ruolo Viewer
    if (
        auth_context["role"] == "viewer"
        and request.method not in ("GET", "HEAD")
        and not own_notification_read
        and request.url.path
        not in (
            "/api/admin/evaluations/ai-analysis-pdf",
            "/api/admin/ai/analyze",
            "/api/admin/auth/login",
            "/api/admin/auth/change-password",
        )
    ):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Azione non consentita per il profilo Viewer (sola lettura)",
        )

    return auth_context


async def log_audit(
    azione: str, operatore: str, dettagli: str, target_id: Optional[str] = None
):
    from ..audit import post_commit
    return await post_commit(azione, operatore, dettagli, target_id)


def _classify_scale(scale_name: str, scale_id: str) -> str:
    """Classifica una scala in base a nome e id (entrambi già lowercase)."""
    n = scale_name.replace("í", "i").replace("ì", "i")
    i = scale_id.lower()
    if "pos" in n or "pos" in i:
        return "pos"
    if "martin" in n or "martin" in i:
        return "san_martin"
    if "sis" in n or "sis" in i:
        return "sis"
    if (
        "ogva" in n
        or "griglia_autonomia" in n
        or "autonomi" in n
        or "ogva" in i
        or "griglia_autonomia" in i
    ):
        return "ogva"
    if "sabs" in n or "sabs" in i:
        return "sabs"
    if (
        "oso" in n
        or "scheda osservativa" in n
        or "scheda_osservativa" in n
        or "oso" in i
        or "scheda_osservativa" in i
    ):
        return "oso"
    return "altro"


async def _update_patient_scale_dates(patient_id: str):
    from ..expiry import project, KINDS
    patient = await patients_collection.find_one({"id": patient_id})
    if not patient:
        return
    await project([patient])
    # Compatibility cache only: filters/KPI always recompute from source evaluations.
    dates = {f"ultimo_{kind}_compilato": patient[f"ultimo_{kind}_compilato"] for kind in KINDS}
    await patients_collection.update_one({"_id": patient["_id"]}, {"$set": dates})


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
        eval_doc = await evaluations_collection.find_one(
            {"_id": ObjectId(evaluation_id)}
        )
        if eval_doc:
            return eval_doc

    # Nessun documento trovato con i campi indicizzati: log warning e restituisce None.
    _logger.warning(
        "[_find_evaluation_document] id='%s' non trovato con nessun campo indicizzato."
        " Il documento potrebbe avere uno schema non standard: verificare e migrare.",
        evaluation_id,
    )
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
    for a, b in [
        ("á", "a"),
        ("à", "a"),
        ("é", "e"),
        ("è", "e"),
        ("í", "i"),
        ("ì", "i"),
        ("ó", "o"),
        ("ò", "o"),
        ("ú", "u"),
        ("ù", "u"),
    ]:
        val = val.replace(a, b)
    return val


def _load_builtin_san_martin_scale() -> Optional[dict]:
    """Carica il protocollo San Martin bundled per reidratare metadati mancanti."""
    app_dir = Path(__file__).resolve().parent.parent
    candidate_files = [
        app_dir / "ScalaSanMartin.json",
        app_dir / "Scala San Martin.json",
        app_dir / "routers" / "ScalaSanMartin.json",
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
    app_dir = Path(__file__).resolve().parent.parent
    candidate_files = [
        app_dir / "ScalaSIS.json",
        app_dir / "routers" / "ScalaSIS.json",
    ]
    for candidate in candidate_files:
        if not candidate.exists():
            continue
        try:
            data = json.loads(candidate.read_text(encoding="utf-8-sig"))
            return data.get("scala")
        except (OSError, json.JSONDecodeError):
            continue
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
    is_san_martin = (
        "sanmartin" in normalized_id or "sanmartin" in normalized_name
    )

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
