from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .routes import admin_router, client_router, public_admin_router
from . import auth as auth_module

app = FastAPI(
    title="Autify API",
    description="API per la piattaforma Multi-Frontend (Admin/Client) Autify di Valutazione Multidimensionale.",
    version="2.17.6"
)

@app.on_event("startup")
async def startup_event():
    """Inizializza il sistema al primo avvio: crea l'utente admin di default se necessario."""
    await auth_module.ensure_default_admin()

# Configurazione CORS per permettere le chiamate dai frontend (Admin e Client)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Modificare in prod inserendo i domini specifici come https://tiglio.autify.it
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Inclusione dei router separati
app.include_router(public_admin_router, prefix="/api/admin")
app.include_router(admin_router, prefix="/api/admin")
app.include_router(client_router, prefix="/api/client")

@app.get("/", tags=["Health"])
async def health_check():
    return {"status": "ok", "message": "Autify Backend is running"}
