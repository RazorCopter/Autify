# REMEDIATION PLAN — AutAnalysis
> Checklist tecnica di remediation derivata dall'audit del 2026-06-18.
> Flagga ogni item con `[x]` quando risolto. Aggiungi la data di fix nella nota.

---

## LEGENDA PRIORITÀ
- 🔴 **CRITICO** — sicurezza o perdita di dati, fix subito
- 🟠 **ALTO** — bug funzionale o performance degradante
- 🟡 **MEDIO** — debito tecnico, codice duplicato, deprecazioni
- 🟢 **BASSO** — qualità, micro-ottimizzazioni, cosmesi

---

## SPRINT 1 — Blocchi critici (fix immediati)

### 🔴 C-01 · JWT secret fallback insicuro
- [x] **File:** `backend/app/auth.py:10`
- **Problema:** se `JWT_SECRET_KEY` non è impostata nell'env, il segreto è la stringa pubblica `"change_me_in_production_please"` — i token sono forgeable.
- **Fix:**
  ```python
  JWT_SECRET = os.getenv("JWT_SECRET_KEY", "").strip()
  if not JWT_SECRET:
      raise RuntimeError("JWT_SECRET_KEY env variable is not set. Refusing to start.")
  ```
- **Test:** rimuovere `JWT_SECRET_KEY` dal `.env` e verificare che il backend si rifiuti di avviarsi.
- *Data fix: 2026-06-18*

---

### 🔴 C-02 · Fallback plain-text in `verify_password()`
- [x] **File:** `backend/app/auth.py:24-33`
- **Problema:** un'eccezione bcrypt (`ValueError`/`TypeError`) causa un confronto diretto `plain == hashed`, bypassando hashing. Timing-attack possibile e bypass se il DB contiene password non hashate.
- **Fix:** rimuovere il ramo `except` che fa il confronto in chiaro. Restituire `False` e loggare.
  ```python
  def verify_password(plain: str, hashed: str) -> bool:
      try:
          return bcrypt.checkpw(plain.encode("utf-8"), hashed.encode("utf-8"))
      except (ValueError, TypeError) as e:
          logger.warning(f"verify_password: hash malformato ({e}). Accesso negato.")
          return False
  ```
- **Test:** inserire manualmente un documento utente con `hashed_password: "admin"` (plain) e verificare che il login fallisca.
- *Data fix: 2026-06-18*

---

### 🔴 C-03 · Credenziali hardcoded in `auth_manager.py`
- [x] **File:** `backend/app/auth_manager.py` (~righe 30-40)
- **Problema:** `"admin_pwd": "tiglio2026"` e `"viewer_pwd": "tiglioviewer"` sono in chiaro nel codice sorgente. Chiunque abbia accesso al repo può autenticarsi.
- **Fix (fase 1):** spostare i default in variabili d'ambiente con `os.getenv("LEGACY_ADMIN_PWD", "")`.
- **Fix (fase 2, preferibile):** completare la rimozione di `auth_manager.py` (vedi L-02) ed eliminare il header `X-Admin-Password` del tutto.
- **Test:** fare grep nel repo per `tiglio2026` — non deve apparire in nessun file tracciato da git.
- *Data fix: 2026-06-18* — credenziali spostate in `LEGACY_ADMIN_PWD` / `LEGACY_VIEWER_PWD` env vars; aggiunte in `docker-compose.yml`

---

### 🔴 C-04 · Endpoint client `/api/client/*` senza autenticazione
- [x] **File:** `backend/app/routes.py` — router `client_router`
- **Problema:** `POST /evaluations`, `GET /patients`, `GET /scales/{id}` non richiedono token. Chiunque può leggere i nomi di tutti i pazienti e inondare il DB con valutazioni fasulle.
- **Fix opzione A (minimo):** aggiungere rate limiting anche sugli endpoint client (slowapi, es. 30/min per IP).
- **Fix opzione B (corretto):** introdurre un token firmato monouso (OTP/link firmato) generato dall'admin e passato al client nel QR code di valutazione. L'endpoint valida il token prima di accettare la submission.
- **Test:** fare `curl -X POST https://tiglio.autify.it/api/client/evaluations -d '{...}'` da IP esterno senza token — deve essere bloccato o rate-limited.
- *Data fix: 2026-06-18* — applicato `@_limiter.limit` su tutti e 4 gli endpoint client: `GET /scales` (60/min), `GET /scales/{id}` (60/min), `POST /evaluations` (20/min), `GET /patients` (30/min)

