import os
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-for-unit-tests")

import pytest
import json
import io
from datetime import datetime, timezone
from fastapi.testclient import TestClient
from unittest.mock import patch, MagicMock

# Import the FastAPI app
from app.main import app

# ==============================================================================
# MOTOR / MONGODB ASYNC MOCKS
# ==============================================================================

class MockCursor:
    """Mock class for Motor's AsyncIOMotorCursor."""
    def __init__(self, data):
        self.data = data

    def sort(self, key, direction=-1):
        # Simple mock sorting for evaluations: sort by compiler date
        if key == "data_compilazione":
            def get_date(x):
                d = x.get("data_compilazione")
                if not d:
                    return datetime.min.replace(tzinfo=timezone.utc)
                if isinstance(d, str):
                    return datetime.fromisoformat(d)
                return d
            self.data = sorted(self.data, key=get_date, reverse=(direction == -1))
        return self

    def skip(self, count):
        self.data = self.data[count:]
        return self

    def limit(self, count):
        if count is not None:
            self.data = self.data[:count]
        return self

    async def to_list(self, length=None):
        if length is not None:
            return self.data[:length]
        return self.data


class MockCollection:
    """Mock class for Motor's AsyncIOMotorCollection."""
    def __init__(self, name, documents=None):
        self.name = name
        self.documents = documents if documents is not None else []
        self.inserted_docs = []
        self.replaced_docs = []
        self.deleted_filters = []

    def find(self, filter_query, *args, **kwargs):
        filtered = []
        for doc in self.documents:
            match = True
            for k, v in filter_query.items():
                if isinstance(v, dict) and "$in" in v:
                    if doc.get(k) not in v["$in"]:
                        match = False
                        break
                elif doc.get(k) != v:
                    match = False
                    break
            if match:
                # Return a deep-like copy to prevent in-place modification bugs
                filtered.append(dict(doc))
        return MockCursor(filtered)

    async def find_one(self, filter_query, *args, **kwargs):
        for doc in self.documents:
            match = True
            for k, v in filter_query.items():
                if isinstance(v, dict) and "$in" in v:
                    if doc.get(k) not in v["$in"]:
                        match = False
                        break
                elif doc.get(k) != v:
                    match = False
                    break
            if match:
                return dict(doc)
        return None

    async def insert_one(self, document):
        # Simulate generating id if missing
        if "id" not in document:
            document["id"] = "pat_mock_gen"
        self.documents.append(document)
        self.inserted_docs.append(document)
        
        class InsertOneResult:
            inserted_id = "mock_inserted_id"
        return InsertOneResult()

    async def replace_one(self, filter_query, replacement, upsert=False):
        self.replaced_docs.append((filter_query, replacement))
        replaced = False
        for idx, doc in enumerate(self.documents):
            match = True
            for k, v in filter_query.items():
                if doc.get(k) != v:
                    match = False
                    break
            if match:
                self.documents[idx] = replacement
                replaced = True
                break
        if not replaced and upsert:
            self.documents.append(replacement)
            
        class ReplaceOneResult:
            matched_count = 1 if replaced else (1 if upsert else 0)
            modified_count = 1
        return ReplaceOneResult()

    async def delete_many(self, filter_query):
        self.deleted_filters.append(filter_query)
        initial_len = len(self.documents)
        self.documents = [
            doc for doc in self.documents 
            if not all(doc.get(k) == v for k, v in filter_query.items())
        ]
        
        class DeleteResult:
            deleted_count = initial_len - len(self.documents)
        return DeleteResult()

    async def count_documents(self, filter_query=None):
        if filter_query is None or filter_query == {}:
            return len(self.documents)
        count = 0
        for doc in self.documents:
            match = True
            for k, v in filter_query.items():
                if doc.get(k) != v:
                    match = False
                    break
            if match:
                count += 1
        return count

    async def update_one(self, filter_query, update_query):
        set_fields = update_query.get("$set", {})
        inc_fields = update_query.get("$inc", {})
        matched = False
        for doc in self.documents:
            match = True
            for k, v in filter_query.items():
                if doc.get(k) != v:
                    match = False
                    break
            if match:
                for field, val in set_fields.items():
                    doc[field] = val
                for field, val in inc_fields.items():
                    doc[field] = doc.get(field, 0) + val
                matched = True
                break
        class UpdateOneResult:
            matched_count = 1 if matched else 0
            modified_count = 1 if matched else 0
        return UpdateOneResult()

    async def delete_one(self, filter_query):
        matched = False
        for idx, doc in enumerate(self.documents):
            match = True
            for k, v in filter_query.items():
                if doc.get(k) != v:
                    match = False
                    break
            if match:
                del self.documents[idx]
                matched = True
                break
        class DeleteOneResult:
            deleted_count = 1 if matched else 0
        return DeleteOneResult()

    async def update_many(self, filter_query, update_query):
        matched_count = 0
        modified_count = 0
        set_fields = update_query.get("$set", {})
        for doc in self.documents:
            match = True
            for k, v in filter_query.items():
                if k == "$exists":
                    # Simple mock exist check
                    pass
                elif isinstance(v, dict) and "$exists" in v:
                    exists_val = v["$exists"]
                    if exists_val == False and k in doc:
                        match = False
                    elif exists_val == True and k not in doc:
                        match = False
                elif doc.get(k) != v:
                    match = False
                    break
            if match:
                matched_count += 1
                for field, val in set_fields.items():
                    doc[field] = val
                modified_count += 1
        class UpdateManyResult:
            def __init__(self, m_count, mod_count):
                self.matched_count = m_count
                self.modified_count = mod_count
        return UpdateManyResult(matched_count, modified_count)



