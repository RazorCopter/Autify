from app.routers.patients import _build_patient_search_condition


def _matches_regex(value: str, regex_condition: dict) -> bool:
    import re

    flags = re.IGNORECASE if "i" in regex_condition.get("$options", "") else 0
    return re.search(regex_condition["$regex"], value, flags) is not None


def _matches(document: dict, condition: dict) -> bool:
    if "$and" in condition:
        return all(_matches(document, item) for item in condition["$and"])
    if "$or" in condition:
        return any(_matches(document, item) for item in condition["$or"])

    field, regex_condition = next(iter(condition.items()))
    return _matches_regex(document.get(field, ""), regex_condition)


def test_multi_word_search_matches_name_and_surname_prefix() -> None:
    condition = _build_patient_search_condition("Demo Gor")

    assert _matches({"nome": "Demo", "cognome": "Gorgone"}, condition)
    assert not _matches({"nome": "Demo", "cognome": "Rossi"}, condition)


def test_multi_word_search_is_order_independent() -> None:
    condition = _build_patient_search_condition("Gor Demo")

    assert _matches({"nome": "Demo", "cognome": "Gorgone"}, condition)


def test_search_escapes_regex_metacharacters() -> None:
    condition = _build_patient_search_condition("Demo G.")

    assert _matches({"nome": "Demo", "cognome": "G. Rossi"}, condition)
    assert not _matches({"nome": "Demo", "cognome": "Gorgone"}, condition)
