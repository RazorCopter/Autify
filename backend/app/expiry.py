"""Shared, read-only expiry projection; legacy dates are normalized without rewriting data."""
import calendar
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from fastapi import HTTPException
from .database import database
from .evaluation_contract import validate_answers

KINDS = ("pos", "san_martin", "sis", "ogva", "sabs", "oso")
DEFAULT_MONTHS = dict(zip(KINDS, (12, 12, 36, 12, 12, 12)))
ROME = ZoneInfo("Europe/Rome")


def utc_date(value):
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            for fmt in ("%d/%m/%Y", "%d-%m-%Y", "%Y/%m/%d"):
                try:
                    value = datetime.strptime(value, fmt)
                    break
                except ValueError:
                    continue
            else:
                return None
    if not isinstance(value, datetime):
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def policy_from(doc):
    configured = doc.get("scale_validity_months", {})
    required = doc.get("required_scale_types", ["pos", "san_martin", "sis"])
    warning = doc.get("expiry_warning_days", 30)
    if not isinstance(configured, dict):
        raise HTTPException(422, "Mesi di validita non validi")
    months = {**DEFAULT_MONTHS, **configured}
    if (set(months) != set(KINDS) or any(type(v) is not int or not 1 <= v <= 120 for v in months.values())
            or not isinstance(required, list) or not required or any(not isinstance(k, str) or k not in KINDS for k in required)
            or len(set(required)) != len(required)
            or type(warning) is not int or not 0 <= warning <= 365):
        raise HTTPException(422, "Policy scadenze non valida: correggere le impostazioni server")
    return {"scale_validity_months": months, "required_scale_types": required,
            "expiry_warning_days": warning, "timezone": "Europe/Rome"}


async def load_policy():
    return policy_from(await database.settings.find_one({"id": "global_settings"}) or {})


def expiry_day(value, months):
    local = value.astimezone(ROME).date()
    year, month = divmod(local.year * 12 + local.month - 1 + months, 12)
    return local.replace(year=year, month=month + 1, day=min(local.day, calendar.monthrange(year, month + 1)[1]))


async def project(patients, now=None):
    """One projection for list, KPI and badges. No implicit legacy snapshot writes."""
    from .routers._helpers import _classify_scale
    now = now or datetime.now(timezone.utc)
    today = now.astimezone(ROME).date()
    policy = await load_policy()
    scales = {}
    async for scale in database.scales.find({}):
        for key in (scale.get("id"), scale.get("_id")):
            if key is not None:
                scales[str(key)] = scale
    owners = {}
    for patient in patients:
        for key in (patient.get("id"), patient.get("_id")):
            if key is not None:
                owners[str(key)] = patient["id"]
    latest, counts = {}, {}
    # Batch identifiers to avoid oversized Mongo $in requests; consume every cursor.
    keys = list(owners)
    for offset in range(0, len(keys), 500):
        async for ev in database.evaluations.find({"id_paziente": {"$in": keys[offset:offset + 500]}}):
            pid = owners[str(ev["id_paziente"])]
            counts[pid] = counts.get(pid, 0) + 1
            snapshot = ev.get("snapshot_scala")
            scale = snapshot if isinstance(snapshot, dict) and snapshot else scales.get(str(ev.get("id_scala")), {})
            kind = _classify_scale(str(scale.get("nome", "")).lower(), str(ev.get("id_scala", "")))
            if kind not in KINDS:
                continue
            date = utc_date(ev.get("data_compilazione"))
            try:
                validate_answers(ev.get("risposte", []), scale)
                complete = bool(date) and date <= now
            except (ValueError, TypeError, KeyError, AttributeError):
                complete = False
            # Unparseable dates must be surfaced, never hidden behind an older valid row.
            rank = (date or datetime.max.replace(tzinfo=timezone.utc), str(ev.get("_id", "")))
            if (pid, kind) not in latest or rank > latest[pid, kind][0]:
                latest[pid, kind] = (rank, date, complete, bool(snapshot))
    for patient in patients:
        states = {}
        for kind in KINDS:
            item = latest.get((patient["id"], kind))
            date = item[1] if item else None
            due = expiry_day(date, policy["scale_validity_months"][kind]) if date and item[2] else None
            days = (due - today).days if due else None
            state = ("mancante" if not item else "incompleta" if not item[2] else
                     "scaduta" if days < 0 else "in_scadenza" if days <= policy["expiry_warning_days"] else "valida")
            states[kind] = {"stato": state, "data": date.isoformat() if date else None,
                            "scadenza": due.isoformat() if due else None, "giorni_residui": days,
                            "validity_months": policy["scale_validity_months"][kind],
                            "provenienza": "snapshot" if item and item[3] else "catalogo_corrente_legacy"}
            patient[f"ultimo_{kind}_compilato"] = date.isoformat() if date else None
        required_states = [states[k]["stato"] for k in policy["required_scale_types"]]
        patient["stato_valutazioni"] = (
            "mai_valutati" if not counts.get(patient["id"]) else
            "incompleti" if any(s in ("mancante", "incompleta") for s in required_states) else
            "scaduti" if "scaduta" in required_states else
            "in_scadenza" if "in_scadenza" in required_states else "coperti")
        patient["stato_scale"] = states
        patient["scadenze_calcolate_al"] = now.isoformat()
    return policy
