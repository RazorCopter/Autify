from .audit import event as audit_event
"""Durable polling worker. Never replay an ambiguous provider call automatically."""
import asyncio
import base64
import hashlib
import logging
import uuid
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException
from .database import database as db
from .transactions import atomic, touch_patient
from .ai import AIAttachment
from .ai.adapters import get_ai_adapter
from .ai_context import digest, text_hash
from .version import APP_VERSION

logger = logging.getLogger("autify")
LEASE_SECONDS = 900
MAX_RUNNING = 2
MAX_PENDING = 200


async def queue_lock(session):
    await db.settings.update_one({"id": "global_settings"},
        {"$inc": {"job_queue_revision": 1}}, upsert=True, session=session)


async def enqueue(document):
    from .audit import correlation_id, record
    document["correlation_id"] = correlation_id.get()
    async def insert(session):
        await queue_lock(session)
        if await db.ai_jobs.count_documents({"status": "pending"}, session=session) >= MAX_PENDING:
            raise HTTPException(429, "Coda IA piena. Riprovare piu tardi.")
        await touch_patient(document["id_paziente"], session, active=True, expected_id=document.get("parent_mongo_id"))
        await db.ai_jobs.insert_one(dict(document), session=session)
        await record("RICHIESTA_ANALISI_IA", document["username"], "Job IA accodato", document["id"], session=session)
    await atomic(insert)


async def publish(job, *, report=None, provider=None, model=None, usage=None, error=None, expired=False):
    async def finish(session):
        now = datetime.now(timezone.utc)
        selector = {"id": job["id"], "status": "running", "lease_token": job.get("lease_token")}
        selector["lease_expires_at"] = {"$lte": now} if expired else {"$gt": now}
        if expired and not job.get("lease_expires_at"):
            selector["lease_expires_at"] = None
        current = await db.ai_jobs.find_one(selector, session=session)
        if not current:
            return
        # This write conflicts with deletion, enqueue and other child writers.
        parent_query = {"id": job.get("id_paziente")}
        if job.get("parent_mongo_id") is not None:
            parent_query["_id"] = job["parent_mongo_id"]
        parent = await db.patients.find_one(parent_query, session=session)
        if not parent:
            await db.ai_jobs.delete_one(selector, session=session)
            await db.notifications.delete_many({"job_id": job["id"]}, session=session)
            return
        await touch_patient(job["id_paziente"], session, expected_id=job.get("parent_mongo_id"))
        analysis_id = "an_" + job["id"]
        success = error is None
        if success:
            await db.ai_analyses.insert_one({
                "id": analysis_id, "job_id": job["id"], "id_paziente": job["id_paziente"],
                "timestamp": now, "report": report, "notes": "",
                "evaluations_used": job.get("evaluations_used", []),
                "provider": provider, "model": model, "usage": usage,
                "owner_username": job["username"],
                "provenance": job.get("provenance"), "execution": job.get("execution"),
                "review_status": "draft", "report_hash": text_hash(report),
            }, session=session)
        await db.ai_jobs.update_one(selector, {"$set": {
            "status": "completed" if success else "failed", "completed_at": now,
            "analysis_id": analysis_id if success else None, "error_message": error,
            "report_preview": report[:240] if success else None,
        }, "$unset": {"attachment": "", "user_prompt": "", "system_prompt": ""}}, session=session)
        await db.notifications.insert_one({
            "id": "nt_" + job["id"], "username": job["username"],
            "type": "ai_analysis_completed" if success else "ai_analysis_failed",
            "title": "Elaborazione IA completata" if success else "Elaborazione IA interrotta",
            "message": "Relazione disponibile" if success else error,
            "job_id": job["id"], "analysis_id": analysis_id if success else None,
            "id_paziente": job["id_paziente"], "patient_name": job.get("patient_name"),
            "read": False, "created_at": now,
        }, session=session)
        audit = audit_event("AI_ANALYSIS" if success else "AI_JOB_FAILED", job["username"], "Pubblicazione atomica job IA", job["id"])
        if job.get("correlation_id"):
            audit["correlation_id"] = job["correlation_id"]
        await db.audit_logs.insert_one(audit, session=session)
    await atomic(finish)


async def recover_expired():
    now = datetime.now(timezone.utc)
    async for job in db.ai_jobs.find({"status": "running", "$or": [
        {"lease_expires_at": {"$lte": now}}, {"lease_expires_at": None},
    ]}).limit(100):
        try:
            await publish(job, expired=True, error=(
                "Esecuzione interrotta o scaduta; esito provider non determinabile. "
                "Nessuna ripetizione automatica. Verificare prima di avviare una nuova analisi."))
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.warning("Recovery job %s rinviata; nessun replay provider", job.get("id"))


