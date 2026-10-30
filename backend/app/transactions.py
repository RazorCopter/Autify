"""Shared transaction boundary for data integrity operations."""
from fastapi import HTTPException
from pymongo import ReadPreference
from pymongo.read_concern import ReadConcern
from pymongo.write_concern import WriteConcern
from .database import database


async def atomic(callback):
    hello = await database.command("hello")
    if not hello.get("setName") or not hello.get("isWritablePrimary"):
        raise HTTPException(503, "Operazione richiede MongoDB replica set disponibile.")
    async with await database.client.start_session() as session:
        return await session.with_transaction(
            callback, read_concern=ReadConcern("snapshot"),
            write_concern=WriteConcern("majority"), read_preference=ReadPreference.PRIMARY,
        )


async def touch_patient(patient_id, session, *, active=False, expected_id=None):
    query = {"id": patient_id}
    if expected_id is not None:
        query["_id"] = expected_id
    if active:
        query["attivo"] = {"$ne": False}
    result = await database.patients.update_one(
        query, {"$inc": {"write_revision": 1}}, session=session)
    if not result.matched_count:
        raise HTTPException(409, "Utente non disponibile per questa operazione.")