# ==============================================================================
# PYTEST FIXTURES
# ==============================================================================

@pytest.fixture
def mock_patients():
    return [
        {
            "id": "pat_1",
            "nome": "Mario",
            "cognome": "Rossi",
            "altezza": 175,
            "peso": 70.0,
            "sesso": "M",
            "data_nascita": "1990-01-01",
            "note": "Paziente storico",
            "attivo": True
        },
        {
            "id": "pat_2",
            "nome": "Laura",
            "cognome": "Bianchi",
            "altezza": 162,
            "peso": 55.0,
            "sesso": "F",
            "data_nascita": "1995-05-15",
            "note": "Paziente senza valutazioni",
            "attivo": True
        }
    ]

@pytest.fixture
def mock_scales():
    return [
        {
            "id": "pos_2024",
            "nome": "Scala POS",
            "descrizione": "Scala di valutazione POS",
            "sezioni": []
        },
        {
            "id": "san_martin",
            "nome": "Scala San Martin",
            "descrizione": "Scala di valutazione San Martin",
            "sezioni": []
        }
    ]

@pytest.fixture
def mock_evaluations():
    return [
        {
            "id_valutazione": "eval_pos_1",
            "id_paziente": "pat_1",
            "id_scala": "pos_2024",
            "anno": 2026,
            "data_compilazione": datetime(2026, 1, 15, 10, 0, 0, tzinfo=timezone.utc),
            "nome_operatore": "Dott. Verdi",
            "risposte": []
        },
        {
            "id_valutazione": "eval_martin_1",
            "id_paziente": "pat_1",
            "id_scala": "san_martin",
            "anno": 2026,
            "data_compilazione": datetime(2026, 2, 20, 11, 30, 0, tzinfo=timezone.utc),
            "nome_operatore": "Dott. Neri",
            "risposte": []
        }
    ]

@pytest.fixture
def mock_users():
    return [
        {
            "username": "admin",
            "role": "admin",
            "ai_enabled": True,
            "is_default": True,
            "token_version": 1,
        },
        {
            "username": "viewer_user",
            "role": "viewer",
            "ai_enabled": False,
            "is_default": False,
            "token_version": 1,
        }
    ]