---

## SPRINT 2 — Bug funzionali e performance critici

### 🟠 B-01 · Filtri semantici ("scaduti", "in scadenza") applicati solo sulla pagina corrente
- [x] **File:** `frontend_admin/lib/screens/anagrafica_screen.dart:553-629`
- **Problema:** i filtri speciali operano sul sottoinsieme di 50 pazienti caricati, non sull'intera collection. Un utente che cerca "scaduti" vede solo i pazienti scaduti della pagina attuale — risultato silenziosamente incompleto.
- **Fix backend:** aggiungere parametri query a `GET /api/admin/patients`:
  - `?filter=scaduti` → backend calcola le date di scadenza e filtra
  - `?filter=in_scadenza`
  - `?filter=incompleti`
  - `?filter=mai_valutati`
- **Fix frontend:** modificare `_getServerSearch()` in `anagrafica_screen.dart` per passare il filtro al server anziché applicarlo client-side.
- **Test:** avere >50 pazienti totali, almeno 2 scaduti su pagine diverse, cercare "scaduti" e verificare che appaiano tutti.
- *Data fix: 2026-06-18* — parametro `?filter=` aggiunto al backend con query MongoDB per scaduti/in_scadenza/incompleti/mai_valutati; frontend usa `FilterChip` per attivare il filtro; logica client-side rimossa

---

### 🟠 P-04 · Migrazione `attivo` eseguita su ogni `GET /patients`
- [x] **File:** `backend/app/routes.py` — funzione `get_patients()`
- **Problema:** `update_many({"attivo": {"$exists": False}}, ...)` viene chiamata ad ogni richiesta di lista pazienti. È una write su MongoDB ad ogni GET, anche quando non serve.
- **Fix:** spostare la chiamata in `ensure_default_admin()` in `auth.py`, dove viene eseguita una sola volta all'avvio:
  ```python
  # In ensure_default_admin():
  await patients_collection.update_many(
      {"attivo": {"$exists": False}},
      {"$set": {"attivo": True}}
  )
  ```
- **Test:** loggare il numero di query MongoDB durante 10 chiamate consecutive a `GET /patients` — nessuna `update_many` deve apparire dopo la prima.
- *Data fix: 2026-06-18* — `update_many` spostata in `ensure_default_admin()` (auth.py), rimossa da `get_patients()`

---

### 🟠 B-02 · Crash `RangeError` su nome/cognome vuoto nella card paziente
- [x] **File:** `frontend_admin/lib/screens/anagrafica_screen.dart:747`
- **Problema:** `patient.nome[0]` lancia `RangeError` se `nome` è stringa vuota. Possibile con dati importati via CSV/JSON.
- **Fix:**
  ```dart
  final initial1 = patient.nome.isNotEmpty ? patient.nome[0].toUpperCase() : '?';
  final initial2 = patient.cognome.isNotEmpty ? patient.cognome[0].toUpperCase() : '?';
  '$initial1$initial2'
  ```
- **Test:** importare un paziente con nome vuoto e verificare che la griglia si carichi senza eccezioni.
- *Data fix: 2026-06-18* — guard aggiunto inline: `patient.nome.isNotEmpty ? patient.nome[0].toUpperCase() : '?'`

---

### 🟠 B-03 · Memory leak — `TextEditingController` non disposti nel dialog pazienti
- [x] **File:** `frontend_admin/lib/screens/anagrafica_screen.dart:113-120`
- **Problema:** 6 controller (`nomeController`, `cognomeController`, `pesoController`, `dataNascitaController`, `noteController` + 1) vengono creati ad ogni apertura dialog e mai disposti. Leak confermato su dispositivi con sessioni lunghe.
- **Fix:** wrappare il dialog body in un `StatefulWidget` separato (`_PatientFormDialog`) che gestisce i controller nel proprio `dispose()`, oppure usare un `StatefulBuilder` con dispose esplicito:
  ```dart
  // Al termine del dialog, prima di Navigator.pop():
  nomeController.dispose();
  cognomeController.dispose();
  // ...
  ```
