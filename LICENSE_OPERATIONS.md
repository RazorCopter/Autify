# Operazioni del sistema licenze

## Segreti e responsabilità

- `LICENSE_SHARED_SECRET` cifra le comunicazioni fra backend e License Server. Deve essere identico nei due servizi, avere almeno 32 caratteri e non deve essere esposto al frontend.
- `LICENSE_ADMIN_KEY` protegge gli endpoint amministrativi del License Server. Deve essere diverso dal segreto condiviso e disponibile solo agli operatori autorizzati.
- I codici licenza sono mostrati in chiaro soltanto al momento della creazione. Nel database del License Server sono memorizzati come hash.
- Il token di licenza è opaco, distinto dal codice e associato all'istanza attivata. Nel License Server è memorizzato soltanto il relativo hash.

Generare valori casuali distinti, per esempio con `openssl rand -hex 32`, conservarli nel secret store dell'ambiente e non inserirli nel repository o nelle immagini Docker.

## Rotazione del segreto condiviso

La cifratura corrente accetta una sola `LICENSE_SHARED_SECRET`; non esiste una finestra automatica con doppia chiave. La rotazione richiede quindi un aggiornamento coordinato:

1. pianificare una breve finestra di manutenzione e salvare un backup del database MongoDB e del volume `license_data`;
2. generare il nuovo segreto;
3. arrestare o isolare il backend per evitare richieste firmate con il vecchio segreto;
4. aggiornare `LICENSE_SHARED_SECRET` sia nel backend sia nel License Server;
5. ricreare entrambi i container e verificare `/health` sul License Server;
6. dal backend forzare una validazione remota di una licenza attiva;
7. eliminare il vecchio segreto dal secret store dopo la verifica.

La rotazione del segreto condiviso non invalida i token opachi: i token sono dati cifrati durante il transito, ma non sono derivati dal segreto.

## Rotazione e revoca dei token opachi

Il token viene generato all'attivazione e non è recuperabile dal suo hash. Per sostituirlo:

1. identificare il codice licenza tramite il suffisso e i dati operativi conservati al momento dell'emissione;
2. chiamare `POST /v1/admin/licenses/release` con il codice completo e `X-License-Admin-Key`;
3. verificare che il vecchio token non sia più accettato;
4. riattivare lo stesso codice sull'istanza autorizzata: verrà emesso un nuovo token casuale;
5. forzare la validazione remota dal backend e verificare il nuovo stato.

Per bloccare definitivamente una licenza usare `POST /v1/admin/licenses/revoke`; una licenza revocata non deve essere rilasciata e riattivata.

## Migrazione delle licenze legacy

Il License Server riconosce temporaneamente il token legacy deterministico, pari all'hash del codice, soltanto per righe già attivate senza `token_hash`. Questa compatibilità serve esclusivamente alla migrazione.

Procedura consigliata:

1. eseguire il backup di MongoDB e SQLite;
2. distribuire backend e License Server aggiornati mantenendo invariati `LICENSE_SHARED_SECRET` e gli identificativi di istanza;
3. validare le installazioni esistenti e monitorare gli errori `404`, `409` e gli stati `invalid`;
4. per ogni installazione legacy, effettuare `release` e una nuova attivazione controllata per ottenere un token opaco;
5. verificare nel database del License Server che `token_hash` sia valorizzato;
6. rimuovere il ramo di compatibilità legacy soltanto quando non restano righe attive con `token_hash IS NULL`.

Non modificare manualmente `instance_id`, `code_hash` o `token_hash`. Non cancellare il record MongoDB della licenza per tentare una migrazione: l'identificativo dell'istanza e la cache offline fanno parte dello stato di sicurezza.

## Verifica end-to-end Docker

Con Docker Desktop avviato e un `.env` compilato a partire da `.env.example`:

```bash
docker compose config --quiet
docker compose up --build -d
docker compose ps
docker compose logs --no-color autify-license-server autify-api
curl http://localhost:8001/health
```

Completare la prova creando una licenza tramite endpoint amministrativo, attivandola dalla UI e forzando una validazione remota. Al termine usare `docker compose down`; non aggiungere `-v` se il volume delle licenze deve essere conservato.