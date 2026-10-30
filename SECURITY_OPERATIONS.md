# C7 — Rete, credenziali, sessioni ed export

Versione locale4.0.8, 30 ottobre2026. Nessun test, analyzer, build, chiamata provider, deploy o modifica al database cliente eseguito. Le procedure sotto sono preparate per la fase di verifica e rilascio.

## Interventi applicativi

- CORS ammette `PATCH`; origini esatte da `CORS_ORIGINS`, niente wildcard introdotte. CORS non sostituisce autenticazione o autorizzazioni.
- Nuove password e reset amministrativi: minimo12 caratteri, massimo72 byte UTF-8, niente valori composti solo da spazi. Login degli account preesistenti preservato. JWT richiede segreto >=32 caratteri non uguale al placeholder d'esempio. Nuovi token durano60 minuti, configurabile15–480 tramite `JWT_EXPIRY_MINUTES`; quelli già emessi mantengono il proprio `exp` fino a scadenza/revoca.
- JWT browser in `sessionStorage`; il vecchio token persistente viene rimosso da `localStorage` all'avvio, richiedendo un nuovo login. Reload della scheda conserva la sessione. I metadati UI possono restare locali; API usa ruolo e versione token dal DB. Questo limita la persistenza, ma non rende il token HttpOnly: codice JavaScript eseguito nella pagina può ancora leggerlo. Migrazione cookie/CSRF non introdotta in questo intervento.
- CSV solo admin, pulsante disabilitato agli altri ruoli, `no-store` e audit di avvio. Ogni cella controllata anche dopo spazi/controlli Unicode; prefisso apostrofo se può iniziare una formula `= + - @` oppure inizia con tab/CR/LF. Il DB non cambia. Il CSV mantiene delimitatore `;`, quoting, Unicode e BOM. Le date sono ricostruite con il servizio C6 in lotti100, senza il vecchio limite100 scale o confronto tra tipi misti. Audit di avvio non certifica download completato; uno stream interrotto va scaricato di nuovo.
- Risposte `/api/` non memorizzabili in cache. Nginx applica nosniff, SameOrigin per iframe, no-referrer, restrizione camera/microfono/geolocalizzazione e CSP di base per object/base/frame-ancestors. Inclusioni ripetute nei location che definiscono `add_header`, perché l'ereditarietà standard non somma automaticamente le direttive. Nessuna policy `script-src` restrittiva non verificata con Flutter, nessuna promessa di prevenzione completa XSS. HSTS/TLS pubblico va gestito sul terminatore HTTPS dell'installazione, non sul listener HTTP8090.
- Backend uid/gid10001, filesystem in sola lettura, `/tmp` tmpfs256MiB, niente capability, no-new-privileges. Cache Matplotlib in `/tmp`. Dimensionare tmpfs dopo verifica PDF concorrenti. Mongo su rete Compose interna `data`, condivisa con la sola API; nessuna porta DB pubblicata. Un amministratore dell'host Docker rimane privilegiato.

## Credenziali IA e rotazione

Le nuove scritture richiedono `AI_SETTINGS_ENCRYPTION_KEY` casuale dedicata >=32 caratteri. Nessuna cifratura nuova deriva dal JWT e nessun seed pubblico di fallback. Formato Fernet `enc:v2:<key-id>:<token>`, identificativo derivato dalla chiave senza esporla.

Lettura supportata:

1. `enc:v2`: chiave attiva o `AI_SETTINGS_PREVIOUS_KEYS`, array JSON delle vecchie chiavi IA.
2. `enc:v1`: stessi materiali e derivazione JWT storica usando JWT corrente oppure `AI_SETTINGS_LEGACY_JWT_KEYS`, array JSON dei JWT originali. La derivazione JWT è limitata alla lettura legacy.
3. Valori legacy in chiaro: migrati dal loader con la chiave dedicata; senza chiave si segnala503. Nessuna sostituzione automatica della configurazione IA malformata o illeggibile con default vuoti. Le migrazioni at-rest usano confronto del documento letto prima di scrivere: una modifica concorrente genera409.

