"""Immutable scale context and strict validation shared by all evaluation writers."""
import copy
import hashlib
from datetime import datetime, timezone
from bson import json_util
from fastapi import HTTPException
from .database import database
from .transactions import atomic


def scale_snapshot(scale, provenance="original"):
    result = copy.deepcopy(scale)
    result.pop("_id", None)
    result.pop("write_revision", None)
    result.pop("snapshot_provenance", None)
    result.pop("snapshot_hash", None)
    digest = hashlib.sha256(json_util.dumps(result, sort_keys=True).encode()).hexdigest()
    result["snapshot_hash"] = digest
    result["snapshot_provenance"] = provenance
    return result


def question_contract(scale):
    sections = scale.get("sezioni") or scale.get("domini") or scale.get("sottoscale") or []
    aliases, questions = {}, {}
    sis = (
        scale.get("tipo_scala") == "sis"
        or "sis" in str(scale.get("id", "")).lower()
        or "sis" in str(scale.get("info", {}).get("id", "")).lower()
        or "sis" in str(scale.get("nome", "")).lower()
    )
    if sis and not scale.get("sezioni"):
        sections = list(sections)
        for key, code in (("sezione_2_protezione_tutela", "SEZ2"),
                          ("sezione_3_medica", "SEZ3M"), ("sezione_3_comportamentale", "SEZ3C")):
            raw = scale.get(key) or {}
            sections.append({"codice": code, "domande": [
                {
                    **q,
                    "codice": f"BC{q['id'][1:]}" if code == "SEZ3C" and q.get("id", "").startswith("C") and len(q.get("id", "")) > 1 and q.get("id")[1:].isdigit() else q.get("id"),
                    "id": f"BC{q['id'][1:]}" if code == "SEZ3C" and q.get("id", "").startswith("C") and len(q.get("id", "")) > 1 and q.get("id")[1:].isdigit() else q.get("id"),
                    "opzioni": [{"punteggio": v} for v in (0, 1, 2)] if code != "SEZ2" else [],
                }
                for q in raw.get("item", [])
            ]})
    for section in sections:
        section_code = section.get("codice_sezione") or section.get("codice", "")
        for q in section.get("domande", []):
            ident = q.get("codice") or q.get("id_domanda") or q.get("id")
            if not isinstance(ident, str) or not ident or ident in questions:
                raise ValueError("Identificativi domanda assenti o duplicati nel protocollo")
            questions[ident] = (q, sis and section_code in (*"ABCDEF", "SEZ2"))
            for alias in (ident, q.get("id_domanda"), q.get("codice"), q.get("id")):
                if alias:
                    if alias in aliases and aliases[alias] != ident:
                        raise ValueError("Alias domanda ambiguo")
                    aliases[alias] = ident
    if not questions:
        raise ValueError("Protocollo privo di domande")
    if sis:
        # Supported SIS form shipped in scale/Scala_SIS.json: 49 items A-F.
        core = {f"{code}{i}" for code, count in zip("ABCDEF", (8, 8, 9, 8, 8, 8)) for i in range(1, count + 1)}
        present_core = {ident for ident, (_, tridimensional) in questions.items()
                        if tridimensional and ident[0] in "ABCDEF"}
        if present_core != core:
            raise ValueError("Protocollo SIS incompleto rispetto ai 49 item A-F supportati")
    return aliases, questions


def validate_answers(answers, scale, *, complete=True):
    aliases, questions = question_contract(scale)
    seen, normalized = set(), []
    for answer in answers:
        ident = aliases.get(answer.get("codice_domanda"))
        if ident is None or ident in seen:
            raise ValueError("Domanda sconosciuta o risposta duplicata")
        seen.add(ident)
        question, tridimensional = questions[ident]
        score = answer.get("punteggio")
        if tridimensional:
            if (not isinstance(score, dict) or set(score) != {"F", "D", "T"}
                    or any(type(v) is not int or not 0 <= v <= 4 for v in score.values())):
                raise ValueError(f"{ident}: attesi F/D/T interi tra 0 e 4")
            if ident == "A3" and score["F"] > 3:
                raise ValueError("A3: frequenza massima 3 nel protocollo SIS supportato")
        else:
            if type(score) is not int:
                raise ValueError(f"{ident}: atteso punteggio intero")
            if question.get("tipo") == "composito":
                parts = question.get("sottodomande")
                if not isinstance(parts, list) or not parts or not 0 <= score <= len(parts):
                    raise ValueError(f"{ident}: conteggio composito non valido")
            else:
                allowed = {o["punteggio"] for o in question.get("opzioni", []) if type(o.get("punteggio")) is int}
                if not allowed or score not in allowed:
                    raise ValueError(f"{ident}: punteggio non previsto dal protocollo")
        normalized.append({**answer, "codice_domanda": ident})
    if complete and seen != set(questions):
        raise ValueError(f"Valutazione incompleta: {len(seen)} risposte su {len(questions)}")
    return normalized