@pytest.fixture
def setup_mock_db(mock_patients, mock_scales, mock_evaluations, mock_users):
    """
    Fixture that patches the database collections across all app.routers modules.
    This replaces evaluations_collection, patients_collection, and scales_collection
    with mock implementations pre-populated with test data.
    """
    mock_patients_coll = MockCollection("patients", mock_patients)
    mock_scales_coll = MockCollection("scales", mock_scales)
    mock_evals_coll = MockCollection("evaluations", mock_evaluations)
    mock_ai_analyses_coll = MockCollection("ai_analyses", [])
    mock_users_coll = MockCollection("users", mock_users)

    # Router modules that import database collections (ARCH-01 refactoring)
    ROUTER_MODULES = [
        "app.routers.auth",
        "app.routers.patients",
        "app.routers.evaluations",
        "app.routers.settings",
        "app.routers.ai",
        "app.routers.backup",
        "app.routers.dashboard",
        "app.routers.misc",
        "app.routers._helpers",
    ]

    mock_settings_coll = MockCollection("settings", [])
    mock_audit_logs_coll = MockCollection("audit_logs", [])

    patches = []
    collection_map = {
        "patients_collection": mock_patients_coll,
        "scales_collection": mock_scales_coll,
        "evaluations_collection": mock_evals_coll,
        "ai_analyses_collection": mock_ai_analyses_coll,
        "users_collection": mock_users_coll,
        "settings_collection": mock_settings_coll,
        "audit_logs_collection": mock_audit_logs_coll,
    }
    for mod in ROUTER_MODULES:
        for coll_name, mock_coll in collection_map.items():
            patches.append(patch(f"{mod}.{coll_name}", mock_coll))
    # Also patch the auth module's own users_collection
    patches.append(patch("app.auth.users_collection", mock_users_coll))

    for p in patches:
        p.start()

    yield {
        "patients": mock_patients_coll,
        "scales": mock_scales_coll,
        "evaluations": mock_evals_coll,
        "ai_analyses": mock_ai_analyses_coll,
        "users": mock_users_coll,
    }

    for p in patches:
        p.stop()


@pytest.fixture
def client():
    """TestClient instance for API communication."""
    import os
    os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-for-unit-tests")
    from app.auth import create_access_token
    token = create_access_token(username="admin", role="admin", ai_enabled=True)
    c = TestClient(app)
    c.headers.update({"Authorization": f"Bearer {token}"})
    return c


# ==============================================================================
# UNIT TESTS FOR ENDPOINT 1: get_patients (GET /api/admin/patients)
# ==============================================================================

def test_get_patients_success(client, setup_mock_db):
    """
    Test that GET /api/admin/patients returns the complete list of patients
    enriched with the compilation dates of their last compiled POS and San Martin scales.
    """
    response = client.get("/api/admin/patients")
    
    assert response.status_code == 200
    res_data = response.json()
    assert res_data["total"] == 2
    patients_data = res_data["items"]
    assert len(patients_data) == 2

    # Check Mario Rossi (pat_1) who has both POS and San Martin evaluations
    pat_mario = next(p for p in patients_data if p["id"] == "pat_1")
    assert pat_mario["nome"] == "Mario"
    assert pat_mario["cognome"] == "Rossi"
    # ultimo_pos_compilato should match datetime(2026, 1, 15, 10, ...) -> "2026-01-15T10:00:00+00:00"
    assert pat_mario["ultimo_pos_compilato"] == "2026-01-15T10:00:00+00:00"
    # ultimo_san_martin_compilato should match datetime(2026, 2, 20, 11, 30, ...) -> "2026-02-20T11:30:00+00:00"
    assert pat_mario["ultimo_san_martin_compilato"] == "2026-02-20T11:30:00+00:00"

    # Check Laura Bianchi (pat_2) who has no evaluations
    pat_laura = next(p for p in patients_data if p["id"] == "pat_2")
    assert pat_laura["nome"] == "Laura"
    assert pat_laura["cognome"] == "Bianchi"
    assert pat_laura["ultimo_pos_compilato"] is None
    assert pat_laura["ultimo_san_martin_compilato"] is None


# ==============================================================================
# UNIT TESTS FOR ENDPOINT 2: create_patient (POST /api/admin/patients)
# ==============================================================================

def test_create_patient_success(client, setup_mock_db):
    """
    Test that POST /api/admin/patients correctly saves a new patient
    and generates an appropriate unique patient ID if not provided.
    """
    new_patient_payload = {
        "nome": "Giuseppe",
        "cognome": "Verdi",
        "altezza": 180,
        "peso": 82.5,
        "sesso": "M",
        "data_nascita": "1980-05-15",
        "note": "Paziente di test di nuova inserzione"
    }

    response = client.post("/api/admin/patients", json=new_patient_payload)
    
    assert response.status_code == 201
    created_patient = response.json()
    
    assert created_patient["nome"] == "Giuseppe"
    assert created_patient["cognome"] == "Verdi"
    # Verify ID is automatically generated (starts with pat_)
    assert "id" in created_patient
    assert created_patient["id"].startswith("pat_")
    
    # Verify the patient document is indeed stored in the mocked database
    db = setup_mock_db
    stored_patients = db["patients"].documents
    assert any(p["id"] == created_patient["id"] for p in stored_patients)


