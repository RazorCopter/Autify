from fastapi import APIRouter, HTTPException, Query, status, UploadFile, File, Form
from fastapi.responses import StreamingResponse
from typing import List, Literal
from bson import ObjectId
from .models import Scale, Evaluation, Patient, AppSettings, Section, Question, Option, DOMINI_POS, AggregatedEvaluation, EvaluationUpdateRequest
from .database import evaluations_collection, database, settings_collection
from .pdf_generator import generate_evaluation_pdf, aggregate_domains
from datetime import datetime
import json
import uuid
import io

admin_router = APIRouter()
client_router = APIRouter()

scales_collection = database.get_collection("scales")
patients_collection = database.get_collection("patients")


async def _find_evaluation_document(evaluation_id: str):
    """Recupera una valutazione supportando sia il campo applicativo che fallback legacy."""
    eval_doc = await evaluations_collection.find_one({"id_valutazione": evaluation_id})
    if eval_doc:
        return eval_doc

    eval_doc = await evaluations_collection.find_one({"id": evaluation_id})
    if eval_doc:
        return eval_doc

    if ObjectId.is_valid(evaluation_id):
        return await evaluations_collection.find_one({"_id": ObjectId(evaluation_id)})

    return None

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
    if not patient_dict.get("id"):
        patient_dict.pop("id", None)
        patient = Patient(**patient_dict)
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
    """
    Importa una scala clinica da un file JSON strutturato.

    Formato atteso:
    {
      "scala": {
        "id": "pos_2024",          // opzionale, generato se assente
        "nome": "Scala POS",
        "descrizione": "...",      // opzionale
        "domini": [
          {
            "codice": "SP",
            "nome": "Sviluppo Personale",
            "descrizione": "...",  // opzionale
            "domande": [
              {
                "codice": "SP-1",
                "testo": "...",
                "note": "...",     // opzionale
                "opzioni": [
                  { "punteggio": 3, "etichetta": "Riesce da solo", "descrizione": "..." }
                ]
              }
            ]
          }
        ]
      }
    }
    """
    if not (file.filename or '').lower().endswith('.json'):
        raise HTTPException(status_code=400, detail="Il file deve essere un JSON (.json)")

    content = await file.read()
    try:
        data = json.loads(content.decode('utf-8-sig'))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise HTTPException(status_code=422, detail=f"JSON non valido: {exc}")

    scala_data = data.get("scala")
    if not scala_data:
        raise HTTPException(status_code=422, detail="Campo 'scala' mancante nel JSON")

    # ── ID e metadati radice ──────────────────────────────────────────────
    scale_id = scala_data.get("id") or f"scale_{uuid.uuid4().hex[:8]}"
    nome = scala_data.get("nome") or "Scala senza nome"
    descrizione = scala_data.get("descrizione") or \
        f"Importata il {datetime.utcnow().strftime('%Y-%m-%d')}"

    # ── Costruzione sezioni ───────────────────────────────────────────────
    sezioni: list[Section] = []

    for dominio in scala_data.get("domini", []):
        codice_dom = dominio.get("codice") or ""
        nome_dom = dominio.get("nome") or dominio.get("titolo_sezione") or codice_dom
        desc_dom = dominio.get("descrizione")

        domande: list[Question] = []
        for d in dominio.get("domande", []):
            codice_q = d.get("codice")
            testo_q = d.get("testo") or d.get("testo_domanda") or ""
            note_q = d.get("note")

            opzioni: list[Option] = []
            for o in d.get("opzioni", []):
                opzioni.append(Option(
                    punteggio=int(o.get("punteggio", 0)),
                    testo_risposta=o.get("etichetta") or o.get("testo_risposta") or "",
                    descrizione=o.get("descrizione"),
                ))

            # Ordina opzioni per punteggio decrescente (3→1) per consistenza UI
            opzioni.sort(key=lambda x: x.punteggio, reverse=True)

            domande.append(Question(
                id_domanda=f"q_{uuid.uuid4().hex[:8]}",
                codice=codice_q,
                testo_domanda=testo_q,
                note=note_q,
                opzioni=opzioni,
            ))

        sezioni.append(Section(
            codice_sezione=codice_dom,
            titolo_sezione=nome_dom,
            descrizione_sezione=desc_dom,
            domande=domande,
        ))

    if not sezioni:
        raise HTTPException(status_code=422, detail="Il JSON non contiene domini/sezioni")

    scale = Scale(
        id=scale_id,
        nome=nome,
        descrizione=descrizione,
        sezioni=sezioni,
    )

    # Upsert: se esiste già una scala con lo stesso id, la sostituisce
    await scales_collection.replace_one(
        {"id": scale_id}, scale.model_dump(), upsert=True
    )

    total_questions = sum(len(s.domande) for s in sezioni)
    return {
        "message": "Scala importata con successo",
        "id": scale_id,
        "nome": nome,
        "sezioni": len(sezioni),
        "domande_totali": total_questions,
    }


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


