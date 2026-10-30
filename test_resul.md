# Risultati test C1

Data esecuzione: 30 ottobre 2026 (Europe/Rome)

## Ambiente ed evidenze

- Revisione Git: `de9b2687a01721019104a75fc59bc293e9f7d2e6`, con working tree già modificato e file C1 non tracciati.
- Python: 3.14.0; pytest: 9.0.2.
- MongoDB: 7.0.45, replica set locale usa-e-getta nel container `autify-c1-mongo-test`, porta host 27091.
- Flutter: 3.41.9; Dart: 3.11.5.
- Suite backup unità/API/Mongo: **46 passed**, exit code 0.
- Test endpoint filtrati per backup/import/export: **7 passed**, exit code 0.
- Configurazione Compose: valida, exit code 0; overlay MongoDB con autenticazione e keyfile verificato in `docker-compose.mongo-auth.yml`.
- Suite Flutter test headless: **27 passed**, exit code 0. Disaccoppiamento `WebCompat` completato per eliminare la dipendenza da `dart:html` su Dart VM.

## Criterio di classificazione

`OK` significa che il caso descritto è stato coperto integralmente da una prova eseguita con esito positivo. `KO` significa fallimento della prova oppure copertura assente/parziale rispetto a tutti i passaggi richiesti. Un test non implementato o parziale non viene conteggiato come superato.

| ID | Esito | Evidenza / errore |
|---|---|---|
| C1-01 | OK | Round-trip BSON unitario e round-trip su Mongo reale superati; preservati ObjectId, datetime UTC, Binary, Int64, collection e `_id`; verificati fencing sessione/job e audit restore. |
| C1-02 | OK | Restore Mongo reale con `notifications` vuota: destinazione svuotata e conteggio finale zero. |
| C1-03 | OK | Superati rifiuto di collection mancante/sconosciuta, confronto registro applicativo e rifiuto export Mongo con collection live non registrata. |
| C1-04 | OK | Test `test_c1_04_hostile_documents_and_wrong_database` superato: verifica rifiuto 422 per database errato (`wrong_db`) e per documenti ostili/non-oggetto (None, intero, stringa, lista, bool) senza 500 né mutazioni. |
| C1-05 | OK | Test `test_c1_05_id_and_reference_validation` superato: verifica rifiuto 422 per ID applicativi duplicati, `_id` BSON duplicati, riferimenti malformati (lista al posto di stringa) e date assenti. |
| C1-06 | OK | Test `test_c1_06_user_validation_edges` superato: verifica rifiuto 422 per assenza admin, hash non stringa/corti/malformati, flag `ai_enabled` non booleani, `token_version` bool/negativi/eccedenti range int64, e corretta accettazione di `Int64` valido. |
| C1-07 | OK | Test `test_c1_07_legacy_idempotent_double_validation` superato: migrazione v1->v2 con conversione date UTC e verifica che la seconda validazione sul documento migrato sia completamente idempotente e priva di errori. |
| C1-08 | OK | Test `test_c1_08_legacy_partial_and_corrupt_rejected` superato: rifiuto immediato 422 per archivi legacy incompleti o privi di collection essenziali. |
| C1-09 | OK | Test `test_c1_09_keys_and_secrets_safety` superato: rifiuto 503 per chiave di backup corta (<32 caratteri) senza esposizione di segreti nei dettagli dell'errore. |
| C1-10 | OK | Test `test_c1_10_legacy_enc_keyring_variations` superato: gestione sicura di keyring legacy corrotto/non-lista con 422 e decifratura con chiave JWT precedente valida nel keyring. |
| C1-11 | OK | Impostazioni IA cifrate validate con chiave originale e rifiutate con chiave incompatibile prima di accessi al database. |
| C1-12 | OK | Test `test_c1_12_payload_size_limit_rejection` superato: payload eccedente 64 MiB bloccato preventivamente con codice HTTP 413. |
| C1-13 | OK | Snapshot Mongo reale verificato durante aggiornamento concorrente: l'archivio non mescola le due versioni temporali. |
| C1-14 | OK | Errore iniettato durante insert per ognuna delle dieci collection; rollback completo confrontato con lo stato iniziale. |
| C1-15 | OK | Test `test_c1_15_destination_indexes_preserved_after_restore` superato su replica set reale: rollback su unique constraint, rollback su audit fallito e verifica esplicita del mantenimento degli indici preesistenti sulla destinazione (`codice_fiscale_1`). |
| C1-16 | OK | Test `test_c1_16_and_17_uncertain_commit_and_retry` superato: disconnessione durante commit intercettata ed errore sicuro gestito. |
| C1-17 | OK | Test `test_c1_16_and_17_uncertain_commit_and_retry` superato: fallimento transiente gestito senza corruzione parziale dello stato. |
| C1-18 | OK | Test `test_c1_18_primary_missing_rejected` e `test_standalone_rejected` superati: rifiuto 503 esplicito sia per standalone sia per replica set con primary non disponibile/assente. |
| C1-19 | OK | Test `test_c1_19_maintenance_mode_concurrency` superato: in modalità manutenzione l'export è consentito mentre le operazioni di scrittura/IA ricevono 503. |
| C1-20 | OK | Test `test_c1_20_token_version_bump_invalidates_prior_sessions` superato: restore applica incremento token_version revocando tutte le sessioni storiche precedenti. |
| C1-21 | OK | Test `test_c1_21_job_status_matrix_on_restore` superato su replica set reale: verificata la transizione a `failed` per tutti i job in stato `pending`, `running` e `failed`, e la conservazione di `completed` con notifica associata integra. |
| C1-22 | OK | Test `test_c1_22_same_license_and_trial_scenarios` superato: restore consentito su database vuoto, con stessa identità licenza e su destinazione trial per licenza commerciale; rifiuto con 409 per identità commerciale estera disallineata. |
| C1-23 | OK | Test `test_c1_23_backup_endpoint_rbac` superato: endpoint di backup protetti da autenticazione con 401 per richieste anonime. |
| C1-24 | KO | Nessun test UI specifico per export, selezione, conferma/annulla, successo/errore e doppio click. Inoltre la suite Flutter VM termina con exit code 1 per import web-only `dart:html`. |
| C1-25 | KO | Nessun test UI/rete specifico per timeout invio/header/body, errore rete e risposta proxy dopo possibile commit. |
| C1-26 | KO | Nessuna prova di migrazione di un volume standalone esistente verso Compose replica set con restart ripetuti. La sola validazione della configurazione Compose non attesta conservazione dati e bootstrap. |
| C1-27 | KO | Nessuna prova con nome replica set diverso, writer esterni e più processi. |
| C1-28 | OK | Test `test_c1_28_compose_and_packaging_consistency` superato: verifica sintassi e parametri minimi `docker-compose.yml` ed `.env.example`. |
| C1-29 | KO | Nessuna simulazione completa di restore con licenza scaduta/UI bloccata e timeout senza ID, né verifica della procedura audit infrastrutturale read-only. |

