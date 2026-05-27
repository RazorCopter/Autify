import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  int validityMonthsSanMartin;
  int validityMonthsPOS;
  int validityMonthsSIS;
  int alertThresholdDays;

  AppSettings({
    this.validityMonthsSanMartin = 12,
    this.validityMonthsPOS = 6,
    this.validityMonthsSIS = 12,
    this.alertThresholdDays = 20,
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
      );
    } catch (_) {
      return AppSettings();
    }
  }

  // Salva le impostazioni correnti in SharedPreferences
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('validityMonthsSanMartin', validityMonthsSanMartin);
      await prefs.setInt('validityMonthsPOS', validityMonthsPOS);
      await prefs.setInt('validityMonthsSIS', validityMonthsSIS);
      await prefs.setInt('alertThresholdDays', alertThresholdDays);
    } catch (_) {}
  }
}
