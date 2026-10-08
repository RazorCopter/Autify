import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_admin/screens/dashboard_screen.dart';
import 'package:frontend_admin/widgets/dashboard_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final stats = <String, dynamic>{
    'totale_utenze': 24,
    'totale_utenze_attive': 21,
    'totale_valutazioni_eseguite': 63,
    'copertura_scale': {
      'coperti_percentuale': 72.2,
      'coperti_count': 52,
      'scaduti_count': 9,
    },
    'alert_stats': {
      'totale_scaduti': 3,
      'totale_in_scadenza': 2,
      'totale_mai_valutati': 1,
      'totale_incompleti': 0,
    },
    'distribuzione_scale': [
      {
        'scala_id': 'pos',
        'scala_nome': 'Personal Outcomes Scale',
        'count': 18,
        'percentuale': 75.0,
      },
      {
        'scala_id': 'sis',
        'scala_nome': 'Supports Intensity Scale',
        'count': 14,
        'percentuale': 58.3,
      },
    ],
    'trend_somministrazioni': [
      {'mese': 'Mag 2026', 'count': 4},
      {'mese': 'Giu 2026', 'count': 8},
      {'mese': 'Lug 2026', 'count': 6},
      {'mese': 'Ago 2026', 'count': 9},
      {'mese': 'Set 2026', 'count': 7},
      {'mese': 'Ott 2026', 'count': 11},
    ],
    'forecast_somministrazioni': [
      {'settimana': 'W1', 'routine': 0, 'criticita': 2},
      {'settimana': 'W2', 'routine': 0, 'criticita': 1},
      {'settimana': 'W3', 'routine': 0, 'criticita': 0},
    ],
    'ultimi_alert': [
      {
        'paziente_id': 'P-001',
        'paziente_nome': 'Ada',
        'paziente_cognome': 'Rossi',
        'giorni_da_ultima_valutazione': 205,
        'stato': 'scaduto',
        'scala_nome': 'POS',
      },
    ],
    'demographics': {
      'sesso': {'M': 10, 'F': 9, 'Altro/Non specificato': 2},
      'fasce_eta': {
        '0-18': 4,
        '19-35': 6,
        '36-50': 5,
        '51+': 5,
        'Non specificata': 1,
      },
    },
    'is_truncated': false,
  };

  Future<void> pumpDashboard(
    WidgetTester tester, {
    required Size size,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: DashboardScreen(
          usernameOverride: 'Mario',
          statsLoader: () async => stats,
          onNavigate: (_, {searchFilter, semanticFilter}) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void expectNoLayoutErrors(WidgetTester tester) {
    final exceptions = <Object>[];
    Object? exception;
    while ((exception = tester.takeException()) != null) {
      exceptions.add(exception!);
    }
    expect(exceptions, isEmpty);
  }

  testWidgets('a 320px usa KPI 2x2 e non genera overflow', (tester) async {
    await pumpDashboard(tester, size: const Size(320, 900));

    expect(find.byKey(const ValueKey('dashboard-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-kpi-card-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('dashboard-kpi-card-3')), findsOneWidget);
    expect(find.text('N/D'), findsOneWidget);

    final first = tester.getRect(
      find.byKey(const ValueKey('dashboard-kpi-slot-0')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('dashboard-kpi-slot-1')),
    );
    final third = tester.getRect(
      find.byKey(const ValueKey('dashboard-kpi-slot-2')),
    );
    expect(second.top, closeTo(first.top, 0.1));
    expect(third.top, greaterThan(first.bottom));
    expect(first.width, lessThan(150));
    expectNoLayoutErrors(tester);
  });

  testWidgets('a 800px mantiene due colonne KPI senza overflow',
      (tester) async {
    await pumpDashboard(tester, size: const Size(800, 1000));

    final first = tester.getRect(
      find.byKey(const ValueKey('dashboard-kpi-slot-0')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('dashboard-kpi-slot-1')),
    );
    final third = tester.getRect(
      find.byKey(const ValueKey('dashboard-kpi-slot-2')),
    );
    expect(second.top, closeTo(first.top, 0.1));
    expect(third.top, greaterThan(first.bottom));
    expect(find.text('Andamento somministrazioni'), findsOneWidget);
    expectNoLayoutErrors(tester);
  });

  testWidgets('a 1440px dispone i quattro KPI sulla stessa riga',
      (tester) async {
    await pumpDashboard(tester, size: const Size(1440, 1000));

    final tops = List.generate(
      4,
      (index) =>
          tester.getRect(find.byKey(ValueKey('dashboard-kpi-slot-$index'))).top,
    );
    for (final top in tops.skip(1)) {
      expect(top, closeTo(tops.first, 0.1));
    }
    expect(find.text('Centro alert'), findsOneWidget);
    expectNoLayoutErrors(tester);
  });

  testWidgets('stato errore espone retry coerente', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          statsLoader: () async => null,
          onNavigate: (_, {searchFilter, semanticFilter}) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('dashboard-error')), findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);
    expectNoLayoutErrors(tester);
  });

  testWidgets('griglia KPI pura rispetta il target 2x2 a 320px',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: DashboardKpiGrid(
              items: List.generate(
                4,
                (index) => DashboardKpiData(
                  label: 'KPI $index',
                  value: '$index',
                  supportingText: 'Dato reale',
                  icon: Icons.assessment_outlined,
                  accent: DashboardTokens.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final first = tester.getRect(
      find.byKey(const ValueKey('dashboard-kpi-slot-0')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('dashboard-kpi-slot-1')),
    );
    expect(first.left, lessThan(second.left));
    expect(first.top, closeTo(second.top, 0.1));
    expectNoLayoutErrors(tester);
  });
}
