"""Bounded PDF rendering and escaping for all user-provided paragraph text."""
import asyncio
import functools
import threading
from html import escape
from fastapi import HTTPException

_render_lock = threading.RLock()
_slots = asyncio.Semaphore(2)


def xml_text(value):
    text = "" if value is None else str(value)
    text = "".join(c for c in text if ord(c) >= 32 or c in "\t\n\r")
    return escape(text, quote=False).replace("\n", "<br/>")


def serialized_pdf(function):
    @functools.wraps(function)
    def render(*args, **kwargs):
        # Matplotlib fonts/layout still share caches even with isolated Figure objects.
        with _render_lock:
            return function(*args, **kwargs)
    return render


async def render_pdf(function, *args, **kwargs):
    try:
        await asyncio.wait_for(_slots.acquire(), timeout=5)
    except asyncio.TimeoutError as exc:
        raise HTTPException(503, "Generazione PDF occupata: riprovare tra poco", headers={"Retry-After": "5"}) from exc
    task = asyncio.create_task(asyncio.to_thread(function, *args, **kwargs))
    try:
        return await asyncio.shield(task)
    except asyncio.CancelledError:
        # A Python thread cannot be cancelled; retain the slot until it finishes.
        await task
        raise
    finally:
        _slots.release()