def test_create_patient_validation_error(client, setup_mock_db):
    """
    Test that POST /api/admin/patients returns a 422 Validation Error
    when sending missing mandatory fields (e.g. nome/cognome).
    """
    invalid_payload = {
        "altezza": 170,
        "peso": 65.0
    }
    
    response = client.post("/api/admin/patients", json=invalid_payload)
    assert response.status_code == 422


# ==============================================================================
# UNIT TESTS FOR ENDPOINT 3: import_scale (POST /api/admin/import-scale)
# ==============================================================================

def test_import_scale_success(client, setup_mock_db):
    """
    Test that POST /api/admin/import-scale successfully parses and imports
    a valid clinical scale JSON, saving it inside scales_collection.
    """
    valid_scale_json = {
        "scala": {
            "id": "scala_test_import",
            "nome": "Scala di Test Importazione",
            "descrizione": "Protocollo clinico per verificare l'import",
            "domini": [
                {
                    "codice": "SP",
                    "nome": "Sviluppo Personale",
                    "descrizione": "Attività per lo sviluppo personale",
                    "domande": [
                        {
                            "codice": "SP-1",
                            "testo": "Riesce ad acquisire nuove competenze?",
                            "note": "Osservare in ambiente protetto",
                            "opzioni": [
                                { "punteggio": 3, "etichetta": "Sempre da solo" },
                                { "punteggio": 2, "etichetta": "Con aiuto" },
                                { "punteggio": 1, "etichetta": "Non riesce" }
                            ]
                        }
                    ]
                }
            ]
        }
    }

    # Encode dictionary to JSON string bytes
    json_bytes = json.dumps(valid_scale_json).encode("utf-8")
    
    # Post files parameter
    response = client.post(
        "/api/admin/import-scale",
        files={"file": ("scala_test.json", io.BytesIO(json_bytes), "application/json")}
    )

    assert response.status_code == 200
    result = response.json()
    
    assert result["message"] == "Scala importata con successo"
    assert result["id"] == "scala_test_import"
    assert result["nome"] == "Scala di Test Importazione"
    assert result["sezioni"] == 1
    assert result["domande_totali"] == 1

    # Verify that the scale document is stored in the mocked database
    db = setup_mock_db
    stored_scales = db["scales"].documents
    imported_doc = next(s for s in stored_scales if s["id"] == "scala_test_import")
    assert imported_doc["nome"] == "Scala di Test Importazione"
    assert len(imported_doc["sezioni"]) == 1
    assert imported_doc["sezioni"][0]["codice_sezione"] == "SP"
    assert len(imported_doc["sezioni"][0]["domande"]) == 1
    assert imported_doc["sezioni"][0]["domande"][0]["codice"] == "SP-1"


def test_import_scale_invalid_extension(client, setup_mock_db):
    """
    Test that POST /api/admin/import-scale returns a 400 Bad Request
    when uploading a file that is not a JSON file (e.g. text file).
    """
    response = client.post(
        "/api/admin/import-scale",
        files={"file": ("invalid_file.txt", io.BytesIO(b"Hello World"), "text/plain")}
    )
    assert response.status_code == 400
    assert "Il file deve essere un JSON" in response.json()["detail"]


def test_import_scale_missing_root_field(client, setup_mock_db):
    """
    Test that POST /api/admin/import-scale returns a 422 Unprocessable Entity
    if the JSON structure is missing the 'scala' root field.
    """
    invalid_structure_json = {
        "nome": "Scala Senza Campo Scala",
        "id": "invalid_id"
    }
    json_bytes = json.dumps(invalid_structure_json).encode("utf-8")

    response = client.post(
        "/api/admin/import-scale",
        files={"file": ("invalid.json", io.BytesIO(json_bytes), "application/json")}
    )
    assert response.status_code == 422
    assert "Campo 'scala' mancante nel JSON" in response.json()["detail"]


