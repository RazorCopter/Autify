from .audit import event as audit_event
"""Versioned backups and atomic restore. Never fall back to destructive standalone writes."""
import copy
import hashlib
import json
import os
import re
import uuid
from datetime import datetime, timezone

from bson import BSON, json_util
from bson.errors import InvalidDocument
from bson.json_util import CANONICAL_JSON_OPTIONS
from cryptography.fernet import InvalidToken
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi import HTTPException
from pydantic import ValidationError
from pymongo import ReadPreference
from pymongo.errors import ConnectionFailure, PyMongoError
from pymongo.read_concern import ReadConcern
from pymongo.write_concern import WriteConcern

from .ai.crypto import decrypt_secret, SecretConfigurationError, SecretDecryptionError
from .ai.models import AISettingsStored
from .database import BACKUP_COLLECTIONS
from .models import Patient, Evaluation, Scale, AiAnalysis
from .version import APP_VERSION

MAGIC = b"AUTIFY-BACKUP-2\n"
MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
MAX_PAYLOAD_BYTES = MAX_ARCHIVE_BYTES - 4096
LEGACY_COLLECTIONS = set(BACKUP_COLLECTIONS) - {"ai_jobs", "notifications"}
DATE_FIELDS = {
    "evaluations": ("data_compilazione",),
    "users": ("created_at", "updated_at"),
    "ai_analyses": ("timestamp", "reviewed_at"),
    "ai_jobs": ("created_at", "started_at", "completed_at", "lease_expires_at"),
    "notifications": ("created_at", "read_at"),
    "audit_logs": ("timestamp",),
    "licenses": ("activated_at", "expires_at", "last_validated_at", "created_at", "updated_at"),
}


def invalid(message):
    raise HTTPException(422, message)


def _key(secret):
    if not isinstance(secret, str) or len(secret) < 32:
        raise HTTPException(503, "Configurare una BACKUP_ENCRYPTION_KEY di almeno 32 caratteri.")
    return hashlib.sha256(b"autify-backup-v2:" + secret.encode()).digest()


def _key_id(key):
    return hashlib.sha256(key).hexdigest()[:16]


def encrypt_backup(payload):
    key = _key(os.getenv("BACKUP_ENCRYPTION_KEY", ""))
    header = MAGIC + _key_id(key).encode("ascii")
    nonce = os.urandom(12)
    result = header + nonce + AESGCM(key).encrypt(nonce, payload, header)
    if len(result) > MAX_ARCHIVE_BYTES:
        raise HTTPException(413, "Backup oltre il limite di 64 MiB; usare la procedura MongoDB per archivi grandi.")
    return result


def decrypt_backup(data):
    try:
        if data.startswith(MAGIC):
            header_size = len(MAGIC) + 16
            header, nonce, ciphertext = data[:header_size], data[header_size:header_size+12], data[header_size+12:]
            previous = json.loads(os.getenv("BACKUP_PREVIOUS_KEYS", "[]"))
            if not isinstance(previous, list):
                raise ValueError("invalid keyring")
            secrets = [os.getenv("BACKUP_ENCRYPTION_KEY", "")] + previous
            for secret in secrets:
                if not isinstance(secret, str) or len(secret) < 32:
                    continue
                key = _key(secret)
                if header[len(MAGIC):] == _key_id(key).encode("ascii"):
                    return AESGCM(key).decrypt(nonce, ciphertext, header)
        else:
            # Legacy nonce+ciphertext, encrypted with SHA256(JWT_SECRET_KEY).
            previous = json.loads(os.getenv("LEGACY_BACKUP_JWT_SECRETS", "[]"))
            if not isinstance(previous, list):
                raise ValueError("invalid legacy keyring")
            for secret in [os.getenv("JWT_SECRET_KEY", "")] + previous:
                if not isinstance(secret, str) or not secret:
                    continue
                try:
                    return AESGCM(hashlib.sha256(secret.encode()).digest()).decrypt(data[:12], data[12:], None)
                except Exception:
                    continue
    except Exception:
        pass
    raise HTTPException(422, "Backup corrotto o chiave non disponibile. Conservare la chiave originale nel keyring di ripristino.")


def encode_document(document):
    return json_util.dumps(document, json_options=CANONICAL_JSON_OPTIONS, ensure_ascii=False).encode("utf-8")


