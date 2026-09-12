import logging
from fastapi import APIRouter, HTTPException, status, UploadFile, File, Header, Depends, Request, Query
from slowapi import Limiter
from slowapi.util import get_remote_address
from fastapi.responses import StreamingResponse

_limiter = Limiter(key_func=get_remote_address)
_logger = logging.getLogger("autify")
from typing import List, Optional
from bson import ObjectId
import httpx
from ..models import Scale, Evaluation, Patient, PaginatedPatients, AppSettings, Section, Question, Option, DOMINI_POS, AggregatedEvaluation, EvaluationUpdateRequest, AiAnalysis, AiAnalysisCreate, AiAnalysisUpdate, AiAnalysisRequest, AiPdfRequest, UserCreate, UserUpdate, AuditLogCreate, AuditLogResponse
from ..database import evaluations_collection, settings_collection, patients_collection, scales_collection, users_collection, ai_analyses_collection, audit_logs_collection
from ..pdf_generator import generate_evaluation_pdf, generate_ai_analysis_pdf
from ..analytics import compute_psychometric_analysis, compute_direct_scores, build_domain_map, calcola_punteggi_sis
from datetime import datetime, timezone, timedelta
import json
import re
from pydantic import BaseModel
import uuid
import io
import os
import asyncio
from pathlib import Path
from .. import auth as auth_module
from . import _invalidate_dashboard_cache

from ._helpers import (
    verify_auth,
    log_audit,
    _find_evaluation_document,
    _extract_evaluation_identifier,
    _build_evaluation_selector,
    _hydrate_scale_doc,
    _update_patient_scale_dates,
)

admin_router = APIRouter(dependencies=[Depends(verify_auth)])
public_admin_router = APIRouter()
client_router = APIRouter(dependencies=[Depends(verify_auth)])


# ==========================================
# ADMIN ROUTER (/api/admin)
# ==========================================

@admin_router.get("/evaluations/{id_patient}", response_model=List[Evaluation], tags=["Admin - Evaluations"])
async def get_evaluations(id_patient: str):
    """Storico completo per un utente, per fini analitici."""
    cursor = evaluations_collection.find({"id_paziente": id_patient})
    evaluations = await cursor.to_list(length=1000)
    return evaluations

