import base64
import hashlib
import os
from typing import Optional
from cryptography.fernet import Fernet, InvalidToken

_CIPHER_PREFIX = "enc:v1:"

def _get_fernet_key() -> bytes:
    """
    Recupera o deriva una chiave a 32 byte urlsafe base64 per Fernet.
    Utilizza prima AI_SETTINGS_ENCRYPTION_KEY; in alternativa deriva stabilmente
    una chiave a 32 byte a partire da JWT_SECRET_KEY.
    """
    raw_env_key = os.environ.get("AI_SETTINGS_ENCRYPTION_KEY")
    if raw_env_key:
        try:
            # Verifica se è già un urlsafe base64 valido a 32 byte
            decoded = base64.urlsafe_b64decode(raw_env_key)
            if len(decoded) == 32:
                return raw_env_key.encode("utf-8")
        except Exception:
            pass
        # Se presente come stringa arbitraria, deriviamo SHA-256
        derived = hashlib.sha256(raw_env_key.encode("utf-8")).digest()
        return base64.urlsafe_b64encode(derived)

    # Fallback con JWT_SECRET_KEY o seed deterministico
    jwt_secret = os.environ.get("JWT_SECRET_KEY", "autify-default-secret-seed-ai-crypto-key")
    derived = hashlib.sha256(f"autify-ai-salt:{jwt_secret}".encode("utf-8")).digest()
    return base64.urlsafe_b64encode(derived)

def get_fernet() -> Fernet:
    return Fernet(_get_fernet_key())

def encrypt_secret(secret: Optional[str]) -> Optional[str]:
    """Cifra un segreto (API key o header) restituendo una stringa con prefisso enc:v1:."""
    if not secret or not secret.strip():
        return None
    secret_str = secret.strip()
    # Se è già cifrato con il nostro prefisso, non cifriamo due volte
    if secret_str.startswith(_CIPHER_PREFIX):
        return secret_str
    fernet = get_fernet()
    encrypted_bytes = fernet.encrypt(secret_str.encode("utf-8"))
    return f"{_CIPHER_PREFIX}{encrypted_bytes.decode('utf-8')}"

def decrypt_secret(encrypted_text: Optional[str]) -> Optional[str]:
    """Decifra un segreto. Se non è cifrato (legacy o plain in dev), lo restituisce tal quale."""
    if not encrypted_text or not encrypted_text.strip():
        return None
    raw = encrypted_text.strip()
    if not raw.startswith(_CIPHER_PREFIX):
        # Valore legacy in chiaro
        return raw
    token = raw[len(_CIPHER_PREFIX):]
    fernet = get_fernet()
    try:
        decrypted_bytes = fernet.decrypt(token.encode("utf-8"))
        return decrypted_bytes.decode("utf-8")
    except (InvalidToken, Exception):
        # In caso di chiave cambiata o token non valido
        return None

def mask_secret(secret: Optional[str]) -> Optional[str]:
    """
    Restituisce un hint mascherato sicuro per il frontend (es. sk-1234...abcd).
    Non restituisce mai il valore completo.
    """
    if not secret:
        return None
    s = secret.strip()
    if len(s) <= 8:
        return "***"
    if s.startswith("sk-") and len(s) > 12:
        return f"{s[:7]}...{s[-4:]}"
    return f"{s[:4]}...{s[-4:]}"
