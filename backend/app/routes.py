from fastapi import APIRouter, HTTPException, status, UploadFile, File
from fastapi.responses import StreamingResponse
from typing import List, Optional
from bson import ObjectId
from .models import Scale, Evaluation, Patient, AppSettings, Section, Question, Option, DOMINI_POS, AggregatedEvaluation, EvaluationUpdateRequest
from .database import evaluations_collection, settings_collection, patients_collection, scales_collection, users_collection
from .pdf_generator import generate_evaluation_pdf
from .analytics import compute_psychometric_analysis, compute_direct_scores, build_domain_map
from datetime import datetime, timezone
import json
import uuid
import io
from pathlib import Path

admin_router = APIRouter()
client_router = APIRouter()


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


def _normalize_scale_name(value: Optional[str]) -> str:
    return (value or "").lower().replace(" ", "").replace("-", "")


def _load_builtin_san_martin_scale() -> Optional[dict]:
    """Carica il protocollo San Martin bundled per reidratare metadati mancanti."""
    app_dir = Path(__file__).resolve().parent
    candidate_files = [
        app_dir / "ScalaSanMartin.json",
        app_dir / "Scala San Martin.json",
    ]

    for candidate in candidate_files:
        if not candidate.exists():
            continue
        try:
            data = json.loads(candidate.read_text(encoding="utf-8-sig"))
            scala = data.get("scala")
            if scala:
                return scala
        except (OSError, json.JSONDecodeError):
            continue
    return None


def _hydrate_scale_doc(scale_doc: Optional[dict]) -> dict:
    """
    Ripristina i metadati psicometrici per le scale San Martin importate
    prima del supporto a `scoring_tables`.
    """
    if not scale_doc:
        return {}

    if scale_doc.get("scoring_tables"):
        return scale_doc

    normalized_id = _normalize_scale_name(scale_doc.get("id"))
    normalized_name = _normalize_scale_name(scale_doc.get("nome"))
    is_san_martin = "sanmartin" in normalized_id or "sanmartin" in normalized_name

    if not is_san_martin:
        return scale_doc

    builtin_scale = _load_builtin_san_martin_scale()
    if not builtin_scale:
        return scale_doc

    enriched_scale = dict(scale_doc)
    for key, value in builtin_scale.items():
        if key not in enriched_scale:
            enriched_scale[key] = value
    return enriched_scale

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
        f"Importata il {datetime.now(timezone.utc).strftime('%Y-%m-%d')}"

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

    scale_dict = scale.model_dump()
    extra_metadata = {
        key: value
        for key, value in scala_data.items()
        if key not in {"id", "nome", "descrizione", "domini"}
    }
    scale_dict.update(extra_metadata)

    await scales_collection.replace_one(
        {"id": scale_id}, scale_dict, upsert=True
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
    existing = await scales_collection.find_one({"id": id})
    if existing:
        # Mantiene qualsiasi metadato extra già salvato nel documento Mongo.
        preserved_metadata = {
            key: value
            for key, value in existing.items()
            if key not in {"_id", "id", "nome", "descrizione", "sezioni"}
        }
        scale_dict.update(preserved_metadata)
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
):
    """Genera e scarica il PDF della valutazione con grafico a barre."""
    eval_doc = await _find_evaluation_document(evaluation_id)
    if not eval_doc:
        raise HTTPException(
            status_code=404,
            detail=f"Valutazione non trovata per id '{evaluation_id}'",
        )

    patient_doc = await patients_collection.find_one({"id": eval_doc["id_paziente"]})
    scale_doc = _hydrate_scale_doc(
        await scales_collection.find_one({"id": eval_doc["id_scala"]})
    )

    analysis = compute_psychometric_analysis(
        risposte=eval_doc.get("risposte", []),
        scale_doc=scale_doc or {},
    )

    domain_map = build_domain_map(scale_doc or {})
    if not domain_map:
        domain_map = DOMINI_POS
    domains = compute_direct_scores(eval_doc.get("risposte", []), domain_map)

    pdf_bytes = generate_evaluation_pdf(
        evaluation=eval_doc,
        patient=patient_doc or {},
        scale=scale_doc or {},
        domains=domains,
        analysis=analysis,
    )

    filename = f"valutazione_{evaluation_id[:8]}.pdf"
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@admin_router.get("/evaluations/{patient_id}/{scale_id}",
                  response_model=List[AggregatedEvaluation],
                  tags=["Admin - Evaluations"])
