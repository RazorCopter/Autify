import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_admin/models/app_settings.dart';
import 'package:frontend_admin/services/settings_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitUntilInitialized(SettingsNotifier notifier) async {
    while (!notifier.initialized) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('la dashboard classica è il valore predefinito', () async {
    final settings = await AppSettings.load();
    expect(settings.dashboardV4Enabled, isFalse);
  });

  test('la preferenza Autify 4.0 viene salvata e riletta', () async {
    final settings = AppSettings(dashboardV4Enabled: true);
    await settings.save();

    final reloaded = await AppSettings.load();
    expect(reloaded.dashboardV4Enabled, isTrue);
  });

  test('SettingsNotifier aggiorna il toggle in tempo reale', () async {
    final notifier = SettingsNotifier();
    await waitUntilInitialized(notifier);
    expect(notifier.dashboardV4Enabled, isFalse);

    await notifier.setDashboardV4Enabled(true);
    expect(notifier.dashboardV4Enabled, isTrue);

    final persisted = await AppSettings.load();
    expect(persisted.dashboardV4Enabled, isTrue);
  });
}