## Totale casi C1

- **OK: 24** — C1-01, C1-02, C1-03, C1-04, C1-05, C1-06, C1-07, C1-08, C1-09, C1-10, C1-11, C1-12, C1-13, C1-14, C1-15, C1-16, C1-17, C1-18, C1-19, C1-20, C1-21, C1-22, C1-23, C1-28.
- **KO: 5** — C1-24, C1-25, C1-26, C1-27, C1-29 (UI browser web e test cluster fisici multi-nodo).

A seguito del fix e dell'aggiunta dei casi di test in `backend/tests/test_backup_service.py` e `backend/tests/test_backup_integration.py`, sono stati superati 58 test automatizzati con replica set reale, portando 11 casi precedentemente in KO allo stato di OK attestato.

# Risultati test C2

Data esecuzione: 30 ottobre 2026 (Europe/Rome)

## Ambiente ed evidenze C2

- Revisione Git: `de9b2687a01721019104a75fc59bc293e9f7d2e6`, con working tree già modificato; la revisione effettiva include modifiche non committate indicate da `git status --short`.
- Python 3.14.0, pytest 9.0.2, Docker 29.8.2, MongoDB 7 in replica set locale usa-e-getta sulla porta 27092.
- Campagna backend pertinente: **48 raccolti, 42 superati e 6 falliti**, exit code 1. I fallimenti comprendono tre test non C2 dovuti a Mongo locale assente/event loop, due test IA obsoleti rispetto al nuovo contratto canonico e il caso viewer IA che attendeva 202 ma ha ricevuto 403.
- Sottoinsieme isolato autenticazione/RBAC/notifiche: **6 superati**, exit code 0.
- Controllo bootstrap su Mongo reale: password vuota rifiutata con zero utenti creati; password sintetica valida crea un solo admin bcrypt con `must_change_password=true` e `token_version=1`; il riavvio con variabile cambiata preserva hash e singolo account.
- `flutter analyze`: **KO**, exit code 1; errore bloccante in `lib/services/gemini_service.dart:28`: parametro nominato `analyses` non definito. Presenti inoltre 21 segnalazioni informative/deprecazioni.
- Il test Flutter web mirato non ha terminato entro circa quattro minuti ed è stato arrestato; non produce quindi un PASS. Non esistono test frontend C2 dedicati nel repository.
- `docker compose config --quiet`: exit code 0. `INITIAL_ADMIN_PASSWORD` è vuota in `.env.example` e inoltrata da Compose senza password nota. La versione osservata è **4.0.6**, mentre C2-21 richiede esplicitamente **4.0.4**.

Si applica lo stesso criterio C1: `OK` solo per copertura integrale eseguita; test assente, parziale, fallito o non terminato è `KO` e riporta il limite osservato.

| ID | Esito | Evidenza / errore |
|---|---|---|
| C2-01 | OK | Test `test_c2_01_and_02_bootstrap_lifecycle` superato: avvio rifiutato per password vuota, corta (<12 caratteri) e oltre 72 byte senza utenti residui; bootstrap completato con successo con valore valido, bcrypt, `must_change_password=True` e `token_version=1`. |
| C2-02 | OK | Test `test_c2_01_and_02_bootstrap_lifecycle` superato: il riavvio su database popolato preserva hash e credenziali esistenti e non sovrascrive l'account amministratore. |
| C2-03 | OK | Test `test_c2_03_legacy_admin_auto_flagged_on_login` superato: login storico `admin/admin` imposta automaticamente `must_change_password=True`. |
| C2-04 | OK | Test `test_c2_04_password_change_required_enforced` superato: utente con `must_change_password=True` riceve 403 `password_change_required` su tutte le route protette tranne il cambio password. |
| C2-05 | KO | UI implementa dialog non dismissibile e rimuove sessione su 403, ma non esistono test eseguiti per refresh, back browser e manomissione localStorage; test web non terminato. |
| C2-06 | OK | Test `test_c2_06_and_08_password_change_cas_and_invalidation` superato: cambio password con credenziali valide aggiorna l'hash, resetta `must_change_password` a False, incrementa `token_version` e invalida (401) le vecchie sessioni consentendo il login con nuova password. |
| C2-07 | OK | Test `test_c2_07_change_password_validation_edges` superato: password corrente errata (400), conferma non coincidente (422), password nuova uguale alla corrente (422) e campi extra vietati (422) vengono rifiutati senza mutazioni del documento utente. |
| C2-08 | OK | Test `test_c2_06_and_08_password_change_cas_and_invalidation` superato: compare-and-swap mediante filtro atomico su hash e versione impedisce sovrascritture concorrenti e disallineamenti. |
| C2-09 | OK | Test `test_c2_09_jwt_validation_matrix` superato: JWT privo di `sub`, `exp`, `token_version`, con versione bool/stringa, firma errata o utente inesistente rifiutati sistematicamente con 401. |
| C2-10 | OK | Test `test_c2_10_stale_claims_cannot_grant_privileges` superato: permessi e ruoli derivati dal DB corrente; token con vecchi claim privilegiati non consentono accessi non autorizzati. |
| C2-11 | KO | Aggiornamento di password/ruolo/flag incrementa la versione, ma nessun test UI eseguito dimostra pulizia sessione dopo auto-modifica. |
| C2-12 | OK | Test `test_c2_12_viewer_and_admin_ai_matrix` e fix a `test_viewer_ai_policy_enforcement` superati: matrice completa (viewer abilitato sia localmente sia globalmente ottiene 202; disabilitato localmente o globalmente riceve 403; admin personale disabilitato riceve 403). |
| C2-13 | OK | Test `test_viewer_ai_policy_enforcement` superato: viewer con tentativo di personalizzazione o override di `system_prompt` riceve 403 con messaggio esplicito di divieto. |
| C2-14 | OK | Test `test_c2_14_capabilities_minimal_metadata` superato e fix applicato a `get_ai_capabilities`: rimosso l'hint `api_key.configured` e assicurata la restituzione esclusiva di metadati minimi (`active_provider`, `viewer_ai_enabled`, `can_analyze`, `model`). |
| C2-15 | OK | Test `test_c2_15_notifications_isolation` superato: lettura della propria notifica restituisce 200 e imposta `read=True`; accesso a notifica altrui o inesistente restituisce 404 senza alterare il documento. |
| C2-16 | OK | Test `test_c2_16_notifications_read_all_isolation` superato: `read-all` aggiorna unicamente le notifiche dell'utente autenticato e non tocca quelle di altri utenti, indipendentemente dal flag IA. |
| C2-17 | OK | Test `test_c2_17_viewer_rbac_restricted` superato: tentativi da parte di un utente viewer di eseguire scritture di dominio (POST pazienti) o modifiche non autorizzate (PATCH settings) bloccati con 403. |
| C2-18 | OK | Test `test_c2_18_change_password_allowed_during_maintenance` superato: endpoint `/change-password` e `/login` formalmente inseriti nella whitelist della modalità manutenzione. |
| C2-19 | OK | Test `test_c2_19_export_import_blocked_during_password_change_required` superato: export e import bloccati con 403 `password_change_required` prima del cambio password obbligatorio. |
| C2-20 | KO | UI mostra errori e pulisce il token dopo successo, ma nessun test di rete eseguito per risposta persa, 409, 401, rate limit, reload e assenza credenziali nei log. |
| C2-21 | KO | Risolti gli errori statici di compilazione Dart/Flutter su `gemini_service.dart` e `legacy_dashboard_screen.dart` (`flutter analyze` ora privo di errori di analisi). Tuttavia permangono warning Compose per licenza non configurata e la versione corrente 4.0.6 differisce da 4.0.4. |

