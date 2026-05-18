"""
analytics.py — Motore di calcolo psicometrico per scale cliniche.

Supporta sia scale con tabelle di conversione (San Martín) sia scale semplici (POS)
con semplice aggregazione per dominio.
"""

from typing import Any, Dict, List, Optional

SAN_MARTIN_STANDARD_SCORE_RANGES: Dict[str, List[tuple[int, int, int]]] = {
    "AU": [(48, 48, 17), (46, 47, 16), (43, 45, 15), (41, 42, 14), (39, 40, 13),
           (36, 38, 12), (34, 35, 11), (31, 33, 10), (29, 30, 9), (27, 28, 8),
           (24, 26, 7), (22, 23, 6), (20, 21, 5), (17, 19, 4), (15, 16, 3),
           (13, 14, 2), (0, 13, 1)],
    "BE": [(47, 48, 15), (45, 46, 14), (43, 44, 13), (41, 42, 12), (38, 40, 11),
           (36, 37, 10), (34, 35, 9), (32, 33, 8), (30, 31, 7), (27, 29, 6),
           (25, 26, 5), (23, 24, 4), (21, 22, 3), (19, 20, 2), (0, 19, 1)],
    "BF": [(48, 48, 15), (46, 47, 14), (44, 45, 13), (42, 43, 12), (40, 41, 11),
           (38, 39, 10), (36, 37, 9), (34, 35, 8), (32, 33, 7), (30, 31, 6),
           (28, 29, 5), (26, 27, 4), (24, 25, 3), (22, 23, 2), (0, 21, 1)],
    "BM": [(48, 48, 14), (46, 47, 13), (44, 45, 12), (42, 43, 11), (40, 41, 10),
           (38, 39, 9), (36, 37, 8), (34, 35, 7), (32, 33, 6), (30, 31, 5),
           (28, 29, 4), (25, 27, 3), (23, 24, 2), (0, 22, 1)],
    "DI": [(48, 48, 15), (46, 47, 14), (44, 45, 13), (43, 43, 12), (41, 42, 11),
           (39, 40, 10), (37, 38, 9), (36, 36, 8), (34, 35, 7), (32, 33, 6),
           (30, 31, 5), (29, 29, 4), (27, 28, 3), (25, 26, 2), (0, 24, 1)],
    "SP": [(47, 48, 15), (45, 46, 14), (42, 44, 13), (40, 41, 12), (37, 39, 11),
           (35, 36, 10), (32, 34, 9), (30, 31, 8), (27, 29, 7), (25, 26, 6),
           (22, 24, 5), (20, 21, 4), (17, 19, 3), (15, 16, 2), (0, 14, 1)],
    "IS": [(43, 44, 15), (40, 42, 14), (38, 39, 13), (35, 37, 12), (33, 34, 11),
           (30, 32, 10), (28, 29, 9), (25, 27, 8), (23, 24, 7), (20, 22, 6),
           (18, 19, 5), (15, 17, 4), (13, 14, 3), (11, 12, 2), (0, 10, 1)],
    "RI": [(47, 48, 15), (45, 46, 14), (43, 44, 13), (41, 42, 12), (39, 40, 11),
           (36, 38, 10), (34, 35, 9), (32, 33, 8), (30, 31, 7), (27, 29, 6),
           (25, 26, 5), (23, 24, 4), (21, 22, 3), (19, 20, 2), (0, 18, 1)],
}

