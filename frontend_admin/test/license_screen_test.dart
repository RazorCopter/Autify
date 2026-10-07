import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_admin/screens/license_screen.dart';
import 'package:frontend_admin/services/license_api.dart';

class _FakeApiService implements LicenseApi {
  _FakeApiService({
    required this.status,
    this.activationError,
  });

  final LicenseStatus status;
  final LicenseApiException? activationError;
  String? activatedCode;
  bool? forceRemote;

  @override
  Future<LicenseServerInfo> getLicenseServerInfo() async =>
      const LicenseServerInfo(
        url: 'https://licenze.ghome.it',
        configured: true,
        reachable: true,
      );

  @override
  Future<LicenseStatus> getLicenseStatus({bool forceRemote = false}) async {
    this.forceRemote = forceRemote;
    return status;
  }

  @override
  Future<LicenseStatus> activateLicense(String code) async {
    activatedCode = code;
    if (activationError != null) throw activationError!;
    return status;
  }

  @override
  Future<LicenseStatus> deactivateLicense() async {
    return _trialStatus;
  }
}

const _trialStatus = LicenseStatus(
  status: 'trial',
  valid: true,
  plan: 'trial',
  trial: true,
  offline: false,
  daysRemaining: 12,
);

const _activeStatus = LicenseStatus(
  status: 'active',
  valid: true,
  plan: '12M',
  trial: false,
  offline: false,
  daysRemaining: 300,
);

Widget _app(Widget child) => MaterialApp(home: child);

Widget _appWithLicenseRoute({
  required LicenseApi api,
  required bool blocking,
}) =>
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LicenseScreen(
                  api: api,
                  blocking: blocking,
                ),
              ),
            ),
            child: const Text('Apri licenza'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('permette di tornare indietro quando non e bloccante',
      (tester) async {
    final api = _FakeApiService(status: _activeStatus);
    await tester.pumpWidget(_appWithLicenseRoute(api: api, blocking: false));

    await tester.tap(find.text('Apri licenza'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Apri licenza'), findsOneWidget);
  });

  testWidgets('non permette di aggirare la schermata licenza bloccante',
      (tester) async {
    final api = _FakeApiService(status: _activeStatus);
    await tester.pumpWidget(_appWithLicenseRoute(api: api, blocking: true));

    await tester.tap(find.text('Apri licenza'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsNothing);
    expect(find.text('Licenza Autify'), findsOneWidget);
  });

  testWidgets('mostra lo stato della licenza trial', (tester) async {
    final api = _FakeApiService(status: _trialStatus);

    await tester.pumpWidget(_app(LicenseScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Periodo di prova attivo'), findsOneWidget);
    expect(find.text('Trial 15 giorni'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Attiva licenza'), findsOneWidget);
    expect(find.text('Server licenza'), findsOneWidget);
    expect(find.text('https://licenze.ghome.it'), findsOneWidget);
    expect(find.text('Raggiungibile'), findsOneWidget);
    expect(api.forceRemote, isFalse);
  });

  testWidgets('attiva il codice e notifica il chiamante', (tester) async {
    final api = _FakeApiService(status: _activeStatus);
    var activated = false;

    await tester.pumpWidget(_app(LicenseScreen(
      api: api,
      onActivated: () => activated = true,
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  AUTIFY-TEST-CODE-1234  ');
    await tester.tap(find.text('Attiva licenza'));
    await tester.pumpAndSettle();

    expect(api.activatedCode, 'AUTIFY-TEST-CODE-1234');
    expect(activated, isTrue);
    expect(find.text('Licenza attiva'), findsOneWidget);
    expect(find.text('12M'), findsOneWidget);
  });

  testWidgets('visualizza un errore restituito durante l attivazione',
      (tester) async {
    final api = _FakeApiService(
      status: _trialStatus,
      activationError: const LicenseApiException('Codice non valido'),
    );

    await tester.pumpWidget(_app(LicenseScreen(api: api)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'AUTIFY-BAD-CODE-1234');
    await tester.tap(find.text('Attiva licenza'));
    await tester.pumpAndSettle();

    expect(find.text('Codice non valido'), findsOneWidget);
  });

  testWidgets('mostra pulsante di rilascio licenza se commerciale e apre dialog di conferma',
      (tester) async {
    final api = _FakeApiService(status: _activeStatus);

    await tester.pumpWidget(_app(LicenseScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('license-deactivate-btn')), findsOneWidget);

    await tester.tap(find.byKey(const Key('license-deactivate-btn')));
    await tester.pumpAndSettle();

    expect(find.text('Rilascia Licenza'), findsOneWidget);
    expect(find.text('Conferma rilascio'), findsOneWidget);
    expect(find.text('Annulla'), findsOneWidget);

    // Conferma rilascio
    await tester.tap(find.text('Conferma rilascio'));
    await tester.pumpAndSettle();

    expect(find.text('Periodo di prova attivo'), findsOneWidget);
  });
}