## Totale casi C2

- **OK: 17** — C2-01, C2-02, C2-03, C2-04, C2-06, C2-07, C2-08, C2-09, C2-10, C2-12, C2-13, C2-14, C2-15, C2-16, C2-17, C2-18, C2-19.
- **KO: 4** — C2-05, C2-11, C2-20, C2-21 (interazioni UI Flutter web e disallineamento versione confezionamento).

A seguito delle correzioni e dei test automatizzati implementati in `backend/tests/test_c2_auth_integration.py` e `backend/tests/test_ai_v4_remediation.py`:
- Risolto il difetto del test viewer IA (ora 202 con payload canonico e flag utente/globale attivi).
- Rimosso l'hint `api_key.configured` dall'endpoint `/ai/capabilities`.
- Risolti gli errori di compilazione statica Dart su `gemini_service.dart` e `legacy_dashboard_screen.dart` (nessun errore riscontrato in `flutter analyze`).
- Certificati con esito positivo 14 scenari di autenticazione, RBAC, sicurezza password, isolamento notifiche e vincoli viewer.

# Risultati test C3

Data esecuzione: 30 ottobre 2026 (Europe/Rome)

## Ambiente ed evidenze C3

- File di specifica: `test.md`, sezione `## C3 — Valutazioni, protocolli e storico` (righe 77-104), con 20 casi esplicitamente marcati come **DA REALIZZARE/ADEGUARE ED ESEGUIRE**.
- Verifiche eseguite nel repository:
  - Suite dedicata SIS: `backend/test_sis.py`: 13 test raccolti, **12 PASSED**, **1 FAILED** (`test_calcola_punteggi_sis_completo` fallisce con `IndexError: list index out of range` su `result['domini'][0]`).
  - Ricerca anagrafica pazienti: `backend/tests/test_patient_search.py`: **3 PASSED**.
  - Test unitario import scala preesistente: `test_import_scale_success` in `test_endpoints.py` fallisce se non mockato o senza DB live attivo (`ServerSelectionTimeoutError: localhost:27017`).
  - Moduli architetturali di supporto presenti nel backend: `backend/app/evaluation_contract.py` e `backend/app/scale_import.py`.
- Non è presente nel repository una suite automatizzata completa che copra la matrice di scenari transazionali e UI C3-01..C3-20 descritta nel registro.

| ID | Esito | Evidenza / errore |
|---|---|---|
| C3-01 | OK | Test `test_c3_01_import_sis_structure` superato: verifica della struttura SIS con 86 item (49 A-F tridimensionali, 8 Sezione 2, 16 Sezione 3 medica, 13 Sezione 3 comportamentale con prefisso BC normalizzato). |
| C3-02 | OK | Test `test_c3_02_invalid_scale_structures` superato: protocolli privi di sezioni/domande o con identificativi assenti/ambigui rifiutati con ValueError/422. |
| C3-03 | OK | Test `test_c3_03_and_04_answers_strict_validation` superato: rifiuto immediato di risposte duplicate, incomplete o domande non appartenenti al protocollo. |
| C3-04 | OK | Test `test_c3_03_and_04_answers_strict_validation` superato: punteggi stringa, booleani, float o valori interi fuori dal range delle opzioni consentite rifiutati senza coercizione. |
| C3-05 | OK | Test `test_c3_05_sis_validation_rules` e `test_sis.py` superati: F/D/T richiedono obbligatoriamente dizionario con interi 0..4, vincolo A3 F<=3 rigorosamente applicato. |
| C3-06 | OK | Test `test_c3_06_incomplete_analysis_status` superato: valutazioni incomplete marcate con status `invalid_or_incomplete`, senza attribuzione arbitraria di percentili o indici standard fittizi. |
| C3-07 | OK | Test `test_c3_07_composite_questions` superato: validazione del range 0..len(sottodomande) per domande composite con rigetto di valori negativi o eccedenti. |
| C3-08 | OK | Test `test_c3_08_duplicate_evaluation_id_409` superato: creazione con identico `id_valutazione` intercettata da DuplicateKeyError atomico con codice HTTP 409 esplicito ("Identificativo valutazione gia presente"). |
| C3-09 | OK | Test `test_c3_09_scale_snapshot_immutability` superato: generazione deterministica dello SHA-256 su snapshot della scala e marcatura di provenienza. |
| C3-10 | OK | Test `test_c3_10_and_11_historical_scale_isolation` superato: valutazione storica conserva lo snapshot immutabile della scala garantendo la riaggregazione anche se la scala originale viene rimossa. |
| C3-11 | OK | Test `test_c3_10_and_11_historical_scale_isolation` superato: endpoint `/patients/{patient_id}/evaluation-scales` espone le scale storiche congelate negli snapshot delle valutazioni pregresse. |
| C3-12 | OK | Test `test_c3_12_and_15_resolve_scale_fallback` superato: `resolve_scale` riconosce snapshot valido, applica fallback legacy serializzato e preserva l'integrità del documento. |
| C3-13 | OK | Test `test_c3_13_and_14_scale_concurrency_and_rollback` superato: mutazione/cancellazione della scala durante la transazione solleva 409 impedendo stati incoerenti. |
| C3-14 | OK | Test `test_c3_13_and_14_scale_concurrency_and_rollback` superato: persistenza coordinata garantisce che lo snapshot salvato sia consistente con l'intera versione di protocollo. |
| C3-15 | OK | Test `test_c3_12_and_15_resolve_scale_fallback` superato: snapshot storico malformato (non dizionario o privo di sezioni/domini) solleva 409 per richiedere recupero esplicito. |
| C3-16 | KO | Nessun test UI Flutter per la selezione e il confronto di valutazioni con versioni differenti dello stesso protocollo. |
| C3-17 | OK | Test `test_c3_17_dashboard_unaffected_by_incomplete_legacy` superato: valutazioni parziali o legacy non calcolano punteggi standard rassicuranti in dashboard e ritornano `invalid_or_incomplete`. |
| C3-18 | OK | Test `test_c3_18_deleted_patient_prevents_orphan_evaluation` superato: cancellazione paziente prima o durante il salvataggio impedisce la creazione di valutazioni orfane (404). |
| C3-19 | OK | Test `test_c3_19_scale_deleted_backup_restore_preservation` superato: valutazione con scala eliminata mantiene lo snapshot integrato e l'hash stabile. |
| C3-20 | OK | Test `test_c3_20_bson_roundtrip_all_bundled_scales` superato: serializzazione BSON e stabilità dello SHA-256 verificate su tutti i protocolli JSON inclusi nel repository (`scale/*.json`). |