async def _import_sis_scale(scala_data: dict, scale_id: str, nome: str, descrizione: str) -> dict:
    """
    Importa una scala SIS con la sua struttura specializzata.

    La scala SIS ha un formato diverso dalle scale standard (POS, San Martín):
    - Usa 'sottoscale' invece di 'domini'
    - Ogni item ha risposta tridimensionale (F, D, T) invece di opzioni multiple
    - Include sezioni supplementari (protezione, medica, comportamentale)
    - Include tabelle di conversione specifiche
    """
    info = scala_data.get("info", {})
    if info:
        scale_id = info.get("id", scale_id)
        nome = info.get("nome", nome)
        descrizione = info.get("sottotitolo", descrizione)

    sezioni: list[Section] = []

    # Sottoscale A-F → sezioni con domande (senza opzioni, dato che la risposta è F/D/T)
    for sottoscala in scala_data.get("sottoscale", []):
        codice = sottoscala.get("codice", "")
        nome_sez = sottoscala.get("nome", codice)
        domande: list[Question] = []
        for d in sottoscala.get("domande", []):
            domande.append(Question(
                id_domanda=d.get("id", f"q_{uuid.uuid4().hex[:8]}"),
                codice=d.get("id"),
                testo_domanda=d.get("testo", ""),
                note=d.get("note"),
                opzioni=[],
            ))
        sezioni.append(Section(
            codice_sezione=codice,
            titolo_sezione=nome_sez,
            descrizione_sezione=None,
            domande=domande,
        ))

    # Sezione 2: Protezione e tutela
    sez2 = scala_data.get("sezione_2_protezione_tutela", {})
    if sez2 and sez2.get("item"):
        domande_sez2: list[Question] = []
        for item in sez2["item"]:
            domande_sez2.append(Question(
                id_domanda=item.get("id", f"q_{uuid.uuid4().hex[:8]}"),
                codice=item.get("id"),
                testo_domanda=item.get("testo", ""),
                opzioni=[],
            ))
        sezioni.append(Section(
            codice_sezione="SEZ2",
            titolo_sezione=sez2.get("titolo", "Scala supplementare di protezione e tutela legale"),
            descrizione_sezione=sez2.get("note"),
            domande=domande_sez2,
        ))

    # Sezione 3 Medica
    sez3m = scala_data.get("sezione_3_medica", {})
    if sez3m and sez3m.get("item"):
        domande_med: list[Question] = []
        for item in sez3m["item"]:
            domande_med.append(Question(
                id_domanda=item.get("id", f"q_{uuid.uuid4().hex[:8]}"),
                codice=item.get("id"),
                testo_domanda=item.get("testo", ""),
                opzioni=[
                    Option(punteggio=0, testo_risposta="Assente"),
                    Option(punteggio=1, testo_risposta="Parziale"),
                    Option(punteggio=2, testo_risposta="Estensivo"),
                ],
            ))
        sezioni.append(Section(
            codice_sezione="SEZ3M",
            titolo_sezione=sez3m.get("titolo", "Bisogni di sostegno non ordinari di tipo medico"),
            descrizione_sezione=sez3m.get("note"),
            domande=domande_med,
        ))

    # Sezione 3 Comportamentale
    sez3c = scala_data.get("sezione_3_comportamentale", {})
    if sez3c and sez3c.get("item"):
        domande_comp: list[Question] = []
        for item in sez3c["item"]:
            domande_comp.append(Question(
                id_domanda=item.get("id", f"q_{uuid.uuid4().hex[:8]}"),
                codice=item.get("id"),
                testo_domanda=item.get("testo", ""),
                opzioni=[
                    Option(punteggio=0, testo_risposta="Assente"),
                    Option(punteggio=1, testo_risposta="Parziale"),
                    Option(punteggio=2, testo_risposta="Estensivo"),
                ],
            ))
        sezioni.append(Section(
            codice_sezione="SEZ3C",
            titolo_sezione=sez3c.get("titolo", "Bisogni di sostegno non ordinari di tipo comportamentale"),
            descrizione_sezione=sez3c.get("note"),
            domande=domande_comp,
        ))

    if not sezioni:
        raise HTTPException(status_code=422, detail="Il JSON SIS non contiene sottoscale o sezioni")

    scale = Scale(id=scale_id, nome=nome, descrizione=descrizione, sezioni=sezioni)
    scale_dict = scale.model_dump()

    # Preserva TUTTI i metadati extra del JSON SIS per il motore di calcolo
    extra_metadata = {
        key: value
        for key, value in scala_data.items()
        if key not in {"id", "nome", "descrizione", "domini"}
    }
    scale_dict.update(extra_metadata)
    scale_dict["tipo_scala"] = "sis"

    await scales_collection.replace_one({"id": scale_id}, scale_dict, upsert=True)

    total_questions = sum(len(s.domande) for s in sezioni)
    return {
        "message": "Scala SIS importata con successo",
        "id": scale_id,
        "nome": nome,
        "sezioni": len(sezioni),
        "domande_totali": total_questions,
        "tipo": "SIS (Supports Intensity Scale)",
    }


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
    domains = compute_direct_scores(eval_doc.get("risposte", []), domain_map, scale_doc)

    pdf_bytes = await asyncio.to_thread(
        generate_evaluation_pdf,
        eval_doc,
        patient_doc or {},
        scale_doc or {},
        domains,
        analysis,
    )

    filename = f"valutazione_{evaluation_id[:8]}.pdf"
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
@admin_router.post("/evaluations/ai-analysis-pdf", tags=["Admin - Evaluations"])
async def download_ai_analysis_pdf(request: AiPdfRequest):
    pdf_bytes = await asyncio.to_thread(generate_ai_analysis_pdf, request.patient, request.report)
    filename = f"analisi_ai_{request.patient.get('cognome', 'paziente')}.pdf"
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
    """Recupera lo storico valutazioni per utente+scala ordinato per data decrescente."""
    cursor = evaluations_collection.find(
        {"id_paziente": patient_id, "id_scala": scale_id}
    ).sort("data_compilazione", -1)
    eval_docs = await cursor.to_list(length=1000)
    if not eval_docs:
        raise HTTPException(status_code=404, detail="Nessuna valutazione trovata")

    # Carica tutte le scale usate in una sola query invece di N find_one (P-03)
    scale_ids_needed = list({e["id_scala"] for e in eval_docs if e.get("id_scala")})
    raw_scales = await scales_collection.find({"id": {"$in": scale_ids_needed}}).to_list(length=None)
    _scale_cache: dict = {s["id"]: _hydrate_scale_doc(s) for s in raw_scales if s.get("id")}

    history = []
    for eval_doc in eval_docs:
        scale_doc = _scale_cache.get(eval_doc.get("id_scala"))
        domain_map = build_domain_map(scale_doc or {})
        if not domain_map:
            domain_map = DOMINI_POS
        domains = compute_direct_scores(eval_doc.get("risposte", []), domain_map, scale_doc=scale_doc)
        history.append(
            AggregatedEvaluation(
                id_valutazione=_extract_evaluation_identifier(eval_doc),
                id_paziente=eval_doc["id_paziente"],
                id_scala=eval_doc["id_scala"],
                anno=eval_doc["anno"],
                data_compilazione=(
                    eval_doc["data_compilazione"].replace(tzinfo=timezone.utc)
                    if isinstance(eval_doc["data_compilazione"], datetime) and eval_doc["data_compilazione"].tzinfo is None
                    else eval_doc["data_compilazione"]
                ),
                nome_operatore=eval_doc["nome_operatore"],
                nome_intervistato=eval_doc.get("nome_intervistato"),
                demographics=eval_doc.get("demographics"),
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
    update_data = {"risposte": new_risposte}
    if payload.nome_operatore is not None:
        update_data["nome_operatore"] = payload.nome_operatore
        existing["nome_operatore"] = payload.nome_operatore
    if payload.nome_intervistato is not None:
        update_data["nome_intervistato"] = payload.nome_intervistato
        existing["nome_intervistato"] = payload.nome_intervistato
    if payload.demographics is not None:
        update_data["demographics"] = payload.demographics
        existing["demographics"] = payload.demographics
        
    await evaluations_collection.update_one(
        _build_evaluation_selector(existing),
        {"$set": update_data}
    )
    existing["risposte"] = new_risposte
    scale_doc = _hydrate_scale_doc(
        await scales_collection.find_one({"id": existing["id_scala"]})
    )
    domain_map = build_domain_map(scale_doc or {})
    if not domain_map:
        domain_map = DOMINI_POS
    domains = compute_direct_scores(new_risposte, domain_map, scale_doc=scale_doc)
    return AggregatedEvaluation(
        id_valutazione=_extract_evaluation_identifier(existing),
        id_paziente=existing["id_paziente"],
        id_scala=existing["id_scala"],
        anno=existing["anno"],
        data_compilazione=existing["data_compilazione"],
        nome_operatore=existing["nome_operatore"],
        nome_intervistato=existing.get("nome_intervistato"),
        demographics=existing.get("demographics"),
        domini=domains,
        risposte=new_risposte,
    )

@admin_router.delete("/evaluations/{evaluation_id}", tags=["Admin - Evaluations"])
async def delete_evaluation(evaluation_id: str):
    """Elimina definitivamente una singola valutazione dal database."""
    eval_doc = await _find_evaluation_document(evaluation_id)
    if not eval_doc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Valutazione non trovata")

    patient_id = eval_doc.get("id_paziente")
    selector = _build_evaluation_selector(eval_doc)
    result = await evaluations_collection.delete_one(selector)
    if result.deleted_count == 0:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Errore nell'eliminazione della valutazione")
    _invalidate_dashboard_cache()

    if patient_id:
        await _update_patient_scale_dates(patient_id)

    return {"status": "success", "message": "Valutazione eliminata con successo"}


# ==========================================
# CLIENT ROUTER (/api/client)
# ==========================================

@client_router.post("/evaluations", response_model=Evaluation, status_code=status.HTTP_201_CREATED, tags=["Client - Evaluations"])
@_limiter.limit("20/minute")
async def create_evaluation(request: Request, evaluation: Evaluation, auth_context: dict = Depends(verify_auth)):
    """Salva una nuova valutazione compilata nel database dopo aver validato paziente, scala e risposte."""
    # 1. Validazione esistenza utente (SCORE-01, Task 10.1)
    id_paziente = evaluation.id_paziente
    patient_doc = await patients_collection.find_one({"id": id_paziente})
    if not patient_doc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Utente con ID '{id_paziente}' non trovato"
        )

    # 2. Validazione esistenza scala (SCORE-01, Task 10.1)
    id_scala = evaluation.id_scala
    scale_doc = await scales_collection.find_one({"id": id_scala})
    if not scale_doc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Scala con ID '{id_scala}' non trovata"
        )

    # 3. Validazione risposte e punteggi rispetto alla definizione della scala (SCORE-01, Task 10.1)
    valid_question_ids = set()
    allowed_scores_by_question = {}
    for section in scale_doc.get("sezioni", []):
        for q in section.get("domande", []):
            qid = q.get("id_domanda")
            qcode = q.get("codice")
            options = q.get("opzioni", [])
            allowed_scores = {opt["punteggio"] for opt in options if "punteggio" in opt}
            if qid:
                valid_question_ids.add(qid)
                if allowed_scores:
                    allowed_scores_by_question[qid] = allowed_scores
            if qcode:
                valid_question_ids.add(qcode)
                if allowed_scores:
                    allowed_scores_by_question[qcode] = allowed_scores

    if valid_question_ids and evaluation.risposte:
        for ans in evaluation.risposte:
            if ans.codice_domanda not in valid_question_ids:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail=f"La domanda '{ans.codice_domanda}' non appartiene alla scala '{id_scala}'"
                )

            # Validazione punteggio SIS tridimensionale
            if isinstance(ans.punteggio, dict):
                for dim in ("F", "D", "T"):
                    val = ans.punteggio.get(dim)
                    if val is None or not isinstance(val, int) or val < 0 or val > 4:
                        raise HTTPException(
                            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                            detail=f"Punteggio SIS non valido per dimensione {dim} nella domanda '{ans.codice_domanda}': atteso intero 0-4"
                        )
            elif isinstance(ans.punteggio, int):
                allowed = allowed_scores_by_question.get(ans.codice_domanda)
                if allowed and ans.punteggio not in allowed:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail=f"Punteggio {ans.punteggio} non valido per la domanda '{ans.codice_domanda}'. Punteggi ammessi: {sorted(allowed)}"
                    )

    eval_dict = evaluation.model_dump()
    if not eval_dict.get("data_compilazione"):
        eval_dict["data_compilazione"] = datetime.now(timezone.utc)
    # Imposta l'operatore autenticato dal token JWT
    operatore_autenticato = auth_context.get("username") or "Operatore Sconosciuto"
    eval_dict["nome_operatore"] = operatore_autenticato
    
    # DATA-02: Snapshot Scala
    scale_snapshot = dict(scale_doc)
    scale_snapshot.pop("_id", None)
    eval_dict["snapshot_scala"] = scale_snapshot
    evaluation = Evaluation(**eval_dict)
    result = await evaluations_collection.insert_one(eval_dict)

    if not result.inserted_id:
        raise HTTPException(status_code=500, detail="Errore nel salvataggio della valutazione")
    _invalidate_dashboard_cache()

    # Mantiene aggiornati i campi ultimo_*_compilato sul paziente (FUN-01, Task 8.2)
    await _update_patient_scale_dates(id_paziente)
        
    # Salva il log di audit con l'operatore autenticato
    operatore = operatore_autenticato
    utente_info = ""
    cognome = patient_doc.get("cognome", "")
    nome = patient_doc.get("nome", "")
    if cognome or nome:
        utente_info = f" per {cognome} {nome}"
                
    await log_audit(
        "COMPILAZIONE_SCALA", 
        operatore, 
        f"{operatore} ha compilato la Scala {id_scala}{utente_info}".strip(), 
        id_paziente
    )
        
    return evaluation

