from fastapi import HTTPException
import uuid
from .models import Scale, Section, Question, Option
from .evaluation_contract import save_scale

async def _import_sis_scale(scala_data: dict, scale_id: str, nome: str, descrizione: str, *, actor=None) -> dict:
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
        if key not in {"id", "nome", "descrizione", "domini", "sezioni", "_id", "write_revision"}
    }
    scale_dict.update(extra_metadata)
    scale_dict["tipo_scala"] = "sis"

    await save_scale(scale_id, scale_dict, actor=actor, action="IMPORT_SCALA")

    total_questions = sum(len(s.domande) for s in sezioni)
    return {
        "message": "Scala SIS importata con successo",
        "id": scale_id,
        "nome": nome,
        "sezioni": len(sezioni),
        "domande_totali": total_questions,
        "tipo": "SIS (Supports Intensity Scale)",
    }