def test_import_scale_no_sections(client, setup_mock_db):
    """
    Test that POST /api/admin/import-scale returns a 422 Unprocessable Entity
    if the JSON structure is valid but contains no domains/sections.
    """
    no_sections_json = {
        "scala": {
            "id": "scala_no_sections",
            "nome": "Scala vuota",
            "domini": []
        }
    }
    json_bytes = json.dumps(no_sections_json).encode("utf-8")

    response = client.post(
        "/api/admin/import-scale",
        files={"file": ("empty_scale.json", io.BytesIO(json_bytes), "application/json")}
    )
    assert response.status_code == 422
    assert "Il JSON non contiene domini/sezioni" in response.json()["detail"]


# ==============================================================================
# NEW UNIT TESTS FOR ADDED FEATURES
# ==============================================================================

def test_create_patient_duplicate_id(client, setup_mock_db):
    """
    Test that POST /api/admin/patients returns a 400 Bad Request
    when providing an ID that already exists in the database.
    """
    duplicate_payload = {
        "id": "pat_1",  # Pre-populated in mock_patients
        "nome": "Giuseppe",
        "cognome": "Verdi",
        "altezza": 180,
        "peso": 82.5,
        "sesso": "M",
        "data_nascita": "1980-05-15",
        "note": "Paziente con ID gia esistente"
    }
    response = client.post("/api/admin/patients", json=duplicate_payload)
    assert response.status_code == 400
    assert "Utente con questo ID" in response.json()["detail"]


def test_import_scale_file_size_exceeded(client, setup_mock_db):
    """
    Test that POST /api/admin/import-scale returns a 400 Bad Request
    when the uploaded JSON exceeds 5MB.
    """
    large_bytes = b" " * (5 * 1024 * 1024 + 10)
    response = client.post(
        "/api/admin/import-scale",
        files={"file": ("large_file.json", io.BytesIO(large_bytes), "application/json")}
    )
    assert response.status_code == 400
    assert "Il file supera la dimensione massima" in response.json()["detail"]


def test_update_settings_masking(client, setup_mock_db):
    """
    Test that POST /api/admin/settings hides/replaces API key correctly.
    """
    settings_payload = {
        "gemini_api_key": "***-HIDDEN",
        "valutazioni_per_pagina": 15
    }
    
    with patch("app.routers.settings.settings_collection", MockCollection("settings", [])) as mock_settings:
        response = client.post("/api/admin/settings", json=settings_payload)
        assert response.status_code == 200
        # Check that saved doc in DB has gemini_api_key as None
        assert mock_settings.documents[0]["gemini_api_key"] is None


def test_analytics_zero_questions():
    """
    Test that _build_domain_analyses directly sets standard, percentile, and fascia to None
    when a domain has 0 answered questions (num_domande == 0), preventing false clinical interpretations.
    """
    from app.analytics import _build_domain_analyses
    
    direct_scores = [
        {
            "codice": "SP",
            "etichetta": "Sviluppo Personale",
            "punteggio_totale": 0,
            "num_domande": 0
        }
    ]
    table_a = {}  # empty, shouldn't be accessed
    
    analyses, total_std = _build_domain_analyses(direct_scores, table_a)
    
    assert len(analyses) == 1
    sp_analysis = analyses[0]
    assert sp_analysis["codice"] == "SP"
    assert sp_analysis["punteggio_standard"] is None
    assert sp_analysis["percentile_dominio"] is None
    assert sp_analysis["fascia"] is None
    assert total_std is None


# ==============================================================================
# TESTS FOR SEC-01 & SEC-02 (P0 Remediation)
# ==============================================================================

