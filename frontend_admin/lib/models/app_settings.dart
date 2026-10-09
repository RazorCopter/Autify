import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const String dashboardV4PreferenceKey = 'autify_dashboard_v4_enabled';

  int validityMonthsSanMartin;
  int validityMonthsPOS;
  int validityMonthsSIS;
  int alertThresholdDays;
  bool dashboardV4Enabled;

  AppSettings({
    this.validityMonthsSanMartin = 12,
    this.validityMonthsPOS = 6,
    this.validityMonthsSIS = 12,
    this.alertThresholdDays = 20,
    this.dashboardV4Enabled = false,
  });

  // Carica le impostazioni da SharedPreferences
  static Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AppSettings(
        validityMonthsSanMartin: prefs.getInt('validityMonthsSanMartin') ?? 12,
        validityMonthsPOS: prefs.getInt('validityMonthsPOS') ?? 6,
        validityMonthsSIS: prefs.getInt('validityMonthsSIS') ?? 12,
        alertThresholdDays: prefs.getInt('alertThresholdDays') ?? 20,
        dashboardV4Enabled: prefs.getBool(dashboardV4PreferenceKey) ?? false,
      );
    } catch (_) {
      return AppSettings();
    }
  }

  // Salva le impostazioni correnti in SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('validityMonthsSanMartin', validityMonthsSanMartin);
    await prefs.setInt('validityMonthsPOS', validityMonthsPOS);
    await prefs.setInt('validityMonthsSIS', validityMonthsSIS);
    await prefs.setInt('alertThresholdDays', alertThresholdDays);
    await prefs.setBool(dashboardV4PreferenceKey, dashboardV4Enabled);
  }
}