def incomplete_analysis(answers, scale):
    try:
        validate_answers(answers, scale)
    except (ValueError, TypeError, KeyError, AttributeError) as exc:
        return {"domini": [], "scala_nome": scale.get("nome", ""),
                "indice_qv": None, "indice_sis": None, "percentile": None,
                "somma_punteggi_standard": None, "validation_status": "invalid_or_incomplete",
                "validation_message": str(exc)}
    return None


def require_answers(answers, scale):
    try:
        return validate_answers(answers, scale)
    except (ValueError, TypeError, KeyError, AttributeError) as exc:
        raise HTTPException(422, str(exc)) from exc


async def resolve_scale(evaluation):
    snapshot = evaluation.get("snapshot_scala")
    if isinstance(snapshot, dict) and (snapshot.get("sezioni") or snapshot.get("domini") or snapshot.get("sottoscale")):
        return copy.deepcopy(snapshot)
    if snapshot:
        raise HTTPException(409, "Snapshot storico malformato: richiede recupero esplicito.")
    # Freeze a legacy fallback once, serialized with scale replacement/deletion.
    async def freeze(session):
        scale = await database.scales.find_one({"id": evaluation["id_scala"]}, session=session)
        if not scale:
            raise HTTPException(409, "Snapshot storico assente e protocollo non disponibile: recuperare un archivio originale.")
        await database.scales.update_one({"_id": scale["_id"]}, {"$inc": {"write_revision": 1}}, session=session)
        selector = {"_id": evaluation["_id"]}
        current = await database.evaluations.find_one(selector, session=session)
        if not current:
            raise HTTPException(404, "Valutazione non trovata")
        if current.get("snapshot_scala"):
            return current["snapshot_scala"]
        result = scale_snapshot(scale, "legacy_current_not_original")
        await database.evaluations.update_one(selector, {"$set": {"snapshot_scala": result}}, session=session)
        from .audit import record
        await record("RICOSTRUZIONE_SNAPSHOT_LEGACY", "sistema", "Congelato protocollo corrente; versione originale non attestata", str(evaluation.get("id_valutazione", evaluation["_id"])),
                     session=session, target_version=result["snapshot_hash"])
        return result
    return await atomic(freeze)


async def save_scale(scale_id, replacement, *, actor=None, action="MODIFICA_SCALA"):
    from .audit import record
    """Freeze unsnapshotted legacy records before changing their only reference."""
    async def save(session):
        current = await database.scales.find_one({"id": scale_id}, session=session)
        if current:
            await database.evaluations.update_many(
                {"id_scala": scale_id, "$or": [{"snapshot_scala": None}, {"snapshot_scala": {}}]},
                {"$set": {"snapshot_scala": scale_snapshot(current, "legacy_current_not_original")}}, session=session)
        if replacement is None:
            if not current:
                raise HTTPException(404, "Protocollo non trovato")
            await database.scales.delete_one({"id": scale_id}, session=session)
        else:
            question_contract(replacement)
            await database.scales.replace_one({"id": scale_id}, replacement, upsert=True, session=session)
        if actor:
            await record(action, actor, "Protocollo e snapshot storici aggiornati atomicamente", scale_id,
                         session=session, target_version=scale_snapshot(replacement)["snapshot_hash"] if replacement else None)
    try:
        await atomic(save)
    except (ValueError, TypeError, KeyError, AttributeError) as exc:
        raise HTTPException(422, "Protocollo non valido: " + str(exc)) from exc
