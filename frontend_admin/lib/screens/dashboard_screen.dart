import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/settings_notifier.dart';
import 'dashboard_v4_screen.dart';
import 'legacy_dashboard_screen.dart';

typedef DashboardNavigationCallback = void Function(
  int tabIndex, {
  String? searchFilter,
  String? semanticFilter,
});

/// Punto unico di selezione fra la dashboard classica e Autify 4.0.
class DashboardScreen extends StatelessWidget {
  final DashboardNavigationCallback onNavigate;
  final Widget? headerAction;

  const DashboardScreen({
    super.key,
    required this.onNavigate,
    this.headerAction,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsNotifier>(
      builder: (context, settings, child) {
        if (!settings.initialized) {
          return const Scaffold(
            backgroundColor: Color(0xFFF3F8FF),
            body: Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          );
        }

        if (!settings.dashboardV4Enabled) {
          return LegacyDashboardScreen(
            key: const ValueKey('legacy-dashboard'),
            headerAction: headerAction,
            onNavigate: onNavigate,
          );
        }

        return DashboardV4Screen(
          key: const ValueKey('dashboard-v4'),
          headerAction: headerAction,
          onNavigate: onNavigate,
          statsLoader: const ApiService().getDashboardStats,
          onUseClassicDashboard: () => settings.setDashboardV4Enabled(false),
        );
      },
    );
  }
}