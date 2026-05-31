import json
import sys

def convert_sabs(input_path, output_path):
    with open(input_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    sabs = data["scala"]
    info = sabs["info"]
    
    # Costruisco la struttura target
    target = {
        "id": info["id"],
        "nome": info["nome"],
        "descrizione": info.get("target", "Adulti con disabilità intellettiva"),
        "sezioni": []
    }
    
    # Mappa le domande per sottoscala
    domande_by_sottoscala = {}
    for d in sabs.get("domande", []):
        sottoscala = d.get("sottoscala")
        if sottoscala not in domande_by_sottoscala:
            domande_by_sottoscala[sottoscala] = []
            
        target_domanda = {
            "id_domanda": str(d["id"]),
            "codice": d.get("codice"),
            "testo_domanda": d["testo"],
            "tipo": d.get("tipo", "likert"),
            "note": d.get("note")
        }
        
        # Opzioni
        if d.get("tipo") == "likert" and "opzioni" in d:
            target_domanda["opzioni"] = [
                {
                    "punteggio": op.get("punteggio"),
                    "testo_risposta": op.get("etichetta")
                }
                for op in d["opzioni"]
            ]
        elif d.get("tipo") == "composito" and "sottodomande" in d:
            target_domanda["sottodomande"] = [
                {
                    "testo": sub.get("testo")
                }
                for sub in d["sottodomande"]
            ]
        
        domande_by_sottoscala[sottoscala].append(target_domanda)
        
    # Costruisco le sezioni
    for s in sabs.get("sottoscale", []):
        codice = s.get("codice")
        target["sezioni"].append({
            "codice_sezione": codice,
            "titolo_sezione": s.get("nome"),
            "descrizione_sezione": None,
            "domande": domande_by_sottoscala.get(codice, [])
        })
        
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(target, f, ensure_ascii=False, indent=2)
        
if __name__ == "__main__":
    convert_sabs(sys.argv[1], sys.argv[2])