tab_qv: Dict[int, tuple[int, Any]] = {
    122: (132, 98),
    121: (131, 98),
    120: (130, 98),
    119: (129, 97),
    118: (128, 97),
    117: (128, 97),
    116: (127, 96),
    115: (126, 96),
    114: (125, 95),
    113: (125, 95),
    112: (124, 94),
    111: (124, 94),
    110: (122, 93),
    109: (122, 93),
    108: (121, 92),
    107: (120, 91),
    106: (119, 90),
    105: (119, 89),
    104: (118, 88),
    103: (117, 87),
    102: (116, 86),
    101: (116, 85),
    100: (115, 84),
    99: (114, 82),
    98: (113, 81),
    97: (113, 80),
    96: (112, 78),
    95: (111, 77),
    94: (110, 75),
    93: (110, 74),
    92: (109, 72),
    91: (108, 70),
    90: (107, 68),
    89: (107, 67),
    88: (106, 65),
    87: (105, 63),
    86: (105, 61),
    85: (104, 59),
    84: (103, 57),
    83: (102, 55),
    82: (101, 53),
    81: (101, 51),
    80: (100, 50),
    79: (99, 47),
    78: (98, 45),
    77: (98, 43),
    76: (97, 41),
    75: (96, 39),
    74: (95, 37),
    73: (95, 35),
    72: (94, 34),
    71: (93, 32),
    70: (92, 30),
    69: (91, 28),
    68: (90, 26),
    67: (90, 23),
    66: (89, 22),
    65: (89, 22),
    64: (88, 20),
    63: (87, 19),
    62: (86, 17),
    61: (85, 16),
    60: (85, 15),
    59: (84, 14),
    58: (83, 13),
    57: (82, 12),
    56: (82, 11),
    55: (81, 10),
    54: (80, 9),
    53: (79, 8),
    52: (79, 8),
    51: (78, 7),
    50: (77, 6),
    49: (77, 6),
    48: (76, 5),
    47: (75, 5),
    46: (74, 4),
    45: (74, 4),
    44: (73, 3),
    43: (72, 3),
    42: (71, 3),
    41: (70, 2),
    40: (70, 2),
    39: (69, 2),
    38: (69, 2),
    37: (68, 2),
    36: (67, 1),
    35: (67, 1),
    34: (66, 1),
    33: (65, 1),
    32: (64, 1),
    31: (63, 1),
    30: (62, 1),
    29: (62, 1),
    28: (61, "<1"),
    27: (60, "<1"),
    26: (59, "<1"),
    25: (58, "<1"),
    24: (58, "<1"),
    23: (57, "<1"),
    22: (57, "<1"),
    21: (56, "<1"),
    20: (55, "<1"),
    19: (54, "<1"),
    18: (53, "<1"),
    17: (52, "<1"),
    16: (52, "<1"),
    15: (25, "<1"),
    14: (24, "<1"),
    13: (23, "<1"),
    12: (22, "<1"),
    11: (21, "<1"),
    10: (20, "<1"),
    9: (19, "<1"),
    8: (18, "<1"),
}


def build_domain_map(scale_doc: dict) -> Dict[str, str]:
    """Costruisce la mappa {codice_dominio: nome_dominio} da un documento Scale."""
    domain_map: Dict[str, str] = {}
    for sezione in scale_doc.get("sezioni", []):
        cod = sezione.get("codice_sezione", "")
        nome = sezione.get("titolo_sezione", cod)
        if cod:
            domain_map[cod.upper()] = nome
    return domain_map


def compute_direct_scores(risposte: list, domain_map: Dict[str, str]) -> List[dict]:
    """Calcola i punteggi diretti (grezzi) per ogni dominio."""
    sorted_prefixes = sorted(domain_map.keys(), key=len, reverse=True)
    aggregated: Dict[str, dict] = {}
    for cod, label in domain_map.items():
        aggregated[cod] = {
            "codice": cod,
            "etichetta": label,
            "punteggio_totale": 0,
            "num_domande": 0,
        }

    for r in risposte:
        codice = r.get("codice_domanda", "")
        for prefix in sorted_prefixes:
            if codice.upper().startswith(prefix.upper()):
                aggregated[prefix]["punteggio_totale"] += r.get("punteggio", 0)
                aggregated[prefix]["num_domande"] += 1
                break

    return list(aggregated.values())


def _std_to_fascia(std: int) -> str:
    """Restituisce la fascia interpretativa per un punteggio standard."""
    if std <= 4:
        return "Molto Basso"
    elif std <= 7:
        return "Basso"
    elif std <= 12:
        return "Medio"
    elif std <= 15:
        return "Alto"
    else:
        return "Molto Alto"


