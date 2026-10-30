# C8 — Audit, PDF, licenze e rilascio

Versione locale4.0.9, 30 ottobre2026. Fix applicati per lettura/editing; test, analyzer, installazione pacchetti, rendering PDF, build e deploy non eseguiti. Nessun database cliente toccato. Le istruzioni di verifica e rilascio sono preparate per una fase successiva.

## Audit e confini transazionali

`audit.py` costruisce eventi con event-id, schema1, app-version, correlation-id generato dal server, timestamp UTC, attore/azione/target e versione del target quando disponibile (hash snapshot/report). Nuovi dettagli sintetici, massimo512 caratteri, senza risposte, report, note, password, chiavi o prompt. I vecchi eventi non vengono riscritti per inventare campi mancanti.

Audit e mutazione condividono la transazione per valutazioni create/update/delete, import/modifica/delete protocolli inclusa SIS, anagrafiche, account operatori/cambio password, impostazioni generali/IA/scadenze/rewrap, bozze manuali/note/approvazione/delete relazioni, accodamento/pubblicazione job e restore. Il freeze legacy C3 registra la ricostruzione come sistema. C1/C3/C4 già richiedono un replica set; non viene introdotto un fallback standalone. Un errore audit impedisce il commit dei flussi transazionali.

Login, esportazioni, operazioni remote sulle licenze e alcune funzioni diagnostiche conservano audit successivo all'azione: non si può annullare retroattivamente una chiamata al centrale o un download avviato. `post_commit` segnala il guasto nei log e con `X-Audit-Status: degraded`, più `X-Correlation-ID`; il wrapper HTTP Flutter mostra un avviso. Il risultato dell'azione già conclusa non diventa un errore che suggerisca un retry cieco. La segnalazione non ricrea l'evento perduto e non è un outbox persistente. Nessuna garanzia di consegna audit durante indisponibilità del DB su quei percorsi. Gli export registrano avvio, non completamento download.

Il registro è leggibile solo da admin, anche via API; UI non mostra il contenuto agli altri ruoli. Limite1–1000, default200 e offset>=0, ordinamento timestamp/_id. Correlazione/versione visibili nel tooltip degli eventi nuovi. Indici su cronologia e correlazione. Nessun TTL: retention non definita dalla struttura, quindi nessuna cancellazione automatica di eventi o prove storiche. Heartbeat, lease, cache e flag di lettura notifiche non generano un evento per ogni aggiornamento tecnico. Le migrazioni at-rest delle credenziali preservano i CAS C7; la ricifratura amministrativa esplicita è tracciata atomicamente.

## PDF e fedeltà allo storico

`pdf_service.xml_text` tratta il testo libero come testo: escape di `& < >`, rimozione controlli XML e conversione delle nuove righe in interruzioni generate dall'app. Applicato a note, codici, domande/opzioni, intestazione organizzazione, metadati e campi personali che entrano in Paragraph. Il Markdown IA mantiene solo il sottoinsieme generato dal parser dopo escape; HTML, immagini e URL nel testo non diventano risorse ReportLab da caricare.

Il generatore non sovrascrive più domande/opzioni dello snapshot con `Scala_POS.json`. La scala risolta da C3 rimane l'unica fonte; testi mancanti restano mancanti, senza ricostruzioni silenziose da un protocollo diverso. Etichette nuove coerenti con l'ambito educativo; nessuna modifica alle tabelle normative.

Figure Matplotlib locali, senza pyplot globale, e lock di rendering per processo anche per le chiamate dirette al generatore. API ammette al massimo2 lavori PDF per processo (uno può attendere il lock), attesa posto massimo5s, poi503 con Retry-After. Se un client cancella, il thread Python non si può interrompere: il posto resta occupato fino al termine. Il limite non è distribuito tra processi e non è un timeout di esecuzione del documento. Il payload del vecchio export libero ha report limitato a1.000.000 caratteri. La memoria tmpfs C7 e il comportamento su note molto lunghe sono da misurare. Nessun PDF è stato renderizzato o verificato visivamente in questa fase.

## Licenze e accesso ai dati

- `force_remote=true` riservato agli admin; la schermata viewer rilegge lo stato senza forzare il centrale.
- Indice unico parziale su `licenses.id`; bootstrap trial concorrente gestisce solo DuplicateKeyError. Duplicati storici fermano l'avvio: fare inventario e riconciliazione esplicita, senza eliminarli automaticamente.
- Lock per processo serializza operazioni licenza; richieste di stato sovrapposte riusano una validazione già avvenuta. Compare-and-swap impedisce che una risposta remota tardiva sostituisca una successiva attivazione/disattivazione/validazione. Più processi possono ancora chiamare il centrale: non si afferma un single-flight distribuito né exactly-once delle operazioni remote. Il409 invita a rileggere lo stato senza ripetere automaticamente un'azione remota dall'esito incerto.
- Lifetime permanentemente attivata conserva la politica esistente: niente verifica periodica automatica, salvo forzatura amministrativa. Nessun cambio del protocollo centrale, della crittografia o della politica commerciale di revoca. Una revoca lifetime automatica richiederebbe una decisione esplicita tra client e centrale.
- Cache/grace esistenti preservate; timestamp futuro non estende il periodo offline. Errori crittografici di risposta sono trattati come validazione non disponibile, senza fidarsi del payload. TLS/proxy/redirect seguono il client diretto senza proxy d'ambiente.
- Il rilascio di una licenza non genera altri15 giorni di trial: torna soltanto all'eventuale residuo della finestra originale da created_at; senza data originale nessuna nuova finestra inventata. Instance-id conservato.
- A licenza scaduta restano login/cambio password e backup/restore admin C1. La schermata bloccante ora permette all'admin di scaricare il backup. Non riapre le operazioni educative; restore continua a richiedere manutenzione e vincoli C1. I dati non vengono cancellati per scadenza. Il recupero dell'archivio cifrato richiede sempre le chiavi custodite dall'installazione.