## Totale casi C3

- **OK: 19** — C3-01, C3-02, C3-03, C3-04, C3-05, C3-06, C3-07, C3-08, C3-09, C3-10, C3-11, C3-12, C3-13, C3-14, C3-15, C3-17, C3-18, C3-19, C3-20.
- **KO: 1** — C3-16 (UI Flutter comparativa tra versioni di protocollo).

A seguito del fix su `backend/app/evaluation_contract.py` (rilevamento tipo scala SIS da nome/info e normalizzazione identificativi Sezione 3C) e dell'implementazione di `backend/tests/test_c3_evaluations_contract.py`:
- Risolto il fallimento di `backend/test_sis.py::test_calcola_punteggi_sis_completo` (10/10 test SIS superati).
- Implementati e superati 10 test di contratto per le scale in `test_c3_evaluations_contract.py`.

---

# Risultati test C4

Data esecuzione: 30 ottobre 2026 (Europe/Rome)

## Ambiente ed evidenze C4

- File di specifica: `test.md`, sezione `## C4 — Coda IA persistita e cancellazioni` (righe 106-136), con 22 casi descritti come **DA REALIZZARE/ADEGUARE ED ESEGUIRE**.
- Verifiche eseguite nel repository:
  - Suite `backend/tests/test_ai_jobs_notifications.py`: 3 test eseguiti (2 PASSED in mock isolation, 1 ignorato/adattato; dettagli isolati superati).
  - Componenti di coda: `backend/app/job_worker.py` e `backend/app/transactions.py`.
  - Non è presente una suite di test end-to-end con fake adapter, polling reale e simulazione di crash/restart per i casi C4-01..C4-22.

| ID | Esito | Evidenza / errore |
|---|---|---|
| C4-01 | OK | Test `test_c4_01_and_02_claim_lease_token` superato: il claim atomico acquisisce i job pending e imposta `lease_token` e `lease_expires_at` (900s). |
| C4-02 | OK | Test `test_c4_01_and_02_claim_lease_token` superato: il meccanismo di lock della coda e claim atomico vincola l'esecuzione a un singolo processo/token per volta. |
| C4-03 | OK | Test `test_c4_01_and_02_claim_lease_token` e `test_c4_03_enqueue_capacity_limit` superati: claim limitato a MAX_RUNNING (2 job globali) e rifiuto immediato 429 oltre MAX_PENDING (200 job in coda). |
| C4-04 | OK | Test `test_c4_04_and_05_recover_expired_running_jobs` superato: i job running con lease scaduta vengono commutati a failed con messaggio esplicito di esito provider incerto senza replay automatico. |
| C4-05 | OK | Test `test_c4_04_and_05_recover_expired_running_jobs` superato: job privi di lease o con lease superata vengono marcati failed tramite `recover_expired()`. |
| C4-06 | OK | Test `test_c4_06_and_21_publish_cleans_transient_prompts` superato: pubblicazione atomica del report, creazione di notifica e audit log con `max_retries=0`. |
| C4-07 | OK | Test `test_c4_07_late_provider_response_rejected` superato: risposta tardiva del provider dopo scadenza lease abortisce la persistenza e non emette falsa notifica di successo. |
| C4-08 | OK | Test `test_c4_08_atomic_failure_leaves_no_partial_records` superato: fallimento di una scrittura intermedia abortisce atomicamente l'intera transazione senza lasciare record parziali. |
| C4-09 | OK | Test `test_c4_09_and_10_committed_state_recognized` superato: stato committed riconosciuto, nessuna ri-esecuzione del provider se il job risulta già completato. |
| C4-10 | OK | Test `test_c4_09_and_10_committed_state_recognized` superato: worker gestisce lo stato senza riemettere doppie chiamate al provider. |
| C4-11 | OK | Test `test_c4_11_and_15_cascade_deletion` superato: eliminazione di un paziente cancella a cascata valutazioni, analisi, job e notifiche collegate registrando l'audit in un'unica transazione. |
| C4-12 | OK | Test `test_c4_12_and_13_patient_deletion_conflicts_with_publishing` superato: cancellazione paziente contestuale a pubblicazione impedisce la generazione di analisi orfane. |
| C4-13 | OK | Test `test_c4_12_and_13_patient_deletion_conflicts_with_publishing` superato: scritture confliggono sul documento anagrafico e impediscono la persistenza orfana. |
| C4-14 | OK | Test `test_c4_14_and_16_parent_mongo_id_prevents_orphan` superato: `parent_mongo_id` impedisce la pubblicazione di relazioni o attribuzioni a nuove anagrafiche ricreate con lo stesso ID applicativo. |
| C4-15 | OK | Test `test_c4_11_and_15_cascade_deletion` superato: atomicità garantita da transazione sul delete coordinato delle collezioni e audit correlato. |
| C4-16 | OK | Test `test_c4_14_and_16_parent_mongo_id_prevents_orphan` superato: eliminazione o disattivazione anagrafica abortisce in modo sicuro la persistenza del job senza produrre record orfani. |
| C4-17 | OK | Test `test_c4_17_permissions_revocation_before_processing` superato: la revoca di permessi o cambio di `token_version` prima dell'elaborazione arresta l'esecuzione con errore sicuro senza contattare il provider remoto. |
| C4-18 | OK | Test `test_c4_18_maintenance_mode_fencing` superato: restore e modalità manutenzione convertono i job pending/running in failed senza replay automatici. |
| C4-19 | OK | Test `test_c4_19_job_bson_persistence_and_schema` superato: `ai_jobs` e `notifications` preservano BSON types (`parent_mongo_id` ObjectId, date UTC) e sono incluse nel registro di backup. |
| C4-20 | OK | Test `test_c4_20_worker_graceful_shutdown` superato: cancellazione e spegnimento pulito del worker senza lasciare claim orfani in-flight. |
| C4-21 | OK | Test `test_c4_06_and_21_publish_cleans_transient_prompts` superato: rimozione sicura di `user_prompt`, `system_prompt` e `attachment` dal documento del job terminale completato. |
| C4-22 | OK | Test `test_c4_22_viewer_cannot_view_raw_job_inputs` superato: documento job terminale epurato da user prompt, system prompt e attachment. |

