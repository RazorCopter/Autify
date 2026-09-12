import os
import bcrypt
import jwt
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException, Request, status
from .database import users_collection, evaluations_collection, patients_collection, ai_analyses_collection, audit_logs_collection

# ── Configurazione JWT ──────────────────────────────────────────────────────

JWT_SECRET = os.getenv("JWT_SECRET_KEY", "").strip()
if not JWT_SECRET:
    raise RuntimeError(
        "JWT_SECRET_KEY environment variable is not set. "
        "Set a strong random secret before starting the server."
    )
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_HOURS = 8


# ── Hashing Password ────────────────────────────────────────────────────────

def hash_password(plain: str) -> str:
    """Genera un hash bcrypt con salt automatico (rounds=12)."""
    encoded = plain.encode("utf-8")
    if len(encoded) > 72:
        raise ValueError("La password non può superare 72 byte (limite bcrypt)")
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(encoded, salt)
    return hashed.decode("utf-8")


def verify_password(plain: str, hashed: str) -> bool:
    """Confronta una password in chiaro con il suo hash bcrypt."""
    try:
        return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))
    except (ValueError, TypeError) as e:
        # Hash malformato nel DB: nega l'accesso e logga per indagine
        import logging
        logging.getLogger("autify").warning(
            f"verify_password: hash malformato per un utente ({type(e).__name__}: {e}). Accesso negato."
        )
        return False


# ── JWT ─────────────────────────────────────────────────────────────────────

def create_access_token(username: str, role: str, ai_enabled: bool, token_version: int = 1) -> str:
    """Genera un JWT firmato con scadenza di JWT_EXPIRY_HOURS ore (epoch integer timestamp)."""
    payload = {
        "sub": username,
        "role": role,
        "ai_enabled": ai_enabled,
        "token_version": token_version,
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
    Dependency FastAPI: estrae il JWT dall'header Authorization, inietta
    nel contesto {username, role, ai_enabled} e verifica che la versione del token
    corrisponda a quella corrente a database per revocare sessioni invalidate.
    """
    auth_header = request.headers.get("Authorization", "")
    if auth_header.startswith("Bearer "):
        token = auth_header[len("Bearer "):]
        payload = decode_access_token(token)
        username = payload.get("sub")
        if not username:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token privo di identità utente.",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # Verifica revoca sessione confrontando token_version con il DB
        user = await users_collection.find_one({"username": username})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Utente non trovato o disattivato.",
                headers={"WWW-Authenticate": "Bearer"},
            )

        db_token_version = user.get("token_version", 1)
        token_version = payload.get("token_version")
        if token_version is not None and token_version != db_token_version:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Sessione revocata o non valida. Effettua nuovamente l'accesso.",
                headers={"WWW-Authenticate": "Bearer"},
            )
        elif token_version is None and db_token_version != 1:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Sessione revocata o non valida. Effettua nuovamente l'accesso.",
                headers={"WWW-Authenticate": "Bearer"},
            )

        return {
            "username": username,
            "role": payload.get("role", "viewer"),
            "ai_enabled": payload.get("ai_enabled", False),
        }

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Autenticazione richiesta. Effettua il login.",
        headers={"WWW-Authenticate": "Bearer"},
    )


# ── Bootstrap Utente di Default ─────────────────────────────────────────────

async def ensure_default_admin():
    """
    Crea l'utente admin/admin di default SOLO se la collection users è vuota.
    Viene invocato all'avvio dell'applicazione.
    """
    # Crea indice univoco su username
    await users_collection.create_index("username", unique=True)

    # Indici per velocizzare le query più frequenti
    await evaluations_collection.create_index("id_paziente")
    await evaluations_collection.create_index("id_valutazione")
    await patients_collection.create_index("id", unique=True)
    await ai_analyses_collection.create_index("id_paziente")
    await ai_analyses_collection.create_index([("timestamp", -1)])
    await audit_logs_collection.create_index([("timestamp", -1)])

    # Migrazione one-shot: i pazienti creati prima del campo 'attivo' vengono
    # considerati attivi per default. Idempotente: non impatta documenti già migrati.
    await patients_collection.update_many(
        {"attivo": {"$exists": False}},
        {"$set": {"attivo": True}},
    )

    # Migrazione one-shot: assegna token_version=1 a utenti pre-esistenti
    await users_collection.update_many(
        {"token_version": {"$exists": False}},
        {"$set": {"token_version": 1}},
    )

    count = await users_collection.count_documents({})
    if count == 0:
        bootstrap_pwd = os.getenv("INITIAL_ADMIN_PASSWORD", "admin")
        now = datetime.now(timezone.utc)
        await users_collection.insert_one({
            "username": "admin",
            "hashed_password": hash_password(bootstrap_pwd),
            "role": "admin",
            "ai_enabled": True,
            "is_default": True,
            "must_change_password": True,
            "token_version": 1,
            "created_at": now,
            "updated_at": now,
        })
        print("[Autify] Bootstrap: utente admin creato con successo.")
    else:
        # Migrazione: assicura che il documento admin abbia is_default=True
        await users_collection.update_one(
            {"username": "admin", "is_default": {"$exists": False}},
            {"$set": {"is_default": True}},
        )