def _get_domain_conversion_table(
    domain_code: str,
    num_domande: int,
    table_a: Dict[str, Any],
) -> Dict[str, Any]:
    """Seleziona la tabella di conversione corretta per il dominio corrente."""
    domini_12 = table_a.get("domini_con_12_item", {})
    dominio_11 = table_a.get("dominio_IS_con_11_item", {})

    # San Martín ha 7 domini da 12 item e un dominio da 11 item.
    # Privilegiamo il numero di item effettivamente aggregati, con fallback sul codice.
    if num_domande == 11 and dominio_11:
        return dominio_11
    if domain_code.upper() == "IS" and dominio_11:
        return dominio_11
    return domini_12


def _lookup_standard_score_from_matrix(domain_code: str, raw_score: int) -> Optional[int]:
    """Calcola il punteggio standard usando la matrice specifica per dominio."""
    ranges = SAN_MARTIN_STANDARD_SCORE_RANGES.get(domain_code.upper())
    if not ranges:
        return None

    for min_score, max_score, standard_score in ranges:
        if min_score <= raw_score <= max_score:
            return standard_score
    return None


def _lookup_conversion_entry(
    score: int,
    table_section: Dict[str, Any],
) -> Optional[Dict[str, Any]]:
    """
    Recupera la riga di conversione in modo robusto:
    1. match esatto sulla chiave stringa;
    2. clamp sul range dichiarato della tabella;
    3. fallback al vicino più prossimo se il JSON fosse incompleto.
    """
    conversion_map = table_section.get("conversione", {})
    if not conversion_map:
        return None

    exact_key = str(score)
    if exact_key in conversion_map:
        return conversion_map[exact_key]

    numeric_keys = sorted(
        int(key)
        for key in conversion_map.keys()
        if str(key).lstrip("-").isdigit()
    )
    if not numeric_keys:
        return None

    declared_range = table_section.get("punteggi_diretti_range")
    if isinstance(declared_range, list) and len(declared_range) == 2:
        min_score, max_score = int(declared_range[0]), int(declared_range[1])
    else:
        min_score, max_score = numeric_keys[0], numeric_keys[-1]

    clamped_score = min(max(score, min_score), max_score)
    clamped_key = str(clamped_score)
    if clamped_key in conversion_map:
        return conversion_map[clamped_key]

    closest_key = min(numeric_keys, key=lambda key: abs(key - score))
    return conversion_map.get(str(closest_key))


def _build_domain_analyses(
    direct_scores: List[dict],
    table_a: Dict[str, Any],
) -> tuple[List[dict], Optional[int]]:
    """Converte i punteggi grezzi di dominio in punteggi standard."""
    domain_analyses: List[dict] = []
    total_standard = 0
    has_any_standard_score = False

    for domain in direct_scores:
        raw_score = domain["punteggio_totale"]
        domain_code = domain["codice"]
        num_domande = domain["num_domande"]

        table_section = _get_domain_conversion_table(
            domain_code=domain_code,
            num_domande=num_domande,
            table_a=table_a,
        )
        entry = _lookup_conversion_entry(
            score=raw_score,
            table_section=table_section,
        ) or {}
        standard_score = _lookup_standard_score_from_matrix(domain_code, raw_score)
        if standard_score is None:
            standard_score = entry.get("std")

        # I percentili del dominio dipendono direttamente e matematicamente dal Punteggio Standard (media 10, DS 3).
        # Per garantire la coerenza clinica, ricaviamo il percentile direttamente dal Punteggio Standard effettivo.
        if standard_score is not None:
            std_to_perc_map = {
                1: 1, 2: 1, 3: 1, 4: 2, 5: 5, 6: 9, 7: 16, 8: 25, 9: 37,
                10: 50, 11: 63, 12: 75, 13: 84, 14: 91, 15: 95, 16: 98,
                17: 99, 18: 99, 19: 99, 20: 99
            }
            percentile = std_to_perc_map.get(standard_score, entry.get("perc"))
        else:
            percentile = entry.get("perc")

        fascia = _std_to_fascia(standard_score) if standard_score is not None else None

        print(
            f"DEBUG ANALYTICS - Dominio {domain_code} - "
            f"Grezzo: {raw_score} (item: {num_domande}) -> "
            f"Standard calcolato: {standard_score}, Percentile: {percentile}"
        )

        domain_analyses.append({
            "codice": domain_code,
            "etichetta": domain["etichetta"],
            "punteggio_diretto": raw_score,
            "punteggio_standard": standard_score,
            "percentile_dominio": percentile,
            "fascia": fascia,
            "num_domande": num_domande,
        })

        if standard_score is not None:
            total_standard += standard_score
            has_any_standard_score = True

    return domain_analyses, total_standard if has_any_standard_score else None


