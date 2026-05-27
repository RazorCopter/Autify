"""Test unitari per il motore di calcolo SIS."""
from app.analytics import (
    calcola_punteggi_sis,
    _calcola_grezzo_item_sis,
    _lookup_sis_standard_percentile,
    _lookup_indice_sis,
    _classifica_intensita_sis,
    _calcola_alert_sezione3,
    _calcola_sezione2_top4,
)


def test_grezzo_item_standard():
    assert _calcola_grezzo_item_sis({"F": 2, "D": 3, "T": 1}, "A1") == 6
    print("OK Test 1: grezzo A1 = 6")


def test_grezzo_item_a3_fmax():
    assert _calcola_grezzo_item_sis({"F": 4, "D": 4, "T": 4}, "A3") == 11
    print("OK Test 2: grezzo A3 (F_max=3) = 11")


def test_lookup_dominio_a():
    std, perc = _lookup_sis_standard_percentile(45, "A")
    assert std == 11 and perc == 63, f"Expected (11, 63) got ({std}, {perc})"
    print(f"OK Test 3: A grezzo=45 -> std={std}, perc={perc}")


def test_lookup_dominio_d_zero():
    std, perc = _lookup_sis_standard_percentile(0, "D")
    assert std == 6 and perc == 9
    print(f"OK Test 4: D grezzo=0 -> std={std}, perc={perc}")


def test_indice_sis_59():
    indice, perc = _lookup_indice_sis(59)
    assert indice == 100 and perc == 50
    print(f"OK Test 5: somma=59 -> indice={indice}, perc={perc}")


def test_classificazione():
    assert _classifica_intensita_sis(80) == "Livello I"
    assert _classifica_intensita_sis(95) == "Livello II"
    assert _classifica_intensita_sis(100) == "Livello III"
    assert _classifica_intensita_sis(120) == "Livello IV"
    print("OK Test 6: classificazione I/II/III/IV")


def test_alert_sezione3_con_estensivo():
    result = _calcola_alert_sezione3({"M1": 0, "M2": 1, "M3": 0, "M4": 2})
    assert result["alert"] is True
    assert result["count_parziale"] == 1
    assert result["count_estensivo"] == 1
    print(f"OK Test 7: alert medico attivo")


def test_alert_sezione3_senza_alert():
    result = _calcola_alert_sezione3({"M1": 0, "M2": 0, "M3": 1, "M4": 1})
    assert result["alert"] is False
    print(f"OK Test 8: no alert (totale=2, no estensivi)")


def test_sezione2_top4():
    sez2 = {
        "P1": {"F": 1, "D": 0, "T": 0},
        "P2": {"F": 3, "D": 3, "T": 2},
        "P3": {"F": 4, "D": 4, "T": 4},
        "P4": {"F": 0, "D": 0, "T": 0},
        "P5": {"F": 2, "D": 1, "T": 1},
        "P6": {"F": 1, "D": 1, "T": 1},
        "P7": {"F": 3, "D": 2, "T": 3},
        "P8": {"F": 0, "D": 1, "T": 0},
    }
    top4 = _calcola_sezione2_top4(sez2)
    assert len(top4) == 4
    assert top4[0]["id"] == "P3"
    assert top4[0]["punteggio_grezzo"] == 12
    ids = [t["id"] for t in top4]
    print(f"OK Test 9: top4 = {ids}")


def test_calcola_punteggi_sis_completo():
    risposte = []
    # Dominio A: 8 item, tutti F=2/D=2/T=2 → grezzo item=6, grezzo dominio=48
    for i in range(1, 9):
        risposte.append({"codice_domanda": f"A{i}", "punteggio": {"F": 2, "D": 2, "T": 2}})
    # Domini B-F: tutti F=1/D=1/T=1 → grezzo item=3
    for dom in "BCDEF":
        num = 9 if dom == "C" else 8
        for i in range(1, num + 1):
            risposte.append({"codice_domanda": f"{dom}{i}", "punteggio": {"F": 1, "D": 1, "T": 1}})
    # Sezione 2
    for i in range(1, 9):
        risposte.append({"codice_domanda": f"P{i}", "punteggio": {"F": 2, "D": 1, "T": 1}})
    # Sezione 3 medica
    for i in range(1, 5):
        risposte.append({"codice_domanda": f"M{i}", "punteggio": 0})
    risposte.append({"codice_domanda": "M5", "punteggio": 2})
    # Sezione 3 comportamentale
    for i in range(1, 4):
        risposte.append({"codice_domanda": f"BC{i}", "punteggio": 1})

    result = calcola_punteggi_sis(risposte, {"nome": "SIS Test"})

    # Verifica dominio A: grezzo=48 → std=12, perc=75
    dom_a = result["domini"][0]
    assert dom_a["codice"] == "A"
    assert dom_a["punteggio_grezzo"] == 48, f"A grezzo: {dom_a['punteggio_grezzo']}"
    assert dom_a["punteggio_standard"] == 12, f"A std: {dom_a['punteggio_standard']}"
    assert dom_a["percentile"] == 75, f"A perc: {dom_a['percentile']}"

    # Verifica dominio B: grezzo=8*3=24 → std=7, perc=16
    dom_b = result["domini"][1]
    assert dom_b["punteggio_grezzo"] == 24
    assert dom_b["punteggio_standard"] == 7

    # Verifica dominio C: grezzo=9*3=27 → std=11, perc=63
    dom_c = result["domini"][2]
    assert dom_c["punteggio_grezzo"] == 27
    assert dom_c["punteggio_standard"] == 11

    # Verifica somma standard, indice, classificazione
    assert result["somma_punteggi_standard"] is not None
    assert result["indice_sis"] is not None
    assert result["classificazione_intensita"] is not None

    # Alert medico attivo (c'è un M5=2)
    assert result["alert_medico"] is True
    # Alert comportamentale: 3 item con valore 1, totale=3, no estensivi → False
    assert result["alert_comportamentale"] is False

    print(f"OK Test 10: Calcolo completo SIS")
    for d in result["domini"]:
        print(f"  {d['codice']}: grezzo={d['punteggio_grezzo']}, std={d['punteggio_standard']}, perc={d['percentile']}")
    print(f"  Somma standard: {result['somma_punteggi_standard']}")
    print(f"  Indice SIS: {result['indice_sis']}")
    print(f"  Percentile: {result['percentile']}")
    print(f"  Classificazione: {result['classificazione_intensita']}")
    print(f"  Top4 Sez2: {result['sezione_2_top4']}")
    print(f"  Alert medico: {result['alert_medico']}")
    print(f"  Alert comport.: {result['alert_comportamentale']}")


if __name__ == "__main__":
    test_grezzo_item_standard()
    test_grezzo_item_a3_fmax()
    test_lookup_dominio_a()
    test_lookup_dominio_d_zero()
    test_indice_sis_59()
    test_classificazione()
    test_alert_sezione3_con_estensivo()
    test_alert_sezione3_senza_alert()
    test_sezione2_top4()
    test_calcola_punteggi_sis_completo()
    print()
    print("=== TUTTI I 10 TEST SUPERATI ===")
