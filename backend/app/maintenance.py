"""Restart-only maintenance: no domain requests or background jobs during restore.

Deploy exactly one API process in this mode; stop all other writers first.
The request lock also serializes login/audit and license status against restore.
"""
import asyncio
import os
from starlette.responses import JSONResponse


def maintenance_enabled():
    return os.getenv("BACKUP_MAINTENANCE_MODE", "false").lower() == "true"


class BackupMaintenanceMiddleware:
    def __init__(self, app):
        self.app = app
        self.enabled = maintenance_enabled()
        self.lock = asyncio.Lock()

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or not self.enabled:
            return await self.app(scope, receive, send)
        allowed = {
            ("GET", "/"), ("GET", "/health/ready"), ("POST", "/api/admin/auth/login"),
            ("POST", "/api/admin/auth/change-password"),
            ("GET", "/api/admin/license/status"), ("GET", "/api/admin/settings"),
            ("GET", "/api/admin/users"), ("GET", "/api/admin/export-db"),
            ("POST", "/api/admin/import-db"), ("GET", "/api/admin/audit-logs"),
        }
        if scope["method"] != "OPTIONS" and (scope["method"], scope["path"]) not in allowed:
            response = JSONResponse({"detail": "Manutenzione backup in corso: operazioni educative e IA sospese."}, status_code=503)
            return await response(scope, receive, send)
        async with self.lock:
            await self.app(scope, receive, send)