async def get_aggregated_evaluation(patient_id: str, scale_id: str):
    """Recupera lo storico valutazioni per paziente+scala ordinato per data decrescente."""
    cursor = evaluations_collection.find(
        {"id_paziente": patient_id, "id_scala": scale_id}
    ).sort("data_compilazione", -1)
    eval_docs = await cursor.to_list(length=1000)
    if not eval_docs:
        raise HTTPException(status_code=404, detail="Nessuna valutazione trovata")

    history = []
    for eval_doc in eval_docs:
        scale_doc = _hydrate_scale_doc(
            await scales_collection.find_one({"id": eval_doc["id_scala"]})
        )
        domain_map = build_domain_map(scale_doc or {})
        if not domain_map:
            domain_map = DOMINI_POS
        domains = compute_direct_scores(eval_doc.get("risposte", []), domain_map)
        history.append(
            AggregatedEvaluation(
                id_valutazione=eval_doc["id_valutazione"],
                id_paziente=eval_doc["id_paziente"],
                id_scala=eval_doc["id_scala"],
                anno=eval_doc["anno"],
                data_compilazione=eval_doc["data_compilazione"],
                nome_operatore=eval_doc["nome_operatore"],
                nome_intervistato=eval_doc.get("nome_intervistato"),
                domini=domains,
                risposte=eval_doc.get("risposte", []),
            )
        )
    return history


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
    scale_doc = _hydrate_scale_doc(
        await scales_collection.find_one({"id": existing["id_scala"]})
    )
    domain_map = build_domain_map(scale_doc or {})
    if not domain_map:
        domain_map = DOMINI_POS
    domains = compute_direct_scores(new_risposte, domain_map)
    return AggregatedEvaluation(
        id_valutazione=existing["id_valutazione"],
        id_paziente=existing["id_paziente"],
        id_scala=existing["id_scala"],
        anno=existing["anno"],
        data_compilazione=existing["data_compilazione"],
        nome_operatore=existing["nome_operatore"],
        nome_intervistato=existing.get("nome_intervistato"),
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


@admin_router.get("/evaluations/{evaluation_id}/analysis", tags=["Admin - Evaluations"])
async def get_evaluation_analysis(evaluation_id: str):
    """Restituisce l'analisi psicometrica completa di una valutazione."""
    eval_doc = await _find_evaluation_document(evaluation_id)
    if not eval_doc:
        raise HTTPException(
            status_code=404,
            detail=f"Valutazione non trovata per id '{evaluation_id}'",
        )
    scale_doc = _hydrate_scale_doc(
        await scales_collection.find_one({"id": eval_doc["id_scala"]})
    )
    if not scale_doc:
        raise HTTPException(status_code=404, detail="Scala associata non trovata")

    analysis = compute_psychometric_analysis(
        risposte=eval_doc.get("risposte", []),
        scale_doc=scale_doc,
    )
    analysis["id_valutazione"] = eval_doc.get("id_valutazione") or evaluation_id
    analysis["id_paziente"] = eval_doc.get("id_paziente", "")
    analysis["id_scala"] = eval_doc.get("id_scala", "")
    return analysis


# ─── DATABASE EXPORT / IMPORT ────────────────────────────────────────────────

async def _collect_collection(name: str, collection) -> list:
    """Raccoglie tutti i documenti di una collezione, convertendo ObjectId in stringa."""
    docs = []
    async for doc in collection.find({}):
        doc.pop('_id', None)
        docs.append(doc)
    return docs


@admin_router.get("/export-db", tags=["Admin - Database"])
async def export_database():
    """Esporta l'intero database in un unico file JSON."""
    db_dump = {
        "metadata": {
            "exported_at": datetime.now(timezone.utc).isoformat(),
            "version": "1.0",
        },
        "collections": {
            "patients": await _collect_collection("patients", patients_collection),
            "evaluations": await _collect_collection("evaluations", evaluations_collection),
            "scales": await _collect_collection("scales", scales_collection),
            "users": await _collect_collection("users", users_collection),
            "settings": await _collect_collection("settings", settings_collection),
        }
    }
    json_bytes = json.dumps(db_dump, ensure_ascii=False, indent=2, default=str).encode('utf-8')

    filename = f"autanalysis_backup_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
    return StreamingResponse(
        io.BytesIO(json_bytes),
        media_type="application/json",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@admin_router.post("/import-db", tags=["Admin - Database"])
async def import_database(file: UploadFile = File(...)):
    """Importa l'intero database da un file JSON di backup."""
    if not (file.filename or '').lower().endswith('.json'):
        raise HTTPException(status_code=400, detail="Il file deve essere un JSON (.json)")

    content = await file.read()
    try:
        data = json.loads(content.decode('utf-8-sig'))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise HTTPException(status_code=422, detail=f"JSON non valido: {exc}")

    collections_data = data.get("collections")
    if not collections_data:
        raise HTTPException(status_code=422, detail="Formato backup non valido: 'collections' mancante")

    mapping = {
        "patients": patients_collection,
        "evaluations": evaluations_collection,
        "scales": scales_collection,
        "users": users_collection,
        "settings": settings_collection,
    }

    imported_counts = {}
    for coll_name, coll in mapping.items():
        docs = collections_data.get(coll_name, [])
        if docs:
            await coll.delete_many({})
            await coll.insert_many(docs)
            imported_counts[coll_name] = len(docs)

    return {
        "message": "Database importato con successo",
        "collections": imported_counts,
    }


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
    if not eval_dict.get("data_compilazione"):
        eval_dict["data_compilazione"] = datetime.now(timezone.utc)
    evaluation = Evaluation(**eval_dict)
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
