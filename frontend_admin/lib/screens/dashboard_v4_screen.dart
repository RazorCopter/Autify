import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../widgets/dashboard_components.dart';

typedef DashboardStatsLoader = Future<Map<String, dynamic>?> Function();
typedef DashboardNavigationCallback = void Function(
  int tabIndex, {
  String? searchFilter,
  String? semanticFilter,
});

class DashboardV4Screen extends StatefulWidget {
  final DashboardNavigationCallback onNavigate;
  final Widget? headerAction;

  /// Funzione per il caricamento delle statistiche dashboard.
  final DashboardStatsLoader statsLoader;
  final String? usernameOverride;
  final VoidCallback? onUseClassicDashboard;

  const DashboardV4Screen({
    super.key,
    required this.onNavigate,
    required this.statsLoader,
    this.headerAction,
    this.usernameOverride,
    this.onUseClassicDashboard,
  });

  @override
  State<DashboardV4Screen> createState() => _DashboardV4ScreenState();
}

class _DashboardV4ScreenState extends State<DashboardV4Screen> {
  bool _isLoading = true;
  Map<String, dynamic>? _stats;
  DateTime? _lastLoaded;

  Future<Map<String, dynamic>?> _fetchStats() => widget.statsLoader();

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final stats = await _fetchStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _lastLoaded = stats == null ? null : DateTime.now();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stats = null;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashboardTokens.canvas,
      body: Stack(
        children: [
          const Positioned.fill(child: DashboardAuroraBackground()),
          RefreshIndicator(
            onRefresh: _loadStats,
            color: DashboardTokens.primary,
            child: SingleChildScrollView(
              key: const ValueKey('dashboard-scroll-view'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                _horizontalPadding(context),
                20,
                _horizontalPadding(context),
                36,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 22),
                      AnimatedSwitcher(
                        duration: DashboardTokens.motion,
                        child: _isLoading
                            ? const _DashboardLoadingState(
                                key: ValueKey('dashboard-loading'),
                              )
                            : _stats == null
                                ? _buildErrorState()
                                : _DashboardContent(
                                    key: const ValueKey('dashboard-content'),
                                    stats: _stats!,
                                    onNavigate: widget.onNavigate,
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _horizontalPadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return 12;
    if (width < 1200) return 24;
    return 32;
  }

  Widget _buildHeader() {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    final now = DateTime.now();
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Centro di Controllo Documentale',
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: DashboardTokens.deepNavy,
            fontSize: compact ? 25 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Stato e monitoraggio della documentazione · ${_formatLongDate(now)}',
          style: const TextStyle(
            color: DashboardTokens.textMuted,
            fontSize: 13,
          ),
        ),
        if (_lastLoaded != null) ...[
          const SizedBox(height: 3),
          Text(
            'Dati aggiornati alle ${_twoDigits(_lastLoaded!.hour)}:${_twoDigits(_lastLoaded!.minute)}',
            style: const TextStyle(
              color: DashboardTokens.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Aggiorna dati dashboard',
          child: Semantics(
            button: true,
            label: 'Aggiorna dati dashboard',
            child: SizedBox(
              width: 44,
              height: 44,
              child: IconButton.outlined(
                key: const ValueKey('dashboard-refresh-button'),
                onPressed: _isLoading ? null : _loadStats,
                icon: const Icon(Icons.refresh_rounded),
                color: DashboardTokens.primary,
                style: IconButton.styleFrom(
                  backgroundColor: DashboardTokens.surface,
                  side: const BorderSide(color: DashboardTokens.border),
                ),
              ),
            ),
          ),
        ),
        if (widget.headerAction != null) ...[
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(child: widget.headerAction),
          ),
        ],
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          text,
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerRight, child: actions),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: text),
        const SizedBox(width: 20),
        actions,
      ],
    );
  }

  Widget _buildErrorState() {
    return DashboardSurfaceCard(
      key: const ValueKey('dashboard-error'),
      child: DashboardEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Dati temporaneamente non disponibili',
        message:
            'Non è stato possibile recuperare la panoramica. I dati esistenti non sono stati sostituiti con valori stimati.',
        action: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              height: 44,
              child: FilledButton.icon(
                onPressed: _loadStats,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Riprova'),
              ),
            ),
            if (widget.onUseClassicDashboard != null)
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: widget.onUseClassicDashboard,
                  icon: const Icon(Icons.undo_rounded),
                  label: const Text('Torna alla dashboard classica'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final Map<String, dynamic> stats;
  final DashboardNavigationCallback onNavigate;

  const _DashboardContent({
    super.key,
    required this.stats,
    required this.onNavigate,
  });

  int _intValue(String key) => _asInt(stats[key]);

  @override
  Widget build(BuildContext context) {
    final total = _intValue('totale_utenze');
    final active = _intValue('totale_utenze_attive');
    final coverage = _mapValue(stats['copertura_scale']);
    final activeEvaluations = _asInt(coverage['coperti_count']);
    final missingScales = _asInt(coverage['scaduti_count']);
    final coveragePercent = _asDouble(coverage['coperti_percentuale']);
    final alerts = _mapValue(stats['alert_stats']);
    final overdue = _asInt(alerts['totale_scaduti']);
    final expiring = _asInt(alerts['totale_in_scadenza']);
    final neverEvaluated = _asInt(alerts['totale_mai_valutati']);
    final incomplete = _asInt(alerts['totale_incompleti']);
    final kpis = [
      DashboardKpiData(
        label: 'UTENZE ATTIVE',
        value: '$active',
        supportingText:
            total == 0 ? 'Nessuna utenza censita' : 'su $total censite',
        icon: Icons.people_alt_outlined,
        accent: DashboardTokens.primary,
        assetBackground: PremiumDashboardAssets.activeUsersCardBackground,
        onTap: () => onNavigate(2),
        tooltip: 'Apri l’anagrafica utenti',
      ),
      DashboardKpiData(
        label: 'VALUTAZIONI ATTIVE',
        value: '$activeEvaluations',
        supportingText:
            '${_formatNumber(coveragePercent)}% della documentazione in validità',
        icon: Icons.fact_check_outlined,
        accent: DashboardTokens.indigo,
        assetBackground: PremiumDashboardAssets.activeEvaluationsCardBackground,
        onTap: () => onNavigate(2),
        tooltip: 'Apri l’anagrafica per consultare le valutazioni',
      ),
      DashboardKpiData(
        label: 'SCALE MANCANTI',
        value: '$missingScales',
        supportingText: 'Scale scadute o mai compilate',
        icon: Icons.warning_amber_rounded,
        accent: DashboardTokens.danger,
        assetBackground: PremiumDashboardAssets.missingScalesCardBackground,
        onTap: () => onNavigate(2, semanticFilter: 'incompleti'),
        tooltip: 'Apri le utenze con documentazione incompleta',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardKpiGrid(items: kpis),
        const SizedBox(height: DashboardTokens.gap),
        _ComplianceStrip(
          overdue: overdue,
          expiring: expiring,
          incomplete: incomplete,
          neverEvaluated: neverEvaluated,
          truncated: stats['is_truncated'] == true,
          onNavigate: onNavigate,
        ),
        const SizedBox(height: DashboardTokens.gap),
        LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 1200;
            final tablet = constraints.maxWidth >= 600;
            final trendCard = _CoverageCard(
              coverage: coverage,
            );
            final alertCard = _AlertCenterCard(
              alerts: _listValue(stats['ultimi_alert']),
              alertStats: alerts,
              onNavigate: onNavigate,
            );

            if (desktop) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: trendCard),
                  const SizedBox(width: DashboardTokens.gap),
                  Expanded(child: alertCard),
                ],
              );
            }

            return Column(
              children: [
                trendCard,
                const SizedBox(height: DashboardTokens.gap),
                alertCard,
                if (tablet) const SizedBox.shrink(),
              ],
            );
          },
        ),
        const SizedBox(height: DashboardTokens.gap),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 600;
            final distribution = _DistributionCard(
              distributions: _listValue(stats['distribuzione_scale']),
              totalPatients: total,
            );
            final demographics = _DemographicsCard(
              demographics: _mapValue(stats['demographics']),
            );

