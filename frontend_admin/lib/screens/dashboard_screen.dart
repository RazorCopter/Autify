import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../services/api_service.dart';
import '../widgets/dashboard_components.dart';

typedef DashboardStatsLoader = Future<Map<String, dynamic>?> Function();
typedef DashboardNavigationCallback = void Function(
  int tabIndex, {
  String? searchFilter,
  String? semanticFilter,
});

class DashboardScreen extends StatefulWidget {
  final DashboardNavigationCallback onNavigate;
  final Widget? headerAction;

  /// Iniezione opzionale usata dai test widget e dalle preview offline.
  final DashboardStatsLoader? statsLoader;
  final String? usernameOverride;

  const DashboardScreen({
    super.key,
    required this.onNavigate,
    this.headerAction,
    this.statsLoader,
    this.usernameOverride,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _stats;
  DateTime? _lastLoaded;

  Future<Map<String, dynamic>?> _fetchStats() =>
      widget.statsLoader?.call() ?? _apiService.getDashboardStats();

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
      body: RefreshIndicator(
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
    final username =
        (widget.usernameOverride ?? ApiService.currentUsername).trim();
    final greeting = _greetingFor(now.hour);
    final displayName = username.isEmpty ? 'team' : username;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$greeting, $displayName',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: DashboardTokens.text,
            fontSize: compact ? 25 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Panoramica operativa · ${_formatLongDate(now)}',
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
        action: SizedBox(
          height: 44,
          child: FilledButton.icon(
            onPressed: _loadStats,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Riprova'),
          ),
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
    final evaluations = _intValue('totale_valutazioni_eseguite');
    final coverage = _mapValue(stats['copertura_scale']);
    final coveragePercent = _asDouble(coverage['coperti_percentuale']);
    final alerts = _mapValue(stats['alert_stats']);
    final overdue = _asInt(alerts['totale_scaduti']);
    final expiring = _asInt(alerts['totale_in_scadenza']);
    final neverEvaluated = _asInt(alerts['totale_mai_valutati']);
    final incomplete = _asInt(alerts['totale_incompleti']);
    final actionCount = overdue + expiring + neverEvaluated + incomplete;

    final kpis = [
      DashboardKpiData(
        label: 'UTENZE ATTIVE',
        value: '$active',
        supportingText:
            total == 0 ? 'Nessuna utenza censita' : 'su $total censite',
        icon: Icons.people_alt_outlined,
        accent: DashboardTokens.primary,
        onTap: () => onNavigate(2),
        tooltip: 'Apri l’anagrafica utenti',
      ),
      DashboardKpiData(
        label: 'VALUTAZIONI ESEGUITE',
        value: '$evaluations',
        supportingText: 'somministrazioni registrate',
        icon: Icons.fact_check_outlined,
        accent: DashboardTokens.purple,
        onTap: () => onNavigate(2),
        tooltip: 'Apri l’anagrafica per consultare le valutazioni',
      ),
      DashboardKpiData(
        label: 'COPERTURA SCALE',
        value: '${_formatNumber(coveragePercent)}%',
        supportingText: '${_asInt(coverage['coperti_count'])} coperture valide',
        icon: Icons.verified_outlined,
        accent: DashboardTokens.success,
        onTap: () => onNavigate(2),
        tooltip: 'Apri le utenze per verificare la copertura',
      ),
      const DashboardKpiData(
        label: 'MEDIA FUNZIONALE',
        value: 'N/D',
        supportingText: 'dato non fornito dall’API',
        icon: Icons.analytics_outlined,
        accent: DashboardTokens.warning,
        tooltip:
            'La media funzionale non è disponibile nei dati reali della dashboard e non viene stimata.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DashboardKpiGrid(items: kpis),
        const SizedBox(height: DashboardTokens.gap),
        _SystemHealthBar(
          active: active,
          total: total,
          coveragePercent: coveragePercent,
          overdue: overdue,
          actionCount: actionCount,
          truncated: stats['is_truncated'] == true,
          onOpenCritical: () => onNavigate(2, semanticFilter: 'scaduti'),
        ),
        const SizedBox(height: DashboardTokens.gap),
        LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 1200;
            final tablet = constraints.maxWidth >= 600;
            final trendCard = _TrendChartCard(
              trend: _listValue(stats['trend_somministrazioni']),
              forecast: _listValue(stats['forecast_somministrazioni']),
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

class _SystemHealthBar extends StatelessWidget {
  final int active;
  final int total;
  final double coveragePercent;
  final int overdue;
  final int actionCount;
  final bool truncated;
  final VoidCallback onOpenCritical;

  const _SystemHealthBar({
    required this.active,
    required this.total,
    required this.coveragePercent,
    required this.overdue,
    required this.actionCount,
    required this.truncated,
    required this.onOpenCritical,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final healthColor = overdue > 0
        ? DashboardTokens.danger
        : actionCount > 0
            ? DashboardTokens.warning
            : DashboardTokens.success;
    final label = overdue > 0
        ? 'Attenzione richiesta'
        : actionCount > 0
            ? 'Monitoraggio attivo'
            : 'Operatività regolare';

    final details = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DashboardStatusPill(
          label: label,
          color: healthColor,
          icon: overdue > 0
              ? Icons.error_outline_rounded
              : Icons.check_circle_outline_rounded,
        ),
        DashboardStatusPill(
          label: '$active/$total utenze attive',
          color: DashboardTokens.primary,
          icon: Icons.people_outline_rounded,
        ),
        DashboardStatusPill(
          label: '${_formatNumber(coveragePercent)}% copertura',
          color: DashboardTokens.success,
          icon: Icons.verified_outlined,
        ),
        if (truncated)
          const DashboardStatusPill(
            label: 'Dataset parziale',
            color: DashboardTokens.warning,
            icon: Icons.info_outline_rounded,
          ),
      ],
    );

    final action = overdue > 0
        ? SizedBox(
            height: 44,
            child: TextButton.icon(
              onPressed: onOpenCritical,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text('$overdue scadute'),
              style: TextButton.styleFrom(
                foregroundColor: DashboardTokens.danger,
                minimumSize: const Size(44, 44),
              ),
            ),
          )
        : null;

    return DashboardSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderColor: healthColor.withValues(alpha: 0.24),
      semanticLabel: 'Stato sistema: $label',
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                if (action != null) ...[
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              ],
            )
          : Row(
              children: [
                Expanded(child: details),
                if (action != null) ...[
                  const SizedBox(width: 12),
                  action,
                ],
              ],
            ),
    );
  }
}

class _TrendChartCard extends StatelessWidget {
  final List<dynamic> trend;
  final List<dynamic> forecast;

  const _TrendChartCard({required this.trend, required this.forecast});

  @override
  Widget build(BuildContext context) {
    final historical = trend.map(_TrendPoint.fromHistory).toList();
    final forecastPoints = forecast.map(_TrendPoint.fromForecast).toList();
    final hasHistory = historical.isNotEmpty;
    final hasForecast = forecastPoints.any((point) => point.value > 0);
    final allValues = [
      ...historical.map((point) => point.value),
      ...forecastPoints.map((point) => point.value),
    ];
    final maxValue = allValues.isEmpty
        ? 1.0
        : math.max(1.0, allValues.reduce(math.max).toDouble());
    final chartMaxY = math.max(4.0, (maxValue * 1.25).ceilToDouble());
    final chartHeight = MediaQuery.sizeOf(context).width < 600 ? 236.0 : 278.0;

    final series = <LineChartBarData>[];
    if (hasHistory) {
      series.add(
        LineChartBarData(
          spots: historical
              .asMap()
              .entries
              .map((entry) => FlSpot(entry.key.toDouble(), entry.value.value))
              .toList(),
          isCurved: true,
          curveSmoothness: 0.28,
          color: DashboardTokens.primary,
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
            show: true,
            color: DashboardTokens.primary.withValues(alpha: 0.1),
          ),
        ),
      );
    }
    if (hasForecast) {
      final forecastStartX = historical.length.toDouble();
      series.add(
        LineChartBarData(
          spots: forecastPoints
              .asMap()
              .entries
              .map(
                (entry) => FlSpot(
                  forecastStartX + entry.key,
                  entry.value.value,
                ),
              )
              .toList(),
          isCurved: true,
          color: DashboardTokens.warning,
          barWidth: 2.5,
          dashArray: const [7, 5],
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    final labels = [
      ...historical.map((point) => point.label),
      if (hasForecast) ...forecastPoints.map((point) => point.label),
    ];

    return DashboardSurfaceCard(
      semanticLabel: 'Andamento somministrazioni e previsione',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionHeader(
            title: 'Andamento somministrazioni',
            subtitle: 'Volumi mensili reali e criticità previste a 8 settimane',
            trailing: Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                const _ChartLegend(
                  label: 'Storico',
                  color: DashboardTokens.primary,
                ),
                if (hasForecast)
                  const _ChartLegend(
                    label: 'Forecast criticità',
                    color: DashboardTokens.warning,
                    dashed: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (!hasHistory && !hasForecast)
            SizedBox(
              height: chartHeight,
              child: const DashboardEmptyState(
                icon: Icons.show_chart_rounded,
                title: 'Nessuna serie disponibile',
                message:
                    'Le somministrazioni compariranno qui quando saranno registrate.',
              ),
            )
          else
            SizedBox(
              height: chartHeight,
              child: Semantics(
                label:
                    'Grafico con ${historical.length} periodi storici e ${hasForecast ? forecastPoints.length : 0} periodi previsionali',
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: math.max(1, labels.length - 1).toDouble(),
                    minY: 0,
                    maxY: chartMaxY,
                    lineBarsData: series,
                    borderData: FlBorderData(
                      show: true,
                      border: const Border(
                        bottom: BorderSide(color: DashboardTokens.border),
                        left: BorderSide(color: DashboardTokens.border),
                      ),
                    ),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: math.max(1, chartMaxY / 4),
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: DashboardTokens.border,
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          interval: math.max(1, chartMaxY / 4),
                          getTitlesWidget: (value, meta) => Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              color: DashboardTokens.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.round();
                            if (index < 0 || index >= labels.length) {
                              return const SizedBox.shrink();
                            }
                            final showEvery = labels.length > 10 ? 2 : 1;
                            if (index % showEvery != 0 &&
                                index != labels.length - 1) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                labels[index],
                                style: const TextStyle(
                                  color: DashboardTokens.textMuted,
                                  fontSize: 9.5,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => DashboardTokens.text,
                        tooltipRoundedRadius: 10,
                        getTooltipItems: (spots) => spots.map((spot) {
                          final index = spot.x.round();
                          final label = index >= 0 && index < labels.length
                              ? labels[index]
                              : 'Periodo';
                          final forecastSpot = spot.barIndex > 0;
                          return LineTooltipItem(
                            '$label\n${spot.y.toInt()} ${forecastSpot ? 'criticità' : 'somministrazioni'}',
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  duration: DashboardTokens.motion,
                  curve: Curves.easeOutCubic,
                ),
              ),
            ),
          if (forecast.isNotEmpty && !hasForecast) ...[
            const SizedBox(height: 12),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: DashboardTokens.textMuted,
                ),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Il backend non segnala criticità previste. La componente “routine” non è pianificata e resta esclusa dal grafico.',
                    style: TextStyle(
                      color: DashboardTokens.textMuted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendPoint {
  final String label;
  final double value;

  const _TrendPoint(this.label, this.value);

  factory _TrendPoint.fromHistory(dynamic raw) {
    final item = _mapValue(raw);
    return _TrendPoint(
      (item['mese'] ?? '—').toString(),
      _asDouble(item['count']),
    );
  }

  factory _TrendPoint.fromForecast(dynamic raw) {
    final item = _mapValue(raw);
    return _TrendPoint(
      (item['settimana'] ?? '—').toString(),
      _asDouble(item['criticita']),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final String label;
  final Color color;
  final bool dashed;

  const _ChartLegend({
    required this.label,
    required this.color,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 20,
          child: Row(
            children: dashed
                ? [
                    Container(width: 7, height: 3, color: color),
                    const SizedBox(width: 3),
                    Container(width: 7, height: 3, color: color),
                  ]
                : [Container(width: 20, height: 3, color: color)],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: DashboardTokens.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
    final visible = sorted.take(5).toList();
    final totalActions = _asInt(alertStats['totale_scaduti']) +
        _asInt(alertStats['totale_in_scadenza']) +
        _asInt(alertStats['totale_mai_valutati']) +
        _asInt(alertStats['totale_incompleti']);

    return DashboardSurfaceCard(
      semanticLabel: 'Centro alert: $totalActions azioni rilevate',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionHeader(
            title: 'Centro alert',
            subtitle: '$totalActions azioni ordinate per priorità clinica',
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
            for (var index = 0; index < visible.length; index++) ...[
              _AlertRow(
                alert: _mapValue(visible[index]),
                onTap: () {
                  final item = _mapValue(visible[index]);
                  final surname = item['paziente_cognome']?.toString().trim();
                  onNavigate(
                    2,
                    searchFilter:
                        surname == null || surname.isEmpty ? null : surname,
                    semanticFilter: item['stato']?.toString(),
                  );
                },
              ),
              if (index != visible.length - 1)
                const Divider(height: 1, color: DashboardTokens.border),
            ],
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
    final patient = '$firstName $lastName'.trim();
    final scale = alert['scala_nome']?.toString() ?? 'Scala';
    final days = _asInt(alert['giorni_da_ultima_valutazione']);
    final detail = never || days >= 9999
        ? '$scale · nessuna somministrazione'
        : '$scale · $days giorni dall’ultima';

    return Semantics(
      button: true,
      label: '${patient.isEmpty ? 'Utenza' : patient}, $statusLabel, $detail',
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
                        patient.isEmpty ? 'Utenza senza nominativo' : patient,
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
            title: 'Distribuzione scale',
            subtitle: 'Utenze coperte per strumento su $totalPatients censite',
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
              semanticsLabel: 'Copertura $name',
              semanticsValue: '${_formatNumber(percent)}%',
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
      (current, entry) => math.max(current, entry.value),
    );

    return DashboardSurfaceCard(
      semanticLabel: 'Profilo demografico',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardSectionHeader(
            title: 'Profilo demografico',
            subtitle: 'Distribuzione reale delle utenze attive',
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

String _greetingFor(int hour) {
  if (hour < 12) return 'Buongiorno';
  if (hour < 18) return 'Buon pomeriggio';
  return 'Buonasera';
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
