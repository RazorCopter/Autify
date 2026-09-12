# routers module — shared utilities and state
import time as _time

_dashboard_cache: dict = {"data": None, "ts": 0.0}
_DASHBOARD_CACHE_TTL = 300  # 5 minuti


def _invalidate_dashboard_cache() -> None:
    _dashboard_cache["data"] = None
    _dashboard_cache["ts"] = 0.0


from ._helpers import (
    verify_auth,
    log_audit,
    _classify_scale,
    _update_patient_scale_dates,
    _find_evaluation_document,
    _extract_evaluation_identifier,
    _build_evaluation_selector,
    _normalize_scale_name,
    _load_builtin_san_martin_scale,
    _load_builtin_sis_scale,
    _hydrate_scale_doc,
)
