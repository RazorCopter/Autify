import 'package:flutter/material.dart';
import '../models/app_settings.dart';

enum EvaluationStatus { valid, expiring, expired }

class ValidityCalculator {
  static EvaluationStatus getStatus({
    required DateTime completionDate,
    required String scaleType,
    required AppSettings currentSettings,
  }) {
    final today = DateTime.now();

    // Determina i mesi di validità in base al tipo di scala
    int monthsValidity = 6;
    final typeLower = scaleType.toLowerCase();
    if (typeLower.contains('martin') || typeLower.contains('san')) {
      monthsValidity = currentSettings.validityMonthsSanMartin;
    } else {
      monthsValidity = currentSettings.validityMonthsPOS;
    }

    // Scadenza Teorica: data completamento + mesi validità
    final rawExpiration = DateTime(
      completionDate.year,
      completionDate.month + monthsValidity,
      completionDate.day,
      completionDate.hour,
      completionDate.minute,
    );

    // Inizio Alert: Scadenza Teorica - alertThresholdDays
    final alertStart = rawExpiration.subtract(Duration(days: currentSettings.alertThresholdDays));

    // Ritorna lo stato
    if (today.isAfter(rawExpiration)) {
      return EvaluationStatus.expired;
    } else if ((today.isAfter(alertStart) || today.isAtSameMomentAs(alertStart)) &&
               (today.isBefore(rawExpiration) || today.isAtSameMomentAs(rawExpiration))) {
      return EvaluationStatus.expiring;
    } else {
      return EvaluationStatus.valid;
    }
  }

  static Color getColor({
    required DateTime completionDate,
    required String scaleType,
    required AppSettings currentSettings,
  }) {
    final status = getStatus(
      completionDate: completionDate,
      scaleType: scaleType,
      currentSettings: currentSettings,
    );

    switch (status) {
      case EvaluationStatus.expired:
        return const Color(0xFFEF4444); // Rosso Premium
      case EvaluationStatus.expiring:
        return const Color(0xFFF97316); // Arancione Premium
      case EvaluationStatus.valid:
        return const Color(0xFF10B981); // Verde Premium
    }
  }
}
