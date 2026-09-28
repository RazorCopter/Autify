import logging

import httpx
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field

from ._helpers import log_audit, verify_auth
from ..license_service import activate_license, get_license_server_info, get_license_status

public_admin_router = APIRouter()
admin_router = APIRouter(dependencies=[Depends(verify_auth)])
client_router = APIRouter(dependencies=[Depends(verify_auth)])
_logger = logging.getLogger("autify")


class LicenseActivationRequest(BaseModel):
    code: str = Field(min_length=20, max_length=100)


@admin_router.get("/license/status", tags=["Admin - License"])
async def license_status(force_remote: bool = False, auth: dict = Depends(verify_auth)):
    return await get_license_status(force_remote=force_remote)


@admin_router.get("/license/server-info", tags=["Admin - License"])
async def license_server_info(auth: dict = Depends(verify_auth)):
    return await get_license_server_info()


@admin_router.post("/license/activate", tags=["Admin - License"])
async def license_activate(payload: LicenseActivationRequest, auth: dict = Depends(verify_auth)):
    if auth["role"] != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Solo gli amministratori possono attivare una licenza")
    try:
        result = await activate_license(payload.code)
    except httpx.HTTPStatusError as exc:
        detail = "Il server licenze ha rifiutato l'attivazione"
        try:
            detail = exc.response.json().get("detail", detail)
        except ValueError:
            pass
        raise HTTPException(status_code=exc.response.status_code, detail=detail) from exc
    except (httpx.HTTPError, RuntimeError) as exc:
        _logger.warning("Attivazione licenza non disponibile: %s", exc)
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="Server licenze non raggiungibile") from exc
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    await log_audit("license_activate", auth["username"], "Licenza commerciale attivata")
    return result