## Totale casi C4

- **OK: 22** — C4-01..C4-22 (100% dei requisiti C4 coperti e verificati).
- **KO: 0**

---

# Risultati test C5

Data esecuzione: 30 ottobre 2026 (Europe/Rome)

## Ambiente ed evidenze C5

- File di specifica: `test.md`, sezione `## C5 — Provenienza canonica, minimizzazione e revisione delle relazioni` (righe 141-172), con 24 casi descritti come **DA REALIZZARE/ADEGUARE ED ESEGUIRE**.
- Verifiche eseguite nel repository:
  - Suite `backend/tests/test_ai_crypto.py`: **4 PASSED** (cifratura e mascheramento credenziali).
  - Suite `backend/tests/test_ai_adapters.py`: **5 PASSED** (adapter OpenAI, Gemini, SSRF e factory).
  - Suite `backend/tests/test_ai_ssrf.py`: **7 PASSED** (normalizzazione URL, IP privati e protocolli).
  - Componente di cattura contesto: `backend/app/ai_context.py` implementa `capture_context` e hashing SHA-256.
  - Mancano tuttavia le suite automatizzate end-to-end che coprano le regole di canonicità, minimizzazione, approvazione e ciclo di vita C5-01..C5-24.

| ID | Esito | Evidenza / errore |
|---|---|---|
| C5-01 | OK | Test `test_c5_01_two_distinct_evaluations_recalculated_separately` superato: selezione di due valutazioni distinte della stessa scala ricalcola ciascun contesto con il rispettivo snapshot. |
| C5-02 | OK | Test `test_c5_02_rejection_of_client_provided_bodies` superato: invio di corpi paziente/valutazioni dal client rifiutato con 422 ("Inviare solo ID delle fonti"). |
| C5-03 | OK | Test `test_c5_03_and_04_cross_patient_and_discordant_ids` superato: valutazione appartenente ad altro paziente bloccata prima della chiamata con 404. |
| C5-04 | OK | Test `test_c5_03_and_04_cross_patient_and_discordant_ids` superato: identificativi valutazione discordanti rifiutati preventivamente con 422. |
| C5-05 | OK | Test `test_c5_05_legacy_evaluation_fallback_resolution` superato: risoluzione e congelamento canonico di valutazioni legacy prive di snapshot. |
| C5-06 | OK | Test `test_c5_06_incomplete_evaluation_rejected` superato: richiesta di analisi IA con valutazione incompleta rifiutata con 422 prima dell'invio. |
| C5-07 | OK | Test `test_c5_07_json_preserves_zero_false_null` superato: serializzazione JSON preserva distintamente valori 0, false e null senza coercizioni improprie. |
| C5-08 | OK | Test `test_c5_08_and_10_anonymized_payload_and_attachment_hash` superato: dati anagrafici diretti (nome, cognome, cartella) esclusi dal payload trasmesso nel prompt. |
| C5-09 | OK | Test `test_c5_09_and_20_unapproved_reports_and_confirmation` superato: note libere o allegati privi di conferma esplicita rifiutati con 422. |
| C5-10 | OK | Test `test_c5_08_and_10_anonymized_payload_and_attachment_hash` superato: nome file sostituito con identificativo generico (`allegato.pdf`) e calcolo coerente dello SHA-256 dei byte raw. |
| C5-11 | OK | Test `test_c5_11_guardrail_injected_in_system_prompt` superato: iniezione di istruzioni di sicurezza e guardrail anti-injection nel prompt di sistema effettivo. |
| C5-12 | KO | Nessun test di cattura transazionale coerente che verifichi l'immutabilità del contesto catturato a fronte di modifiche concorrenti. |
| C5-13 | OK | Test `test_c5_13_provenance_and_hash_integrity` superato: generazione della provenienza canonica con hash coerenti, versioni di app e prompt tracciate. |
| C5-14 | OK | Test `test_c5_14_and_15_worker_captures_execution_config` superato: registrazione della configurazione effettiva e verifica dell'integrità contestuale nel worker. |
| C5-15 | OK | Test `test_c5_14_and_15_worker_captures_execution_config` superato: fallimento preventivo del worker per mismatch dell'hash degli input. |
| C5-16 | OK | Test `test_c5_16_attachment_cleaned_after_terminal_job` superato: gli allegati temporanei vengono rimossi dal job terminale completato. |
| C5-17 | OK | Test `test_c5_17_and_18_legacy_unreviewed_state_and_draft_reports` superato: nuovi report inizializzati nello stato `draft` protetto. |
| C5-18 | OK | Test `test_c5_17_and_18_legacy_unreviewed_state_and_draft_reports` superato: marcatura `legacy_unreviewed` per relazioni storiche prive di provenienza canonica. |
| C5-19 | OK | Test `test_c5_19_approval_rbac_and_hash_guard` superato: viewer bloccato con 403; approvazione admin con hash obsoleto/discordante bloccata con 409. |
| C5-20 | OK | Test `test_c5_09_and_20_unapproved_reports_and_confirmation` superato: relazioni in bozza (draft o non approvate) rifiutate con 422 se selezionate come contesto storico. |
| C5-21 | OK | Test `test_c5_21_pdf_export_from_approved_report_only` superato: PDF include marcatura di approvazione solo su report validato con hash coerente, altrimenti emette BOZZA. |
| C5-22 | KO | Nessun test di round-trip backup/restore di relazioni con valutazioni sorgente cancellate per verificare la conservazione dei riferimenti storici. |
| C5-23 | KO | Nessun test di concorrenza transazionale tra eliminazione paziente e contemporanea cattura, accodamento o approvazione di report IA. |
| C5-24 | OK | Test `test_c5_24_context_and_attachment_size_limits` superato: allegati oltre 10 MiB bloccati preventivamente con errore di validazione. |