            if (!twoColumns) {
              return Column(
                children: [
                  distribution,
                  const SizedBox(height: DashboardTokens.gap),
                  demographics,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: distribution),
                const SizedBox(width: DashboardTokens.gap),
                Expanded(child: demographics),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ComplianceStrip extends StatelessWidget {
  final int overdue;
  final int expiring;
  final int incomplete;
  final int neverEvaluated;
  final bool truncated;
  final DashboardNavigationCallback onNavigate;

  const _ComplianceStrip({
    required this.overdue,
    required this.expiring,
    required this.incomplete,
    required this.neverEvaluated,
    required this.truncated,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Valutazioni scadute',
        overdue,
        Icons.schedule_rounded,
        DashboardTokens.danger,
        'scaduti'
      ),
      (
        'In scadenza',
        expiring,
        Icons.warning_amber_rounded,
        DashboardTokens.warning,
        'in_scadenza'
      ),
      (
        'Documenti incompleti',
        incomplete,
        Icons.description_outlined,
        DashboardTokens.primary,
        'incompleti'
      ),
      (
        'Da verificare',
        neverEvaluated,
        Icons.visibility_outlined,
        DashboardTokens.purple,
        'mai_valutati'
      ),
    ];
    return PremiumSummaryBar(
      semanticLabel: 'Stato e conformità documentale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 920
                  ? 4
                  : (constraints.maxWidth >= 520 ? 2 : 1);
              const gap = 10.0;
              final itemWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in items)
                    SizedBox(
                      width: itemWidth,
                      child: _ComplianceItem(
                        label: item.$1,
                        value: item.$2,
                        icon: item.$3,
                        color: item.$4,
                        onTap: () => onNavigate(2, semanticFilter: item.$5),
                      ),
                    ),
                ],
              );
            },
          ),
          if (truncated) ...[
            const SizedBox(height: 10),
            const DashboardStatusPill(
              label: 'Dataset parziale',
              color: DashboardTokens.warning,
              icon: Icons.info_outline_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

class _ComplianceItem extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ComplianceItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label: $value',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DashboardTokens.compactRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(DashboardTokens.compactRadius),
            border: Border.all(color: color.withValues(alpha: 0.16)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label,
                        style: const TextStyle(
                          color: DashboardTokens.textMuted,
                          fontSize: 11.5,
                        )),
                    const SizedBox(height: 3),
                    Text('$value',
                        style: TextStyle(
                          color: color,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        )),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverageCard extends StatelessWidget {
  final Map<String, dynamic> coverage;

  const _CoverageCard({required this.coverage});

  @override
  Widget build(BuildContext context) {
    final valid = _asInt(coverage['coperti_count']);
    final missing = _asInt(coverage['scaduti_count']);
    final percent =
        _asDouble(coverage['coperti_percentuale']).clamp(0.0, 100.0).toDouble();
    final total = valid + missing;
    final missingPercent =
        total == 0 ? 0.0 : (missing / total * 100).toDouble();

    return PremiumCoverageCard(
      semanticLabel:
          'Copertura documentale: ${_formatNumber(percent)} percento, $valid valide e $missing mancanti',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardSectionHeader(
            title: 'Copertura Documentale',
            subtitle: 'Rapporto tra scale valide e mancanti',
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final chart = SizedBox(
                width: compact ? 190 : 230,
                height: compact ? 190 : 230,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        startDegreeOffset: -90,
                        centerSpaceRadius: compact ? 58 : 72,
                        sectionsSpace: 3,
                        sections: total == 0
                            ? [
                                PieChartSectionData(
                                  value: 1,
                                  color: DashboardTokens.border,
                                  radius: compact ? 22 : 27,
                                  showTitle: false,
                                ),
                              ]
                            : [
                                PieChartSectionData(
                                  value: valid.toDouble(),
                                  color: DashboardTokens.success,
                                  radius: compact ? 22 : 27,
                                  showTitle: false,
                                ),
                                PieChartSectionData(
                                  value: missing.toDouble(),
                                  color: DashboardTokens.danger,
                                  radius: compact ? 22 : 27,
                                  showTitle: false,
                                ),
                              ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_formatNumber(percent)}%',
                          style: const TextStyle(
                            color: DashboardTokens.deepNavy,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'COPERTURA',
                          style: TextStyle(
                            color: DashboardTokens.textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
              final details = Column(
                children: [
                  _CoverageMetric(
                    label: 'Valide',
                    value: valid,
                    percent: percent,
                    color: DashboardTokens.success,
                    icon: Icons.verified_rounded,
                  ),
                  const SizedBox(height: 12),
                  _CoverageMetric(
                    label: 'Mancanti',
                    value: missing,
                    percent: missingPercent,
                    color: DashboardTokens.danger,
                    icon: Icons.error_outline_rounded,
                  ),
                ],
              );
              if (compact) {
                return Column(
                    children: [chart, const SizedBox(height: 14), details]);
              }
              return Row(
                children: [
                  Expanded(child: Center(child: chart)),
                  const SizedBox(width: 18),
                  Expanded(child: details),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CoverageMetric extends StatelessWidget {
  final String label;
  final int value;
  final double percent;
  final Color color;
  final IconData icon;

  const _CoverageMetric({
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(DashboardTokens.compactRadius),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                      color: DashboardTokens.textMuted,
                      fontSize: 12,
                    )),
                Text('$value',
                    style: const TextStyle(
                      color: DashboardTokens.deepNavy,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    )),
              ],
            ),
          ),
          Text('${_formatNumber(percent)}%',
              style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _AlertCenterCard extends StatelessWidget {
  final List<dynamic> alerts;
  final Map<String, dynamic> alertStats;
  final DashboardNavigationCallback onNavigate;

  const _AlertCenterCard({
    required this.alerts,
    required this.alertStats,
    required this.onNavigate,
  });

  int _priority(dynamic raw) {
    final status = _mapValue(raw)['stato']?.toString();
    if (status == 'scaduto') return 0;
    if (status == 'mai_valutato') return 1;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...alerts]..sort((a, b) {
        final priority = _priority(a).compareTo(_priority(b));
        if (priority != 0) return priority;
        return _asInt(_mapValue(b)['giorni_da_ultima_valutazione'])
            .compareTo(_asInt(_mapValue(a)['giorni_da_ultima_valutazione']));
      });
    final visible = sorted;
    final totalActions = _asInt(alertStats['totale_scaduti']) +
        _asInt(alertStats['totale_in_scadenza']) +
        _asInt(alertStats['totale_mai_valutati']) +
        _asInt(alertStats['totale_incompleti']);

    return PremiumAlertCard(
      semanticLabel: 'Centro alert: $totalActions azioni rilevate',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionHeader(
            title: 'Alert Center — Azioni Richieste Urgenti',
            subtitle: '$totalActions azioni ordinate per priorità operativa',
            trailing: DashboardStatusPill(
              label: '$totalActions',
              color: totalActions > 0
                  ? DashboardTokens.danger
                  : DashboardTokens.success,
              icon: totalActions > 0
                  ? Icons.notifications_active_outlined
                  : Icons.check_rounded,
            ),
          ),
          const SizedBox(height: 14),
          if (visible.isEmpty)
            const DashboardEmptyState(
              icon: Icons.task_alt_rounded,
              title: 'Nessun alert prioritario',
              message: 'Le utenze risultano coperte e monitorate.',
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: visible.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: DashboardTokens.border),
                itemBuilder: (context, index) => _AlertRow(
                  alert: _mapValue(visible[index]),
                  onTap: () {
                    final item = _mapValue(visible[index]);
                    final surname = item['paziente_cognome']?.toString().trim();
                    onNavigate(
                      2,
                      searchFilter:
                          surname == null || surname.isEmpty ? null : surname,
                      semanticFilter:
                          _semanticFilterForAlert(item['stato']?.toString()),
                    );
                  },
                ),
              ),
            ),
          if (totalActions > 0) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () => onNavigate(2, semanticFilter: 'scaduti'),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Gestisci priorità'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DashboardTokens.primary,
                  side: const BorderSide(color: DashboardTokens.border),
                  minimumSize: const Size(44, 44),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final Map<String, dynamic> alert;
  final VoidCallback onTap;

  const _AlertRow({required this.alert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = alert['stato']?.toString() ?? '';
    final overdue = status == 'scaduto';
    final never = status == 'mai_valutato';
    final color = overdue
        ? DashboardTokens.danger
        : never
            ? DashboardTokens.warning
            : DashboardTokens.warning;
    final statusLabel = overdue
        ? 'Scaduta'
        : never
            ? 'Mai valutata'
            : 'In scadenza';
    final firstName = alert['paziente_nome']?.toString().trim() ?? '';
    final lastName = alert['paziente_cognome']?.toString().trim() ?? '';
    final userName = '$firstName $lastName'.trim();
    final scale = alert['scala_nome']?.toString() ?? 'Scala';
    final days = _asInt(alert['giorni_da_ultima_valutazione']);
    final detail = never || days >= 9999
        ? '$scale · nessuna valutazione compilata'
        : '$scale · $days giorni dall’ultima valutazione';

    return Semantics(
      button: true,
      label: '${userName.isEmpty ? 'Utenza' : userName}, $statusLabel, $detail',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    overdue
                        ? Icons.priority_high_rounded
                        : Icons.schedule_rounded,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName.isEmpty ? 'Utenza senza nominativo' : userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: DashboardTokens.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: DashboardTokens.textMuted,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: statusLabel,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: color,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DistributionCard extends StatelessWidget {
  final List<dynamic> distributions;
  final int totalPatients;

  const _DistributionCard({
    required this.distributions,
    required this.totalPatients,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = distributions.map(_mapValue).toList()
      ..sort((a, b) =>
          _asDouble(b['percentuale']).compareTo(_asDouble(a['percentuale'])));

    return DashboardSurfaceCard(
      semanticLabel: 'Distribuzione delle scale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionHeader(
            title: 'Distribuzione Documentazione',
            subtitle:
                'Completamento rispetto al totale di $totalPatients utenti',
          ),
          const SizedBox(height: 20),
          if (sorted.isEmpty)
            const DashboardEmptyState(
              icon: Icons.stacked_bar_chart_rounded,
              title: 'Nessuna scala compilata',
              message: 'La copertura per strumento comparirà qui.',
            )
          else
            for (var index = 0; index < sorted.length; index++) ...[
              _DistributionBar(item: sorted[index]),
              if (index != sorted.length - 1) const SizedBox(height: 17),
            ],
        ],
      ),
    );
  }
}

class _DistributionBar extends StatelessWidget {
  final Map<String, dynamic> item;

  const _DistributionBar({required this.item});

  @override
  Widget build(BuildContext context) {
    final name = item['scala_nome']?.toString() ?? 'Scala senza nome';
    final count = _asInt(item['count']);
    final percent = _asDouble(item['percentuale']).clamp(0, 100).toDouble();

    return Semantics(
      label: '$name, $count utenze, ${_formatNumber(percent)} per cento',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: name,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: DashboardTokens.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$count · ${_formatNumber(percent)}%',
                style: const TextStyle(
                  color: DashboardTokens.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 9,
              backgroundColor: const Color(0xFFEDF1F6),
              valueColor: const AlwaysStoppedAnimation(DashboardTokens.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemographicsCard extends StatelessWidget {
  final Map<String, dynamic> demographics;

  const _DemographicsCard({required this.demographics});

  @override
  Widget build(BuildContext context) {
    final gender = _mapValue(demographics['sesso']);
    final ages = _mapValue(demographics['fasce_eta']);
    final ageEntries = <MapEntry<String, int>>[
      MapEntry('0–18', _asInt(ages['0-18'])),
      MapEntry('19–35', _asInt(ages['19-35'])),
      MapEntry('36–50', _asInt(ages['36-50'])),
      MapEntry('51+', _asInt(ages['51+'])),
      MapEntry('Non specificata', _asInt(ages['Non specificata'])),
    ];
    final total =
        gender.values.fold<int>(0, (sum, value) => sum + _asInt(value));
    final maxAge = ageEntries.fold<int>(
      0,
      (current, entry) => current > entry.value ? current : entry.value,
    );

    return PremiumSocioDemoCard(
      semanticLabel: 'Profilo demografico',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardSectionHeader(
            title: 'Dati Socio-Demografici',
            subtitle: 'Distribuzione per genere e fasce d’età',
          ),
          const SizedBox(height: 20),
          if (demographics.isEmpty || total == 0)
            const DashboardEmptyState(
              icon: Icons.groups_outlined,
              title: 'Dati demografici assenti',
              message:
                  'Completa le anagrafiche per visualizzare la distribuzione.',
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DemographicChip(
                  label: 'Donne',
                  value: _asInt(gender['F']),
                  color: DashboardTokens.purple,
                ),
                _DemographicChip(
                  label: 'Uomini',
                  value: _asInt(gender['M']),
                  color: DashboardTokens.primary,
                ),
                _DemographicChip(
                  label: 'Altro / N.S.',
                  value: _asInt(gender['Altro/Non specificato']),
                  color: DashboardTokens.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 22),
            for (var index = 0; index < ageEntries.length; index++) ...[
              _AgeBar(entry: ageEntries[index], maxValue: maxAge),
              if (index != ageEntries.length - 1) const SizedBox(height: 11),
            ],
          ],
        ],
      ),
    );
  }
}

class _DemographicChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _DemographicChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '$label  $value',
            style: const TextStyle(
              color: DashboardTokens.text,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AgeBar extends StatelessWidget {
  final MapEntry<String, int> entry;
  final int maxValue;

  const _AgeBar({required this.entry, required this.maxValue});

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue == 0 ? 0.0 : entry.value / maxValue;
    return Semantics(
      label: 'Fascia ${entry.key}: ${entry.value} utenze',
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              entry.key,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DashboardTokens.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: fraction,
                backgroundColor: const Color(0xFFEDF1F6),
                valueColor:
                    const AlwaysStoppedAnimation(DashboardTokens.purple),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 28,
            child: Text(
              '${entry.value}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: DashboardTokens.text,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardLoadingState extends StatelessWidget {
  const _DashboardLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Caricamento dati dashboard',
      child: Shimmer.fromColors(
        baseColor: const Color(0xFFE8ECF2),
        highlightColor: const Color(0xFFF8FAFC),
        period: const Duration(milliseconds: 1100),
        child: Column(
          children: [
            const _KpiSkeletonGrid(),
            const SizedBox(height: DashboardTokens.gap),
            const _SkeletonBox(height: 68),
            const SizedBox(height: DashboardTokens.gap),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 1200) {
                  return const Row(
                    children: [
                      Expanded(flex: 2, child: _SkeletonBox(height: 390)),
                      SizedBox(width: DashboardTokens.gap),
                      Expanded(child: _SkeletonBox(height: 390)),
                    ],
                  );
                }
                return const Column(
                  children: [
                    _SkeletonBox(height: 360),
                    SizedBox(height: DashboardTokens.gap),
                    _SkeletonBox(height: 320),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiSkeletonGrid extends StatelessWidget {
  const _KpiSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1200 ? 4 : 2;
        const gap = DashboardTokens.gap;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: List.generate(
            4,
            (_) => SizedBox(
              width: width,
              child: const _SkeletonBox(height: 162),
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double height;

  const _SkeletonBox({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DashboardTokens.radius),
      ),
    );
  }
}

Map<String, dynamic> _mapValue(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const {};
}

List<dynamic> _listValue(dynamic value) => value is List ? value : const [];

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1).replaceAll('.', ',');
}

String _formatLongDate(DateTime date) {
  const weekdays = [
    'lunedì',
    'martedì',
    'mercoledì',
    'giovedì',
    'venerdì',
    'sabato',
    'domenica',
  ];
  const months = [
    'gennaio',
    'febbraio',
    'marzo',
    'aprile',
    'maggio',
    'giugno',
    'luglio',
    'agosto',
    'settembre',
    'ottobre',
    'novembre',
    'dicembre',
  ];
  return '${weekdays[date.weekday - 1]} ${date.day} ${months[date.month - 1]} ${date.year}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String? _semanticFilterForAlert(String? status) {
  return switch (status) {
    'scaduto' => 'scaduti',
    'in_scadenza' => 'in_scadenza',
    'incompleto' => 'incompleti',
    'mai_valutato' => 'mai_valutati',
    _ => null,
  };
}
