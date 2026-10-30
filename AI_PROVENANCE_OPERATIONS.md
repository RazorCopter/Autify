# C5 — Provenienza e revisione IA, 4.0.6

Implementazione locale, 30 ottobre 2026. Verifica finale rinviata: casi C5-01..24 in test.md. Nessun test, build, deploy o invio provider effettuato durante questi fix.

## Contratto di richiesta

POST /ai/analyze riceve id_paziente, evaluation_ids, history_report_ids, note aggiunte e allegato opzionali. Il singolo id_valutazione resta supportato insieme all'utente esplicito. Payload completi patient/evaluations/history_reports del vecchio client vengono rifiutati422: aggiornare frontend e backend insieme. Non usare dati client come fallback.

Il server verifica gli ID applicativi, l'appartenenza all'utente e la completezza delle risposte. Usa ogni snapshot C3 per ricalcolare la sua analisi; due date della stessa scala restano due fonti distinte. Fonti legacy senza snapshot seguono il congelamento dichiarato C3; assenza del protocollo originale non viene mascherata. Identificativi legacy non migrati al campo id_valutazione richiedono una migrazione esplicita, non associazione per nome o scala.

La cattura usa una transazione snapshot con scrittura sul parent. L'input descrive il momento della cattura, non necessariamente lo stato al momento della successiva esecuzione. Le modifiche successive non riscrivono il prompt del job. Sono ammesse analisi basate soltanto su note/allegato o report revisionati, con lista valutazioni vuota esplicita. Limiti100 valutazioni,50 report,1MiB testo contesto e limite allegato preesistente10MiB.

## Dati trasmessi e dati locali

Il payload strutturato contiene riferimento neutro V1/V2, data della valutazione, identificativo/nome del protocollo, punteggi e analisi ricalcolate. Non invia nome/cognome dell'utente, codice fiscale, data nascita, note anagrafiche, demographics, nome dell'operatore e note libere delle risposte. Non introduce una fascia di età inferita. Zero, false e null restano distinti nel JSON; lo snapshot non viene usato come se fosse un risultato analitico.

Note aggiunte, allegati e report selezionati sono contenuti liberi esplicitamente richiesti. Il client chiede conferma della loro revisione/minimizzazione, il server richiede external_content_confirmed quando presenti. Filename allegato generico; bytes conservati per la chiamata. Non viene effettuata una bonifica automatica dei testi o dei documenti: anche titoli di protocolli e relazioni pregresse possono contenere identificativi. Questa riduzione dei campi non equivale ad anonimizzazione o conformità legale certificata.

Il contesto è serializzato come JSON dati, separato dal system prompt; un'istruzione aggiuntiva richiede di trattare note/report/allegati come dati e di produrre una bozza educativa. È una mitigazione dell'iniezione di istruzioni, non una garanzia assoluta sul comportamento del modello. Il viewer continua a non poter fornire override del system prompt.

## Provenienza persistita

Job e relazione generata conservano provenance: versione schema/app/prompt, timestamp cattura, ID fonti, hash SHA256 degli input selezionati e degli snapshot, origine snapshot legacy/original, hash del testo JSON effettivo, del system prompt effettivo e dei bytes dell'allegato. Il digest strutturato usa BSON Extended JSON ordinato per chiavi; i digest di prompt/testo usano bytes UTF-8. Un hash consente confronto con un contenuto disponibile, non permette di ricostruirlo.

Prima della chiamata il worker controlla gli hash degli input persistiti e registra execution: provider, modello richiesto, protocollo, parametri generation/network, hash endpoint, versione app e timestamp. Credenziali/header segreti non sono inclusi. La configurazione viene letta all'esecuzione: se cambiata dopo enqueue, viene registrata quella usata allora. Il nome richiesto non certifica la versione interna eventualmente risolta dal provider. Timeout e assenza di retry restano quelli di C4.

Le relazioni manuali sono manual_unverified; quelle legacy restano prive di provenienza canonica attestata. Nessun backfill di prompt, modello o fonti inventate. Un riferimento a valutazione successivamente eliminata resta tracciato negli hash della relazione; C1 accetta tale riferimento storico se accompagnato dai metadati hash previsti. Non significa che i dati eliminati siano ricostruibili.

## Revisione educativa

Ogni nuova relazione è draft. Un admin deve leggere il testo e approvarlo esplicitamente tramite l'azione UI o POST /patients/ai-analyses/{id}/approve, passando il report_hash letto. La transazione verifica il testo corrente e registra reviewed_by, reviewed_at, reviewed_report_hash e audit. Il viewer non approva. Approvazione e provenienza sono indipendenti: approvare una relazione legacy non la rende generata da input canonici.

Solo report approved con hash del testo ancora corrispondente possono entrare in una nuova analisi come contesto. Note operatore della relazione non vengono aggiunte implicitamente al suo testo. L'export delle relazioni salvate legge il documento server ed espone stato/fonti; l'export libero preesistente rimane disponibile ma reca la dicitura bozza/provenienza non attestata. L'approvazione registra una revisione dell'operatore, non una certificazione automatica dell'accuratezza del modello.

## Conservazione e aggiornamento

Prompt e allegati restano nel job durante attesa/esecuzione; vengono rimossi quando il worker lo terminalizza. Il bootstrap pulisce gli stessi campi dai job completed/failed preesistenti; il restore C1 rimuove gli input transitori e non riaccoda le operazioni. Hash, metadati, report e audit rimangono. Backup precedentemente prodotti o copie esterne possono ancora contenere input: il fix non li modifica né cancella.

Nessuna retention temporale generale o TTL introdotto; la policy per report e audit richiede decisione separata. Worker rifiuta pending pre-C5 senza provenienza canonica: dopo verifica dell'operatore si può richiedere una nuova analisi, senza replay automatico. Non avviare il rilascio prima della verifica integrata C1-C5; adeguare i test precedenti che inviavano payload completi o richiamavano il vecchio builder del prompt.