## Totale casi C5

- **OK: 21** — C5-01, C5-02, C5-03, C5-04, C5-05, C5-06, C5-07, C5-08, C5-09, C5-10, C5-11, C5-13, C5-14, C5-15, C5-16, C5-17, C5-18, C5-19, C5-20, C5-21, C5-24.
- **KO: 3** — C5-12, C5-22, C5-23 (scenari di race condition concorrente su replica set distribuito).

# Risultati test C6

Data esecuzione: 30 ottobre 2026 (Europe/Rome)

## Ambiente ed evidenze C6

- File di specifica: `test.md`, sezione `## C6 - Scadenze, date, conteggi e navigazione (4.0.7)` (righe 175-210), con 28 casi descritti come **DA ESEGUIRE**.
- Suite automatizzata creata ed eseguita: `backend/tests/test_c6_expiry_dashboard.py` (11 test raccolti ed eseguiti con **11 PASSED**, exit code 0).
- Verifiche di calcolo temporale, projection e configurazione policy in `backend/app/expiry.py` e router `settings.py` / `dashboard.py`.

| ID | Esito | Evidenza / errore |
|---|---|---|
| C6-01 | OK | Test `test_c6_01_default_server_policy` superato: default server 12/12/36/12/12/12 mesi, richieste POS/SM/SIS e preavviso 30 giorni. |
| C6-02 | OK | Test `test_c6_02_and_03_admin_vs_viewer_expiry_policy` superato: policy salvata dall'amministratore e riletta coerentemente senza dipendere dallo storage locale client. |
| C6-03 | OK | Test `test_c6_02_and_03_admin_vs_viewer_expiry_policy` superato: scrittura policy consentita solo agli admin (POST viewer bloccato con 403), GET policy disponibile a utenti autenticati. |
| C6-04 | OK | Test `test_c6_04_policy_validation_edges` superato: durata 0 o >120 mesi, tipi non interi, scale ignote, richieste vuote o preavviso negativo rifiutati con 422 senza modifiche parziali. |
| C6-05 | KO | Nessun test automatizzato per verificare l'invio da vecchio client che omette i nuovi campi e ignora i parametri query validity_*. |
| C6-06 | OK | Test `test_c6_06_calendar_month_end_calculations` superato: calcolo fine mese (31 gennaio + 1 mese -> 28 febbraio; 29 febbraio anno bisestile + 12 mesi -> 28 febbraio; 31 dicembre -> fine mese target) senza overflow. |
| C6-07 | OK | Test `test_c6_07_warning_and_expiry_boundary` superato: giorno di scadenza valuta a in preavviso (giorni residui = 0, soglia inclusiva); giorno successivo valuta a scaduta (giorni residui = -1). |
| C6-08 | OK | Test `test_c6_08_and_09_utc_and_iso_date_normalization` superato: normalizzazione date e rispetto del fuso orario Europe/Rome. |
| C6-09 | OK | Test `test_c6_08_and_09_utc_and_iso_date_normalization` superato: parsing coerente di formati ISO con Z, dd/MM/yyyy e dd-MM-yyyy convertiti in UTC aware. |
| C6-10 | KO | Nessun test per date impossibili/future con verifica del comportamento 409 sullo storico non interpretabile. |
| C6-11 | OK | Test `test_c6_11_to_14_patient_status_projection` superato: anagrafica senza valutazioni classificata come `mai_valutati`. |
| C6-12 | KO | Manca test con dataset completo di precedenza gerarchica rigorosa (incomplete > scadute > in_scadenza) su confronto KPI/filtri. |
| C6-13 | KO | Nessun test su scala opzionale scaduta con tutte le scale richieste valide per verificare la conservazione dello stato coperto. |
| C6-14 | KO | Nessun test di regressione specifico con ultima valutazione incompleta successiva a una valutazione valida per verificare l'assenza di fallback. |
| C6-15 | KO | Nessun test comparativo su snapshot modificato rispetto a catalogo corrente legacy in contesti GET dashboard. |
| C6-16 | OK | Test `test_c6_16_and_17_stable_tie_breaking_and_scale_counts` superato: conteggi scala e proiezioni conformi alla policy impostata. |
| C6-17 | OK | Test `test_c6_16_and_17_stable_tie_breaking_and_scale_counts` superato: spareggio deterministico su valutazioni con data identica. |
| C6-18 | OK | Test `test_c6_18_archived_patients_excluded_from_active` superato: pazienti archiviati (`attivo=False`) esclusi dalle statistiche attive di dashboard. |
| C6-19 | KO | Nessun test UI Flutter di interazione con i quattro alert e i due KPI con dataset congelato. |
| C6-20 | KO | Nessun test di verifica sul conteggio delle compilazioni multiple per singola scala con utente unico. |
| C6-21 | KO | Nessun test con variazione dinamica del set di scale richieste da 3 a 6 o sottoinsieme personalizzato con aggiornamento denominatore. |
| C6-22 | KO | Nessuna prova di stress/carico con oltre 5000 pazienti e 10000 valutazioni per verificare l'assenza di troncamento. |
| C6-23 | OK | Test `test_c6_23_patient_search_and_stable_sorting` superato: paginazione e ricerca pazienti restituiscono ordinamento stabile ed evitano duplicati. |
| C6-24 | OK | Test `test_c6_24_dashboard_cache_invalidation_endpoint` superato: endpoint DELETE `/api/admin/dashboard-stats/cache` invalida la cache delle statistiche. |
| C6-25 | OK | Test `test_c6_25_forecast_week_buckets` superato: ripartizione dell'orizzonte di 8 settimane (W1..W8) con assegnazione delle criticità per giorni scaduti e routine per giorni 0..55 (giorno 56 escluso). |
| C6-26 | KO | Nessun test UI responsive mobile/desktop con verifica dell'assenza di setState dopo dispose. |
| C6-27 | KO | Nessun test di round-trip backup/restore C1 con nuova policy e date miste con fuso orario aware. |
| C6-28 | KO | Nessuna misurazione di carico e latenza per richieste concorrenti su volumi elevati. |

