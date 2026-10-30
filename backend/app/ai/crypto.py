"""Versioned AI credentials: dedicated active key, explicit read keyring, no write fallback."""
import base64
import hashlib
import json
import os
from typing import Optional
from cryptography.fernet import Fernet, InvalidToken

_CIPHER_PREFIX = "enc:v2:"

class SecretConfigurationError(RuntimeError):
    pass

class SecretDecryptionError(ValueError):
    pass


def _derive(raw):
    try:
        if len(base64.urlsafe_b64decode(raw)) == 32:
            return raw.encode()
    except Exception:
        pass
    return base64.urlsafe_b64encode(hashlib.sha256(raw.encode()).digest())


def _active():
    raw = os.getenv("AI_SETTINGS_ENCRYPTION_KEY", "").strip()
    if len(raw) < 32:
        raise SecretConfigurationError("Configurare AI_SETTINGS_ENCRYPTION_KEY dedicata di almeno 32 caratteri")
    key = _derive(raw)
    return hashlib.sha256(key).hexdigest()[:16], Fernet(key)


def _previous(name):
    try:
        values = json.loads(os.getenv(name, "[]"))
        if not isinstance(values, list) or any(not isinstance(v, str) or not v.strip() for v in values):
            raise ValueError()
        return values
    except (ValueError, TypeError) as exc:
        raise SecretConfigurationError(f"{name} deve essere un array JSON di chiavi") from exc


def get_fernet():
    return _active()[1]


def encrypt_secret(secret: Optional[str]) -> Optional[str]:
    if not secret or not secret.strip():
        return None
    raw = secret.strip()
    if raw.startswith("enc:"):
        decrypt_secret(raw)  # Never accept unreadable opaque ciphertext supplied by a client.
        return raw
    ident, cipher = _active()
    return f"enc:v2:{ident}:{cipher.encrypt(raw.encode()).decode()}"


def decrypt_secret(encrypted_text: Optional[str]) -> Optional[str]:
    if not encrypted_text or not encrypted_text.strip():
        return None
    raw = encrypted_text.strip()
    if not raw.startswith("enc:"):
        return raw  # Read legacy plaintext only; callers migrate to the dedicated key.
    active_raw = os.getenv("AI_SETTINGS_ENCRYPTION_KEY", "").strip()
    keys = ([active_raw] if active_raw else []) + _previous("AI_SETTINGS_PREVIOUS_KEYS")
    if raw.startswith("enc:v2:"):
        parts = raw.split(":", 3)
        if len(parts) != 4:
            raise SecretDecryptionError("Credenziale IA cifrata non valida")
        ident, token = parts[2:]
        candidates = [Fernet(_derive(key)) for key in keys if hashlib.sha256(_derive(key)).hexdigest()[:16] == ident]
    elif raw.startswith("enc:v1:"):
        token = raw[7:]
        candidates = [Fernet(_derive(key)) for key in keys]
        jwt_keys = ([os.getenv("JWT_SECRET_KEY")] if os.getenv("JWT_SECRET_KEY") else []) + _previous("AI_SETTINGS_LEGACY_JWT_KEYS")
        candidates += [Fernet(base64.urlsafe_b64encode(hashlib.sha256(f"autify-ai-salt:{key}".encode()).digest())) for key in jwt_keys]
    else:
        raise SecretDecryptionError("Versione credenziale IA non supportata")
    for cipher in candidates:
        try:
            return cipher.decrypt(token.encode()).decode()
        except (InvalidToken, UnicodeError):
            continue
    raise SecretDecryptionError("Credenziale IA non leggibile: recuperare la chiave originale, senza sovrascrivere le impostazioni")

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
    if v.startswith("enc:") or v in ("***", "***-HIDDEN"):
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
