import ipaddress
import os
import socket
from urllib.parse import urlparse
from fastapi import HTTPException

def is_private_ip(ip_str: str) -> bool:
    """Verifica se l'indirizzo IP appartiene a loopback, link-local o intervalli privati."""
    try:
        ip = ipaddress.ip_address(ip_str)
        return ip.is_loopback or ip.is_private or ip.is_link_local or ip.is_reserved
    except ValueError:
        return False

def normalize_base_url(url: str) -> str:
    """
    Pulisce e normalizza la base URL di un provider OpenAI-compatible.
    Rimuove slash finali e suffissi erroneamente inclusi come /chat/completions, /responses o /models.
    """
    clean = url.strip().rstrip("/")
    if clean.endswith("/chat/completions"):
        clean = clean[:-len("/chat/completions")].rstrip("/")
    elif clean.endswith("/responses"):
        clean = clean[:-len("/responses")].rstrip("/")
    elif clean.endswith("/models"):
        clean = clean[:-len("/models")].rstrip("/")
    return clean

def validate_base_url(url: str) -> str:
    """
    Valida la Base URL per prevenire vulnerabilità SSRF.
    Consente reti private solo se ALLOW_PRIVATE_AI_ENDPOINTS=true.
    """
    if not url or not url.strip():
        raise HTTPException(status_code=400, detail="La Base URL del provider non può essere vuota.")

    normalized = normalize_base_url(url)
    parsed = urlparse(normalized)

    if parsed.scheme not in ("http", "https"):
        raise HTTPException(
            status_code=400,
            detail=f"Schema URL non valido '{parsed.scheme}'. Utilizzare solo http o https."
        )

    if not parsed.hostname:
        raise HTTPException(status_code=400, detail="L'URL inserito non contiene un hostname valido.")

    # Rifiuta credenziali incluse nell'URL (user:pass@...)
    if parsed.username or parsed.password:
        raise HTTPException(
            status_code=400,
            detail="Non è consentito inserire credenziali o password direttamente nella Base URL."
        )

    hostname = parsed.hostname.lower()

    # Verifica contro allowlist esplicita se definita
    allowed_hosts_env = os.environ.get("ALLOWED_AI_HOSTS", "").strip()
    if allowed_hosts_env:
        allowed_list = [h.strip().lower() for h in allowed_hosts_env.split(",") if h.strip()]
        is_allowed = any(
            hostname == allowed or hostname.endswith(f".{allowed}")
            for allowed in allowed_list
        )
        if not is_allowed:
            raise HTTPException(
                status_code=400,
                detail=f"L'host '{hostname}' non è autorizzato nella whitelist di sistema (ALLOWED_AI_HOSTS)."
            )

    allow_private = os.environ.get("ALLOW_PRIVATE_AI_ENDPOINTS", "").lower() in ("true", "1", "yes")

    # Se l'hostname è già un IP letterale
    if is_private_ip(hostname):
        if not allow_private:
            raise HTTPException(
                status_code=400,
                detail=f"Accesso all'indirizzo IP privato/locale '{hostname}' non consentito. "
                       f"Abilitare ALLOW_PRIVATE_AI_ENDPOINTS per endpoint locali."
            )
        return normalized

    # Risoluzione DNS preventiva per hostnames (es. localhost, vllm.internal, ecc.)
    try:
        addr_info = socket.getaddrinfo(hostname, None)
        for entry in addr_info:
            ip_str = entry[4][0]
            if is_private_ip(ip_str) and not allow_private:
                raise HTTPException(
                    status_code=400,
                    detail=f"L'host '{hostname}' risolve all'indirizzo privato '{ip_str}'. "
                           f"Accesso non consentito per motivi di sicurezza."
                )
    except socket.gaierror:
        # Se non risolve al momento del salvataggio (es. host offline o inesistente)
        # permettiamo il salvataggio se formato valido, ma solleviamo errore in fase di test
        pass

    return normalized