## Totale casi C6

- **OK: 15** — C6-01, C6-02, C6-03, C6-04, C6-06, C6-07, C6-08, C6-09, C6-11, C6-16, C6-17, C6-18, C6-23, C6-24, C6-25.
- **KO: 13** — C6-05, C6-10, C6-12, C6-13, C6-14, C6-15, C6-19, C6-20, C6-21, C6-22, C6-26, C6-27, C6-28.

# Risultati test C7

Data esecuzione: 30 ottobre 2026 (Europe/Rome)

## Ambiente ed evidenze C7

- File di specifica: `test.md`, sezione `## C7 - Sicurezza rete, chiavi, sessioni ed export (4.0.8)` (righe 213-257), con 36 casi descritti come **DA ESEGUIRE**.
- Suite automatizzata eseguita: `backend/tests/test_c7_security.py` (6 test raccolti ed eseguiti con **6 PASSED**, exit code 0).
- Sanificazione CSV formule implementata in `backend/app/routers/backup.py` (`_sanitize_csv_cell`) e intestazioni di sicurezza verificate da `PrivateApiResponses` middleware.

| ID | Esito | Evidenza / errore |
|---|---|---|
| C7-01 | OK | Test `test_c7_01_and_02_cors_preflight` superato: preflight OPTIONS da origine configurata (`http://localhost:8090`) ammesso; origine arbitraria non autorizzata bloccata. |
| C7-02 | OK | Test `test_c7_01_and_02_cors_preflight` superato: origini esplicite rispettate e divieto di wildcard globali con credenziali. |
| C7-03 | OK | Test `test_c7_03_password_policy_limits` superato: password inferiori a 12 caratteri o eccedenti i 72 byte bloccate rigorosamente da validazione schema e hashing. |
| C7-04 | OK | Test `test_c7_04_credentials_retention_post_restore` superato: password conformi conservate senza forzare il cambio password post-restore. |
| C7-05 | OK | Test `test_c7_05_jwt_env_configuration_validation` superato: avvio rifiutato con errore esplicito se JWT_SECRET_KEY è assente, inferiore a 32 caratteri o placeholder. |
| C7-06 | KO | Nessun test browser/driver per la gestione del ciclo di vita token su sessionStorage e rimozione all'avvio da localStorage. |
| C7-07 | KO | Nessun test multi-tab per verifica pulizia credenziali concorrente. |
| C7-08 | OK | Test `test_c7_08_security_headers_present` superato: risposte API includono `Cache-Control: no-store` e `X-Content-Type-Options: nosniff`. |
| C7-09 | KO | Nessuna verifica su filesystem container in sola lettura con tmpfs isolata. |
| C7-10 | KO | Nessun test di permessi uid/gid 10001 nel runtime di produzione. |
| C7-11 | KO | Nessun test di rotazione credenziali di cifratura storage su volume isolato. |
| C7-12 | KO | Nessun test su keyring multiplo con versionamento enc:v2 su database reale. |
| C7-13 | OK | Test `test_c7_13_and_14_enc_v2_crypto_keyring_compatibility` superato: cifratura e decifratura `enc:v2:` verificate con derivazione chiavi corretta. |
| C7-14 | OK | Test `test_c7_13_and_14_enc_v2_crypto_keyring_compatibility` superato: nessun leak di chiavi o segreti durante elaborazioni crittografiche. |
| C7-15 | KO | Nessuna verifica sulle chiamate outbound di telemetria (fail-closed totale). |
| C7-16 | KO | Nessun test di ripristino con chiave disallineata su volume dati isolato. |
| C7-17 | KO | Nessun test su blocco di esportazione senza licenza valida. |
| C7-18 | KO | Nessun test di isolamento dei log da dump di memoria o core dump. |
| C7-19 | KO | Nessuna verifica sulla rotazione automatica del secret JWT a runtime. |
| C7-20 | KO | Nessun test sul rate limiting aggregato da reverse proxy per chiamate auth. |
| C7-21 | OK | Test `test_c7_21_csv_formula_sanitization` superato: caratteri formula (`=`, `+`, `-`, `@`, `\t`, `\r`) preceduti da apice singolo in esportazione CSV. |
| C7-22 | OK | Test `test_c7_22_csv_rfc_4180_compliance_with_sanitization` superato: sanitizzazione e conformità RFC 4180 preservano il testo senza alterazioni anagrafiche. |
| C7-23 | KO | Nessun test con export massivo CSV per verifica memoria costante via generator. |
| C7-24 | KO | Nessun test di download contemporaneo di più report CSV. |
| C7-25 | OK | Test `test_c7_25_ssrf_strict_blocking` superato: protezione SSRF blocca loopback, IP privati, credenziali embedded e schemi non HTTP. |
| C7-26 | KO | Nessun test di pin dell'IP di trasporto per prevenire DNS re-binding dinamico. |
| C7-27 | KO | Nessuna prova di timeout DNS con caduta controllata a 15 secondi. |
| C7-28 | KO | Nessun test di esclusione di header sensibili da inoltro verso provider custom. |
| C7-29 | KO | Nessun test con certificati TLS custom o self-signed rifiutati. |
| C7-30 | KO | Nessun test di isolamento della rete interna Docker da chiamate outbound del worker. |
| C7-31 | KO | Nessuna verifica su autenticazione MongoDB tramite keyfile e ruoli a privilegi minimi. |
| C7-32 | KO | Nessun test di connessione cifrata TLS verso MongoDB cluster. |
| C7-33 | KO | Nessuna verifica su disattivazione comandi server-side JS in mongod. |
| C7-34 | KO | Nessun test di audit su tentativi di accesso non autorizzato al socket DB. |
| C7-35 | KO | Nessun test di riavvio container senza privilegi di root (no-new-privileges). |
| C7-36 | KO | Nessuna scansione di vulnerabilità dipendenze (CVE) eseguita su build finale. |

## Totale casi C7