Procedura di rotazione, da eseguire dopo i casi differiti:

1. Inventariare versione dei segreti, chiavi originarie e backup esistenti; custodire una copia esterna verificata. Non registrare i valori nei log o nei file del repository.
2. Predisporre nuova chiave attiva, conservando vecchie IA e JWT negli appositi keyring. Configurazione tramite gestore segreti/ambiente; riavvio controllato.
3. Admin chiama POST `/api/admin/settings/ai/rewrap-secrets` autenticato. Tutte le credenziali e gli header sono decifrati prima della scrittura; un errore non modifica il documento. Compare-and-swap impedisce di sovrascrivere una configurazione cambiata nel frattempo. Nessun segreto restituito o incluso nell'audit.
4. Verificare lettura/configurazione, richiesta provider e backup/restore isolati. Conservare i vecchi materiali finché esistono backup che li richiedono: rewrap del DB non ricifra gli archivi precedenti.
5. Ruotare il JWT solo dopo aver conservato i materiali necessari ai segreti v1 e ai backup C1. C1 usa un keyring distinto (`LEGACY_BACKUP_JWT_SECRETS`). Non confondere i due.

Restore C1 valida segreti `enc:*` attraverso lo stesso decoder. Mancanza di una chiave, versione sconosciuta o token corrotto blocca il restore prima delle scritture. I backup restano cifrati con la chiave dedicata C1; i materiali crittografici restano fuori dall'archivio dati.

## Endpoint IA configurabili e SSRF

`ALLOWED_AI_HOSTS` confronta hostname esatti, senza autorizzare implicitamente sottodomini. Vuota significa endpoint pubblici HTTPS, non accesso a qualunque rete interna.

Si rifiutano credenziali nell'URL, query/frammenti, controlli, backslash, hostname/porte invalidi, IPv6 con scope, risoluzione DNS fallita o senza indirizzi. Tutti gli A/AAAA restituiti devono rispettare la policy; un record proibito blocca anche un risultato misto pubblico/privato. Loopback, link-local/metadata, multicast, unspecified e riservati sono sempre negati, anche con flag locale.

Per un gateway LAN: hostname/IP esatto in `ALLOWED_AI_HOSTS` e `ALLOW_PRIVATE_AI_ENDPOINTS=true`. Ammessi soltanto intervalli RFC1918 o IPv6 ULA. HTTP richiede inoltre `ALLOW_INSECURE_LOCAL_AI_HTTP=true` e tutti gli IP locali autorizzati. Per esempio un gateway Docker può essere autorizzato per il proprio nome esatto; `localhost` è sempre escluso. I gateway pubblici richiedono HTTPS.

`PinnedAITransport` risolve nuovamente a ogni richiesta effettiva, controlla gli indirizzi e connette l'IP approvato conservando Host e hostname TLS/SNI; verifica certificati attiva. Non segue redirect né proxy d'ambiente. HTTPX/httpcore fissati0.27.2/1.0.9 per il contratto usato. Se il primo indirizzo ammesso non risponde, non viene introdotto un replay automatico della richiesta verso gli altri IP. I retry applicativi preesistenti restano controllati da C4 (worker zero retry).

Il limite DNS asincrono è15s e usa un thread; cancellare l'attesa non può interrompere il resolver di sistema già partito. Configurare anche timeout DNS/egress dell'host. I client dei provider fissi ignorano proxy d'ambiente; le CA private devono essere installate nel trust store, senza disabilitare TLS. Resta da verificare su TLS, IPv4/IPv6 e DNS variabile in ambiente isolato.

