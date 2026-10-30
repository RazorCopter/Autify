"""Small shared output protections, without altering stored educational data."""
import unicodedata


def safe_csv_cell(value):
    if value is None:
        return ""
    text = str(value)
    # CSV quoting alone does not prevent spreadsheet formula evaluation.
    probe = text.lstrip()
    while probe and unicodedata.category(probe[0]) in ("Cc", "Cf", "Zs", "Zl", "Zp"):
        probe = probe[1:].lstrip()
    if probe.startswith(("=", "+", "-", "@")) or text.startswith(("\t", "\r", "\n")):
        return "'" + text
    return text


class PrivateApiResponses:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        async def private_send(message):
            if message["type"] == "http.response.start" and scope.get("path", "").startswith("/api/"):
                headers = [(k, v) for k, v in message.get("headers", []) if k.lower() not in (b"cache-control", b"x-content-type-options")]
                message = {**message, "headers": headers + [(b"cache-control", b"no-store"), (b"x-content-type-options", b"nosniff")]}
            await send(message)
        await self.app(scope, receive, private_send)