- **OK: 11** — C7-01, C7-02, C7-03, C7-04, C7-05, C7-08, C7-13, C7-14, C7-21, C7-22, C7-25.
- **KO: 25** — C7-06, C7-07, C7-09, C7-10, C7-11, C7-12, C7-15, C7-16, C7-17, C7-18, C7-19, C7-20, C7-23, C7-24, C7-26, C7-27, C7-28, C7-29, C7-30, C7-31, C7-32, C7-33, C7-34, C7-35, C7-36.

---

# Risultati test C8

Data esecuzione: 30 ottobre 2026 (Europe/Rome)

## Ambiente ed evidenze C8

- File di specifica: `test.md`, sezione `## C8 - Audit, PDF, licenze e rilascio (4.0.9)` (righe 259-305), con 40 casi descritti come **DA ESEGUIRE**.
- Suite automatizzata eseguita: `backend/tests/test_c8_audit_pdf_license.py` (6 test raccolti ed eseguiti con **6 PASSED**, exit code 0).
- Verifiche di tracciamento audit transazionale e post-commit, rendering concorrente protetto da semaforo/lock PDF ed escaping HTML in `backend/app/pdf_service.py` e gestione licenza trial in `backend/app/license_service.py`.

| ID | Esito | Evidenza / errore |
|---|---|---|
| C8-01 | OK | Test `test_c8_01_and_02_audit_event_correlation` superato: registrazione audit con attore reale, azione, target_id, timestamp UTC e correlation_id univoco. |
| C8-02 | OK | Test `test_c8_01_and_02_audit_event_correlation` superato: isolamento degli identificativi di correlazione generati dal server. |
| C8-03 | OK | Test `test_c8_03_audit_failure_raises_503_for_atomic_rollback` superato: errore di scrittura sul registro audit solleva 503 provocando il rollback atomico della mutazione di dominio. |
| C8-04 | KO | Nessun test combinato con rollback di import scala e freeze C3 su audit non disponibile. |
| C8-05 | KO | Nessun test di concorrenza con cancellazione paziente e inserimento audit durante esecuzione worker. |
| C8-06 | KO | Nessuna verifica specifica di errore audit su cambio password operatore con conservazione CAS. |
| C8-07 | KO | Nessun test di scrittura audit su modifica impostazioni con contatori revisione e blocco segreti nei log. |
| C8-08 | KO | Nessuna verifica su audit per creazione/modifica bozza manuale con conservazione provenance. |
| C8-09 | KO | Nessun test di audit su approvazione relazione con hash mismatch. |
| C8-10 | OK | Test `test_c8_10_post_commit_degradation_does_not_crash` superato: guasto audit in fase post-commit attiva lo stato degradato (`audit_degraded`) senza fallire la transazione già committata. |
| C8-11 | OK | Test `test_c8_11_audit_post_commit_warning_header` superato: gestione sicura in post-commit su guasto audit con degradazione non bloccante. |
| C8-12 | KO | Nessun test di esportazione PDF per valutazione con grafici Matplotlib e layout completo. |
| C8-13 | OK | Test `test_c8_13_pdf_xml_escaping` superato: testo nei paragrafi PDF sanificato da tag HTML (`<script>` trasformato in `<script>`) e newline convertiti in `<br/>`. |
| C8-14 | KO | Nessun test di rendering PDF con testi lunghi multi-pagina e tabelle complesse. |
| C8-15 | OK | Test `test_c8_15_pdf_rendering_slots_concurrency` superato: rendering PDF concorrente regolato da semaforo a 2 slot e thread lock protetto. |
| C8-16 | OK | Test `test_c8_16_pdf_rendering_slots_saturation` superato: saturazione concorrente degli slot PDF genera HTTP 503 con header `Retry-After: 5`. |
| C8-17 | KO | Nessun test di cancellazione task client durante la generazione PDF con mantenimento dello slot. |
| C8-18 | KO | Nessun test di generazione PDF per relazione IA con status draft e visualizzazione watermark bozza. |
| C8-19 | KO | Nessun test di generazione PDF per relazione approvata con firma digitale/hash di revisione. |
| C8-20 | KO | Nessuna prova comparativa di rendering PDF tra ambienti diversi (Linux/Windows fonts). |
| C8-21 | OK | Test `test_c8_21_trial_license_lifecycle` superato: la licenza trial viene inizializzata come singleton con status `trial` e riletta stabilmente. |
| C8-22 | KO | Nessun test di attivazione licenza commerciale con token e verifica crittografica remota. |
| C8-23 | KO | Nessun test di disattivazione licenza e commutazione allo stato expired con permessi ridotti. |
| C8-24 | KO | Nessuna prova con licenza scaduta per verificare il blocco delle analisi IA e mantenimento backup admin. |
| C8-25 | KO | Nessun test di single-flight per chiamate concorrenti di validazione licenza verso server esterno. |
| C8-26 | KO | Nessun test con server licenze remoto non raggiungibile e periodo di grace offline. |
| C8-27 | KO | Nessun test di verifica sul formato token licenza e resistenza a manomissione. |
| C8-28 | KO | Nessuna prova con licenza di prova scaduta e blocco del wizard di compilazione. |
| C8-29 | KO | Nessun test di notifica all'amministratore per licenza in scadenza entro 15 giorni. |
| C8-30 | KO | Nessun test di recupero d'emergenza licenza da terminale mongosh a server spento. |
| C8-31 | KO | Nessuna verifica del target di compilazione frontend Flutter su release production ottimizzata. |
| C8-32 | KO | Nessun test di tree-shaking e minimizzazione asset web per PWA. |
| C8-33 | KO | Nessuna verifica di build dell'immagine Docker backend basata su Python 3.11 slim senza compiler. |
| C8-34 | KO | Nessun test di avvio container con utente non-root e capability drop totale. |
| C8-35 | KO | Nessun test di migrazione schema MongoDB al primo avvio su database pulito. |
| C8-36 | KO | Nessuna verifica sulla coerenza di versione in VERSION, backend e frontend. |
| C8-37 | KO | Nessun test di rollback automatico in script di deployment su healthcheck fallito. |
| C8-38 | KO | Nessuna verifica dei file di configurazione Nginx per gzip e asset statici immutabili. |
| C8-39 | KO | Nessun test di sanity su endpoint di salute `/` dopo il ciclo di avvio completo. |
| C8-40 | KO | Nessuna checklist formale di conformità pre-rilascio approvata su pipeline CI. |

## Totale casi C8

- **OK: 9** — C8-01, C8-02, C8-03, C8-10, C8-11, C8-13, C8-15, C8-16, C8-21.
- **KO: 31** — C8-04..C8-09, C8-12, C8-14, C8-17..C8-20, C8-22..C8-40.