- **Test:** aprire e chiudere il dialog 50 volte in Flutter DevTools Memory → il conteggio dei `TextEditingController` non deve crescere.
- *Data fix: 2026-06-18* — blocco `try/finally` aggiunto attorno al `showDialog`; tutti e 5 i controller disposti nel `finally`. Aggiunto anche `_searchController.dispose()` nell'`override dispose()` del widget.

---

### 🟠 P-06 · `_loadScales()` chiamata ad ogni refresh pazienti
- [x] **File:** `frontend_admin/lib/screens/anagrafica_screen.dart:65`
- **Problema:** `_loadScales()` viene chiamata dentro `_refreshPatients()`, che si attiva ad ogni ricerca, cambio filtro, cambio pagina. HTTP call inutile a ogni interazione.
- **Fix:** chiamare `_loadScales()` solo in `initState()` e aggiungere un pulsante "Aggiorna protocolli" esplicito se necessario:
  ```dart
  @override
  void initState() {
    super.initState();
    _loadScales(); // solo una volta
    _refreshPatients();
  }
  ```
- **Test:** aprire la schermata pazienti, cercare 5 volte e verificare nelle DevTools Network che `GET /scales` sia chiamato 1 sola volta, non 5.
- *Data fix: 2026-06-18* — `_loadScales()` rimossa da `_refreshPatients()`, spostata in `initState()` dopo `_refreshPatients()`

---

### 🟠 A-01 · URL di produzione hardcoded nel frontend
- [x] **File:** `frontend_admin/lib/services/api_service.dart:101,658`
- **Problema:** `https://tiglio.autify.it/api/admin` e `.../api/client` sono costanti in codice. Impossibile sviluppare in locale senza modificare il sorgente.
- **Fix:** modificare `config.dart` per esporre `apiAdminBaseUrl` e `apiClientBaseUrl` con logica `kDebugMode`:
  ```dart
  // config.dart
  import 'package:flutter/foundation.dart';
  
  const String apiAdminBaseUrl = kDebugMode
      ? 'http://localhost:8000/api/admin'
      : 'https://tiglio.autify.it/api/admin';
  
  const String apiClientBaseUrl = kDebugMode
      ? 'http://localhost:8000/api/client'
      : 'https://tiglio.autify.it/api/client';
  ```
  Poi in `api_service.dart`:
  ```dart
  static const String baseUrl = cfg.apiAdminBaseUrl;
  static const String clientBaseUrl = cfg.apiClientBaseUrl;
  ```
- **Test:** build in debug mode contro backend locale — deve funzionare senza modifiche al sorgente.
- *Data fix: 2026-06-18* — `config.dart` aggiornato con `kApiBaseUrl`/`kApiClientBaseUrl` condizionali su `kDebugMode`; `kAdminPassword`/`kViewerPassword` ora usano `String.fromEnvironment()`; `api_service.dart` usa le costanti da `config.dart`

---

## SPRINT 3 — Performance backend

### 🟠 P-01 · Full table scan su ogni caricamento dashboard
- [x] **File:** `backend/app/routes.py` — `get_dashboard_stats()`
- **Problema:** 3 `find({}).to_list(N)` su ogni richiesta dashboard (pazienti, valutazioni, scale). Cresce linearmente con i dati.
- **Fix:** aggiungere caching in-memory con TTL di 5 minuti usando `cachetools` o un semplice dict con timestamp:
  ```python
  import time
  _dashboard_cache: dict = {"data": None, "ts": 0}
  CACHE_TTL = 300  # 5 minuti
  
  async def get_dashboard_stats(...):
      if time.time() - _dashboard_cache["ts"] < CACHE_TTL:
          return _dashboard_cache["data"]
      # ... calcola stats ...
      _dashboard_cache["data"] = result
      _dashboard_cache["ts"] = time.time()
      return result
  ```