def _no_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def decode_document(payload):
    if len(payload) > MAX_PAYLOAD_BYTES:
        raise HTTPException(413, "Il contenuto del backup supera il limite supportato di 64 MiB.")
    try:
        raw = json.loads(payload.decode("utf-8-sig"), object_pairs_hook=_no_duplicate_keys)
        if not isinstance(raw, dict):
            invalid("Il backup deve essere un oggetto JSON.")
        # Reject ambiguous duplicate keys before Extended JSON converts BSON values.
        document = json_util.loads(json.dumps(raw), json_options=CANONICAL_JSON_OPTIONS)
    except (ValueError, TypeError, KeyError, OverflowError, RecursionError):
        invalid("JSON/BSON non valido o ambiguo.")
    return validate_document(document)


def validate_document(document):
    if not isinstance(document, dict):
        invalid("Il backup deve essere un oggetto JSON.")
    document = copy.deepcopy(document)
    meta = document.get("metadata")
    if not isinstance(meta, dict) or not isinstance(meta.get("version"), str):
        invalid("Metadata/versione backup mancanti.")
    schema = meta.get("schema_version", 1)
    if type(schema) is not int or schema not in (1, 2):
        invalid("Versione formato backup non supportata.")
    collections = document.get("collections")
    if not isinstance(collections, dict):
        invalid("collections deve essere un oggetto.")
    expected = set(BACKUP_COLLECTIONS) if schema == 2 else LEGACY_COLLECTIONS
    if set(collections) != expected:
        invalid("Backup incompleto o collection sconosciute: richiesto l'intero archivio della versione indicata.")
    if schema == 2 and meta.get("database") != "autanalysis":
        invalid("Database del backup non riconosciuto.")
    if schema == 1:
        collections.update(ai_jobs=[], notifications=[])

    identifiers = {name: set() for name in BACKUP_COLLECTIONS}
    required = {
        "patients": ("id",), "evaluations": ("id_valutazione", "id_paziente", "id_scala"),
        "scales": ("id",), "users": ("username",), "settings": ("id",),
        "ai_analyses": ("id", "id_paziente"), "ai_jobs": ("id", "username", "status"),
        "notifications": ("id", "username", "message"), "licenses": ("id", "instance_id", "status", "plan"),
        "audit_logs": ("azione", "operatore"),
    }
    models = {"patients": Patient, "evaluations": Evaluation, "scales": Scale, "ai_analyses": AiAnalysis}
    for name, docs in collections.items():
        if not isinstance(docs, list):
            invalid(f"Collection {name}: attesa una lista.")
        mongo_ids = set()
        for index, doc in enumerate(docs):
            label = f"{name}[{index}]"
            if not isinstance(doc, dict):
                invalid(f"{label}: documento non valido.")
            for field in required[name]:
                if not isinstance(doc.get(field), str) or not doc[field].strip():
                    invalid(f"{label}: campo {field} mancante/non valido.")
            mandatory_dates = {
                "evaluations": "data_compilazione", "ai_analyses": "timestamp",
                "ai_jobs": "created_at", "notifications": "created_at", "audit_logs": "timestamp",
            }
            if name in mandatory_dates and doc.get(mandatory_dates[name]) is None:
                invalid(f"{label}: data obbligatoria mancante.")
            if name != "audit_logs":
                ident = doc[required[name][0]]
                if ident in identifiers[name]:
                    invalid(f"{label}: identificativo duplicato.")
                identifiers[name].add(ident)
            try:
                if "_id" in doc:
                    encoded_id = BSON.encode({"_id": doc["_id"]})
                    if encoded_id in mongo_ids:
                        invalid(f"{label}: _id duplicato.")
                    mongo_ids.add(encoded_id)
                for field in DATE_FIELDS.get(name, ()):
                    value = doc.get(field)
                    if value is None:
                        continue
                    if isinstance(value, str) and schema == 1:
                        value = datetime.fromisoformat(value.replace("Z", "+00:00"))
                    if not isinstance(value, datetime):
                        invalid(f"{label}: data {field} non valida.")
                    doc[field] = value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)
                if name in models:
                    models[name].model_validate(doc, strict=True)
                if len(BSON.encode(doc)) >= 16 * 1024 * 1024:
                    invalid(f"{label}: documento troppo grande per MongoDB.")
            except (ValidationError, ValueError, TypeError, OverflowError, InvalidDocument):
                invalid(f"{label}: schema o tipi BSON non validi.")
            if name == "users":
                password_hash = doc.get("hashed_password")
                if doc.get("role") not in ("admin", "viewer") or not isinstance(password_hash, str) or not re.fullmatch(r"\$2[aby]\$(0[4-9]|[12][0-9]|3[01])\$[./A-Za-z0-9]{53}", password_hash):
                    invalid(f"{label}: ruolo o hash credenziali non valido.")
                for flag in ("ai_enabled", "is_default", "must_change_password"):
                    if flag in doc and type(doc[flag]) is not bool:
                        invalid(f"{label}: campo {flag} non booleano.")
                token_version = doc.get("token_version", 1)
                if doc["username"] != doc["username"].lower() or not isinstance(token_version, int) or isinstance(token_version, bool) or not 1 <= token_version < 2**63:
                    invalid(f"{label}: identità/sessione non valida.")
            if name == "settings":
                if doc["id"] != "global_settings":
                    invalid(f"{label}: impostazioni sconosciute.")
                if doc.get("ai") is not None:
                    try:
                        AISettingsStored.model_validate(doc["ai"], strict=True)
                    except ValidationError:
                        invalid(f"{label}: configurazione IA non valida.")
            if name == "ai_jobs" and doc["status"] not in ("pending", "running", "completed", "failed"):
                invalid(f"{label}: stato job sconosciuto.")
            if name == "notifications" and type(doc.get("read", False)) is not bool:
                invalid(f"{label}: stato lettura non valido.")
    if not any(u["role"] == "admin" for u in collections["users"]):
        invalid("Il backup deve contenere almeno un amministratore con credenziali valide.")
    if len(collections["licenses"]) != 1 or collections["licenses"][0]["id"] != "autify_license":
        invalid("Il backup deve contenere esattamente la licenza dell'istanza.")
    lic = collections["licenses"][0]
    if lic["status"] not in ("trial", "active", "expired", "revoked", "invalid", "validation_required"):
        invalid("Stato licenza non riconosciuto.")
    if lic["plan"] != "trial" and (not isinstance(lic.get("license_token"), str) or not lic["license_token"].strip()):
        invalid("Token licenza commerciale mancante.")
    if lic["plan"] != "lifetime" and lic.get("expires_at") is None:
        invalid("Scadenza licenza mancante.")
    for ev in collections["evaluations"]:
        if ev["id_paziente"] not in identifiers["patients"]:
            invalid("Valutazione con riferimento utente inesistente.")
        if ev["id_scala"] not in identifiers["scales"]:
            snapshot = ev.get("snapshot_scala")
            if not isinstance(snapshot, dict) or snapshot.get("id") != ev["id_scala"]:
                invalid("Valutazione senza scala corrente o snapshot storico valido.")
            try:
                Scale.model_validate(snapshot, strict=True)
            except ValidationError:
                invalid("Snapshot storico della scala non valido.")
    for name in ("ai_analyses", "ai_jobs", "notifications"):
        for doc in collections[name]:
            for field in ("id_paziente", "job_id"):
                if doc.get(field) is not None and not isinstance(doc[field], str):
                    invalid(f"{name}: riferimento {field} non valido.")
            if doc.get("id_paziente") and doc["id_paziente"] not in identifiers["patients"]:
                invalid(f"{name}: riferimento utente inesistente.")
            if name == "ai_analyses":
                provenance = doc.get("provenance") or {}
                sources = provenance.get("evaluations", []) if isinstance(provenance, dict) else []
                captured_ids = {source.get("id") for source in sources
                                if isinstance(source, dict) and isinstance(source.get("id"), str)
                                and isinstance(source.get("input_hash"), str)
                                and re.fullmatch(r"[a-f0-9]{64}", source["input_hash"])
                                and isinstance(source.get("snapshot_hash"), str)
                                and re.fullmatch(r"[a-f0-9]{64}", source["snapshot_hash"])} if isinstance(sources, list) else set()
                if any(e not in identifiers["evaluations"] and e not in captured_ids for e in doc.get("evaluations_used", [])):
                    invalid("Relazione IA con fonte inesistente e senza provenienza storica.")
            if name == "notifications" and doc.get("job_id") and doc["job_id"] not in identifiers["ai_jobs"]:
                invalid("Notifica con riferimento job inesistente.")
    # Validate encrypted settings before deleting anything; never silently lose provider keys.
    def check_secrets(value):
        if isinstance(value, dict):
            for child in value.values():
                check_secrets(child)
        elif isinstance(value, str) and value.startswith("enc:"):
            try:
                decrypt_secret(value)
            except (SecretConfigurationError, SecretDecryptionError):
                invalid("Chiave IA incompatibile: configurare la chiave originale prima del ripristino.")
    for settings in collections["settings"]:
        check_secrets(settings.get("ai", {}))
    if schema == 1:
        # The decoder and restore both validate. Return a fully migrated document
        # so a second validation uses the ten-collection contract and BSON dates.
        meta.update(schema_version=2, database="autanalysis", migrated_from_schema=1)
    return document


