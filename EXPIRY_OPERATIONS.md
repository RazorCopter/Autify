# C6 — Policy scadenze e conteggi

Implementazione locale 4.0.7, 30 ottobre 2026. Test, analisi statiche, build e verifica su dati reali rinviati. Nessuna migrazione o modifica al database cliente eseguita.

## Contratto comune

`backend/app/expiry.py` proietta le valutazioni negli stati usati da dashboard, filtri dell'anagrafica e indicatori Flutter. Le date `ultimo_*` persistite sono solo cache di compatibilità: non governano più i filtri. La dashboard non usa più la cache di cinque minuti per questi risultati.

Le durate provengono da `settings.global_settings.scale_validity_months`: preservati i default server POS12, San Martín12, SIS36, OGVA12, SABS12, OSO12 mesi. `required_scale_types` parte da POS/San Martín/SIS, come il precedente denominatore della dashboard; OGVA/SABS/OSO sono selezionabili. `expiry_warning_days` parte da30. Sono valori operativi preesistenti da confermare con la struttura, non prescrizioni scientifiche introdotte dall'audit.

GET `/api/admin/expiry-policy` restituisce la policy; POST richiede admin e il documento completo con i tre campi. Durate intere1–120, preavviso0–365, almeno una scala richiesta tra le sei, senza duplicati. La schermata Impostazioni salva esplicitamente sul server; le vecchie preferenze locali e i parametri query `validity_*` non governano più scadenze o indicatori. I vecchi client settings che omettono i nuovi campi ne preservano i valori persistiti. Aggiornare client e server insieme.

## Calendario e dati legacy

- Mongo restituisce datetime consapevoli del fuso (`tz_aware=True`); nuove valutazioni normalizzate UTC. Naive legacy interpretati UTC, coerentemente con le scritture storiche. Non viene inventato il fuso originale.
- Lettura compatibile con datetime BSON, ISO con/senza offset, date `dd/MM/yyyy`, `dd-MM-yyyy`, `yyyy/MM/dd`. Nessun parsing euristico di altre stringhe.
- Scadenza: data locale Europe/Rome più mesi calendario, giorno ridotto all'ultimo disponibile del mese. Valida per tutto il giorno di scadenza, scaduta dal giorno successivo. Preavviso inclusivo; con zero giorni interessa soltanto la data di scadenza. Dipendenza `tzdata` per ambienti privi del database IANA.
- La valutazione più recente per scala determina lo stato, con spareggio `_id`. Risposte validate con il contratto C3, snapshot preferito. Legacy senza snapshot usa catalogo corrente con provenienza dichiarata, senza congelamenti o scritture implicite in GET. Una nuova incompleta non viene nascosta da una vecchia completa.
- Data invalida ha priorità di segnalazione e rende la scala incompleta; data futura pure. Nessuna data fittizia convertita in valutazione valida. Lo storico richiede correzione esplicita delle date non interpretabili (409).

## Significato dei conteggi

Categorie utenti disgiunte, in ordine: nessuna valutazione → `mai_valutati`; scala richiesta mancante/incompleta → `incompleti`; almeno una richiesta scaduta → `scaduti`; almeno una richiesta in preavviso → `in_scadenza`; altrimenti `coperti`. Scale opzionali visibili ma escluse dal requisito di copertura.

Le schede “Utenze coperte” e “Utenze da completare” aprono rispettivamente i filtri `coperti` (comprende in scadenza) e `da_completare` (mai valutati, incompleti, scaduti). I quattro alert aprono la categoria omonima. Conteggi riferiti agli utenti attivi; `attivo` assente significa attivo sia nella lista sia nella dashboard.

Il grafico di copertura conta coppie utente attivo / scala richiesta, incluse quelle in preavviso. Denominatore esplicito API `coverage_denominator`, unità `coverage_unit`. Non coincide con il numero di utenti o compilazioni. `totale_valutazioni_eseguite` conta tutte le compilazioni degli utenti attivi, anche incomplete. La distribuzione conta utenti unici per scala e divide per gli attivi; i trend mensili usano Europe/Rome. Il forecast conta scadenze di scale richieste nei prossimi56 giorni, non appuntamenti pianificati.

## Limiti e verifica differita

Eliminati i tagli silenziosi nei percorsi C6: dashboard, ricostruzione date, filtro anagrafica, storico valutazioni, ultima relazione IA e selettore utenti. Lista paginata con ordinamento cognome/nome/id/_id, filtro prima della paginazione. Identificativi per query valutazioni in blocchi di500; cursori consumati interamente. Nessuna nuova collection.

La normalizzazione è in lettura: non è stata eseguita una migrazione massiva BSON. La validazione di completezza su snapshot richiede codice applicativo; non è stata sostituita con una semplice aggregazione Mongo sui massimi delle date, che avrebbe ignorato le valutazioni invalide. I filtri semantici e la dashboard rimangono proporzionali ai dati letti; lo storico completo è una risposta non paginata per compatibilità. Necessari test di carico e, per grandi installazioni, una proiezione persistita con invalidazione transazionale prima di promettere tempi o memoria costanti.

Le richieste mostrano lo stato corrente, non una fotografia congelata tra click e pagina seguente. Scritture concorrenti, cambio policy o passaggio di giorno possono legittimamente modificare il conteggio. Rileggere dashboard/elenco dopo modifiche. Altri limiti dei registri amministrativi non coinvolti nelle scadenze non sono stati rimossi indiscriminatamente.

Casi differiti C6 in `test.md`; checkpoint di ripresa in `file.md`. Nessuna verifica runtime eseguita.