Riferimenti tecnici consultati: [trasporti HTTPX](https://www.python-httpx.org/advanced/transports/), [implementazione SNI httpcore1.0.9](https://github.com/encode/httpcore/blob/1.0.9/httpcore/_async/connection.py), [ereditarietà header Nginx](https://nginx.org/en/docs/http/ngx_http_headers_module.html).

## Mongo autenticato — attivazione separata sul volume esistente

Il Compose base preserva l'avvio legacy senza autenticazione per evitare un cambio cieco su volumi esistenti. La rete interna riduce la raggiungibilità ma non equivale all'autenticazione. **ASTRA-16 resta parzialmente aperto operativamente finché non viene attivato e verificato l'overlay autenticato.** Non sono stati creati utenti Mongo né chiavi su questa macchina.

Preparati `docker-compose.mongo-auth.yml` e `ops/provision_mongo_users.js`. Non cancellano il volume, non rinominano `autanalysis`, non reimpostano password esistenti. API con account `readWrite` limitato ad `autanalysis`; account di recupero root separato, passato solo al DB/healthcheck. L'API non riceve root. Il provisioning verifica ruoli/credenziali degli utenti omonimi prima di continuare; conflitti richiedono riconciliazione esplicita.

Procedura destinata al gestore dell'installazione, con finestra di manutenzione:

1. Backup C1 e inventario di replica set, volume, utenti/ruoli già presenti. Preparare recupero e fermare i writer. Procedura riferita al singolo nodo `autify-rs` già inizializzato da C1; non avviare l'overlay su volume vuoto senza bootstrap dedicato.
2. Generare offline password casuali distinte >=32 caratteri per root/app e un keyfile Mongo base64 di lunghezza ammessa. Salvare sotto `secrets/` esclusa da Git o nel gestore segreti. Sul nodo il keyfile sarà copiato con proprietario mongodb e permessi0400. Non committare credenziali o keyfile.
3. Con Mongo legacy ancora disponibile solo in manutenzione, caricare le quattro variabili `MONGO_ROOT_USERNAME`, `MONGO_ROOT_PASSWORD`, `MONGO_APP_USERNAME`, `MONGO_APP_PASSWORD` nella sessione host in modo riservato. Eseguire esplicitamente lo script nel container via stdin; non inserire password come argomenti. Esempio PowerShell, **non eseguito**:

   ```powershell
   Get-Content -Raw ops/provision_mongo_users.js | docker compose exec -T -e MONGO_ROOT_USERNAME -e MONGO_ROOT_PASSWORD -e MONGO_APP_USERNAME -e MONGO_APP_PASSWORD autify-db mongosh --quiet
   ```

4. Preparare `.env`/gestore segreti con URI app autenticata, password codificata URL, `authSource=autanalysis&replicaSet=autify-rs`, root per healthcheck e `MONGO_KEYFILE_PATH`. Il file `.env` letto da Compose non esporta automaticamente variabili nella shell host per il passo3.
5. Avviare con entrambi i file in ogni successiva operazione di deploy:

   ```powershell
   docker compose -f docker-compose.yml -f docker-compose.mongo-auth.yml up -d
   ```

6. Verificare primary/health autenticati; rifiuto letture senza credenziali; API/C1 snapshot, restore, indici e transazioni C3/C4 con account app. Provare il recupero root in ambiente isolato. Nessun comando di cancellazione volume.

L'overlay abilita keyfile e controllo accessi, non TLS Mongo. Per requisiti di cifratura in transito DB o deployment multi-host serve una configurazione certificati dedicata. La procedura richiede gestione operativa, conservazione dei segreti e verifica; non viene presentata come migrazione automatica o completata. Riferimento: [abilitazione autenticazione su replica set esistente](https://www.mongodb.com/docs/manual/tutorial/enforce-keyfile-access-control-in-existing-replica-set/).

Checkpoint12 in `file.md`, casi differiti C7 in `test.md`. C7 non equivale a un collaudo o certificazione di sicurezza; gli aspetti operativi e i residui sopra sono espliciti.