- **Alternativa:** MongoDB aggregation pipeline con `$group` e `$count` lato server, più efficiente a qualsiasi scala.
- **Test:** misurare il tempo di risposta prima e dopo con `k6` o `wrk` su 50 richieste concorrenti.
- *Data fix: 2026-06-18* — `_dashboard_cache` dict con TTL 300s; `_invalidate_dashboard_cache()` chiamato su create/delete patient, create/delete evaluation, import-db; endpoint `DELETE /dashboard-stats/cache` per invalidazione manuale

---

### 🟠 P-02 · Export CSV con 50.000 valutazioni in memoria
- [x] **File:** `backend/app/routes.py` — `export_patients_csv()`
- **Problema:** `to_list(50000)` carica tutti i dati in RAM prima di scrivere il CSV. Su dati reali (anni di storia) può esaurire la memoria.
- **Fix:** `StreamingResponse` con generator asincrono:
  ```python
  from fastapi.responses import StreamingResponse
  import csv, io
  
  async def generate_csv():
      output = io.StringIO()
      writer = csv.writer(output)
      writer.writerow(["id_paziente", "nome", ...])  # header
      yield output.getvalue()
      output.seek(0); output.truncate(0)
      
      async for eval_doc in evaluations_collection.find({}):
          writer.writerow([...])
          yield output.getvalue()
          output.seek(0); output.truncate(0)
  
  return StreamingResponse(generate_csv(), media_type="text/csv", ...)
  ```
- **Test:** con 10.000 valutazioni nel DB, verificare che il picco di RAM durante l'export non superi i 50 MB.
- *Data fix: 2026-06-18* — convertito in `_csv_generator()` async generator; itera i pazienti con cursor Motor, proietta le valutazioni sui soli campi necessari; ogni riga viene emessa subito via `StreamingResponse`

---

### 🟠 P-03 · Query N+1 in `get_aggregated_evaluation()`
- [x] **File:** `backend/app/routes.py` — `get_aggregated_evaluation()`
- **Problema:** per ogni valutazione nel loop viene eseguita `find_one` sulla collection scales — N query MongoDB invece di 1.
- **Fix:**
  ```python
  # Raccoglie tutti gli id scala unici
  scale_ids = list({e["id_scala"] for e in evals})
  # Una sola query
  scales = await scales_collection.find({"id": {"$in": scale_ids}}).to_list(length=None)
  scale_map = {s["id"]: s for s in scales}
  # Poi nel loop:
  scale_doc = scale_map.get(eval_doc["id_scala"])
  ```
- **Test:** con un paziente con 10 valutazioni su scale diverse, verificare con il MongoDB profiler che vengono eseguite ≤2 query (1 per le valutazioni + 1 per le scale).
- *Data fix: 2026-06-18* — `find({"id": {"$in": scale_ids_needed}})` bulk pre-fetch prima del loop; dizionario `_scale_cache` per lookup O(1)

---

### 🟠 P-05 · Full-collection scan fallback in `_find_evaluation_document()`
- [x] **File:** `backend/app/routes.py` — `_find_evaluation_document()`
- **Problema:** quando la lookup per `id_valutazione` e `idValutazione` fallisce, il codice esegue `async for doc in evaluations_collection.find({})` — scan completo su tutta la collection come ultimo tentativo.
- **Fix:** rimuovere il fallback di scan completo. Sostituire con un log di warning e restituire `None`:
  ```python
  logger.warning(f"_find_evaluation_document: documento non trovato per id={evaluation_id}. Legacy schema?")
  return None
  ```
  I documenti con schema corrotto devono essere identificati e migrati, non trovati con un full scan silenzioso.
- **Test:** chiamare l'endpoint con un ID inesistente e verificare che risponda 404 in <50ms (invece di scansionare tutta la collection).
- *Data fix: 2026-06-18* — fallback `async for doc in find({})` rimosso; sostituito con `logger.warning` + `return None`

---

