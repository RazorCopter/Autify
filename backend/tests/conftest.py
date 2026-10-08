import os
os.environ.setdefault("JWT_SECRET_KEY", "test-secret-key-for-unit-tests")

import pytest
from app.main import app
from app.license_service import require_valid_license

@pytest.fixture(autouse=True)
def valid_license_override():
    """I test endpoint verificano il dominio, non il server licenze esterno."""
    async def _valid_license():
        return {"valid": True, "status": "active"}

    app.dependency_overrides[require_valid_license] = _valid_license
    yield
    app.dependency_overrides.pop(require_valid_license, None)
