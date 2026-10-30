"""Audit events: transactional when requested, explicit degradation for legacy post-commit calls."""
import contextvars
import logging
import uuid
from datetime import datetime, timezone
from fastapi import HTTPException
from pymongo.errors import PyMongoError
from .database import database
from .version import APP_VERSION

correlation_id = contextvars.ContextVar("audit_correlation_id", default=None)
audit_degraded = contextvars.ContextVar("audit_degraded", default=False)


def event(action, actor, details=None, target_id=None, *, target_version=None):
    return {"event_id": str(uuid.uuid4()), "schema_version": 1,
            "azione": action, "operatore": actor, "target_id": target_id,
            "dettagli": str(details)[:512] if details else None,
            "timestamp": datetime.now(timezone.utc), "app_version": APP_VERSION,
            "correlation_id": correlation_id.get() or str(uuid.uuid4()),
            "target_version": target_version}


async def record(action, actor, details=None, target_id=None, *, session=None, target_version=None, db=None):
    try:
        await (db if db is not None else database).audit_logs.insert_one(
            event(action, actor, details, target_id, target_version=target_version), session=session)
    except PyMongoError as exc:
        # The surrounding transaction rolls back the domain write.
        raise HTTPException(503, "Registro audit non disponibile: operazione non confermata") from exc


async def post_commit(action, actor, details=None, target_id=None):
    try:
        await record(action, actor, details, target_id)
        return True
    except Exception:
        audit_degraded.set(True)
        logging.getLogger("autify").error("Audit post-commit non disponibile; correlation_id=%s azione=%s", correlation_id.get(), action)
        # Never turn an already committed mutation into a retryable HTTP failure.
        return False


class AuditContextMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        identifier = str(uuid.uuid4())  # Do not trust user-supplied identifiers in the log.
        token = correlation_id.set(identifier)
        degraded_token = audit_degraded.set(False)
        async def audit_send(message):
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", [])) + [(b"x-correlation-id", identifier.encode()),
                    (b"x-audit-status", b"degraded" if audit_degraded.get() else b"ok")]
                message = {**message, "headers": headers}
            await send(message)
        try:
            await self.app(scope, receive, audit_send)
        finally:
            correlation_id.reset(token)
            audit_degraded.reset(degraded_token)


async def ensure_indexes():
    await database.audit_logs.create_index([("timestamp", -1), ("_id", -1)], name="audit_chronology")
    await database.audit_logs.create_index("correlation_id", name="audit_correlation")
