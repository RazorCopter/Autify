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
    string_candidates = [
        {"id_valutazione": evaluation_id},
        {"idValutazione": evaluation_id},
        {"id": evaluation_id},
        {"_id": evaluation_id},
    ]

    eval_doc = await evaluations_collection.find_one({"$or": string_candidates})
    if eval_doc:
        return eval_doc

    if ObjectId.is_valid(evaluation_id):
        eval_doc = await evaluations_collection.find_one({"_id": ObjectId(evaluation_id)})
        if eval_doc:
            return eval_doc

    # Fallback ultra-tollerante per documenti legacy/importati da backup:
    # confronta in memoria i principali campi identificativi come stringhe.
    async for doc in evaluations_collection.find({}):
        doc_identifiers = [
            doc.get("id_valutazione"),
            doc.get("idValutazione"),
            doc.get("id"),
            doc.get("_id"),
        ]
        if any(str(value) == evaluation_id for value in doc_identifiers if value is not None):
            return doc

    return None


def _extract_evaluation_identifier(eval_doc: dict) -> str:
    """Restituisce sempre un identificativo stabile e risolvibile per la valutazione."""
    if eval_doc.get("id_valutazione"):
        return str(eval_doc["id_valutazione"])
    if eval_doc.get("idValutazione"):
        return str(eval_doc["idValutazione"])
    if eval_doc.get("id"):
        return str(eval_doc["id"])
    if eval_doc.get("_id") is not None:
        return str(eval_doc["_id"])
    return ""


