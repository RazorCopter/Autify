from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from .routers import auth, patients, evaluations, settings, ai, backup, dashboard, misc, license
from . import auth as auth_module
from .license_service import ensure_trial_license, require_valid_license

limiter = Limiter(key_func=get_remote_address)

@asynccontextmanager
async def lifespan(_app: FastAPI):
    await auth_module.ensure_default_admin()
    await ensure_trial_license()
    yield

app = FastAPI(
    title="Autify API",
    description="API per la piattaforma Multi-Frontend (Admin/Client) Autify di Valutazione Multidimensionale.",
    version="4.0.0",
    lifespan=lifespan,
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

import os

_cors_origins_env = os.getenv("CORS_ORIGINS", "https://tiglio.autify.it,http://localhost:8090,http://localhost:8000")
_allowed_origins = [orig.strip() for orig in _cors_origins_env.split(",") if orig.strip()]

# Configurazione CORS per permettere le chiamate dai frontend (Admin e Client)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

# Inclusione dei router separati (ARCH-01)
for module in [auth, patients, evaluations, settings, ai, backup, dashboard, misc, license]:
    dependencies = [] if module in (auth, license) else [Depends(require_valid_license)]
    app.include_router(module.public_admin_router, prefix="/api/admin", dependencies=dependencies)
    app.include_router(module.admin_router, prefix="/api/admin", dependencies=dependencies)
    app.include_router(module.client_router, prefix="/api/client", dependencies=dependencies)

@app.get("/", tags=["Health"])
async def health_check():
    return {"status": "ok", "message": "Autify Backend is running"}