async def require_transactions(db):
    hello = await db.command("hello")
    if not hello.get("setName") or not hello.get("isWritablePrimary"):
        raise HTTPException(503, "Backup atomico richiede MongoDB replica set con primary disponibile. Consultare BACKUP_OPERATIONS.md.")
    unknown = set(await db.list_collection_names()) - set(BACKUP_COLLECTIONS)
    unknown = {name for name in unknown if not name.startswith("system.")}
    if unknown:
        raise HTTPException(409, "Collection non registrate presenti nel database: aggiornare il contratto backup prima di procedere.")


async def export_archive(db):
    # Fail before database work if the encryption key has not been configured.
    _key(os.getenv("BACKUP_ENCRYPTION_KEY", ""))
    await require_transactions(db)

    async def collect(session):
        collections = {}
        size = 0
        for name in BACKUP_COLLECTIONS:
            docs = []
            async for doc in db[name].find({}, session=session):
                size += len(encode_document(doc)) + 2
                if size > MAX_PAYLOAD_BYTES - 4096:
                    raise HTTPException(413, "Archivio oltre 64 MiB; usare la procedura MongoDB per archivi grandi.")
                docs.append(doc)
            collections[name] = docs
        return {
            "metadata": {"schema_version": 2, "version": APP_VERSION, "database": "autanalysis",
                         "exported_at": datetime.now(timezone.utc), "backup_id": str(uuid.uuid4())},
            "collections": collections,
        }

    async with await db.client.start_session() as session:
        document = await session.with_transaction(collect, read_concern=ReadConcern("snapshot"),
                                                 write_concern=WriteConcern("majority"), read_preference=ReadPreference.PRIMARY)
    payload = encode_document(document)
    if len(payload) > MAX_PAYLOAD_BYTES:
        raise HTTPException(413, "Archivio oltre il limite supportato.")
    # Do not hand out a new-format archive that this service cannot restore.
    validate_document(document)
    return encrypt_backup(payload)


