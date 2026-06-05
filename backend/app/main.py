from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from .routes import admin_router, client_router, public_admin_router
from . import auth as auth_module

limiter = Limiter(key_func=get_remote_address)

app = FastAPI(
    title="Autify API",
    description="API per la piattaforma Multi-Frontend (Admin/Client) Autify di Valutazione Multidimensionale.",
    version="2.22.0"
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.on_event("startup")
async def startup_event():
    """Inizializza il sistema al primo avvio: crea l'utente admin di default se necessario."""
    await auth_module.ensure_default_admin()

# Configurazione CORS per permettere le chiamate dai frontend (Admin e Client)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://tiglio.autify.it"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)

# Inclusione dei router separati
app.include_router(public_admin_router, prefix="/api/admin")
app.include_router(admin_router, prefix="/api/admin")
app.include_router(client_router, prefix="/api/client")

@app.get("/", tags=["Health"])
async def health_check():
    return {"status": "ok", "message": "Autify Backend is running"}
