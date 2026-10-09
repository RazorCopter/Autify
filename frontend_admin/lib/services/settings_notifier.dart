import 'package:flutter/material.dart';
import '../models/app_settings.dart';

class SettingsNotifier extends ChangeNotifier {
  AppSettings _settings = AppSettings();
  bool _initialized = false;

  AppSettings get settings => _settings;
  bool get initialized => _initialized;
  bool get dashboardV4Enabled => _settings.dashboardV4Enabled;

  /// Alias semantico per l'abilitazione della nuova interfaccia e degli asset premium.
  bool get enablePremiumDashboardUI => _settings.dashboardV4Enabled;

  SettingsNotifier() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _settings = await AppSettings.load();
    _initialized = true;
    notifyListeners();
  }

  Future<void> updateSettings({
    int? validityMonthsSanMartin,
    int? validityMonthsPOS,
    int? validityMonthsSIS,
    int? alertThresholdDays,
  }) async {
    if (validityMonthsSanMartin != null) {
      _settings.validityMonthsSanMartin = validityMonthsSanMartin;
    }
    if (validityMonthsPOS != null) {
      _settings.validityMonthsPOS = validityMonthsPOS;
    }
    if (validityMonthsSIS != null) {
      _settings.validityMonthsSIS = validityMonthsSIS;
    }
    if (alertThresholdDays != null) {
      _settings.alertThresholdDays = alertThresholdDays;
    }
    await _settings.save();
    notifyListeners();
  }

  Future<void> setDashboardV4Enabled(bool enabled) async {
    if (_settings.dashboardV4Enabled == enabled) return;
    final previous = _settings.dashboardV4Enabled;
    _settings.dashboardV4Enabled = enabled;
    notifyListeners();
    try {
      await _settings.save();
    } catch (_) {
      _settings.dashboardV4Enabled = previous;
      notifyListeners();
      rethrow;
    }
  }

  /// Alias semantico per il toggle della UI e degli asset premium.
  Future<void> setEnablePremiumDashboardUI(bool enabled) =>
      setDashboardV4Enabled(enabled);
}
