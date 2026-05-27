import 'package:flutter/material.dart';
import '../models/app_settings.dart';

class SettingsNotifier extends ChangeNotifier {
  AppSettings _settings = AppSettings();
  bool _initialized = false;

  AppSettings get settings => _settings;
  bool get initialized => _initialized;

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
}
