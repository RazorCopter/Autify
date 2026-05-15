import asyncio
import csv
import os
import uuid
from motor.motor_asyncio import AsyncIOMotorClient
from models import Scale, Section, Question

# Connessione locale per lo script standalone
MONGODB_URL = os.getenv("MONGODB_URL", "mongodb://localhost:27017")
client = AsyncIOMotorClient(MONGODB_URL)
database = client.autanalysis
scales_collection = database.get_collection("scales")

async def seed_from_csv():
    csv_filename = 'POS eterovalutativa.xlsx - Foglio1.csv'
    csv_path = os.path.join(os.path.dirname(__file__), csv_filename)
    
    if not os.path.exists(csv_path):
        print(f"File non trovato: {csv_path}")
        print(f"Assicurati di creare/caricare '{csv_filename}' in questa directory prima di lanciare lo script.")
        return

    sezioni_dict = {}
    current_section = "Sezione Generale"

    with open(csv_path, mode='r', encoding='utf-8-sig') as f:
        # Usa Sniffer per rilevare il separatore (virgola o punto e virgola)
        content = f.read(2048)
        if not content.strip():
            return
        
        try:
            dialect = csv.Sniffer().sniff(content)
        except csv.Error:
            # Fallback se lo sniffer fallisce
            dialect = csv.excel
        
        f.seek(0)
        reader = csv.reader(f, dialect=dialect)
        
        for row in reader:
            # Pulisce gli spazi bianchi ed elimina elementi vuoti
            row_cleaned = [str(x).strip() for x in row]
            non_empty = [x for x in row_cleaned if x]
            
            # Riga vuota, salta
            if not non_empty:
                continue
                
            # Se la riga contiene un solo elemento, assumiamo sia il titolo della categoria
            if len(non_empty) == 1:
                # Controlla che non sia una roba tipo "ID"
                val = non_empty[0]
                if len(val) > 2: # Evita sezioni chiamate "A" o numeri isolati
                    current_section = val
                continue
            
            # Altrimenti è una domanda
            # Troviamo il testo della domanda (assumiamo sia il primo testo lungo)
            testo = non_empty[0]
            if len(testo) < 5 and len(non_empty) > 1:
                # Probabilmente il primo campo era un ID numerico
                testo = non_empty[1]
                
            # Genera un id univoco se non c'è, altrimenti prova a usare un id dalla riga se presente
            id_domanda = f"pos_{uuid.uuid4().hex[:8]}"
            
            # Forza tipo_risposta come richiesto
            tipo = "rating_1_to_5"

            domanda = Question(
                id_domanda=id_domanda,
                testo_domanda=testo,
                tipo_risposta=tipo
            )
            
            if current_section not in sezioni_dict:
                sezioni_dict[current_section] = []
            sezioni_dict[current_section].append(domanda)

    # Costruisci l'albero della Scala
    sezioni_list = []
    for sec_title, domande in sezioni_dict.items():
        sezioni_list.append(Section(titolo_sezione=sec_title, domande=domande))

    scala_pos = Scale(
        id="scala_pos",
        nome="Scala POS Eterovalutativa",
        descrizione="Scala per la valutazione clinica importata da file CSV reale.",
        sezioni=sezioni_list
    )

    # Aggiorna il database svuotandolo prima
    await scales_collection.delete_many({}) # Svuota l'intera collection per fare pulizia
    result = await scales_collection.insert_one(scala_pos.model_dump())
    
    print(f"Seeding completato con successo! Scala salvata con _id: {result.inserted_id}")
    print(f"Totale sezioni trovate: {len(sezioni_list)}")
    for s in sezioni_list:
        print(f" - {s.titolo_sezione} ({len(s.domande)} domande)")
    print(f"Totale domande importate: {sum(len(s.domande) for s in sezioni_list)}")

if __name__ == "__main__":
    asyncio.run(seed_from_csv())
