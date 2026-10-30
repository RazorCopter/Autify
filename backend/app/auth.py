import os
import bcrypt
import jwt
from pymongo.errors import DuplicateKeyError
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException, Request, status
from .database import users_collection, evaluations_collection, patients_collection, ai_analyses_collection, audit_logs_collection

# ── Configurazione JWT ──────────────────────────────────────────────────────

JWT_SECRET = os.getenv("JWT_SECRET_KEY", "").strip()
if len(JWT_SECRET) < 32 or JWT_SECRET.startswith("CAMBIA_"):
    raise RuntimeError(
        "JWT_SECRET_KEY mancante, troppo corta o uguale al placeholder. "
        "Configurare un segreto casuale di almeno 32 caratteri prima di avviare il server."
    )
JWT_ALGORITHM = "HS256"
JWT_EXPIRY_MINUTES = int(os.getenv("JWT_EXPIRY_MINUTES", "60"))
if not 15 <= JWT_EXPIRY_MINUTES <= 480:
    raise RuntimeError("JWT_EXPIRY_MINUTES deve essere tra 15 e 480")


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
    except (ValueError, TypeError, AttributeError) as e:
        # Hash malformato nel DB: nega l'accesso e logga per indagine
        import logging
        logging.getLogger("autify").warning(
            f"verify_password: hash malformato per un utente ({type(e).__name__}: {e}). Accesso negato."
        )
        return False


# ── JWT ─────────────────────────────────────────────────────────────────────

def create_access_token(username: str, role: str, ai_enabled: bool, token_version: int = 1) -> str:
    """Genera un JWT firmato con scadenza di JWT_EXPIRY_MINUTES minuti (epoch integer timestamp)."""
    payload = {
        "sub": username,
        "role": role,
        "ai_enabled": ai_enabled,
        "token_version": token_version,
        "exp": int((datetime.now(timezone.utc) + timedelta(minutes=JWT_EXPIRY_MINUTES)).timestamp()),
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
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM],
                             options={"require": ["sub", "exp", "iat", "token_version"]})
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
        if not isinstance(username, str) or not username:
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
        if (not isinstance(token_version, int) or isinstance(token_version, bool)
                or not isinstance(db_token_version, int) or isinstance(db_token_version, bool)
                or not 1 <= token_version < 2**63 or token_version != db_token_version):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Sessione revocata o non valida. Effettua nuovamente l'accesso.",
                headers={"WWW-Authenticate": "Bearer"},
            )
        if user.get("must_change_password", False) and (
            request.method, request.url.path
        ) != ("POST", "/api/admin/auth/change-password"):
            raise HTTPException(403, detail={
                "code": "password_change_required",
                "message": "Cambia la password prima di accedere alle altre funzioni.",
            })
        if user.get("role") not in ("admin", "viewer"):
            raise HTTPException(401, "Profilo operatore non valido.")

        return {
            "username": username,
            "role": user["role"],
            "ai_enabled": user.get("ai_enabled") is True,
            "token_version": db_token_version,
        }

    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Autenticazione richiesta. Effettua il login.",
        headers={"WWW-Authenticate": "Bearer"},
    )


# ── Bootstrap Utente di Default ─────────────────────────────────────────────

async def ensure_default_admin():
    """
    Crea admin con password iniziale esplicita SOLO se users è vuota.
    Viene invocato all'avvio dell'applicazione.
    """
    # Crea indice univoco su username
    await users_collection.create_index("username", unique=True)

    # Indici per velocizzare le query più frequenti
    await evaluations_collection.create_index("id_paziente")
    await evaluations_collection.create_index("id_valutazione", unique=True, name="evaluation_id_unique",
                                               partialFilterExpression={"id_valutazione": {"$type": "string"}})
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
        bootstrap_pwd = os.getenv("INITIAL_ADMIN_PASSWORD", "")
        if (len(bootstrap_pwd) < 12 or len(bootstrap_pwd.encode("utf-8")) > 72
                or not bootstrap_pwd.strip()):
            raise RuntimeError("Configurare INITIAL_ADMIN_PASSWORD casuale (almeno 12 caratteri, massimo 72 byte) per il primo avvio.")
        now = datetime.now(timezone.utc)
        bootstrap_user = {
            "username": "admin",
            "hashed_password": hash_password(bootstrap_pwd),
            "role": "admin",
            "ai_enabled": True,
            "is_default": True,
            "must_change_password": True,
            "token_version": 1,
            "created_at": now,
            "updated_at": now,
        }
        try:
            await users_collection.insert_one(bootstrap_user)
        except DuplicateKeyError:
            # Another process bootstrapped first; never replace its credentials.
            pass
        print("[Autify] Bootstrap: account amministrativo disponibile.")
    else:
        legacy_admin = await users_collection.find_one({"username": "admin"})
        if legacy_admin and verify_password("admin", legacy_admin.get("hashed_password", "")):
            await users_collection.update_one(
                {"username": "admin", "hashed_password": legacy_admin["hashed_password"]},
                {"$set": {"must_change_password": True}},
            )
        # Migrazione: assicura che il documento admin abbia is_default=True
        await users_collection.update_one(
            {"username": "admin", "is_default": {"$exists": False}},
            {"$set": {"is_default": True}},
        )
