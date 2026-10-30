import asyncio
import functools
import base64
import hashlib
import json
import os
import secrets
import time
import uuid
import math
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.exceptions import InvalidTag
from fastapi import HTTPException, status

from .database import licenses_collection
from pymongo.errors import DuplicateKeyError

LICENSE_ID = "autify_license"
TRIAL_DAYS = 15
CACHE_HOURS = int(os.getenv("LICENSE_CACHE_HOURS", "24"))
OFFLINE_GRACE_HOURS = int(os.getenv("LICENSE_OFFLINE_GRACE_HOURS", "72"))


_license_lock = asyncio.Lock()
_index_lock = asyncio.Lock()
_index_ready = False


def serialized_license(function):
    @functools.wraps(function)
    async def run(*args, **kwargs):
        async with _license_lock:
            return await function(*args, **kwargs)
    return run


async def _store_license(document, updates):
    # A remote response must not overwrite a newer activation, release or validation.
    selector = {"id": LICENSE_ID, "instance_id": document["instance_id"],
                "license_token": document.get("license_token"), "status": document.get("status"),
                "last_validated_at": document.get("last_validated_at")}
    result = await licenses_collection.update_one(selector, {"$set": updates})
    if result.matched_count != 1:
        raise HTTPException(409, "Stato licenza cambiato durante la richiesta: rileggere. Un'operazione remota potrebbe essere gia avvenuta; non ripeterla automaticamente.")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _key() -> bytes:
    secret = os.getenv("LICENSE_SHARED_SECRET", "")
    if len(secret) < 32:
        raise RuntimeError("LICENSE_SHARED_SECRET deve contenere almeno 32 caratteri")
    return hashlib.sha256(secret.encode("utf-8")).digest()


def _encrypt(payload: dict[str, Any]) -> dict[str, str]:
    nonce = os.urandom(12)
    ciphertext = AESGCM(_key()).encrypt(
        nonce, json.dumps(payload, separators=(",", ":"), default=str).encode("utf-8"), None
    )
    return {
        "nonce": base64.urlsafe_b64encode(nonce).decode("ascii"),
        "ciphertext": base64.urlsafe_b64encode(ciphertext).decode("ascii"),
    }


def _decrypt(envelope: dict[str, str]) -> dict[str, Any]:
    nonce = base64.urlsafe_b64decode(envelope["nonce"])
    ciphertext = base64.urlsafe_b64decode(envelope["ciphertext"])
    plaintext = AESGCM(_key()).decrypt(nonce, ciphertext, None)
    return json.loads(plaintext.decode("utf-8"))


def _parse_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str) and value:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    return None


def _serialize(document: dict, *, message: str | None = None) -> dict:
    now = utcnow()
    expires_at = _parse_datetime(document.get("expires_at"))
    stored_status = document.get("status", "invalid")
    expired = expires_at is not None and expires_at <= now
    status = "expired" if expired and stored_status in ("trial", "active") else stored_status
    valid = status in ("trial", "active")
    days_remaining = (
        None
        if expires_at is None
        else max(0, math.ceil((expires_at - now).total_seconds() / 86400))
    )
    return {
        "status": status,
        "valid": valid,
        "plan": document.get("plan", "trial"),
        "trial": document.get("plan") == "trial",
        "instance_id": document.get("instance_id"),
        "activated_at": document.get("activated_at"),
        "expires_at": document.get("expires_at"),
        "last_validated_at": document.get("last_validated_at"),
        "days_remaining": days_remaining,
        "offline": bool(document.get("offline", False)),
        "permanently_activated": bool(document.get("permanently_activated", False)),
        "message": message,
    }


async def ensure_trial_license() -> dict:
    global _index_ready
    async with _index_lock:
        if not _index_ready:
            await licenses_collection.create_index("id", unique=True, partialFilterExpression={"id": {"$type": "string"}}, name="license_id_unique")
            _index_ready = True
    existing = await licenses_collection.find_one({"id": LICENSE_ID})
    if existing:
        return existing
    now = utcnow()
    document = {
        "id": LICENSE_ID,
        "instance_id": str(uuid.uuid4()),
        "status": "trial",
        "plan": "trial",
        "activated_at": now,
        "expires_at": now + timedelta(days=TRIAL_DAYS),
        "license_token": None,
        "code_suffix": None,
        "last_validated_at": None,
        "offline": False,
        "created_at": now,
    }
    try:
        await licenses_collection.insert_one(document)
    except DuplicateKeyError:
        # Gestisce in modo idempotente avvii concorrenti di più worker.
        existing = await licenses_collection.find_one({"id": LICENSE_ID})
        if existing:
            return existing
        raise
    return document


async def _license_server_call(path: str, payload: dict[str, Any]) -> dict[str, Any]:
    url = os.getenv("LICENSE_SERVER_URL", "").rstrip("/")
    if not url:
        raise RuntimeError("LICENSE_SERVER_URL non configurato")
    body = {
        **payload,
        "timestamp": int(time.time()),
        "request_nonce": secrets.token_urlsafe(24),
    }
    timeout = float(os.getenv("LICENSE_SERVER_TIMEOUT_SECONDS", "8"))
    async with httpx.AsyncClient(timeout=timeout, follow_redirects=False, trust_env=False) as client:
        response = await client.post(f"{url}{path}", json=_encrypt(body))
        response.raise_for_status()
        return _decrypt(response.json())