## Dipendenze e pipeline preparata

`BUILD_VERSIONS.json` registra le immagini e i digest verificati tramite metadati dei registry: Python3.11.14, builder Flutter3.41.9 (coerente con la versione registrata nel progetto), Nginx1.28.0 e Mongo8.0.4. Dockerfile/Compose usano gli stessi digest. Non sono state scaricate o avviate immagini.

Manifest backend esatti:44 pacchetti runtime e49 per ambiente test, versioni e SHA256 degli artefatti wheel da metadati PyPI. `requirements.txt`/`requirements-test.txt` includono i rispettivi lock; pip richiede hash e solo wheel. Mantenuti FastAPI0.109.2/Pydantic2.6.1/Pydantic-settings2.1.0 invece di copiarne le versioni differenti installate sul computer. HTTPX0.27.2 e httpcore1.0.9 rimangono coerenti con C7. Target della preparazione: CPython3.11 su Linux; non è un lock validato per Python3.14 host Windows. Nessuna installazione o esecuzione ha dimostrato la compatibilità: farlo nella fase test. Le versioni fissate non equivalgono a una verifica CVE.

Flutter usa `pubspec.lock` preesistente e `pub get --enforce-lockfile`; lock e modifiche di altre attività conservati. Il builder Cirrus scelto esiste al digest indicato; il [progetto upstream ha annunciato la cessazione degli aggiornamenti](https://github.com/cirruslabs/docker-images-flutter), quindi il digest evita deriva ma non sostituisce la pianificazione di un futuro builder mantenuto. Non viene promessa identità bit-per-bit di ogni output.

`.github/workflows/verify-release.yml` parte **solo** da workflow_dispatch. Preparazione non avvia GitHub Actions. Quando richiesta, esegue backend/tests su replica set effimero senza volume cliente, i tre file Flutter VM portabili dashboard/settings/licenza e compilazione web. I test Flutter che importano dart:html richiedono una suite browser separata, ancora da completare con C9; i casi test.md non sono tutti automatizzati da questa pipeline. Difetti preesistenti, incluso ASTRA-23, possono bloccare la prima esecuzione: non sono nascosti o marcati passati.

Input opzionale build_images: dopo verifica riuscita prepara immagini, archivio, SHA256, commit, versione, image-id e hash lock. Nessun push, merge, deploy o credenziale di produzione. Azioni GitHub fissate a commit. Readiness pubblica `/health/ready` verifica ping DB e primary scrivibile di un replica set;503 altrimenti. `/` rimane liveness. Compose attende API healthy prima del frontend; la readiness non prova funzionalità PDF, provider IA o round-trip del backup.

## Rilascio e rollback — da eseguire successivamente

1. Completare casi C1–C8, verifiche visive PDF/responsive, suite browser e pipeline sul commit scelto. Usare dati sintetici e istanze isolate. Nessuna certificazione derivata dal solo build o readiness.
2. Inventariare istanza, volumi, overlay Mongo auth C7 e materiali crittografici. Conservare backup C1 verificato e immagini precedenti con commit/image-id. Non rigenerare chiavi all'aggiornamento.
3. Preparare artefatti del commit verificato. Verificare SHA256 dell'archivio sul server prima di `docker load`. Impostare AUTIFY_API_IMAGE/AUTIFY_ADMIN_IMAGE ai tag verificati e confrontare image-id con il manifest.
4. Usare base+`docker-compose.release.yml` e, se attivo, anche `docker-compose.mongo-auth.yml`; deploy con `--no-build --pull never`, per usare gli artefatti verificati. Il base contiene ancora build per sviluppo; il flag impedisce build impliciti. Mantenere lo stesso progetto Compose e gli stessi volumi. Comandi destinati alla fase autorizzata di rilascio, non eseguiti ora:

   ```powershell
   docker compose -f docker-compose.yml -f docker-compose.release.yml -f docker-compose.mongo-auth.yml up -d --no-build --pull never
   ```

5. Controllare readiness, login/RBAC, un elenco, una valutazione, PDF, licenza e backup isolato. Frontend/backend devono essere aggiornati insieme.
6. Rollback applicativo: ricaricare immagini precedenti verificate, ripristinare i tag/ID precedenti negli override e riavviare con gli stessi flag. Non cancellare volumi e non disattivare auth Mongo per risolvere un errore di rollout. Un rollback delle immagini non è un rollback dei dati.
7. Se il codice precedente non legge snapshot/segreti/schema correnti, il rollback richiede un piano dati compatibile, ambiente isolato e restore C1 in manutenzione. Non eseguire un restore cieco sul cliente; conservare il backup dello stato prima del rollback e le chiavi necessarie.

Nessuna nuova collection. Nuovi indici creati soltanto al futuro avvio dell'app. Stato e ripresa in `file.md` checkpoint15, casi C8 in `test.md`. C7 operativo e verifiche C8 restano aperti fino alla relativa esecuzione.
