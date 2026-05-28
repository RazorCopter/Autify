import os
import bcrypt
import jwt
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException, Request, status
from .database import users_collection

# ── Configurazione JWT ──────────────────────────────────────────────────────

JWT_SECRET = os.getenv("JWT_SECRET_KEY", "").strip() or "change_me_in_production_please"
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = 8


# ── Hashing Password ────────────────────────────────────────────────────────

def hash_password(plain: str) -> str:
    """Genera un hash bcrypt con salt automatico (rounds=12)."""
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(plain.encode("utf-8"), salt)
    return hashed.decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    """
    Confronta una password in chiaro con il suo hash bcrypt.
    Fornisce un fallback sicuro a confronto in chiaro per compatibilità con utenti legacy o non migrati.
    """
    try:
        return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))
    except (ValueError, TypeError):
        # Fallback se la password nel DB è salvata in chiaro (es. admin/admin legacy)
        return plain == hashed


# ── JWT ─────────────────────────────────────────────────────────────────────

def create_access_token(username: str, role: str, ai_enabled: bool) -> str:
    """Genera un JWT firmato con scadenza di JWT_EXPIRY_HOURS ore (epoch integer timestamp)."""
    payload = {
        "sub": username,
        "role": role,
        "ai_enabled": ai_enabled,
        "exp": int((datetime.now(timezone.utc) + timedelta(hours=JWT_EXPIRY_HOURS)).timestamp()),
        "iat": int(datetime.now(timezone.utc).timestamp()),
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)
    if isinstance(token, bytes):
        return token.decode("utf-8")
    return token


def decode_access_token(token: str) -> dict:
    """
    Decodifica e verifica un JWT.
    Lancia HTTPException 401 in caso di token scaduto o firma non valida.
    """
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Sessione scaduta. Effettua di nuovo il login.",
        )
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token di autenticazione non valido.",
        )


# ── Dependency FastAPI ───────────────────────────────────────────────────────

async def verify_auth(request: Request) -> dict:
    """
    Dependency FastAPI: estrae il JWT dall'header Authorization e inietta
    nel contesto {username, role, ai_enabled}.
    Supporta in backward-compat anche il vecchio header X-Admin-Password
    per non rompere il frontend client durante la fase di migrazione.
    """
    # 1. Prova il nuovo Bearer JWT
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[len("Bearer "):]
        payload = decode_access_token(token)
        return {
            "username": payload.get("sub"),
            "role": payload.get("role", "viewer"),
            "ai_enabled": payload.get("ai_enabled", False),
        }

    # 2. Backward-compat: vecchio header X-Admin-Password (solo lettura config)
    legacy_pwd = request.headers.get("X-Admin-Password")
    if legacy_pwd:
        from . import auth_manager  # import locale per backward-compat
        try:
            config = auth_manager.get_auth_config()
            if legacy_pwd == config.get("admin_pwd"):
                return {"username": "admin", "role": "admin", "ai_enabled": True}
            elif legacy_pwd == config.get("viewer_pwd"):
                if config.get("viewer_enabled", True):
                    return {"username": "viewer_legacy", "role": "viewer", "ai_enabled": False}
        except Exception:
            pass

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Autenticazione richiesta. Effettua il login.",
    )


# ── Bootstrap Utente di Default ─────────────────────────────────────────────

async def ensure_default_admin():
    """
    Crea l'utente admin/admin di default SOLO se la collection users è vuota.
    Viene invocato all'avvio dell'applicazione.
    """
    # Crea indice univoco su username
    await users_collection.create_index("username", unique=True)

    count = await users_collection.count_documents({})
    if count == 0:
        now = datetime.now(timezone.utc)
        await users_collection.insert_one({
            "username": "admin",
            "hashed_password": hash_password("admin"),
            "role": "admin",
            "ai_enabled": True,
            "is_default": True,
            "created_at": now,
            "updated_at": now,
        })
        print("[Autify] Bootstrap: utente admin/admin creato (cambia la password al primo accesso).")
    else:
        # Migrazione: assicura che il documento admin abbia is_default=True
        await users_collection.update_one(
            {"username": "admin", "is_default": {"$exists": False}},
            {"$set": {"is_default": True}},
        )
