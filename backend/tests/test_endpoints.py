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
                if doc.get(k) != v:
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
                if doc.get(k) != v:
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
            "note": "Paziente storico"
        },
        {
            "id": "pat_2",
            "nome": "Laura",
            "cognome": "Bianchi",
            "altezza": 162,
            "peso": 55.0,
            "sesso": "F",
            "data_nascita": "1995-05-15",
            "note": "Paziente senza valutazioni"
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
def setup_mock_db(mock_patients, mock_scales, mock_evaluations):
    """
    Fixture that patches the database collections in app.routes.
    This replaces evaluations_collection, patients_collection, and scales_collection
    with mock implementations pre-populated with test data.
    """
    mock_patients_coll = MockCollection("patients", mock_patients)
    mock_scales_coll = MockCollection("scales", mock_scales)
    mock_evals_coll = MockCollection("evaluations", mock_evaluations)

    patches = [
        patch("app.routes.patients_collection", mock_patients_coll),
        patch("app.routes.scales_collection", mock_scales_coll),
        patch("app.routes.evaluations_collection", mock_evals_coll),
    ]

    for p in patches:
        p.start()

    yield {
        "patients": mock_patients_coll,
        "scales": mock_scales_coll,
        "evaluations": mock_evals_coll
    }

    for p in patches:
        p.stop()


@pytest.fixture
def client():
    """TestClient instance for API communication."""
    c = TestClient(app)
    c.headers.update({"X-Admin-Password": "tiglio2026"})
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
    patients_data = response.json()
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
    
    with patch("app.routes.settings_collection", MockCollection("settings", [])) as mock_settings:
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

