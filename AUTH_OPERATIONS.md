# Identità e autorizzazioni C2 — 4.0.4

Implementazione locale del 30 ottobre 2026, da verificare tramite i casi C2 in test.md. Nessuna distribuzione effettuata.

## Primo avvio e aggiornamenti

Su database vuoto configurare `INITIAL_ADMIN_PASSWORD` con una password casuale di almeno 12 caratteri e massimo 72 byte UTF-8. Compose passa la variabile al backend; senza valore valido l'avvio si interrompe, senza creare credenziali prevedibili. Il nome iniziale resta `admin`. Custodire la password fuori da Git e cambiarla al primo accesso. La variabile non resetta account di un database già popolato; dopo bootstrap può essere rimossa dalla configurazione dell'installazione conservata in sicurezza. Non modificata la `.env` locale durante i fix.

Gli account già esistenti conservano hash e ruoli. Il vecchio account `admin` ancora protetto dalla password storica `admin` viene marcato per cambio obbligatorio all'avvio e al login; il controllo al login copre anche archivi ripristinati successivamente. Questo non sostituisce la password e non risolve l'eventuale precedente esposizione di quella credenziale: va sostituita dall'operatore. Il recupero di una password dimenticata richiede un altro admin o una procedura amministrativa dedicata; INITIAL_ADMIN_PASSWORD non è un bypass.

## Cambio password e sessioni

Il login restituisce il token e `must_change_password`. Se il flag è attivo, il server rifiuta tutte le altre API protette con 403 e codice `password_change_required`; la sola eccezione è `POST /api/admin/auth/change-password`. Login e health restano pubblici. Il frontend torna al login anche al refresh o quando riceve tale codice; il controllo del localStorage non è un controllo di sicurezza.

Il cambio personale accetta soltanto `current_password`, `new_password`, `confirm_password`, con token dell'interessato. La nuova password deve essere diversa, almeno 12 caratteri, massimo 72 byte, confermata e non composta da soli spazi. La scrittura confronta hash e versione sessione correnti per evitare sovrascritture concorrenti; al successo revoca tutte le sessioni e richiede un nuovo login. Non viene emesso un token sostitutivo. In caso di risposta persa dopo il salvataggio, ripetere il login con la nuova password; non dedurre che il salvataggio sia fallito dal solo errore di rete.

JWT senza i claim obbligatori `sub`, `exp`, `iat`, `token_version` vengono rifiutati: eventuali sessioni storiche senza versione richiedono nuovo login. Ruolo e abilitazione IA sono letti dall'account corrente nel database. Modificare il proprio account da gestione utenze riporta al login quando la modifica revoca il token.

Il cambio personale funziona anche con licenza scaduta e in manutenzione C1; in manutenzione viene serializzato come le altre richieste consentite. Gli account ripristinati con cambio obbligatorio devono completarlo prima di poter usare nuovamente le API backup. La policy precedente di lunghezza per creazione/reset amministrativo di altri account resta invariata: la soglia nuova riguarda bootstrap e cambio personale, non una migrazione forzata di tutte le password.

## Matrice sintetica delle autorizzazioni

| Funzione | Admin | Viewer |
|---|---|---|
| Cambio password personale | Consentito con password corrente | Consentito con password corrente |
| Gestione utenze/impostazioni | Consentita dopo eventuale cambio obbligatorio | Vietata |
| GET settings/ai | Configurazione amministrativa mascherata | 403 |
| GET ai/capabilities | Metadati minimi | Metadati minimi e can_analyze, senza prompt/URL/header/hint chiavi |
| Generazione IA | Richiede flag IA personale | Richiede flag personale e globale, nessun override prompt |
| Lettura job/notifiche | Propri | Propri, anche senza permesso di nuova generazione |
| POST notifica/read e read-all | Solo proprie | Solo proprie |
| Scritture dati educativi | Regole esistenti | Vietate, salvo eccezioni esplicite preesistenti |

Il frontend viewer usa capabilities e omette system_prompt dalle richieste. Il server usa il prompt configurato e rifiuta override viewer anche vuoti. GET settings per viewer non espone gemini_prompt. Le notifiche sono sempre filtrate per username autenticato; l'eccezione RBAC non autorizza percorsi generici sotto notifications.

Aggiornare frontend e backend insieme: il vecchio client tenta il cambio con PUT users e invia il prompt viewer, entrambi incompatibili con il nuovo percorso obbligatorio. Pianificare verifica completa e rilascio congiunto; nessuna garanzia end-to-end finché i casi in test.md non sono eseguiti.
