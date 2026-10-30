"""Fail-closed endpoint policy plus a transport pinned to a validated DNS address."""
import asyncio
import ipaddress
import os
import socket
from urllib.parse import urlsplit
import httpx
from fastapi import HTTPException


def normalize_base_url(url):
    clean = url.strip().rstrip("/")
    for suffix in ("/chat/completions", "/responses", "/models"):
        if clean.endswith(suffix):
            return clean[:-len(suffix)].rstrip("/")
    return clean


def _enabled(name):
    return os.getenv(name, "false").lower() in ("true", "1", "yes")


def _ip(value):
    parsed = ipaddress.ip_address(value)
    return parsed.ipv4_mapped if isinstance(parsed, ipaddress.IPv6Address) and parsed.ipv4_mapped else parsed


def is_private_ip(value):
    try:
        return not _ip(value).is_global
    except ValueError:
        return False


def _parse(url):
    try:
        if not isinstance(url, str) or any(ord(c) < 33 for c in url) or "\\" in url:
            raise ValueError()
        normalized = normalize_base_url(url)
        parsed = urlsplit(normalized)
        if (parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username is not None
                or parsed.password is not None or parsed.query or parsed.fragment or "%" in parsed.netloc):
            raise ValueError()
        host = parsed.hostname.encode("idna").decode("ascii").lower().rstrip(".")
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        if not 1 <= port <= 65535:
            raise ValueError()
    except (ValueError, UnicodeError, AttributeError) as exc:
        raise HTTPException(400, "Base URL non valida: usare un host senza credenziali, query o frammenti") from exc
    allowed = {h.strip().lower().rstrip(".") for h in os.getenv("ALLOWED_AI_HOSTS", "").split(",") if h.strip()}
    if allowed and host not in allowed:
        raise HTTPException(400, "Host IA non presente nella allowlist esatta")
    return normalized, parsed, host, port, host in allowed


def _resolve(url):
    normalized, parsed, host, port, explicitly_allowed = _parse(url)
    try:
        try:
            addresses = [str(_ip(host))]
        except ValueError:
            addresses = list(dict.fromkeys(entry[4][0] for entry in socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)))
        if not addresses:
            raise socket.gaierror()
    except (socket.gaierror, OSError) as exc:
        raise HTTPException(400, "Risoluzione DNS del provider non riuscita; connessione negata") from exc
    local = []
    for address in addresses:
        ip = _ip(address)
        # Metadata/link-local/loopback/unspecified/multicast are never valid AI endpoints.
        if ip.is_loopback or ip.is_link_local or ip.is_unspecified or ip.is_multicast or ip.is_reserved:
            raise HTTPException(400, "Indirizzo di rete non consentito per il provider IA")
        private_lan = (ip in ipaddress.ip_network("10.0.0.0/8") or ip in ipaddress.ip_network("172.16.0.0/12")
                       or ip in ipaddress.ip_network("192.168.0.0/16")) if ip.version == 4 else ip in ipaddress.ip_network("fc00::/7")
        if not ip.is_global and not (private_lan and explicitly_allowed and _enabled("ALLOW_PRIVATE_AI_ENDPOINTS")):
            raise HTTPException(400, "Endpoint non pubblico: servono host esplicito e autorizzazione locale")
        local.append(not ip.is_global)
    if parsed.scheme != "https" and not (all(local) and explicitly_allowed and _enabled("ALLOW_INSECURE_LOCAL_AI_HTTP")):
        raise HTTPException(400, "HTTPS obbligatorio; HTTP locale richiede autorizzazione esplicita")
    return normalized, host, addresses


def validate_base_url(url):
    return _resolve(url)[0]


async def async_validate_base_url(url):
    try:
        return await asyncio.wait_for(asyncio.to_thread(validate_base_url, url), timeout=15)
    except asyncio.TimeoutError as exc:
        raise HTTPException(400, "Timeout DNS del provider; configurazione non salvata") from exc


class PinnedAITransport(httpx.AsyncBaseTransport):
    """Connect to the approved IP, preserving Host, TLS SNI and certificate verification."""
    def __init__(self):
        self._transport = httpx.AsyncHTTPTransport(retries=0, trust_env=False,
            limits=httpx.Limits(max_keepalive_connections=0))

    async def handle_async_request(self, request):
        timeout = request.extensions.get("timeout", {}).get("connect") or 10
        try:
            _, host, addresses = await asyncio.wait_for(asyncio.to_thread(_resolve, str(request.url)), timeout=min(timeout, 15))
        except asyncio.TimeoutError as exc:
            raise httpx.ConnectTimeout("Timeout DNS del provider IA", request=request) from exc
        headers = request.headers.copy()
        headers["Host"] = request.url.netloc.decode("ascii")
        extensions = {**request.extensions, "sni_hostname": host}
        pinned = httpx.Request(request.method, request.url.copy_with(host=addresses[0]),
            headers=headers, stream=request.stream, extensions=extensions)
        return await self._transport.handle_async_request(pinned)

    async def aclose(self):
        await self._transport.aclose()


def ai_http_client(timeout):
    return httpx.AsyncClient(timeout=timeout, follow_redirects=False, trust_env=False, transport=PinnedAITransport())
