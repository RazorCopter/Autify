from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .routes import admin_router, client_router, public_admin_router

app = FastAPI(
    title="AutAnalysis API",
    description="API per la piattaforma Multi-Frontend (Admin/Client) di Valutazione Multidimensionale.",
    version="2.16.15"
)

# Configurazione CORS per permettere le chiamate dai frontend (Admin e Client)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Modificare in prod inserendo i domini specifici come https://aut.ghome.it
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
    return {"status": "ok", "message": "AutAnalysis Backend is running"}