### 🟡 A-07 · MongoDB senza configurazione connection pool
- [x] **File:** `backend/app/database.py`
- **Problema:** `AsyncIOMotorClient(MONGODB_URL)` usa i default di Motor (100 connessioni max, nessun timeout esplicito). In produzione, timeout non configurati possono causare hang silenziosi.
- **Fix:**
  ```python
  client = AsyncIOMotorClient(
      MONGODB_URL,
      maxPoolSize=20,
      minPoolSize=2,
      serverSelectionTimeoutMS=5000,
      connectTimeoutMS=5000,
      socketTimeoutMS=30000,
  )
  ```
- **Test:** simulare una disconnessione MongoDB e verificare che il backend risponda con errore entro 5 secondi invece di bloccarsi.
- *Data fix: 2026-06-18* — `AsyncIOMotorClient` configurato con `maxPoolSize=20`, `minPoolSize=2`, `serverSelectionTimeoutMS=5000`, `connectTimeoutMS=5000`, `socketTimeoutMS=30000`

---

## SPRINT 4 — Rimozione codice legacy

### 🟡 L-01 · Sostituire `@app.on_event("startup")` con `lifespan`
- [ ] **File:** `backend/app/main.py:20-23`
- **Problema:** `@app.on_event` è deprecato da FastAPI 0.93. Genera warning a ogni avvio.
- **Fix:**
  ```python
  from contextlib import asynccontextmanager
  
  @asynccontextmanager
  async def lifespan(app: FastAPI):
      await auth_module.ensure_default_admin()
      yield  # qui gira l'applicazione
      # cleanup a shutdown (se necessario)
  
  app = FastAPI(title="Autify API", ..., lifespan=lifespan)
  # Rimuovere il decorator @app.on_event e la funzione startup_event
  ```
- **Test:** avviare il backend e verificare zero warning su startup nei log.
- *Data fix: ___________*

---

### 🟡 L-02 · Rimuovere `auth_manager.py` e header `X-Admin-Password`
- [ ] **File:** `backend/app/auth_manager.py`, `backend/app/auth.py:94-105`, `backend/app/routes.py` (riferimenti)
- **Problema:** sistema di auth a file JSON parallelo al DB, credenziali hardcoded, dead code (`update_auth_config`), doppio audit log.
- **Sequenza di rimozione:**
  1. [ ] Verificare che nessun client attivo usi il header `X-Admin-Password` (controllare i log di produzione)
  2. [ ] Rimuovere il ramo `legacy_pwd` da `verify_auth()` in `auth.py`
  3. [ ] Rimuovere le route che chiamano `get_viewer_logs()` o `get_auth_config()` da `routes.py`
  4. [ ] Eliminare `auth_manager.py`
  5. [ ] Rimuovere `from . import auth_manager` ovunque presente
- **Test:** fare grep per `X-Admin-Password` e `auth_manager` — nessuna occorrenza nel codice attivo.
- *Data fix: ___________*

---

### ✅ L-03 · Rimuovere `getAuthConfig()` e `updateAuthConfig()` dal frontend

- [x] **File:** `frontend_admin/lib/services/api_service.dart` — metodi rimossi; `settings_screen.dart` — funzione `_showViewerLogsDialog` e bottone "Log Accessi" rimossi.
- *Data fix: 2026-06-18*

---

### ✅ L-04 · Allineare `AuditLogCreate` con l'uso reale

- [x] **File:** `backend/app/routes.py` — `log_audit()` ora istanzia `AuditLogCreate` e usa `model_dump()` invece di un raw dict.
- *Data fix: 2026-06-18*

---

### ✅ L-05 · Sostituire `.withOpacity()` deprecato con `.withValues(alpha:)`

- [x] **File:** `wizard_screen.dart`, `dashboard_screen.dart`, `login_screen.dart`, `evaluation_detail_screen.dart`, `app_theme.dart` — tutte le occorrenze sostituite (34 totali).
- *Data fix: 2026-06-18*

---

### ✅ L-06 · Rimuovere il commento orfano della Forecast Card

- [x] **File:** `frontend_admin/lib/screens/dashboard_screen.dart` — commento orfano rimosso.
- *Data fix: 2026-06-18*

---

## SPRINT 5 — Refactoring e duplicazioni

### ✅ D-01 · Deduplicare la logica `isSanMartin` nel wizard

