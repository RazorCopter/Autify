from fastapi import APIRouter, HTTPException, status, UploadFile, File, Form
from typing import List
from .models import Scale, Evaluation, User, AppSettings, Section, Question
from .database import evaluations_collection, database, users_collection, settings_collection
from datetime import datetime
import csv
import uuid

admin_router = APIRouter()
client_router = APIRouter()

scales_collection = database.get_collection("scales")

# ==========================================
# ADMIN ROUTER (/api/admin)
# ==========================================

@admin_router.get("/users", response_model=List[User], tags=["Admin - Users"])
async def get_users():
    cursor = users_collection.find({})
    users = await cursor.to_list(length=1000)
    return users

@admin_router.post("/users", response_model=User, status_code=status.HTTP_201_CREATED, tags=["Admin - Users"])
async def create_user(user: User):
    user_dict = user.model_dump()
    await users_collection.insert_one(user_dict)
    return user

@admin_router.put("/users/{id}", response_model=User, tags=["Admin - Users"])
async def update_user(id: str, user: User):
    user_dict = user.model_dump()
    result = await users_collection.replace_one({"id": id}, user_dict)
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Utente non trovato")
    return user

@admin_router.delete("/users/{id}", tags=["Admin - Users"])
async def delete_user(id: str):
    result = await users_collection.delete_one({"id": id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Utente non trovato")
    return {"message": "Utente eliminato con successo"}

@admin_router.get("/evaluations/{id_patient}", response_model=List[Evaluation], tags=["Admin - Evaluations"])
async def get_evaluations(id_patient: str):
    """Storico completo per un paziente, per fini analitici."""
    cursor = evaluations_collection.find({"id_paziente": id_patient})
    evaluations = await cursor.to_list(length=1000)
    return evaluations

@admin_router.post("/import-scale", tags=["Admin - Configuration"])
async def import_scale(file: UploadFile = File(...)):
    if not file.filename.endswith('.csv'):
        raise HTTPException(status_code=400, detail="Il file deve essere un CSV")
    
    content = await file.read()
    decoded = content.decode('utf-8-sig').splitlines()
    reader = csv.reader(decoded, delimiter=';') # o sniffing dinamico
    
    sezioni_dict = {}
    current_section = "Sezione Generale"
    
    for row in reader:
        row_cleaned = [str(x).strip() for x in row]
        non_empty = [x for x in row_cleaned if x]
        if not non_empty: continue
        
        if len(non_empty) == 1:
            val = non_empty[0]
            if len(val) > 2:
                current_section = val
            continue
            
        testo = non_empty[0]
        if len(testo) < 5 and len(non_empty) > 1:
            testo = non_empty[1]
            
        domanda = Question(
            id_domanda=f"pos_{uuid.uuid4().hex[:8]}",
            testo_domanda=testo,
            tipo_risposta="rating_1_to_5"
        )
        if current_section not in sezioni_dict: sezioni_dict[current_section] = []
        sezioni_dict[current_section].append(domanda)

    sezioni_list = [Section(titolo_sezione=k, domande=v) for k,v in sezioni_dict.items()]
    scala_pos = Scale(
        id="scala_pos",
        nome="Scala POS Eterovalutativa",
        descrizione=f"Importata il {datetime.utcnow().strftime('%Y-%m-%d')}",
        sezioni=sezioni_list
    )

    await scales_collection.delete_many({})
    await scales_collection.insert_one(scala_pos.model_dump())
    
    return {"message": "Protocollo importato con successo", "sections": len(sezioni_list)}

@admin_router.post("/settings", tags=["Admin - Configuration"])
async def update_settings(settings: AppSettings):
    settings_dict = settings.model_dump()
    await settings_collection.replace_one({"id": settings.id}, settings_dict, upsert=True)
    return {"message": "Impostazioni salvate con successo"}

@admin_router.get("/settings", response_model=AppSettings, tags=["Admin - Configuration"])
async def get_settings():
    doc = await settings_collection.find_one({"id": "global_settings"})
    if doc:
        return AppSettings(**doc)
    return AppSettings()



# ==========================================
# CLIENT ROUTER (/api/client)
# ==========================================

@client_router.get("/scales", response_model=List[Scale], tags=["Client - Scales"])
async def get_scales():
    """Restituisce l'elenco delle scale disponibili per il data entry"""
    cursor = scales_collection.find({})
    scales = await cursor.to_list(length=100)
    return scales

@client_router.post("/evaluations", response_model=Evaluation, status_code=status.HTTP_201_CREATED, tags=["Client - Evaluations"])
async def create_evaluation(evaluation: Evaluation):
    """Salva una nuova valutazione compilata nel database"""
    eval_dict = evaluation.model_dump()
    result = await evaluations_collection.insert_one(eval_dict)
    
    if not result.inserted_id:
        raise HTTPException(status_code=500, detail="Errore nel salvataggio della valutazione")
        
    return evaluation

@client_router.get("/users", response_model=List[User], tags=["Client - Users"])
async def get_client_users():
    """Recupero utenti per la selezione prima del wizard"""
    cursor = users_collection.find({})
    users = await cursor.to_list(length=1000)
    return users