async def restore_document(db, document, username, *, maintenance):
    document = validate_document(document)
    if not maintenance:
        raise HTTPException(409, "Ripristino disponibile solo dopo riavvio in modalità BACKUP_MAINTENANCE_MODE=true.")
    await require_transactions(db)
    restore_id = str(uuid.uuid4())
    counts = {name: len(document["collections"][name]) for name in BACKUP_COLLECTIONS}

    async def replace(session):
        incoming = copy.deepcopy(document["collections"])
        current_license = await db["licenses"].find_one({"id": "autify_license"}, session=session)
        incoming_license = incoming["licenses"][0]
        if current_license and current_license.get("plan") != "trial" and current_license.get("instance_id") != incoming_license["instance_id"]:
            raise HTTPException(409, "Identità licenza diversa: trasferire la licenza con la procedura dedicata prima del ripristino.")
        # Never revive pre-restore sessions, even when the old backup has token_version=1.
        current_users = {u["username"]: u async for u in db["users"].find({}, session=session)}
        for user in incoming["users"]:
            old = current_users.get(user["username"], {}).get("token_version", 1)
            # Random epoch also fences tokens from another installation sharing JWT keys.
            epoch = uuid.uuid4().int >> 66  # positive int64, safe for BSON
            while epoch in (0, 1, old, user.get("token_version", 1)):
                epoch = uuid.uuid4().int >> 66
            user["token_version"] = epoch
        # Running tasks cannot resume from their Python stack after restore.
        for job in incoming["ai_jobs"]:
            if job["status"] in ("pending", "running"):
                job.update(status="failed", completed_at=datetime.now(timezone.utc),
                           error_message="Elaborazione interrotta dal ripristino; riavviare esplicitamente.")
            for transient_field in ("attachment", "user_prompt", "system_prompt"):
                job.pop(transient_field, None)
        for name in BACKUP_COLLECTIONS:
            await db[name].delete_many({}, session=session)
            if incoming[name]:
                await db[name].insert_many(incoming[name], session=session)
        await db["audit_logs"].insert_one({**audit_event("IMPORT_DATABASE", username, "Ripristino atomico completato", restore_id),
                                             "collections": counts}, session=session)

    try:
        async with await db.client.start_session() as session:
            await session.with_transaction(replace, read_concern=ReadConcern("snapshot"),
                                           write_concern=WriteConcern("majority"), read_preference=ReadPreference.PRIMARY,
                                           max_commit_time_ms=30000)
    except PyMongoError as exc:
        if isinstance(exc, ConnectionFailure) or exc.has_error_label("UnknownTransactionCommitResult"):
            raise HTTPException(503, f"Esito commit da verificare nel registro: {restore_id}. Non ripetere automaticamente il ripristino.") from exc
        raise HTTPException(503, "Ripristino non completato: transazione annullata. Nessuna sostituzione parziale applicata.") from exc
    return {"message": "Ripristino atomico completato. Effettua nuovamente il login.",
            "collections": counts, "restore_id": restore_id, "reauthenticate": True}