def _build_evaluation_selector(eval_doc: dict) -> dict:
    """Costruisce il filtro Mongo più affidabile per aggiornare la valutazione trovata."""
    if eval_doc.get("_id") is not None:
        return {"_id": eval_doc["_id"]}
    if eval_doc.get("id_valutazione"):
        return {"id_valutazione": eval_doc["id_valutazione"]}
    if eval_doc.get("idValutazione"):
        return {"idValutazione": eval_doc["idValutazione"]}
    if eval_doc.get("id"):
        return {"id": eval_doc["id"]}
    return {"id_valutazione": _extract_evaluation_identifier(eval_doc)}


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
    
    # Recupera tutte le scale per mappare l'ID al nome
    scales_cursor = scales_collection.find({})
    scales_list = await scales_cursor.to_list(length=100)
    scale_map = {}
    for s in scales_list:
        scale_map[s["id"]] = s["nome"].lower()
        
    # Arricchisce ciascun paziente con le date delle ultime scale compilate
    for pat in patients:
        pat_id = pat["id"]
        
        # Recupera tutte le valutazioni per questo paziente, ordinate per data decrescente
        evals_cursor = evaluations_collection.find({"id_paziente": pat_id}).sort("data_compilazione", -1)
        evals = await evals_cursor.to_list(length=100)
        
        # Inizializziamo i campi come None (o stringhe vuote)
        pat_dict = pat if isinstance(pat, dict) else pat.__dict__
        pat_dict["ultimo_pos_compilato"] = None
        pat_dict["ultimo_san_martin_compilato"] = None
        
        for ev in evals:
            scale_id = ev.get("id_scala")
            scale_name = scale_map.get(scale_id, "").lower()
            
            data_val = ev.get("data_compilazione")
            data_str = None
            if data_val:
                if isinstance(data_val, datetime):
                    data_str = data_val.isoformat()
                else:
                    data_str = str(data_val)
            
            # Se la scala è POS ed è la prima che incontriamo (l'ultima compilata cronologicamente)
            if not pat_dict.get("ultimo_pos_compilato") and ("pos" in scale_name or "pos" in scale_id.lower()):
                pat_dict["ultimo_pos_compilato"] = data_str
                
            # Se la scala è San Martín ed è la prima che incontriamo
            if not pat_dict.get("ultimo_san_martin_compilato") and ("martin" in scale_name or "martin" in scale_id.lower()):
                pat_dict["ultimo_san_martin_compilato"] = data_str
                
            # Se abbiamo trovato entrambe, possiamo interrompere la ricerca per questo paziente
            if pat_dict.get("ultimo_pos_compilato") and pat_dict.get("ultimo_san_martin_compilato"):
                break
                
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
    # Elimina a cascata tutte le valutazioni associate al paziente prima di rimuoverlo
    await evaluations_collection.delete_many({"id_paziente": id})
    
    result = await patients_collection.delete_one({"id": id})
    if result.deleted_count == 0:
        raise HTTPException(status_code=404, detail="Paziente non trovato")
    return {"message": "Paziente e le relative valutazioni eliminati con successo"}

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
    analysis["id_valutazione"] = _extract_evaluation_identifier(eval_doc) or evaluation_id
    analysis["id_paziente"] = eval_doc.get("id_paziente", "")
    analysis["id_scala"] = eval_doc.get("id_scala", "")
    return analysis


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
                id_valutazione=_extract_evaluation_identifier(eval_doc),
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
    existing = await _find_evaluation_document(evaluation_id)
    if not existing:
        raise HTTPException(status_code=404, detail="Valutazione non trovata")

    new_risposte = [r.model_dump() for r in payload.risposte]
    await evaluations_collection.update_one(
        _build_evaluation_selector(existing),
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
        id_valutazione=_extract_evaluation_identifier(existing),
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


@admin_router.get("/dashboard-stats", tags=["Admin - Dashboard"])
async def get_dashboard_stats():
    """
    Ritorna statistiche aggregate pre-calcolate per la Dashboard direzionale:
    - Totale utenze attive
    - Stato copertura (Coperti vs Scaduti/Da valutare) negli ultimi 6 mesi (180 giorni)
    - Distribuzione valutazioni per tipo di scala
    - Trend degli ultimi 6 mesi (valutazioni mensili per scala)
    - Lista degli ultimi alert (max 5) di pazienti da rivalutare urgentemente
    """
    try:
        # 1. Recupero di tutti i pazienti e di tutte le scale per mappare i nomi
        patients_cursor = patients_collection.find({})
        patients = await patients_cursor.to_list(length=2000)
        
        active_patient_ids = set()
        for pat in patients:
            p_id = pat.get("id")
            if p_id:
                active_patient_ids.add(str(p_id))
            p_id2 = pat.get("_id")
            if p_id2:
                active_patient_ids.add(str(p_id2))
        
        scales_cursor = scales_collection.find({})
        scales_list = await scales_cursor.to_list(length=100)
        
        scale_names = {}
        for s in scales_list:
            s_nome = s.get("nome") or "Scala senza nome"
            s_id = s.get("id")
            if s_id:
                scale_names[str(s_id)] = s_nome
            s_id2 = s.get("_id")
            if s_id2:
                scale_names[str(s_id2)] = s_nome
                
        # 2. Recupero di tutte le valutazioni
        evaluations_cursor = evaluations_collection.find({})
        evaluations = await evaluations_cursor.to_list(length=5000)
        
        now = datetime.now(timezone.utc)
        
        # 3. Raggruppamento valutazioni per paziente (saltando orfane e normalizzando gli ID a stringa)
        evals_by_patient = {}
        for ev in evaluations:
            pat_id = ev.get("id_paziente")
            if not pat_id:
                continue
            pat_id_str = str(pat_id)
            if pat_id_str not in active_patient_ids:
                continue
            if pat_id_str not in evals_by_patient:
                evals_by_patient[pat_id_str] = []
            evals_by_patient[pat_id_str].append(ev)
            
        # 4. Calcolo dello stato di copertura di ciascun paziente
        coperti_count = 0
        scaduti_count = 0
        alert_candidates = []
        
        for pat in patients:
            p_id = pat.get("id")
            p_id2 = pat.get("_id")
            
            p_id_str = str(p_id) if p_id else None
            p_id2_str = str(p_id2) if p_id2 else None
            
            pat_display_id = p_id_str or p_id2_str
            if not pat_display_id:
                continue
                
            # Recupera le valutazioni del paziente provando entrambe le chiavi stringa
            pat_evals = []
            if p_id_str and p_id_str in evals_by_patient:
                pat_evals = evals_by_patient[p_id_str]
            elif p_id2_str and p_id2_str in evals_by_patient:
                pat_evals = evals_by_patient[p_id2_str]
            
            if not pat_evals:
                # Mai valutato: è un caso di alert
                scaduti_count += 1
                alert_candidates.append({
                    "paziente_id": pat_display_id,
                    "paziente_nome": pat.get("nome", ""),
                    "paziente_cognome": pat.get("cognome", ""),
                    "ultima_valutazione_data": None,
                    "giorni_da_ultima_valutazione": 9999,  # Alto valore per priorità
                    "stato": "mai_valutato",
                    "scala_nome": "Nessuna scala somministrata"
                })
            else:
                # Ordina le valutazioni per trovare la più recente
                def get_date(ev_doc):
                    d = ev_doc.get("data_compilazione")
                    if isinstance(d, str):
                        try:
                            return datetime.fromisoformat(d.replace("Z", "+00:00"))
                        except ValueError:
                            return datetime.min.replace(tzinfo=timezone.utc)
                    if isinstance(d, datetime):
                        if d.tzinfo is None:
                            return d.replace(tzinfo=timezone.utc)
                        return d
                    return datetime.min.replace(tzinfo=timezone.utc)
                    
                sorted_evals = sorted(pat_evals, key=get_date, reverse=True)
                latest_ev = sorted_evals[0]
                latest_date = get_date(latest_ev)
                
                # Calcolo dei giorni passati da oggi
                days_since = (now - latest_date).days
                
                if days_since <= 180:
                    coperti_count += 1
                else:
                    scaduti_count += 1
                    scale_id = latest_ev.get("id_scala")
                    scale_id_str = str(scale_id) if scale_id else ""
                    scala_nome = scale_names.get(scale_id_str) or scale_names.get(str(scale_id)) or scale_id_str or "Scala sconosciuta"
                    alert_candidates.append({
                        "paziente_id": pat_display_id,
                        "paziente_nome": pat.get("nome", ""),
                        "paziente_cognome": pat.get("cognome", ""),
                        "ultima_valutazione_data": latest_date.isoformat(),
                        "giorni_da_ultima_valutazione": days_since,
                        "stato": "scaduto",
                        "scala_nome": scala_nome
                    })

        # Calcolo percentuale di copertura
        totale_pazienti = len(patients)
        copertura_percentuale = (coperti_count / totale_pazienti * 100) if totale_pazienti > 0 else 0.0
        
        # 5. Ordina gli alert: prima chi non ne ha mai fatte, poi chi ha valutazioni scadute da più tempo
        alert_candidates.sort(key=lambda x: x.get("giorni_da_ultima_valutazione", 0), reverse=True)
        ultimi_alert = alert_candidates[:5]
        
        # 6. Distribuzione per tipo di scala (saltando orfane o non valide)
        distribuzione_raw = {}
        for ev in evaluations:
            pat_id = ev.get("id_paziente")
            if not pat_id:
                continue
            pat_id_str = str(pat_id)
            if pat_id_str not in active_patient_ids:
                continue
            scale_id = ev.get("id_scala")
            if scale_id:
                scale_id_str = str(scale_id)
                distribuzione_raw[scale_id_str] = distribuzione_raw.get(scale_id_str, 0) + 1
            
        totale_valutazioni = sum(distribuzione_raw.values())
        distribuzione_scale = []
        for scale_id, count in distribuzione_raw.items():
            scala_nome = scale_names.get(scale_id) or scale_id or "Scala sconosciuta"
            distribuzione_scale.append({
                "scala_id": scale_id,
                "scala_nome": scala_nome,
                "count": count,
                "percentuale": round((count / totale_valutazioni * 100), 1) if totale_valutazioni > 0 else 0.0
            })
            
        # 7. Trend degli ultimi 6 mesi (BarChart dati delle somministrazioni mensili)
        trend_dati = []
        for i in range(5, -1, -1):
            offset_months = i
            target_year = now.year
            target_month = now.month - offset_months
            while target_month <= 0:
                target_month += 12
                target_year -= 1
                
            mesi_it = {
                1: "Gen", 2: "Feb", 3: "Mar", 4: "Apr", 5: "Mag", 6: "Giu",
                7: "Lug", 8: "Ago", 9: "Set", 10: "Ott", 11: "Nov", 12: "Dic"
            }
            nome_mese = f"{mesi_it[target_month]} {target_year}"
            
            # Filtra valutazioni fatte in questo anno/mese (escludendo orfane)
            count_mese = 0
            dettaglio_scale = {}
            for ev in evaluations:
                pat_id = ev.get("id_paziente")
                if not pat_id:
                    continue
                pat_id_str = str(pat_id)
                if pat_id_str not in active_patient_ids:
                    continue
                
                def get_date(ev_doc):
                    d = ev_doc.get("data_compilazione")
                    if isinstance(d, str):
                        try:
                            return datetime.fromisoformat(d.replace("Z", "+00:00"))
                        except ValueError:
                            return datetime.min.replace(tzinfo=timezone.utc)
                    if isinstance(d, datetime):
                        if d.tzinfo is None:
                            return d.replace(tzinfo=timezone.utc)
                        return d
                    return datetime.min.replace(tzinfo=timezone.utc)
                
                ev_date = get_date(ev)
                if ev_date.year == target_year and ev_date.month == target_month:
                    count_mese += 1
                    scale_id = ev.get("id_scala")
                    scale_id_str = str(scale_id) if scale_id else "unknown"
                    scala_nome = scale_names.get(scale_id_str) or scale_id_str or "Scala sconosciuta"
                    dettaglio_scale[scala_nome] = dettaglio_scale.get(scala_nome, 0) + 1
                    
            trend_dati.append({
                "mese": nome_mese,
                "anno": target_year,
                "num_mese": target_month,
                "count": count_mese,
                "dettaglio_scale": dettaglio_scale
            })
            
        return {
            "totale_utenze_attive": totale_pazienti,
            "totale_valutazioni_eseguite": totale_valutazioni,
            "copertura_scale": {
                "coperti_percentuale": round(copertura_percentuale, 1),
                "coperti_count": coperti_count,
                "scaduti_count": scaduti_count
            },
            "distribuzione_scale": distribuzione_scale,
            "trend_somministrazioni": trend_dati,
            "ultimi_alert": ultimi_alert
        }
    except Exception as e:
        import traceback
        tb_str = traceback.format_exc()
        print("CRITICAL ERROR in get_dashboard_stats:")
        print(tb_str)
        return {
            "totale_utenze_attive": 0,
            "totale_valutazioni_eseguite": 0,
            "copertura_scale": {
                "coperti_percentuale": 0.0,
                "coperti_count": 0,
                "scaduti_count": 0
            },
            "distribuzione_scale": [],
            "trend_somministrazioni": [],
            "ultimi_alert": [],
            "error_traceback": tb_str
        }


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