async def get_license_server_info() -> dict[str, Any]:
    """Restituisce la configurazione pubblica e verifica la raggiungibilità del server."""
    url = os.getenv("LICENSE_SERVER_URL", "").rstrip("/")
    if not url:
        return {
            "license_server_url": "",
            "configured": False,
            "reachable": False,
        }

    timeout = float(os.getenv("LICENSE_SERVER_TIMEOUT_SECONDS", "8"))
    try:
        async with httpx.AsyncClient(timeout=timeout, follow_redirects=False, trust_env=False) as client:
            response = await client.get(f"{url}/health")
            reachable = response.status_code == status.HTTP_200_OK
    except httpx.HTTPError:
        reachable = False

    return {
        "license_server_url": url,
        "configured": True,
        "reachable": reachable,
    }


@serialized_license
async def activate_license(code: str) -> dict:
    document = await ensure_trial_license()
    result = await _license_server_call(
        "/v1/activate", {"code": code.strip().upper(), "instance_id": document["instance_id"]}
    )
    if not result.get("valid"):
        raise ValueError(result.get("reason", "Licenza non valida"))
    now = utcnow()
    is_lifetime = result.get("plan") == "lifetime"
    updates = {
        "status": "active",
        "plan": result.get("plan"),
        "activated_at": _parse_datetime(result.get("activated_at")),
        "expires_at": _parse_datetime(result.get("expires_at")),
        "license_token": result.get("license_token"),
        "code_suffix": code.strip().upper()[-6:],
        "last_validated_at": now,
        "offline": False,
        "permanently_activated": is_lifetime,
        "updated_at": now,
    }
    await _store_license(document, updates)
    return _serialize({**document, **updates})


async def get_license_status(force_remote: bool = False) -> dict:
    requested_at = utcnow()
    async with _license_lock:
        return await _get_license_status(force_remote, requested_at)


async def _get_license_status(force_remote=False, requested_at=None) -> dict:
    document = await ensure_trial_license()
    if document.get("plan") == "trial" or not document.get("license_token"):
        return _serialize(document)

    last_check = _parse_datetime(document.get("last_validated_at"))
    if force_remote and requested_at and last_check and last_check >= requested_at:
        return _serialize(document)

    # Licenze lifetime già attivate: non ricontattare MAI il server
    # (salvo force_remote esplicito dall'admin)
    if not force_remote and document.get("plan") == "lifetime" \
            and document.get("status") == "active" \
            and document.get("permanently_activated"):
        return _serialize(document)

    now = utcnow()
    last_validated = _parse_datetime(document.get("last_validated_at"))
    if not force_remote and last_validated and timedelta(0) <= now - last_validated < timedelta(hours=CACHE_HOURS):
        return _serialize(document)
    try:
        result = await _license_server_call(
            "/v1/validate",
            {"license_token": document["license_token"], "instance_id": document["instance_id"]},
        )
        remote_status = str(result.get("status") or result.get("reason") or "invalid").lower()
        status_value = "active" if result.get("valid") else remote_status
        if status_value not in {"active", "expired", "revoked", "invalid"}:
            status_value = "invalid"
        updates = {
            "status": status_value,
            "plan": result.get("plan", document.get("plan")),
            "expires_at": _parse_datetime(result.get("expires_at")),
            "last_validated_at": now,
            "offline": False,
            "updated_at": now,
        }
        await _store_license(document, updates)
        return _serialize({**document, **updates})
    except (httpx.HTTPError, RuntimeError, ValueError, KeyError, json.JSONDecodeError, InvalidTag):
        within_grace = last_validated is not None and timedelta(0) <= now - last_validated <= timedelta(hours=OFFLINE_GRACE_HOURS)
        if within_grace:
            updates = {"offline": True, "updated_at": now}
            await _store_license(document, updates)
            return _serialize({**document, **updates}, message="Server licenze non raggiungibile: cache offline attiva")
        updates = {"status": "validation_required", "offline": True, "updated_at": now}
        await _store_license(document, updates)
        return _serialize({**document, **updates}, message="Impossibile validare la licenza: periodo offline scaduto")


@serialized_license
async def deactivate_license() -> dict:
    """Rilascia la licenza corrente, liberando il codice per un'altra installazione."""
    document = await licenses_collection.find_one({"id": LICENSE_ID})
    if not document or document.get("plan") == "trial":
        raise ValueError("Nessuna licenza commerciale attiva da disattivare")
    if document.get("status") != "active":
        raise ValueError("La licenza non è attiva e non può essere disattivata")

    # Comunica al server licenze che questa istanza rilascia il codice
    await _license_server_call(
        "/v1/deactivate",
        {"license_token": document["license_token"], "instance_id": document["instance_id"]},
    )

    # Reset locale: torna allo stato trial
    now = utcnow()
    created_at = _parse_datetime(document.get("created_at"))
    trial_end = created_at + timedelta(days=TRIAL_DAYS) if created_at else now
    reset = {
        "status": "trial",
        "plan": "trial",
        "license_token": None,
        "code_suffix": None,
        "permanently_activated": False,
        "expires_at": trial_end,
        "last_validated_at": None,
        "offline": False,
        "updated_at": now,
    }
    await _store_license(document, reset)
    return _serialize({**document, **reset}, message="Licenza disattivata con successo. Il codice è ora riutilizzabile su un'altra installazione.")


async def require_valid_license() -> dict:
    license_status = await get_license_status()
    if not license_status["valid"]:
        raise HTTPException(
            status_code=status.HTTP_402_PAYMENT_REQUIRED,
            detail="Licenza Autify non valida o scaduta",
        )
    return license_status