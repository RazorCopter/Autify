from fastapi import APIRouter, HTTPException, status, UploadFile, File, Form
from typing import List
from .models import Scale, Evaluation, Patient, AppSettings, Section, Question
from .database import evaluations_collection, database, settings_collection
from datetime import datetime
import csv
import uuid

admin_router = APIRouter()
client_router = APIRouter()

scales_collection = database.get_collection("scales")
patients_collection = database.get_collection("patients")

# ==========================================
# ADMIN ROUTER (/api/admin)
# ==========================================

@admin_router.get("/patients", response_model=List[Patient], tags=["Admin - Patients"])
async def get_patients():
    cursor = patients_collection.find({})
    patients = await cursor.to_list(length=1000)
    return patients

@admin_router.get("/scales", response_model=List[Scale], tags=["Admin - Configuration"])
async def get_admin_scales():
    """Restituisce l'elenco completo delle scale e dei protocolli caricati."""
    cursor = scales_collection.find({})
    scales = await cursor.to_list(length=100)
    return scales

@admin_router.post("/patients", response_model=Patient, status_code=status.HTTP_201_CREATED, tags=["Admin - Patients"])
async def create_patient(patient: Patient):
    patient_dict = patient.model_dump()
    await patients_collection.insert_one(patient_dict)
    return patient

@admin_router.put("/patients/{id}", response_model=Patient, tags=["Admin - Patients"])
async def update_patient(id: str, patient: Patient):
    patient_dict = patient.model_dump()
    result = await patients_collection.replace_one({"id": id}, patient_dict)
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Paziente non trovato")
    return patient

@admin_router.delete("/patients/{id}", tags=["Admin - Patients"])
async def delete_patient(id: str):
    result = await patients_collection.delete_one({"id": id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Paziente non trovato")
    return {"message": "Paziente eliminato con successo"}

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
    # Sniffing del delimitatore
    delimiter = ';' if ';' in decoded[0] else ','
    reader = csv.reader(decoded, delimiter=delimiter)
    
    scales_to_import = []
    current_scale = None
    current_section = None

    for row in reader:
        if not row or len(row) < 2: continue
        tipo = row[0].strip().upper()
        testo = row[1].strip()
        descrizione = row[2].strip() if len(row) > 2 else ""

        if tipo == "SCALA":
            if current_scale:
                if current_section:
                    current_scale.sezioni.append(current_section)
                scales_to_import.append(current_scale)
            
            current_scale = Scale(
                id=f"scale_{uuid.uuid4().hex[:8]}",
                nome=testo,
                descrizione=descrizione or f"Importata il {datetime.utcnow().strftime('%Y-%m-%d')}",
                sezioni=[]
            )
            current_section = None
            
        elif tipo == "SEZIONE":
            if not current_scale:
                # Crea scala di default se manca
                current_scale = Scale(
                    id=f"scale_{uuid.uuid4().hex[:8]}",
                    nome="Nuovo Protocollo",
                    descrizione=f"Importata il {datetime.utcnow().strftime('%Y-%m-%d')}",
                    sezioni=[]
                )
            if current_section:
                current_scale.sezioni.append(current_section)
            current_section = Section(titolo_sezione=testo, domande=[])
            
        elif tipo == "DOMANDA":
            if not current_scale:
                current_scale = Scale(
                    id=f"scale_{uuid.uuid4().hex[:8]}",
                    nome="Nuovo Protocollo",
                    descrizione=f"Importata il {datetime.utcnow().strftime('%Y-%m-%d')}",
                    sezioni=[]
                )
            if not current_section:
                current_section = Section(titolo_sezione="Generale", domande=[])
            
            domanda = Question(
                id_domanda=f"q_{uuid.uuid4().hex[:8]}",
                testo_domanda=testo,
                tipo_risposta=descrizione if descrizione else "rating_1_to_5"
            )
            current_section.domande.append(domanda)

    # Aggiunta dell'ultimo blocco
    if current_scale:
        if current_section:
            current_scale.sezioni.append(current_section)
        scales_to_import.append(current_scale)

    if not scales_to_import:
        raise HTTPException(status_code=400, detail="Nessun dato valido trovato nel CSV")

    # Inserimento nel DB (non cancelliamo più tutto, aggiungiamo)
    for s in scales_to_import:
        await scales_collection.insert_one(s.model_dump())
    
    return {"message": "Protocolli importati con successo", "count": len(scales_to_import)}

@admin_router.put("/scales/{id}", response_model=Scale, tags=["Admin - Configuration"])
async def update_scale(id: str, scale: Scale):
    scale_dict = scale.model_dump()
    result = await scales_collection.replace_one({"id": id}, scale_dict)
    if result.matched_count == 0:
        raise HTTPException(status_code=404, detail="Protocollo non trovato")
    return scale

@admin_router.delete("/scales/{id}", tags=["Admin - Configuration"])
async def delete_scale(id: str):
    result = await scales_collection.delete_one({"id": id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Protocollo non trovato")
    return {"message": "Protocollo eliminato con successo"}

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

@client_router.get("/scales/{scale_id}", response_model=Scale, tags=["Client - Scales"])
async def get_scale_by_id(scale_id: str):
    """Restituisce i dettagli completi di una singola scala"""
    scale = await scales_collection.find_one({"id": scale_id})
    if not scale:
        raise HTTPException(status_code=404, detail="Scala non trovata")
    return scale

@client_router.post("/evaluations", response_model=Evaluation, status_code=status.HTTP_201_CREATED, tags=["Client - Evaluations"])
async def create_evaluation(evaluation: Evaluation):
    """Salva una nuova valutazione compilata nel database"""
    eval_dict = evaluation.model_dump()
    result = await evaluations_collection.insert_one(eval_dict)
    
    if not result.inserted_id:
        raise HTTPException(status_code=500, detail="Errore nel salvataggio della valutazione")
        
    return evaluation

@client_router.get("/patients", response_model=List[Patient], tags=["Client - Patients"])
async def get_client_patients():
    """Recupero pazienti per la selezione prima del wizard"""
    cursor = patients_collection.find({})
    patients = await cursor.to_list(length=1000)
    # The frontend only needs id, nome, cognome. Patient model has them.
    return patients
