import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_admin/screens/wizard_screen.dart';
import 'package:frontend_admin/theme/app_theme.dart';

// Mock HttpOverrides per simulare le chiamate API di ApiService per la scala e il salvataggio
class MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return MockHttpClient();
  }
}

class MockHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  MaxConnectionsPerHost? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> get(String host, int port, String path) {
    return Future.value(MockHttpClientRequest('GET', path));
  }

  @override
  Future<HttpClientRequest> post(String host, int port, String path) {
    return Future.value(MockHttpClientRequest('POST', path));
  }

  @override
  Future<HttpClientRequest> put(String host, int port, String path) {
    return Future.value(MockHttpClientRequest('PUT', path));
  }

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) {
    return Future.value(MockHttpClientRequest('DELETE', path));
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => get(url.host, url.port, url.path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => post(url.host, url.port, url.path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => put(url.host, url.port, url.path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => delete(url.host, url.port, url.path);

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) =>
      Future.value(MockHttpClientRequest(method, path));
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => open(method, url.host, url.port, url.path);

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) {}
  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) {}
  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) {}
  @override
  set findProxy(String Function(Uri url)? f) {}
  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) {}
  @override
  set authenticateProxy(Future<bool> Function(String host, int port, String scheme, String? realm)? f) {}
  @override
  void close({bool force = false}) {}
  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri url, String? proxyHost, int? proxyPort)? f) {}
  @override
  set keyLog(void Function(String line)? callback) {}
}

class MockHttpClientRequest implements HttpClientRequest {
  final String method;
  final String path;
  final MockHttpClientResponse _response;

  MockHttpClientRequest(this.method, this.path) : _response = MockHttpClientResponse(method, path);

  @override
  Encoding get encoding => utf8;
  @override
  set encoding(Encoding _encoding) {}
  @override
  HttpHeaders get headers => MockHttpHeaders();
  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) => Future.value();
  @override
  Future<HttpClientResponse> close() => Future.value(_response);
  @override
  void write(Object? obj) {}
  @override
  void writeAll(Iterable objects, [String separator = ""]) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? obj = ""]) {}
  @override
  bool get bufferOutput => true;
  @override
  set bufferOutput(bool value) {}
  @override
  int get contentLength => 0;
  @override
  set contentLength(int value) {}
  @override
  bool get persistentConnection => true;
  @override
  set persistentConnection(bool value) {}
  @override
  Future<HttpClientResponse> get done => Future.value(_response);
  @override
  void destroy() {}
  @override
  set connectionKeepAliveDelay(Duration value) {}
}

class MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  final String method;
  final String path;
  final String _body;

  MockHttpClientResponse(this.method, this.path) : _body = _getMockResponseBody(method, path);

  static String _getMockResponseBody(String method, String path) {
    if (path.contains('/scales/scale-test-1')) {
      return jsonEncode({
        'id': 'scale-test-1',
        'nome': 'Scala Funzionale di Test',
        'descrizione': 'Una scala di test clinico',
        'sezioni': [
          {
            'titolo_sezione': 'Autonomia Personale',
            'domande': [
              {
                'id_domanda': 'domanda-1',
                'codice': 'AP1',
                'testo_domanda': 'Il soggetto è in grado di mangiare autonomamente?',
                'opzioni': [
                  {'testo_risposta': 'Completamente autonomo', 'punteggio': 4},
                  {'testo_risposta': 'Richiede supervisione', 'punteggio': 3},
                  {'testo_risposta': 'Necessita di aiuto parziale', 'punteggio': 2},
                  {'testo_risposta': 'Totalmente dipendente', 'punteggio': 1}
                ],
                'note': 'Valutare il comportamento nell\'ultimo mese.'
              },
              {
                'id_domanda': 'domanda-2',
                'codice': 'AP2',
                'testo_domanda': 'Il soggetto si veste in modo autonomo?',
                'opzioni': [
                  {'testo_risposta': 'Sì, senza alcuna difficoltà', 'punteggio': 4},
                  {'testo_risposta': 'Lievemente rallentato', 'punteggio': 3},
                  {'testo_risposta': 'Necessita di aiuto per allacciare scarpe/bottoni', 'punteggio': 2},
                  {'testo_risposta': 'Completamente assistito', 'punteggio': 1}
                ]
              }
            ]
          }
        ]
      });
    } else if (path.contains('/evaluations')) {
      return jsonEncode({'status': 'created'});
    }
    return '{}';
  }

  @override
  int get statusCode {
    if (path.contains('/evaluations') && method == 'POST') {
      return 201; // Created
    }
    return 200; // OK
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([utf8.encode(_body)]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  int get contentLength => utf8.encode(_body).length;
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  List<Redirect> get redirects => [];
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => true;
  @override
  String get reasonPhrase => 'OK';
  @override
  HttpHeaders get headers => MockHttpHeaders();
  @override
  Future<Socket> detachSocket() => throw UnimplementedError();
  @override
  List<Cookie> get cookies => [];
}

class MockHttpHeaders implements HttpHeaders {
  @override
  List<String>? operator [](String name) => [];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void remove(String name, Object value) {}
  @override
  void removeAll(String name) {}
  @override
  void clear() {}
  @override
  void forEach(void Function(String name, List<String> values) action) {}
  @override
  void noFolding(String name) {}
  @override
  set date(DateTime? _date) {}
  @override
  DateTime? get date => null;
  @override
  set expires(DateTime? _expires) {}
  @override
  DateTime? get expires => null;
  @override
  set ifModifiedSince(DateTime? _ifModifiedSince) {}
  @override
  DateTime? get ifModifiedSince => null;
  @override
  set host(String? _host) {}
  @override
  String? get host => null;
  @override
  set port(int? _port) {}
  @override
  int? get port => null;
  @override
  set contentType(ContentType? _contentType) {}
  @override
  ContentType? get contentType => null;
  @override
  set contentLength(int _contentLength) {}
  @override
  int get contentLength => 0;
  @override
  set chunkedTransferEncoding(bool _chunkedTransferEncoding) {}
  @override
  bool get chunkedTransferEncoding => false;
  @override
  set persistentConnection(bool _persistentConnection) {}
  @override
  bool get persistentConnection => true;
}

void main() {
  setUpAll(() {
    HttpOverrides.global = MockHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  Widget createTestWidget() {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: AppTheme.primaryColor,
      ),
      home: const WizardScreen(
        patientId: 'paziente-1',
        scaleId: 'scale-test-1',
      ),
    );
  }

  group('Flusso di Compilazione Valutazione Clinica (Wizard) - Widget Test', () {
    testWidgets('Flusso completo: dati preliminari, compilazione domande con validazione navigazione e salvataggio', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle(); // Attende il caricamento iniziale dei dettagli della scala

      // ─── FASE 1: SCHEDA DATI PRELIMINARI ───
      // Verifica il rendering della scheda preliminare
      expect(find.text('Dati Valutazione'), findsOneWidget);
      expect(find.text('Compila i dati generali prima di iniziare'), findsOneWidget);

      // Trova i campi di input
      final operatoreField = find.widgetWithLabel(TextField, 'Nome Operatore');
      final intervistatoField = find.widgetWithLabel(TextField, 'Nome Intervistata/o');
      expect(operatoreField, findsOneWidget);
      expect(intervistatoField, findsOneWidget);

      // Inserisce i dati
      await tester.enterText(operatoreField, 'Dott. Rossi');
      await tester.enterText(intervistatoField, 'Mamma del paziente');
      await tester.pumpAndSettle();

      // Clicca su "Inizia Compilazione"
      final startBtn = find.widgetWithText(FilledButton, 'Inizia Compilazione');
      expect(startBtn, findsOneWidget);
      await tester.tap(startBtn);
      await tester.pumpAndSettle(); // Passa alla prima domanda del wizard

      // ─── FASE 2: DOMANDA 1 ───
      // Verifica che la prima domanda venga renderizzata correttamente
      expect(find.text('IL SOGGETTO È IN GRADO DI MANGIARE AUTONOMAMENTE?'), findsOneWidget);
      expect(find.text('AP1'), findsOneWidget); // Codice della domanda
      expect(find.text('Valutare il comportamento nell\'ultimo mese.'), findsOneWidget); // Nota informativa della domanda
      expect(find.text('1 / 2'), findsOneWidget); // Contatore domande

      // Verifica le opzioni a schermo
      expect(find.text('Completamente autonomo'), findsOneWidget);
      expect(find.text('Totalmente dipendente'), findsOneWidget);

      // Il bottone "Avanti" dovrebbe essere disabilitato (o non cliccabile se non viene fornito il punteggio)
      // Nella UI, il bottone è abilitato solo se `hasAnswered` (cioè `_answers.containsKey(_currentKey)`)
      // Proviamo a cliccare su "Avanti" prima di selezionare un'opzione e verifichiamo che non cambi pagina
      final nextBtn = find.widgetWithText(FilledButton, 'Avanti');
      expect(nextBtn, findsOneWidget);
      
      // Il pulsante deve avere onPressed = null, quindi non abilitato. Nel Widget Test possiamo verificarlo:
      final nextBtnWidget = tester.widget<FilledButton>(nextBtn);
      expect(nextBtnWidget.enabled, isFalse);

      // Seleziona un'opzione (es. "Completamente autonomo", che assegna punteggio 4)
      final option1 = find.text('Completamente autonomo');
      await tester.tap(option1);
      await tester.pumpAndSettle();

      // Ora il pulsante "Avanti" dovrebbe essere abilitato
      final nextBtnWidgetEnabled = tester.widget<FilledButton>(nextBtn);
      expect(nextBtnWidgetEnabled.enabled, isTrue);

      // Clicca su "Avanti" per passare alla seconda domanda
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      // ─── FASE 3: DOMANDA 2 (ULTIMA DOMANDA) ───
      // Verifica il caricamento della seconda domanda
      expect(find.text('IL SOGGETTO SI VESTE IN MODO AUTONOMO?'), findsOneWidget);
      expect(find.text('AP2'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);

      // Trova il pulsante che ora dovrebbe mostrare "Salva Valutazione" al posto di "Avanti"
      final saveValBtn = find.widgetWithText(FilledButton, 'Salva Valutazione');
      expect(saveValBtn, findsOneWidget);
      
      // Il pulsante deve essere inizialmente disabilitato
      final saveBtnWidget = tester.widget<FilledButton>(saveValBtn);
      expect(saveBtnWidget.enabled, isFalse);

      // Seleziona l'opzione "Sì, senza alcuna difficoltà" (punteggio 4)
      final option2 = find.text('Sì, senza alcuna difficoltà');
      await tester.tap(option2);
      await tester.pumpAndSettle();

      // Ora il pulsante "Salva Valutazione" dovrebbe essere abilitato
      final saveBtnWidgetEnabled = tester.widget<FilledButton>(saveValBtn);
      expect(saveBtnWidgetEnabled.enabled, isTrue);

      // Aggiunge una nota alla domanda per verificare la sezione note opzionale
      final addNoteToggle = find.text('📝  Aggiungi nota (opzionale)');
      expect(addNoteToggle, findsOneWidget);
      await tester.tap(addNoteToggle);
      await tester.pumpAndSettle(); // Espande il campo di testo per la nota

      final noteField = find.widgetWithLabel(TextField, 'Nota (opzionale)'); // Controlliamo l'hint text o input
      // Nel codice del widget la nota usa una TextField con:
      // label o hintText: 'Es. "Oggi era molto collaborativo, ha risposto con calma..."'
      final textFieldNote = find.byType(TextField).last;
      await tester.enterText(textFieldNote, 'Nota clinica: esecuzione rapida.');
      await tester.pumpAndSettle();

      // Clicca su "Salva Valutazione"
      await tester.tap(saveValBtn);
      await tester.pumpAndSettle(); // Mostra il dialogo di successo del salvataggio

      // ─── FASE 4: DIALOGO DI SUCCESSO ───
      expect(find.text('Valutazione Salvata'), findsOneWidget);
      expect(find.text('I dati sono stati registrati correttamente nel sistema.'), findsOneWidget);

      // Clicca su "Torna alla Home" per uscire dal wizard
      final homeBtn = find.widgetWithText(FilledButton, 'Torna alla Home');
      expect(homeBtn, findsOneWidget);
      await tester.tap(homeBtn);
      await tester.pumpAndSettle();
    });
  });
}
