import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_admin/screens/anagrafica_screen.dart';
import 'package:frontend_admin/theme/app_theme.dart';

// Mock HttpOverrides per simulare le chiamate API di ApiService
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

  // Campi inutilizzati richiesti dall'interfaccia
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
    if (path.contains('/patients')) {
      if (method == 'GET') {
        return jsonEncode([
          {
            'id': 'paziente-1',
            'nome': 'Mario',
            'cognome': 'Rossi',
            'altezza': 175,
            'peso': 70.5,
            'data_nascita': '1990-05-15',
            'sesso': 'M',
            'note': 'Paziente di test',
            'ultimo_pos_compilato': null,
            'ultimo_san_martin_compilato': null
          }
        ]);
      } else if (method == 'POST') {
        return jsonEncode({'status': 'created'});
      }
    } else if (path.contains('/scales')) {
      return jsonEncode([]);
    }
    return '[]';
  }

  @override
  int get statusCode {
    if (path.contains('/patients') && method == 'POST') {
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

  // Campi inutilizzati richiesti dall'interfaccia
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
    // Configura il mock HTTP a livello globale per il test run
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
      home: const Scaffold(
        body: AnagraficaScreen(),
      ),
    );
  }

  group('Flusso Creazione e Validazione Paziente - Widget Test', () {
    testWidgets('Validazione form fallisce con campi Nome e Cognome vuoti', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle(); // Attende il caricamento iniziale dei pazienti dalle API mockate

      // Verifica che la lista mostri il paziente mockato
      expect(find.text('Mario Rossi'), findsOneWidget);

      // Clicca sul pulsante "Aggiungi Paziente" per aprire il dialog
      final addBtn = find.widgetWithText(FilledButton, 'Aggiungi Paziente');
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle(); // Attende l'apertura del Dialog

      // Verifica che il dialog "Nuovo Paziente" sia aperto
      expect(find.text('Nuovo Paziente'), findsOneWidget);

      // Clicca direttamente su "Salva" senza compilare nome e cognome
      final saveBtn = find.widgetWithText(FilledButton, 'Salva');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verifica che vengano mostrati i messaggi di validazione "Campo richiesto" per Nome e Cognome
      expect(find.text('Campo richiesto'), findsNWidgets(2));
    });

    testWidgets('Creazione paziente con successo inserendo dati validi', (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Clicca su "Aggiungi Paziente"
      await tester.tap(find.widgetWithText(FilledButton, 'Aggiungi Paziente'));
      await tester.pumpAndSettle();

      // Compila Nome e Cognome
      final nomeField = find.widgetWithLabel(TextFormField, 'Nome');
      final cognomeField = find.widgetWithLabel(TextFormField, 'Cognome');

      await tester.enterText(nomeField, 'Giuseppe');
      await tester.enterText(cognomeField, 'Verdi');

      // Seleziona il sesso dal dropdown
      final sessoDropdown = find.widgetWithLabel(DropdownButtonFormField<String>, 'Sesso');
      await tester.tap(sessoDropdown);
      await tester.pumpAndSettle();
      
      // Seleziona l'opzione 'M'
      final mOption = find.text('M').last;
      await tester.tap(mOption);
      await tester.pumpAndSettle();

      // Inserisce altezza e peso
      final altezzaField = find.widgetWithLabel(TextFormField, 'Altezza (cm)');
      final pesoField = find.widgetWithLabel(TextFormField, 'Peso (kg)');
      await tester.enterText(altezzaField, '180');
      await tester.enterText(pesoField, '78.5');

      // Clicca su "Salva"
      await tester.tap(find.widgetWithText(FilledButton, 'Salva'));
      await tester.pumpAndSettle();

      // Il dialog dovrebbe chiudersi dopo il salvataggio con successo (codice 201 mockato)
      expect(find.text('Nuovo Paziente'), findsNothing);
    });
  });
}
