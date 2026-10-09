# Autify Dashboard 4.0 — Redesign

## Stato

La Dashboard 4.0 coesiste con la dashboard classica ed è attivabile dalle Impostazioni. La dashboard classica resta il valore predefinito.

## Architettura frontend

Il punto di selezione è `frontend_admin/lib/screens/dashboard_screen.dart`:

- toggle OFF: `LegacyDashboardScreen`;
- toggle ON: `DashboardV4Screen`.

Le due implementazioni usano lo stesso endpoint `GET /dashboard-stats` e la stessa callback di navigazione. Non sono stati modificati database, modelli backend o contratti API.

La preferenza è gestita da `AppSettings` e `SettingsNotifier`, già basati su Provider e SharedPreferences.

Chiave persistente:

```text
autify_dashboard_v4_enabled
```

Default: `false`.

Il logout e la gestione HTTP 401 rimuovono esclusivamente le chiavi di autenticazione, preservando le preferenze locali.

## Componenti introdotti

- `DashboardScreen`: selettore centralizzato;
- `LegacyDashboardScreen`: implementazione classica preservata;
- `DashboardV4Screen`: dashboard premium;
- `DashboardAuroraBackground`;
- `DashboardSurfaceCard`;
- `DashboardKpiGrid` e `DashboardKpiCard`;
- compliance strip interattiva;
- donut di copertura documentale;
- distribuzione documentazione;
- Alert Center scrollabile;
- grafici socio-demografici;
- sidebar premium espansa/compatta, limitata alla Dashboard 4.0.


### Asset Glassmorphic Premium (Dashboard 4.0)

I 9 asset grafici ad alta risoluzione in `frontend_admin/assets/images/` sono centralizzati in `PremiumDashboardAssets` (`frontend_admin/lib/theme/premium_dashboard_assets.dart`) e integrati con superfici modulari scalabili (`BoxFit.cover`, bordi curvi anti-aliased e fallback protetti):

1. `01_sidebar_background.png`: barra laterale desktop (`PremiumSidebar`);
2. `02_main_canvas_background.png`: sfondo canvas operativo (`DashboardAuroraBackground`);
3. `03_card_active_users.png`: KPI Utenze Attive (`DashboardKpiCard`);
4. `04_card_active_evaluations.png`: KPI Valutazioni Attive (`DashboardKpiCard`);
5. `05_card_missing_scales.png`: KPI Scale Mancanti (`DashboardKpiCard`);
6. `06_status_summary_bar.png`: barra stato e conformità (`PremiumSummaryBar`);
7. `07_card_document_coverage.png`: card copertura documentale (`PremiumCoverageCard`);
8. `08_card_urgent_alert_center.png`: card centro alert prioritari (`PremiumAlertCard`);
9. `09_card_socio_demographic.png`: card profilo socio-demografico (`PremiumSocioDemoCard`).

## Design tokens

I token sono isolati in `frontend_admin/lib/widgets/dashboard_components.dart` e non modificano il tema globale della dashboard classica.

Palette principale:

- Deep Navy `#101B3C`;
- Midnight Blue `#142653`;
- Primary Blue `#356DFF`;
- Electric Indigo `#635BFF`;
- Aurora Violet `#9370FF`;
- Ice Cyan `#77E4F2`;
- Success `#20B67A`;
- Warning `#F5A623`;
- Critical `#F05262`.

Sono centralizzati anche raggi, gap, ombre e durata delle interazioni.

## Semantica dei dati

La UI usa il vocabolario educativo di Autify:

- utente;
- valutazione;
- scala di valutazione;
- priorità operativa;
- copertura documentale.

Le chiavi backend legacy `trend_somministrazioni` e `forecast_somministrazioni` non sono mostrate all’utente nella composizione corrente. Non vengono generati trend fittizi.

KPI premium:

1. Utenze attive;
2. Valutazioni attive;
3. Scale mancanti.

La card inventata “Media funzionale” è stata rimossa.

## Responsive

- meno di 600 px: KPI e sezioni impilate;
- da 600 px: KPI su due colonne e pannelli ridistribuiti;
- da 1100 px: tre KPI affiancate;
- da 1200 px: copertura e Alert Center affiancati;
- desktop: sidebar premium espansa o compatta;
- mobile: viene mantenuta la navigazione mobile esistente.

## Accessibilità

- tooltip per navigazione e azioni;
- Semantics per KPI, compliance strip e grafico di copertura;
- focus Material sui controlli;
- colori accompagnati da icone, testi e valori;
- target interattivi di almeno 44 px nelle azioni principali.

## Prestazioni

- nessuna nuova dipendenza;
- sfondo Aurora realizzato con gradienti Flutter;
- nessun blur sovrapposto sulle card;
- liste alert limitate in altezza e scrollabili;
- animazioni brevi e locali;
- design system isolato dalla UI classica.

## Test e verifiche

Verifiche eseguite il 9 ottobre 2026:

- formattazione Dart sui file modificati: completata;
- analisi statica mirata: 0 errori, 0 warning; restano info di deprecazione preesistenti relative a `dart:html`, `dart:js` e `Radio`;
- `flutter analyze --no-fatal-infos`: completato senza errori bloccanti;
- test della persistenza del toggle (`test/dashboard_settings_test.dart`): 3 test superati;
- widget test responsive della Dashboard 4.0 (`test/dashboard_screen_test.dart`): 7 test superati su VM Flutter (disaccoppiamento da `dart:html` via iniezione di `statsLoader`);
- test suite complessiva dashboard: 10 test superati su 10 (3 settings + 7 widget);
- backend test suite (`pytest -q`): 77 test superati, 0 fallimenti;
- build `flutter build web --release --no-pub`: completata con successo.

I test dashboard coprono nel dettaglio layout responsive (320px, 800px, 1440px), terminologia educativa conforme, gestione errori e retry, navigazione semantica degli alert e rendering delle metriche KPI.

## Problemi conosciuti

- Il progetto usa ancora `dart:html` in alcune schermate web preesistenti (wizard, anagrafica); l'architettura introdotta per la Dashboard 4.0 dimostra il pattern di disaccoppiamento riutilizzabile per il refactor graduale delle altre schermate.
- Il backend conserva chiavi tecniche legacy contenenti “somministrazioni”; non vengono esposte nella nuova UI.
- La ricerca nell’header non è presentata come ricerca globale perché non esiste un endpoint unico per utenti, documenti e scale.
- La validazione visiva finale richiede l’app avviata con backend e dati reali.

## Evoluzioni possibili

- estrazione di un repository dashboard tipizzato e indipendente da `dart:html`;
- ricerca federata con un servizio backend dedicato;
- screenshot golden test su viewport desktop e tablet;
- estensione opzionale della shell 4.0 alle altre sezioni;
- preferenze sincronizzate lato server, se verrà introdotta l’infrastruttura necessaria.