def compute_psychometric_analysis(
    risposte: list,
    scale_doc: dict,
) -> dict:
    """
    Calcola l'analisi psicometrica completa.

    Per scale con scoring_tables (San Martín):
      - Punteggio diretto per dominio
      - Punteggio standard (1-20) via tabella A
      - Percentile per dominio via tabella A
      - Indice QdV = somma std → tabella B
      - Percentile globale via tabella B

    Per scale senza scoring_tables (POS): solo punteggi diretti.

    Returns:
        {
            "domini": [{codice, etichetta, punteggio_diretto, punteggio_standard,
                        percentile_dominio, fascia, num_domande}, ...],
            "somma_punteggi_standard": int | None,
            "indice_qv": int | None,
            "percentile": int | None,
            "fascia_qv": str | None,
            "scala_nome": str,
        }
    """
    domain_map = build_domain_map(scale_doc)
    direct_scores = compute_direct_scores(risposte, domain_map)

    scoring = scale_doc.get("scoring_tables")
    if not scoring:
        return {
            "domini": [
                {
                    "codice": d["codice"],
                    "etichetta": d["etichetta"],
                    "punteggio_diretto": d["punteggio_totale"],
                    "punteggio_standard": None,
                    "percentile_dominio": None,
                    "fascia": None,
                    "num_domande": d["num_domande"],
                }
                for d in direct_scores
            ],
            "somma_punteggi_standard": None,
            "indice_qv": None,
            "percentile": None,
            "fascia_qv": None,
            "scala_nome": scale_doc.get("nome", ""),
        }

    table_a = scoring.get("tabella_A_conversione_punteggi_diretti_standard", {})
    table_b = scoring.get("tabella_B_indice_qdv", {})
    domain_analyses, total_standard = _build_domain_analyses(
        direct_scores=direct_scores,
        table_a=table_a,
    )

    indice_qv = None
    percentile = None
    fascia_qv = None

    if total_standard is not None:
        # Override con tab_qv per garantire precisione clinica assoluta con la Tabella B del manuale
        scale_id = scale_doc.get("id", "").lower()
        scale_nome = scale_doc.get("nome", "").lower()
        is_san_martin = (
            "sanmartin" in scale_id or 
            "san_martin" in scale_id or
            "san martin" in scale_nome or
            "san martín" in scale_nome
        )
        if is_san_martin and total_standard in tab_qv:
            indice_qv, percentile = tab_qv[total_standard]
        else:
            qdv_entry = _lookup_conversion_entry(
                score=total_standard,
                table_section=table_b,
            ) or {}
            indice_qv = qdv_entry.get("indice")
            percentile = qdv_entry.get("perc")
            
        fascia_qv = _indice_to_fascia(indice_qv) if indice_qv is not None else None

        print(
            f"DEBUG ANALYTICS - Somma standard: {total_standard} -> "
            f"Indice QV: {indice_qv}, Percentile: {percentile}, Fascia: {fascia_qv}"
        )

    return {
        "domini": domain_analyses,
        "somma_punteggi_standard": total_standard,
        "indice_qv": indice_qv,
        "percentile": percentile,
        "fascia_qv": fascia_qv,
        "scala_nome": scale_doc.get("nome", ""),
    }


def _indice_to_fascia(indice: int) -> str:
    """Restituisce la fascia interpretativa per l'indice QdV (media=100, DS=15)."""
    if indice >= 130:
        return "Molto Alto"
    elif indice >= 116:
        return "Alto"
    elif indice >= 85:
        return "Medio"
    elif indice >= 70:
        return "Basso"
    else:
        return "Molto Basso"