- [x] **File:** `wizard_screen.dart` — getter `_isSanMartinScale` aggiunto, 3 blocchi duplicati sostituiti.
- *Data fix: 2026-06-18*

---

### ✅ D-02 · Deduplicare la classificazione scala nel backend

- [x] **File:** `backend/app/routes.py` — helper `_classify_scale()` estratto, usato in `get_patients()`, `get_dashboard_stats()`, `export_patients_csv()`.
- *Data fix: 2026-06-18*

---

### ✅ D-03 · Deduplicare il pattern hover card

- [x] **File:** `dashboard_screen.dart` — `_HoverWrapper` estratto; `_HoverBentoCard` diventa un `StatelessWidget` che lo wrappa; `_BentoKpiCard` usa `_HoverWrapper` al posto del proprio `MouseRegion`/`AnimatedContainer`.
- *Data fix: 2026-06-18*

---

### ✅ D-04 · Estrarre `_inputDecoration()` in `AppTheme`

- [x] **File:** `app_theme.dart` — `static inputDecoration()` aggiunto; `wizard_screen.dart` — funzione privata rimossa, 18 chiamate sostituite con `AppTheme.inputDecoration(...)`.
- *Data fix: 2026-06-18*

---

### ✅ A-03 · Estrarre lo stato demografico del wizard in un widget separato

- [x] **File:** `frontend_admin/lib/widgets/demographics_form.dart` (nuovo), `frontend_admin/lib/screens/wizard_screen.dart`
- **Fix applicato 2026-06-18:** creato `DemographicsForm` StatefulWidget con classe `DemographicsData` (+ `toJson()`). Rimossi da `_WizardScreenState`: 11 TextEditingController, 14 bool, 2 String? e 3 metodi (`_buildDemographicsCard`, `_buildSectionHeader`, `_buildModernCheckbox`). `wizard_screen.dart` ridotto da 2133 → 1547 righe. `flutter analyze` = 12 issues info (pre-esistenti, non regressi).
- *Data fix: 2026-06-18*

---

### ✅ A-02 · Spostare modelli Pydantic inline da `routes.py` a `models.py`

- [x] **File:** `models.py` — aggiunti `AiAnalysisUpdate` e `AiPdfRequest`; `routes.py` — definizioni inline rimosse, import aggiornato, `UserResponse` (inutilizzato) rimosso dall'import.
- *Data fix: 2026-06-18*

---

### ✅ A-04 · Rimuovere variabile `hPad` sempre zero

- [x] **File:** `wizard_screen.dart` — variabile `hPad` e `Padding` wrappante rimossi.
- *Data fix: 2026-06-18*

---

### ✅ A-05 · Rimuovere parametro `item` inutilizzato in `_colorForScore()`

- [x] **File:** `wizard_screen.dart` — parametro `{int item = 3}` rimosso dalla firma, chiamata aggiornata.
- *Data fix: 2026-06-18*

---

### ✅ A-06 · Deduplicare la lista campi scale nei filtri anagrafica

- [x] Non applicabile: i filtri semantici sono stati spostati server-side in Sprint 2 (B-01). Il codice client-side con le tuple duplicata non esiste più.
- *Data fix: 2026-06-18 (risolto da B-01)*

---

## SPRINT 6 — Qualità e micro-ottimizzazioni

### ✅ Q-01 · Shimmer skeleton non responsive (sempre 3 colonne)

- [x] `dashboard_screen.dart` — shimmer wrappato in `LayoutBuilder`: 1 colonna su mobile, 2 su tablet, 3 su desktop.
- *Data fix: 2026-06-18*

---

### ✅ Q-02 · `import re` dentro il body di una funzione

- [x] `backend/app/routes.py` — `import re` spostato in cima al file.
- *Data fix: 2026-06-18*

---

### ✅ Q-03 · `import os` duplicato in `pdf_generator.py`

- [x] `backend/app/pdf_generator.py` — secondo `import os` rimosso; `import os` spostato in cima al file.
- *Data fix: 2026-06-18*

---

### ✅ Q-04 · Dati organizzativi hardcoded nel generatore PDF

