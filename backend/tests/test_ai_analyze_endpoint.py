import pytest
from unittest.mock import AsyncMock, patch
from .test_endpoints import MockCollection, client, setup_mock_db, mock_patients, mock_scales, mock_evaluations, mock_users
from app.ai.crypto import encrypt_secret

def test_test_ai_connection_endpoint(client, setup_mock_db):
    """Verifica POST /api/admin/ai/test-connection con adapter simulato."""
    with patch("app.routers.ai.get_ai_adapter") as mock_get_adapter:
        mock_adapter = AsyncMock()
        mock_adapter.test_connection.return_value = (True, 45.2, "Connessione a Gemini riuscita (45.2 ms).")
        mock_get_adapter.return_value = mock_adapter

        res = client.post("/api/admin/ai/test-connection", json={
            "provider": "gemini",
            "model": "gemini-2.5-pro",
            "api_key": "test-key"
        })
        assert res.status_code == 200
        data = res.json()
        assert data["success"] is True
        assert data["provider"] == "gemini"
        assert data["latency_ms"] == 45.2
        assert "riuscita" in data["message"]

def test_analyze_multidimensional_context(client, setup_mock_db):
    """Verifica POST /api/admin/ai/analyze con contesto multidimensionale e allegato."""
    from app.routers import ai as ai_router

    mock_analysis_coll = MockCollection("ai_analyses", [])

    with patch.object(ai_router, "ai_analyses_collection", mock_analysis_coll), \
         patch("app.routers.ai.get_ai_adapter") as mock_get_adapter:

        mock_adapter = AsyncMock()
        mock_adapter.generate.return_value = (
            "## Relazione Multidimensionale\nPaziente in miglioramento.",
            {"prompt_tokens": 120, "completion_tokens": 40, "total_tokens": 160}
        )
        mock_get_adapter.return_value = mock_adapter

        payload = {
            "id_paziente": "pat_1",
            "patient": {
                "id": "pat_1",
                "nome": "Mario",
                "cognome": "Rossi",
                "codice_fiscale": "RSSMRA80A01H501U"
            },
            "evaluations": [
                {
                    "id_valutazione": "eval_pos_1",
                    "id_scala": "pos",
                    "data_compilazione": "2026-01-15T10:00:00Z",
                    "domini": [{"codice": "SP", "etichetta": "Sviluppo Personale", "punteggio": 24}]
                }
            ],
            "notes": "L'utente mostra progressi nell'interazione con i pari.",
            "history_reports": [
                {"timestamp": "2025-01-10T10:00:00Z", "report": "Sintesi anno precedente."}
            ],
            "attachment": {
                "filename": "documento.pdf",
                "extension": "pdf",
                "data_base64": "JVBERi0xLjQKJcTl8uXrp/Og0MTGCjQgMCBvYmoKPDwKL1R5cGUgL1BhZ2VzCj4+CmVuZG9iam=="
            }
        }

        res = client.post("/api/admin/ai/analyze", json=payload)
        assert res.status_code == 202
        data = res.json()
        assert data["job_id"].startswith("job_")
        assert data["status"] == "pending"
        assert data["id_paziente"] == "pat_1"
        assert data["patient_name"] == "Mario Rossi"
        assert data["report"] == ""