async def claim():
    token = str(uuid.uuid4())
    async def acquire(session):
        await queue_lock(session)
        if await db.ai_jobs.count_documents({"status": "running"}, session=session) >= MAX_RUNNING:
            return None
        now = datetime.now(timezone.utc)
        return await db.ai_jobs.find_one_and_update(
            {"status": "pending"}, {"$set": {"status": "running", "started_at": now,
            "lease_token": token, "lease_expires_at": now + timedelta(seconds=LEASE_SECONDS)}},
            sort=[("created_at", 1)], return_document=True, session=session)
    return await atomic(acquire)


async def process(job):
    from .routers.settings import get_or_migrate_ai_settings
    try:
        user = await db.users.find_one({"username": job["username"]})
        stored = await get_or_migrate_ai_settings()
        if (not user or user.get("must_change_password") or not user.get("ai_enabled")
                or user.get("token_version", 1) != job.get("owner_token_version")
                or (user.get("role") == "viewer" and not stored.viewer_ai_enabled)):
            raise HTTPException(403, "Autorizzazione cambiata prima dell'esecuzione")
        parent_query = {"id": job["id_paziente"], "attivo": {"$ne": False}}
        if job.get("parent_mongo_id") is not None:
            parent_query["_id"] = job["parent_mongo_id"]
        if not await db.patients.find_one(parent_query):
            raise HTTPException(409, "Utente archiviato o eliminato")
        # A timeout cannot prove that a billed request was not processed.
        stored.network.max_retries = 0
        if not job.get("provenance") or job["provenance"].get("status") != "canonical":
            raise HTTPException(409, "Job precedente al contratto canonico: richiedere una nuova analisi")
        if (text_hash(job["user_prompt"]) != job["provenance"].get("input_hash")
                or text_hash(job["system_prompt"]) != job["provenance"].get("system_prompt_hash")):
            raise HTTPException(409, "Contesto persistito non coerente con la provenienza")
        attachment_hash = hashlib.sha256(base64.b64decode(job["attachment"]["data_base64"], validate=True)).hexdigest() if job.get("attachment") else None
        if attachment_hash != job["provenance"].get("attachment_hash"):
            raise HTTPException(409, "Allegato persistito non coerente con la provenienza")
        config = getattr(stored, stored.active_provider)
        execution = {"app_version": APP_VERSION, "provider": stored.active_provider,
                     "requested_model": config.model, "protocol": getattr(config, "protocol", None),
                     "generation": stored.generation.model_dump(), "network": stored.network.model_dump(),
                     "endpoint_hash": digest(getattr(config, "base_url", stored.active_provider)),
                     "started_at": datetime.now(timezone.utc)}
        execution["configuration_hash"] = digest({k: v for k, v in execution.items() if k != "started_at"})
        recorded = await db.ai_jobs.update_one(
            {"id": job["id"], "status": "running", "lease_token": job["lease_token"],
             "lease_expires_at": {"$gt": datetime.now(timezone.utc)}},
            {"$set": {"execution": execution}})
        if not recorded.matched_count:
            return
        job["execution"] = execution
        adapter = get_ai_adapter(settings=stored)
        report, usage = await asyncio.wait_for(adapter.generate(
            system_prompt=job["system_prompt"], user_prompt=job["user_prompt"],
            attachment=AIAttachment.model_validate(job["attachment"]) if job.get("attachment") else None,
        ), timeout=650)
    except asyncio.CancelledError:
        # Leave running until lease recovery: never requeue a potentially sent request.
        raise
    except Exception:
        logger.warning("Job IA %s interrotto; dettagli provider non esposti", job["id"])
        await publish(job, error="Analisi non completata. Verificare l'esito prima di avviarne una nuova; nessun retry automatico.")
        return
    config = getattr(stored, stored.active_provider)
    # Keep persistence failures distinct from provider failures. An uncertain commit
    # is recovered by job status/lease, never by sending the provider request again.
    await publish(job, report=report, usage=usage, provider=stored.active_provider, model=config.model)


async def run_worker():
    while True:
        try:
            await recover_expired()
            job = await claim()
            if job:
                await process(job)
                continue
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.warning("Worker IA non disponibile; ripresa dal registro persistito al prossimo ciclo")
        await asyncio.sleep(2)


async def ensure_job_indexes():
    await db.ai_jobs.create_index("id", unique=True)
    await db.ai_jobs.create_index([("status", 1), ("created_at", 1)])
    await db.notifications.create_index("id", unique=True)
    await db.ai_analyses.create_index("id", unique=True)
    # Terminal jobs no longer need raw provider input; provenance hashes remain.
    await db.ai_jobs.update_many({"status": {"$in": ["completed", "failed"]}},
        {"$unset": {"attachment": "", "user_prompt": "", "system_prompt": ""}})
