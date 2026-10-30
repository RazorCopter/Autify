# C3/C4 — Valutazioni storiche e job IA, 4.0.5

Implementazione locale del 30 ottobre 2026. Test, analisi statiche e build rinviati; casi centralizzati in test.md. Prima del rilascio verificare lo stack completo con dati sintetici. Nessuna migrazione eseguita sui dati cliente.

## Requisiti operativi

Il replica set MongoDB introdotto da C1 serve ora anche per salvare valutazioni, sostituire/eliminare protocolli, accodare/pubblicare job e cancellare anagrafiche con dipendenze. Non esiste fallback a scritture parziali su standalone. Seguire BACKUP_OPERATIONS.md per la migrazione su copia e la finestra di manutenzione.

Il bootstrap crea indici univoci su id_valutazione (solo valori stringa) e sugli ID di job, notifiche e relazioni. Duplicati preesistenti devono essere inventariati e corretti con decisione esplicita prima dell'aggiornamento: l'applicazione non li elimina o rinumera automaticamente. Preservare backup e configurazione originali. Aggiornare frontend e backend insieme.

## Contratto delle valutazioni

Create e update condividono validazione completa: una risposta per domanda, alias ricondotti allo stesso codice, niente duplicati o domande estranee, tipi interi senza coercizione, opzioni ammesse dal protocollo. SIS richiede il protocollo supportato di49 item A-F documentato in scale/Scala_SIS.json, con F/D/T0..4 e A3 frequenza massima3; le sezioni supplementari presenti vanno compilate. I compositi conservano il contratto corrente di conteggio0..numero sottodomande; non viene inventata una registrazione delle singole selezioni storiche.

Non è stato introdotto uno stato bozza: le nuove valutazioni salvate e le modifiche devono essere complete. I dati legacy incompleti restano conservati, ma analisi/PDF non attribuiscono indici standardizzati a un protocollo incompleto; viene mostrato un avviso. La correttezza delle tabelle normative non è certificata da questo intervento. Le policy scadenza/KPI rimangono oggetto di C6.

Ogni nuova valutazione riceve uno snapshot completo server-side con hash/provenienza. PDF, analisi, aggregati, validazione delle modifiche e schermata dettaglio usano quello snapshot. Il browser può aprire anche protocolli eliminati dalla vista storica, attraverso GET /api/admin/patients/{id}/evaluation-scales; il catalogo per nuove compilazioni continua a mostrare solo protocolli attuali.

Per record senza snapshot si congela una sola volta la scala disponibile, dichiarando `legacy_current_not_original`. Non si può attestare che questa fosse la versione originale. Prima di modificare/importare/eliminare una scala, le valutazioni legacy associate vengono congelate nella stessa transazione; la creazione concorrente scrive sul documento scala per impedire letture miste. Se manca anche la scala corrente oppure lo snapshot è malformato, serve recupero esplicito da un archivio, non una ricostruzione arbitraria. Snapshot già presenti non vengono aggiornati con metadati bundled di versioni successive.

Gli snapshot storici fanno parte dei backup C1: una valutazione senza scala corrente è ammessa se contiene uno snapshot coerente e strutturalmente valido.

## Coda IA e riavvii

POST /ai/analyze persiste il job e restituisce202. Un worker gestito dal lifespan effettua polling ogni2secondi; ciascun processo esegue un job alla volta. Un lock transazionale sul documento settings limita globalmente a2 job running e200 pending. Nessuna nuova collection aggiunta: il registro backup resta di dieci collection.

La transizione pending→running assegna un token lease e scadenza di900secondi. La chiamata al provider ha timeout complessivo650secondi e retry automatici disabilitati, anche se le impostazioni rete consentono retry per altre operazioni. Un errore di rete non prova che il provider non abbia elaborato o fatturato la richiesta.

- **Pending al riavvio:** può essere reclamato; prima del provider vengono ricontrollati account, versione sessione, flag IA e utente attivo. Un pending legacy senza versione del proprietario verificabile fallisce senza invio.
- **Running interrotto:** non torna pending. Alla scadenza lease viene chiuso failed con esito provider incerto; running legacy senza lease viene chiuso in recovery. Nessun replay automatico.
- **Risposta ricevuta:** relazione, stato completed, notifica e audit vengono pubblicati nella stessa transazione, con ID deterministici e controllo token/scadenza lease.
- **Commit incerto o DB indisponibile dopo risposta:** non si richiama il provider. Se il commit non è avvenuto, la risposta in memoria può andare perduta; recovery segnala il job failed/incerto. C4 garantisce coordinamento delle scritture, non exactly-once del servizio remoto né conservazione di una risposta non ancora persistita.
- **Nuova richiesta esplicita:** crea un nuovo job, potenzialmente un nuovo costo. Non usare retry ciechi sul POST dopo timeout; controllare prima l'elenco job e il provider.

Il worker viene cancellato allo shutdown e non viene avviato in BACKUP_MAINTENANCE_MODE. Restano necessari stop degli altri processi/writer esterni e riavvio come documentato in C1. Dopo restore, i job pending/running sono failed, non ripresi automaticamente. Input transitori e allegati vengono rimossi dai job alla pubblicazione terminale del worker; i record terminali storici/restaurati non subiscono una bonifica automatica aggiuntiva.

## Archiviazione e cancellazione

Usare il campo attivo=false per l'archiviazione ordinaria: conserva lo storico e impedisce nuove esecuzioni. Un provider già chiamato non viene annullato dall'archiviazione e può completare il risultato per l'utente ancora esistente.

La cancellazione definitiva elimina anagrafica, valutazioni, relazioni, job e notifiche, con audit nella medesima transazione. Enqueue, nuova valutazione, salvataggio manuale relazione e pubblicazione worker scrivono sul documento utente per entrare in conflitto con delete. Il job conserva anche l'identità Mongo della sua anagrafica: riutilizzare lo stesso ID applicativo non autorizza un vecchio risultato a comparire nel nuovo record. Una richiesta provider già inviata può continuare remotamente, ma non deve ricreare dati locali dopo delete.

Nessun TTL o durata di retention introdotto: serve una policy di prodotto concordata prima di cancellazioni temporali automatiche. Eventuali orfani/duplicati prodotti dalle versioni precedenti richiedono inventario e riparazione dedicati; i fix non cancellano retroattivamente dati senza una decisione. Provenienza canonica di tutte le valutazioni inviate all'IA rimane C5: C4 verifica l'anagrafica e il ciclo di vita del job, non chiude ASTRA-07.