@admin_router.get("/evaluations/{evaluation_id}/pdf", tags=["Admin - Evaluations"])
async def download_evaluation_pdf(
    evaluation_id: str,
    chart_type: Literal["linear", "bars"] = Query("bars", description="Tipo di grafico: linear | bars"),
):
    """Genera e scarica il PDF della valutazione con il grafico selezionato."""
    eval_doc = await _find_evaluation_document(evaluation_id)
    if not eval_doc:
        raise HTTPException(
            status_code=404,
            detail=f"Valutazione non trovata per id '{evaluation_id}'",
        )

    patient_doc = await patients_collection.find_one({"id": eval_doc["id_paziente"]})
    scale_doc   = await scales_collection.find_one({"id": eval_doc["id_scala"]})

    domains = aggregate_domains(eval_doc.get("risposte", []), DOMINI_POS)

    pdf_bytes = generate_evaluation_pdf(
        evaluation=eval_doc,
        patient=patient_doc or {},
        scale=scale_doc or {},
        domains=domains,
        chart_type=chart_type,
    )

    filename = f"valutazione_{evaluation_id[:8]}_{chart_type}.pdf"
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@admin_router.get("/evaluations/{patient_id}/{scale_id}",
                  response_model=AggregatedEvaluation,
                  tags=["Admin - Evaluations"])
async def get_aggregated_evaluation(patient_id: str, scale_id: str):
    """Recupera l'ultima valutazione per paziente+scala con aggregazione per dominio."""
    eval_doc = await evaluations_collection.find_one(
        {"id_paziente": patient_id, "id_scala": scale_id},
        sort=[("data_compilazione", -1)]
    )
    if not eval_doc:
        raise HTTPException(status_code=404, detail="Nessuna valutazione trovata")

    domains = aggregate_domains(eval_doc.get("risposte", []), DOMINI_POS)
    return AggregatedEvaluation(
        id_valutazione=eval_doc["id_valutazione"],
        id_paziente=eval_doc["id_paziente"],
        id_scala=eval_doc["id_scala"],
        anno=eval_doc["anno"],
        data_compilazione=eval_doc["data_compilazione"],
        nome_operatore=eval_doc["nome_operatore"],
        domini=domains,
        risposte=eval_doc.get("risposte", []),
    )


@admin_router.put("/evaluations/{evaluation_id}",
                  response_model=AggregatedEvaluation,
                  tags=["Admin - Evaluations"])
async def update_evaluation(evaluation_id: str, payload: EvaluationUpdateRequest):
    """Modifica inline punteggi/note di una valutazione, restituisce i dati riaggregati."""
    existing = await evaluations_collection.find_one({"id_valutazione": evaluation_id})
    if not existing:
        raise HTTPException(status_code=404, detail="Valutazione non trovata")

    new_risposte = [r.model_dump() for r in payload.risposte]
    await evaluations_collection.update_one(
        {"id_valutazione": evaluation_id},
        {"$set": {"risposte": new_risposte}}
    )
    existing["risposte"] = new_risposte
    domains = aggregate_domains(new_risposte, DOMINI_POS)
    return AggregatedEvaluation(
        id_valutazione=existing["id_valutazione"],
        id_paziente=existing["id_paziente"],
        id_scala=existing["id_scala"],
        anno=existing["anno"],
        data_compilazione=existing["data_compilazione"],
        nome_operatore=existing["nome_operatore"],
        domini=domains,
        risposte=new_risposte,
    )

@admin_router.post("/settings", tags=["Admin - Configuration"])
async def update_settings(settings: AppSettings):
    settings_dict = settings.model_dump()
    
    # Se il frontend invia la chiave mascherata, recuperiamo quella vera dal DB
    if settings_dict.get("gemini_api_key") == "***-HIDDEN":
        existing = await settings_collection.find_one({"id": settings.id})
        if existing:
            settings_dict["gemini_api_key"] = existing.get("gemini_api_key")
            
    await settings_collection.replace_one({"id": settings.id}, settings_dict, upsert=True)
    return {"message": "Impostazioni salvate con successo"}

@admin_router.get("/settings", response_model=AppSettings, tags=["Admin - Configuration"])
async def get_settings():
    doc = await settings_collection.find_one({"id": "global_settings"})
    if doc:
        settings = AppSettings(**doc)
        if settings.gemini_api_key:
            settings.gemini_api_key = "***-HIDDEN"
        return settings
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
