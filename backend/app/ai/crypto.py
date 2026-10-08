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

def is_masked_or_empty(val: Optional[str], stored_decrypted: Optional[str] = None) -> bool:
    """
    Verifica se un valore di credenziale fornito dal client è una maschera,
    un placeholder, un token di cifratura o vuoto.
    """
    if not val or not str(val).strip():
        return True
    v = str(val).strip()
    if v in ("***", "enc:v1:", "***-HIDDEN"):
        return True
    if "..." in v:
        return True
    if stored_decrypted and (v == mask_secret(stored_decrypted) or v == f"Bearer {mask_secret(stored_decrypted)}"):
        return True
    return False

def resolve_secret(
    override_val: Optional[str],
    stored_encrypted: Optional[str],
) -> Optional[str]:
    """
    Risolve un segreto (API key o header sensibile):
    Se l'override è fornito e non è mascherato/vuoto, usa l'override in chiaro.
    Se l'override è mascherato, vuoto o None, recupera e decifra il segreto memorizzato.
    """
    stored_plain = decrypt_secret(stored_encrypted) if stored_encrypted else None
    if is_masked_or_empty(override_val, stored_plain):
        return stored_plain
    return str(override_val).strip() if override_val else stored_plain

def resolve_custom_headers(
    headers_override: Optional[dict],
    stored_headers_encrypted: Optional[dict],
) -> dict:
    """
    Risolve i custom header decifrando quelli memorizzati e consentendo
    override puntuali solo se non contengono valori mascherati.
    """
    stored_enc = stored_headers_encrypted or {}
    if headers_override is None:
        return {k: decrypt_secret(v) or "" for k, v in stored_enc.items()}

    resolved = {}
    for k, v in headers_override.items():
        if not k or not str(k).strip():
            continue
        k_clean = str(k).strip()
        v_clean = str(v).strip() if v is not None else ""
        stored_cipher = stored_enc.get(k_clean)
        res_val = resolve_secret(v_clean, stored_cipher)
        if res_val is not None:
            resolved[k_clean] = res_val
    return resolved