def test_sec_01_client_endpoints_require_auth(setup_mock_db):
    """
    SEC-01: Verify that client endpoints reject anonymous requests with 401
    and reject viewer role on POST with 403.
    """
    anon_client = TestClient(app)
    
    # 1. Anonymous GET /api/client/patients -> 401
    res_pat = anon_client.get("/api/client/patients")
    assert res_pat.status_code == 401

    # 2. Anonymous GET /api/client/scales -> 401
    res_scales = anon_client.get("/api/client/scales")
    assert res_scales.status_code == 401

    # 3. Anonymous POST /api/client/evaluations -> 401
    eval_payload = {
        "id_paziente": "pat_1",
        "id_scala": "scale_pos",
        "anno": 2026,
        "risposte": []
    }
    res_post_anon = anon_client.post("/api/client/evaluations", json=eval_payload)
    assert res_post_anon.status_code == 401

    # 4. Viewer POST /api/client/evaluations -> 403
    from app.auth import create_access_token
    viewer_token = create_access_token(username="viewer_user", role="viewer", ai_enabled=False)
    viewer_client = TestClient(app)
    viewer_client.headers.update({"Authorization": f"Bearer {viewer_token}"})
    
    res_post_viewer = viewer_client.post("/api/client/evaluations", json=eval_payload)
    assert res_post_viewer.status_code == 403


def test_sec_02_export_import_admin_only(setup_mock_db):
    """
    SEC-02: Verify that export-db and import-db reject anonymous (401) and viewer (403),
    allowing only admin.
    """
    from app.auth import create_access_token
    anon_client = TestClient(app)
    viewer_token = create_access_token(username="viewer_user", role="viewer", ai_enabled=False)
    viewer_client = TestClient(app)
    viewer_client.headers.update({"Authorization": f"Bearer {viewer_token}"})

    # Anonymous -> 401
    assert anon_client.get("/api/admin/export-db").status_code == 401
    assert anon_client.post("/api/admin/import-db").status_code == 401

    # Viewer -> 403
    assert viewer_client.get("/api/admin/export-db").status_code == 403
    assert viewer_client.post("/api/admin/import-db").status_code == 403


def test_sec_03_token_version_revocation(setup_mock_db):
    """
    SEC-03: Verify that incrementing token_version in DB revokes older tokens (401).
    """
    from app.auth import create_access_token
    # Token issued with token_version=1
    token_v1 = create_access_token(username="admin", role="admin", ai_enabled=True, token_version=1)
    admin_client = TestClient(app)
    admin_client.headers.update({"Authorization": f"Bearer {token_v1}"})

    # Should succeed with token_version=1
    res = admin_client.get("/api/admin/patients")
    assert res.status_code == 200

    # Simulate token_version increment in database (e.g. password changed or user updated)
    mock_users_coll = setup_mock_db["users"]
    for u in mock_users_coll.documents:
        if u["username"] == "admin":
            u["token_version"] = 2

    # Now request with token_v1 must fail with 401 Unauthorized
    res_revoked = admin_client.get("/api/admin/patients")
    assert res_revoked.status_code == 401
    assert "Sessione revocata" in res_revoked.json()["detail"]

    # Token issued with token_version=2 works
    token_v2 = create_access_token(username="admin", role="admin", ai_enabled=True, token_version=2)
    admin_client.headers.update({"Authorization": f"Bearer {token_v2}"})
    assert admin_client.get("/api/admin/patients").status_code == 200


def test_data_02_cascade_delete_ai_analyses(client, setup_mock_db):
    """
    DATA-02: Verify that deleting a patient cascades to both evaluations and AI analyses.
    """
    # Pre-populate an AI analysis for pat_1
    ai_coll = setup_mock_db["ai_analyses"]
    ai_coll.documents.append({
        "id": "an_test_1",
        "id_paziente": "pat_1",
        "report": "Test report",
        "timestamp": datetime.now(timezone.utc),
    })

    # Delete pat_1
    res = client.delete("/api/admin/patients/pat_1")
    assert res.status_code == 200

    # Verify patient is gone
    assert not any(p["id"] == "pat_1" for p in setup_mock_db["patients"].documents)
    # Verify evaluations for pat_1 are gone
    assert not any(e.get("id_paziente") == "pat_1" for e in setup_mock_db["evaluations"].documents)
    # Verify AI analyses for pat_1 are gone
    assert not any(a.get("id_paziente") == "pat_1" for a in setup_mock_db["ai_analyses"].documents)


