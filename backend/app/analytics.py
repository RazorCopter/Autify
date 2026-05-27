"""
analytics.py — Motore di calcolo psicometrico per scale multidimensionali.

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
        punteggio = r.get("punteggio", 0)
        
        # Gestione robusta per punteggi tridimensionali (SIS) o normali interi
        if isinstance(punteggio, dict):
            # Gestione caso speciale A3: F max = 3
            f_val = min(int(punteggio.get("F", 0)), 3) if codice.upper() == "A3" else int(punteggio.get("F", 0))
            d_val = int(punteggio.get("D", 0))
            t_val = int(punteggio.get("T", 0))
            valore = f_val + d_val + t_val
        else:
            valore = int(punteggio) if isinstance(punteggio, (int, float)) else 0

        for prefix in sorted_prefixes:
            if codice.upper().startswith(prefix.upper()):
                aggregated[prefix]["punteggio_totale"] += valore
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

        if num_domande == 0:
            domain_analyses.append({
                "codice": domain_code,
                "etichetta": domain["etichetta"],
                "punteggio_diretto": 0,
                "punteggio_standard": None,
                "percentile_dominio": None,
                "fascia": None,
                "num_domande": 0,
            })
            continue

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
        # Per garantire la coerenza metodologica, ricaviamo il percentile direttamente dal Punteggio Standard effettivo.
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

    # Dispatch SIS al motore di calcolo dedicato
    scale_id_check = scale_doc.get("id", "").lower()
    if "sis" in scale_id_check or scale_doc.get("tipo_scala") == "sis":
        return calcola_punteggi_sis(risposte, scale_doc)

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
        # Override con tab_qv per garantire precisione assoluta con la Tabella B del manuale
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


# ---------------------------------------------------------------------------
# SIS — Supports Intensity Scale: motore di calcolo dedicato
# ---------------------------------------------------------------------------

# Tabelle di conversione grezzo → (standard, percentile) per ciascun dominio.
# Ogni tupla: (min_grezzo, max_grezzo, punteggio_standard, percentile)
SIS_DOMAIN_RANGES: Dict[str, List[tuple[int, int, int, int]]] = {
    "A": [
        (88, 88, 20, 99),
        (85, 87, 19, 99),
        (81, 84, 18, 99),
        (77, 80, 17, 99),
        (73, 76, 16, 98),
        (68, 72, 15, 95),
        (62, 67, 14, 91),
        (55, 61, 13, 84),
        (48, 54, 12, 75),
        (40, 47, 11, 63),
        (32, 39, 10, 50),
        (25, 31, 9, 37),
        (18, 24, 8, 25),
        (11, 17, 7, 16),
        (6, 10, 6, 9),
        (3, 5, 5, 5),
        (1, 2, 4, 2),
        (0, 0, 3, 1),
    ],
    "B": [
        (90, 90, 19, 99),
        (88, 89, 18, 99),
        (84, 87, 17, 99),
        (79, 83, 16, 98),
        (74, 78, 15, 95),
        (69, 73, 14, 91),
        (63, 68, 13, 84),
        (56, 62, 12, 75),
        (49, 55, 11, 63),
        (41, 48, 10, 50),
        (33, 40, 9, 37),
        (25, 32, 8, 25),
        (16, 24, 7, 16),
        (9, 15, 6, 9),
        (5, 8, 5, 5),
        (2, 4, 4, 2),
        (0, 1, 3, 1),
    ],
    "C": [
        (96, 96, 20, 99),
        (92, 95, 19, 99),
        (86, 91, 18, 99),
        (79, 85, 17, 99),
        (72, 78, 16, 98),
        (64, 71, 15, 95),
        (55, 63, 14, 91),
        (46, 54, 13, 84),
        (36, 45, 12, 75),
        (27, 35, 11, 63),
        (18, 26, 10, 50),
        (9, 17, 9, 37),
        (6, 8, 8, 25),
        (4, 5, 7, 16),
        (3, 3, 6, 9),
        (2, 2, 5, 5),
        (1, 1, 4, 2),
        (0, 0, 3, 1),
    ],
    "D": [
        (92, 92, 20, 99),
        (86, 91, 19, 99),
        (78, 85, 18, 99),
        (70, 77, 17, 99),
        (61, 69, 16, 98),
        (52, 60, 15, 95),
        (42, 51, 14, 91),
        (32, 41, 13, 84),
        (23, 31, 12, 75),
        (15, 22, 11, 63),
        (7, 14, 10, 50),
        (4, 6, 9, 37),
        (2, 3, 8, 25),
        (1, 1, 7, 16),
        (0, 0, 6, 9),
    ],
    "E": [
        (86, 86, 20, 99),
        (79, 85, 19, 99),
        (71, 78, 18, 99),
        (61, 70, 17, 99),
        (51, 60, 16, 98),
        (42, 50, 15, 95),
        (34, 41, 14, 91),
        (26, 33, 13, 84),
        (18, 25, 12, 75),
        (11, 17, 11, 63),
        (6, 10, 10, 50),
        (3, 5, 9, 37),
        (2, 2, 8, 25),
        (1, 1, 7, 16),
        (0, 0, 6, 9),
    ],
    "F": [
        (91, 91, 20, 99),
        (85, 90, 19, 99),
        (77, 84, 18, 99),
        (68, 76, 17, 99),
        (58, 67, 16, 98),
        (48, 57, 15, 95),
        (38, 47, 14, 91),
        (28, 37, 13, 84),
        (19, 27, 12, 75),
        (10, 18, 11, 63),
        (5, 9, 10, 50),
        (3, 4, 9, 37),
        (2, 2, 8, 25),
        (1, 1, 7, 16),
        (0, 0, 6, 9),
    ],
}

# Tabella conversione somma punteggi standard → indice SIS e percentile.
# Valori esatti dalla tabella a p.127 del manuale SIS.
# Ogni tupla: (somma_min, somma_max, indice, percentile)
SIS_INDEX_TABLE: List[tuple[int, int, int, int]] = [
    (97, 999, 143, 99),
    (96, 96, 141, 99),
    (95, 95, 140, 99),
    (94, 94, 139, 99),
    (93, 93, 138, 99),
    (92, 92, 137, 99),
    (91, 91, 136, 99),
    (90, 90, 135, 99),
    (89, 89, 133, 99),
    (88, 88, 132, 99),
    (87, 87, 131, 98),
    (86, 86, 130, 98),
    (85, 85, 129, 97),
    (84, 84, 128, 97),
    (83, 83, 126, 96),
    (82, 82, 125, 95),
    (81, 81, 124, 95),
    (80, 80, 123, 94),
    (79, 79, 122, 93),
    (78, 78, 121, 92),
    (77, 77, 120, 91),
    (76, 76, 118, 89),
    (75, 75, 117, 87),
    (74, 74, 116, 86),
    (73, 73, 115, 84),
    (72, 72, 114, 82),
    (71, 71, 113, 81),
    (70, 70, 111, 77),
    (69, 69, 110, 75),
    (68, 68, 109, 73),
    (67, 67, 108, 70),
    (66, 66, 107, 68),
    (65, 65, 106, 65),
    (64, 64, 105, 63),
    (63, 63, 104, 61),
    (62, 62, 103, 58),
    (61, 61, 102, 55),
    (60, 60, 101, 53),
    (59, 59, 100, 50),
    (58, 58, 99, 47),
    (57, 57, 98, 45),
    (56, 56, 97, 42),
    (55, 55, 96, 39),
    (54, 54, 95, 37),
    (53, 53, 94, 34),
    (52, 52, 93, 32),
    (51, 51, 92, 30),
    (50, 50, 91, 27),
    (49, 49, 90, 25),
    (48, 48, 89, 23),
    (47, 47, 88, 21),
    (46, 46, 87, 19),
    (45, 45, 86, 18),
    (44, 44, 85, 16),
    (43, 43, 84, 14),
    (42, 42, 83, 13),
    (41, 41, 82, 12),
    (40, 40, 81, 10),
    (39, 39, 80, 9),
    (38, 38, 79, 8),
    (37, 37, 78, 7),
    (36, 36, 77, 6),
    (35, 35, 76, 5),
    (34, 34, 75, 5),
    (33, 33, 74, 4),
    (32, 32, 73, 3),
    (31, 31, 72, 3),
    (30, 30, 71, 2),
    (29, 29, 70, 2),
    (28, 28, 69, 2),
    (27, 27, 68, 1),
    (26, 26, 67, 1),
    (25, 25, 66, 1),
    (24, 24, 65, 1),
    (23, 23, 64, 1),
    (22, 22, 63, 1),
    (21, 21, 62, 1),
    (20, 20, 61, 1),
    (19, 19, 60, 1),
    (18, 18, 59, 1),
    (17, 17, 58, 1),
    (16, 16, 57, 1),
    (15, 15, 56, 1),
    (14, 14, 55, 1),
    (13, 13, 54, 1),
    (12, 12, 53, 1),
    (11, 11, 52, 1),
    (10, 10, 51, 1),
    (9, 9, 50, 1),
    (8, 8, 49, 1),
    (7, 7, 48, 1),
    (6, 6, 47, 1),
    (5, 5, 46, 1),
    (4, 4, 45, 1),
    (3, 3, 44, 1),
    (2, 2, 43, 1),
    (1, 1, 42, 1),
    (0, 0, 41, 1),
]

# Etichette dominio SIS (Sezione 1)
_SIS_DOMAIN_LABELS: Dict[str, str] = {
    "A": "Attività relative alla vita nell'ambiente domestico",
    "B": "Attività relative alla vita nella comunità",
    "C": "Attività di apprendimento nel corso della vita",
    "D": "Attività relative all'occupazione",
    "E": "Attività relative alla salute e alla sicurezza",
    "F": "Attività sociali",
}


def _calcola_grezzo_item_sis(risposta: dict, item_id: str) -> int:
    """
    Calcola il punteggio grezzo di un singolo item SIS.

    Il punteggio grezzo è la somma delle tre componenti:
    F (frequenza), D (durata giornaliera), T (tipo di supporto).

    Caso speciale: l'item A3 ha F_max=3 (non 4); il valore di F
    viene quindi limitato a 3 per quell'item.
    """
    f_val: int = int(risposta.get("F", 0))
    d_val: int = int(risposta.get("D", 0))
    t_val: int = int(risposta.get("T", 0))

    # Validazione intervalli 0-4
    f_val = max(0, min(f_val, 4))
    d_val = max(0, min(d_val, 4))
    t_val = max(0, min(t_val, 4))

    # Caso speciale: item A3 ha frequenza massima 3
    if item_id.upper() == "A3":
        f_val = min(f_val, 3)

    return f_val + d_val + t_val


def _lookup_sis_standard_percentile(
    grezzo: int,
    dominio: str,
) -> tuple[Optional[int], Optional[int]]:
    """
    Cerca il punteggio standard e il percentile per un dato punteggio
    grezzo di dominio nella tabella di conversione SIS.

    Restituisce (standard, percentile) oppure (None, None) se il
    dominio non è presente nella tabella.
    """
    ranges = SIS_DOMAIN_RANGES.get(dominio.upper())
    if not ranges:
        return None, None

    # Clamp al range della tabella (primo elemento = max, ultimo = min)
    min_val = ranges[-1][0]
    max_val = ranges[0][1]
    grezzo = max(min_val, min(grezzo, max_val))

    for r_min, r_max, std, perc in ranges:
        if r_min <= grezzo <= r_max:
            return std, perc

    return None, None


def _lookup_indice_sis(
    somma_standard: int,
) -> tuple[Optional[int], Optional[int]]:
    """
    Cerca l'indice SIS e il percentile globale a partire dalla
    somma dei punteggi standard dei 6 domini.

    Il valore viene limitato (clamp) all'intervallo valido della
    tabella di conversione.
    """
    if not SIS_INDEX_TABLE:
        return None, None

    # Clamp al range valido
    table_min = SIS_INDEX_TABLE[-1][0]
    table_max = SIS_INDEX_TABLE[0][1]
    somma_standard = max(table_min, min(somma_standard, table_max))

    for s_min, s_max, indice, perc in SIS_INDEX_TABLE:
        if s_min <= somma_standard <= s_max:
            return indice, perc

    return None, None


def _classifica_intensita_sis(indice: int) -> str:
    """
    Restituisce il livello di classificazione dell'intensità del
    supporto in base all'indice SIS.

    - Livello I:   indice ≤ 84
    - Livello II:  indice 85-99
    - Livello III: indice 100-115
    - Livello IV:  indice ≥ 116
    """
    if indice <= 84:
        return "Livello I"
    elif indice <= 99:
        return "Livello II"
    elif indice <= 115:
        return "Livello III"
    else:
        return "Livello IV"


def _calcola_sezione2_top4(
    risposte_sez2: Dict[str, dict],
) -> List[dict]:
    """
    Calcola il punteggio grezzo (F + D + T) per ogni item della
    Sezione 2 (Protezione e tutela) e restituisce i 4 item con
    punteggio più alto, ordinati in senso decrescente.
    """
    scored: List[dict] = []
    for item_id, risposta in risposte_sez2.items():
        f_val = max(0, min(int(risposta.get("F", 0)), 4))
        d_val = max(0, min(int(risposta.get("D", 0)), 4))
        t_val = max(0, min(int(risposta.get("T", 0)), 4))
        grezzo = f_val + d_val + t_val
        scored.append({"id": item_id, "punteggio_grezzo": grezzo})

    scored.sort(key=lambda x: x["punteggio_grezzo"], reverse=True)
    return scored[:4]


def _calcola_alert_sezione3(
    risposte_sezione: Dict[str, int],
) -> dict:
    """
    Analizza le risposte della Sezione 3 (bisogni medici o
    comportamentali eccezionali).

    Per ogni item il valore può essere:
      0 = nessun bisogno
      1 = bisogno parziale
      2 = bisogno estensivo

    L'alert si attiva se:
      - il totale dei bisogni (parziali + estensivi) supera 5, OPPURE
      - almeno un item ha valore 2 (estensivo).

    Restituisce un dizionario con conteggi, flag di alert e lista
    degli item segnalati.
    """
    count_parziale = 0
    count_estensivo = 0
    items_segnalati: List[dict] = []

    for item_id, valore in risposte_sezione.items():
        valore = max(0, min(int(valore), 2))
        if valore == 1:
            count_parziale += 1
            items_segnalati.append({"id": item_id, "valore": valore})
        elif valore == 2:
            count_estensivo += 1
            items_segnalati.append({"id": item_id, "valore": valore})

    totale = count_parziale + count_estensivo
    alert = totale > 5 or count_estensivo > 0

    return {
        "alert": alert,
        "count_parziale": count_parziale,
        "count_estensivo": count_estensivo,
        "totale": totale,
        "items_segnalati": items_segnalati,
    }


def calcola_punteggi_sis(
    risposte: list,
    scale_config: dict,
) -> dict:
    """
    Funzione principale di orchestrazione per il calcolo dei punteggi
    della Supports Intensity Scale (SIS).

    Parametri
    ---------
    risposte : list
        Lista piatta di risposte, ciascuna con:
          - codice_domanda : str  (es. "A1", "B3", "P1", "M5", "BC1")
          - punteggio : int | dict
            · dict {"F": int, "D": int, "T": int}  per domini A-F e Sezione 2
            · int (0/1/2)                           per Sezione 3

    scale_config : dict
        Documento completo della scala SIS da MongoDB.

    Convenzione prefissi
    --------------------
    - A1..A8, B1..B8, C1..C9, D1..D8, E1..E8, F1..F8  → Domini Sezione 1
    - P1..P8                                            → Sezione 2 (Protezione)
    - M1..M16                                           → Sezione 3 medica
    - BC1..BC13                                         → Sezione 3 comportamentale

    Restituisce
    -----------
    dict con:
        domini, somma_punteggi_standard, indice_sis, percentile,
        classificazione_intensita, sezione_2_top4,
        alert_medico, alert_comportamentale,
        dettaglio_medico, dettaglio_comportamentale, scala_nome.
    """
    # --- Separazione risposte per sezione ---
    risposte_domini: Dict[str, List[dict]] = {
        d: [] for d in "ABCDEF"
    }
    risposte_sez2: Dict[str, dict] = {}
    risposte_sez3_medica: Dict[str, int] = {}
    risposte_sez3_comportamentale: Dict[str, int] = {}

    for r in risposte:
        codice: str = r.get("codice_domanda", "").strip()
        punteggio = r.get("punteggio", 0)
        codice_upper = codice.upper()

        if codice_upper.startswith("BC"):
            # Sezione 3 comportamentale (prefisso "BC")
            risposte_sez3_comportamentale[codice] = (
                int(punteggio) if isinstance(punteggio, (int, float)) else 0
            )
        elif codice_upper.startswith("M"):
            # Sezione 3 medica
            risposte_sez3_medica[codice] = (
                int(punteggio) if isinstance(punteggio, (int, float)) else 0
            )
        elif codice_upper.startswith("P"):
            # Sezione 2 (Protezione e tutela)
            if isinstance(punteggio, dict):
                risposte_sez2[codice] = punteggio
            else:
                risposte_sez2[codice] = {"F": 0, "D": 0, "T": 0}
        else:
            # Domini A-F della Sezione 1
            prefix = codice_upper[0] if codice_upper else ""
            if prefix in risposte_domini:
                item_data = (
                    punteggio if isinstance(punteggio, dict)
                    else {"F": 0, "D": 0, "T": 0}
                )
                risposte_domini[prefix].append({
                    "id": codice,
                    **item_data,
                })

    # --- Calcolo punteggi per ogni dominio A-F ---
    domini_result: List[dict] = []
    somma_standard = 0
    all_domains_have_std = True

    for dom_code in "ABCDEF":
        items = risposte_domini[dom_code]
        grezzo_dominio = 0
        for item in items:
            grezzo_dominio += _calcola_grezzo_item_sis(item, item["id"])

        std, perc = _lookup_sis_standard_percentile(grezzo_dominio, dom_code)

        if std is not None:
            somma_standard += std
        else:
            all_domains_have_std = False

        domini_result.append({
            "codice": dom_code,
            "etichetta": _SIS_DOMAIN_LABELS.get(dom_code, dom_code),
            "punteggio_grezzo": grezzo_dominio,
            "punteggio_standard": std,
            "percentile": perc,
            "num_domande": len(items),
        })

    # --- Indice SIS globale ---
    indice_sis: Optional[int] = None
    percentile_globale: Optional[int] = None
    classificazione: Optional[str] = None

    if all_domains_have_std:
        indice_sis, percentile_globale = _lookup_indice_sis(somma_standard)
        if indice_sis is not None:
            classificazione = _classifica_intensita_sis(indice_sis)

    # --- Sezione 2: top 4 ---
    sezione_2_top4 = _calcola_sezione2_top4(risposte_sez2)

    # --- Sezione 3: alert medici e comportamentali ---
    dettaglio_medico = _calcola_alert_sezione3(risposte_sez3_medica)
    dettaglio_comportamentale = _calcola_alert_sezione3(
        risposte_sez3_comportamentale
    )

    return {
        "domini": domini_result,
        "somma_punteggi_standard": (
            somma_standard if all_domains_have_std else None
        ),
        "indice_sis": indice_sis,
        "percentile": percentile_globale,
        "classificazione_intensita": classificazione,
        "sezione_2_top4": sezione_2_top4,
        "alert_medico": dettaglio_medico["alert"],
        "alert_comportamentale": dettaglio_comportamentale["alert"],
        "dettaglio_medico": {
            "count_parziale": dettaglio_medico["count_parziale"],
            "count_estensivo": dettaglio_medico["count_estensivo"],
            "totale": dettaglio_medico["totale"],
            "items_segnalati": dettaglio_medico["items_segnalati"],
        },
        "dettaglio_comportamentale": {
            "count_parziale": dettaglio_comportamentale["count_parziale"],
            "count_estensivo": dettaglio_comportamentale["count_estensivo"],
            "totale": dettaglio_comportamentale["totale"],
            "items_segnalati": dettaglio_comportamentale["items_segnalati"],
        },
        "scala_nome": scale_config.get(
            "nome", "Supports Intensity Scale (SIS)"
        ),
    }

