import asyncio
from contextlib import suppress
from .job_worker import run_worker, ensure_job_indexes
from .maintenance import maintenance_enabled
from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from .routers import auth, patients, evaluations, settings, ai, backup, dashboard, misc, license
from . import auth as auth_module
from .license_service import ensure_trial_license, require_valid_license
from .maintenance import BackupMaintenanceMiddleware

limiter = Limiter(key_func=get_remote_address)

@asynccontextmanager
async def lifespan(_app: FastAPI):
    from .audit import ensure_indexes
    await ensure_indexes()
    await auth_module.ensure_default_admin()
    await ensure_trial_license()
    await ensure_job_indexes()
    worker = None if maintenance_enabled() else asyncio.create_task(run_worker())
    try:
        yield
    finally:
        if worker:
            worker.cancel()
            with suppress(asyncio.CancelledError):
                await worker

app = FastAPI(
    title="Autify API",
    description="API per la piattaforma Multi-Frontend (Admin/Client) Autify di Valutazione Multidimensionale.",
    version="4.0.9",
    lifespan=lifespan,
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
app.add_middleware(BackupMaintenanceMiddleware)
from .security import PrivateApiResponses
app.add_middleware(PrivateApiResponses)
from .audit import AuditContextMiddleware
app.add_middleware(AuditContextMiddleware)

import os

_cors_origins_env = os.getenv("CORS_ORIGINS", "https://tiglio.autify.it,http://localhost:8090,http://localhost:8000")
_allowed_origins = [orig.strip() for orig in _cors_origins_env.split(",") if orig.strip()]

# Configurazione CORS per permettere le chiamate dai frontend (Admin e Client)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
    expose_headers=["X-Correlation-ID", "X-Audit-Status"],
)

# Inclusione dei router separati (ARCH-01)
for module in [auth, patients, evaluations, settings, ai, backup, dashboard, misc, license]:
    # Admin recovery must remain available even after restoring an expired license.
    # The CSV endpoint in backup keeps its own license dependency.
    dependencies = [] if module in (auth, license, backup) else [Depends(require_valid_license)]
    app.include_router(module.public_admin_router, prefix="/api/admin", dependencies=dependencies)
    app.include_router(module.admin_router, prefix="/api/admin", dependencies=dependencies)
    app.include_router(module.client_router, prefix="/api/client", dependencies=dependencies)

@app.get("/", tags=["Health"])
async def health_check():
    return {"status": "ok", "message": "Autify Backend is running"}


from .ai.crypto import SecretConfigurationError, SecretDecryptionError
from fastapi.responses import JSONResponse

@app.exception_handler(SecretConfigurationError)
@app.exception_handler(SecretDecryptionError)
async def unavailable_ai_key(request, exc):
    return JSONResponse(status_code=503, content={"detail": "Chiavi IA non disponibili: verificare il keyring senza sovrascrivere le impostazioni"})


@app.get("/health/ready", tags=["Health"])
async def readiness():
    from .database import database
    from fastapi.responses import JSONResponse
    from pymongo.errors import PyMongoError
    async def probe():
        await database.command("ping")
        return await database.client.admin.command("hello")
    try:
        topology = await asyncio.wait_for(probe(), timeout=5)
        if not topology.get("setName") or not topology.get("isWritablePrimary"):
            raise RuntimeError("Replica set primary required")
    except (PyMongoError, RuntimeError, asyncio.TimeoutError):
        return JSONResponse(status_code=503, content={"status": "not_ready"})
    return {"status": "ready"}