def test_data_01_import_database_prevalidation(client, setup_mock_db):
    """
    DATA-01: Verify pre-validation before delete_many: malformed backup rejected with 422.
    """
    import io

    # 1. Collections not a dict -> 422
    bad_file = io.BytesIO(b'{"collections": "not_a_dict"}')
    res = client.post(
        "/api/admin/import-db",
        files={"file": ("backup.json", bad_file, "application/json")}
    )
    assert res.status_code == 422

    # 2. Collections has non-list -> 422
    bad_file2 = io.BytesIO(b'{"collections": {"patients": "not_a_list"}}')
    res2 = client.post(
        "/api/admin/import-db",
        files={"file": ("backup.json", bad_file2, "application/json")}
    )
    assert res2.status_code == 422

    # 3. Users list without any admin -> 422
    bad_file3 = io.BytesIO(b'{"collections": {"users": [{"username": "v1", "role": "viewer"}]}}')
    res3 = client.post(
        "/api/admin/import-db",
        files={"file": ("backup.json", bad_file3, "application/json")}
    )
    assert res3.status_code == 422


def test_score_01_and_fun_01_create_evaluation(client, setup_mock_db):
    """
    SCORE-01: Verify server-side validation on patient, scale, and questions.
    FUN-01: Verify sync of ultimo_*_compilato on patient after create_evaluation.
    """
    # 1. Non-existent patient -> 404
    res_bad_pat = client.post("/api/client/evaluations", json={
        "id_paziente": "pat_non_existent",
        "id_scala": "pos_2024",
        "anno": 2026,
        "risposte": []
    })
    assert res_bad_pat.status_code == 404
    assert "Utente con ID" in res_bad_pat.json()["detail"]

    # 2. Non-existent scale -> 404
    res_bad_scale = client.post("/api/client/evaluations", json={
        "id_paziente": "pat_2",
        "id_scala": "scale_inventata",
        "anno": 2026,
        "risposte": []
    })
    assert res_bad_scale.status_code == 404
    assert "Scala con ID" in res_bad_scale.json()["detail"]

    # 3. Valid scale with questions defined: setup a mock scale with a question and allowed scores [1, 2, 3]
    scales_coll = setup_mock_db["scales"]
    scales_coll.documents.append({
        "id": "scale_pos_test",
        "nome": "Scala POS Test",
        "descrizione": "Test",
        "sezioni": [{
            "codice_sezione": "SP",
            "titolo_sezione": "Sezione 1",
            "domande": [{
                "id_domanda": "q_pos_1",
                "codice": "SP_1",
                "testo_domanda": "Domanda 1",
                "opzioni": [
                    {"testo_risposta": "A", "punteggio": 1},
                    {"testo_risposta": "B", "punteggio": 2},
                    {"testo_risposta": "C", "punteggio": 3},
                ]
            }]
        }]
    })

    # 3a. Invalid question code -> 422
    res_bad_q = client.post("/api/client/evaluations", json={
        "id_paziente": "pat_2",
        "id_scala": "scale_pos_test",
        "anno": 2026,
        "risposte": [{"codice_domanda": "domanda_sconosciuta", "punteggio": 1}]
    })
    assert res_bad_q.status_code == 422
    assert "non appartiene alla scala" in res_bad_q.json()["detail"]

    # 3b. Invalid score (e.g. score 99 outside [1, 2, 3]) -> 422
    res_bad_score = client.post("/api/client/evaluations", json={
        "id_paziente": "pat_2",
        "id_scala": "scale_pos_test",
        "anno": 2026,
        "risposte": [{"codice_domanda": "SP_1", "punteggio": 99}]
    })
    assert res_bad_score.status_code == 422
    assert "Punteggio 99 non valido" in res_bad_score.json()["detail"]

    # 4. Valid evaluation -> 201 and auto-updates patient's ultimo_pos_compilato
    res_ok = client.post("/api/client/evaluations", json={
        "id_paziente": "pat_2",
        "id_scala": "scale_pos_test",
        "anno": 2026,
        "data_compilazione": "2026-03-01T10:00:00+00:00",
        "risposte": [{"codice_domanda": "SP_1", "punteggio": 2}]
    })
    assert res_ok.status_code == 201

    # Verify patient pat_2 in DB has ultimo_pos_compilato updated
    pat_2_doc = next(p for p in setup_mock_db["patients"].documents if p["id"] == "pat_2")
    assert pat_2_doc.get("ultimo_pos_compilato") == "2026-03-01T10:00:00+00:00"