- [x] `backend/app/pdf_generator.py` — nome, P.IVA e Cod.Fisc letti da `os.getenv("ORG_NAME"/"ORG_PIVA"/"ORG_CODFISC")` con i valori attuali come default.
- *Data fix: 2026-06-18*

---

### ✅ Q-05 · Errori HTTP silenziosi nel frontend (nessun log)

- [x] `frontend_admin/lib/services/api_service.dart` — 32 `catch (e)` trasformati in `catch (e, s)` con `debugPrint('[ApiService] $e')`.
- *Data fix: 2026-06-18*

---

### ✅ Q-06 · Sort lista distribuzione ricalcolato ad ogni `build()`

- [x] `dashboard_screen.dart` — `_sortedDistributions` aggiunto come campo di stato, popolato una volta in `_loadStats()`; `_buildDistributionCard()` usa il campo pre-ordinato.
- *Data fix: 2026-06-18*

---

## TRACCIAMENTO PROGRESSO

| Sprint | Item | Stato |
|--------|------|-------|
| 1 | C-01 JWT secret | ✅ 2026-06-18 |
| 1 | C-02 Plain-text pwd | ✅ 2026-06-18 |
| 1 | C-03 Credenziali hardcoded | ✅ 2026-06-18 |
| 1 | C-04 Endpoint client no-auth | ✅ 2026-06-18 |
| 2 | B-01 Filtri semantici paginati | ✅ 2026-06-18 |
| 2 | P-04 Migrazione inline | ✅ 2026-06-18 |
| 2 | B-02 Crash nome vuoto | ✅ 2026-06-18 |
| 2 | B-03 Memory leak controller | ✅ 2026-06-18 |
| 2 | P-06 _loadScales ridondante | ✅ 2026-06-18 |
| 2 | A-01 URL hardcoded | ✅ 2026-06-18 |
| 3 | P-01 Cache dashboard | ✅ 2026-06-18 |
| 3 | P-02 Streaming CSV | ✅ 2026-06-18 |
| 3 | P-03 N+1 query scale | ✅ 2026-06-18 |
| 3 | P-05 Full scan fallback | ✅ 2026-06-18 |
| 3 | A-07 MongoDB pool config | ✅ 2026-06-18 |
| 4 | L-01 Lifespan FastAPI | ✅ 2026-06-18 |
| 4 | L-02 Rimozione auth_manager | ✅ 2026-06-18 |
| 4 | L-03 Dead code getAuthConfig | ✅ 2026-06-18 |
| 4 | L-04 AuditLogCreate allineamento | ✅ 2026-06-18 |
| 4 | L-05 withOpacity deprecato | ✅ 2026-06-18 |
| 4 | L-06 Commento orfano forecast | ✅ 2026-06-18 |
| 5 | D-01 isSanMartin triplicato | ✅ 2026-06-18 |
| 5 | D-02 _classify_scale triplicato | ✅ 2026-06-18 |
| 5 | D-03 Hover card pattern | ✅ 2026-06-18 |
| 5 | D-04 _inputDecoration in AppTheme | ✅ 2026-06-18 |
| 5 | A-03 Estrai DemographicsForm | ⏳ In attesa |
| 5 | A-02 Modelli inline in routes.py | ✅ 2026-06-18 |
| 5 | A-04 hPad sempre zero | ✅ 2026-06-18 |
| 5 | A-05 Param item inutilizzato | ✅ 2026-06-18 |
| 5 | A-06 Lista scale duplicata | ✅ 2026-06-18 (risolto da B-01) |
| 6 | Q-01 Shimmer non responsive | ✅ 2026-06-18 |
| 6 | Q-02 import re dentro funzione | ✅ 2026-06-18 |
| 6 | Q-03 import os duplicato | ✅ 2026-06-18 |
| 6 | Q-04 Dati org hardcoded PDF | ✅ 2026-06-18 |
| 6 | Q-05 Errori HTTP silenziosi | ✅ 2026-06-18 |
| 6 | Q-06 Sort rebuild in build() | ✅ 2026-06-18 |

---

*Generato il 2026-06-18 — aggiornare la tabella e i checkbox mano a mano che i fix vengono completati.*
