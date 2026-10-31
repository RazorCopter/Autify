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

/// Breakpoint del layout a due colonne.
const double _kDesktopBreakpoint = 1200;

/// Numero massimo di utenti mostrati nell'anteprima "Azioni prioritarie".
const int _kMaxAlertUsers = 6;

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

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final stats = await widget.statsLoader();
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final hPadding = _horizontalPadding(constraints.maxWidth);
                return SingleChildScrollView(
                  key: const ValueKey('dashboard-scroll-view'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(hPadding, 28, hPadding, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeader(constraints.maxWidth),
                          const SizedBox(height: 24),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            child: _buildState(),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Lo skeleton appare solo al primo caricamento: durante un refresh il
  /// contenuto resta visibile (niente "flash" dell'intera pagina).
  Widget _buildState() {
    if (_stats == null && _isLoading) {
      return const _DashboardLoadingState(key: ValueKey('dashboard-loading'));
    }
    if (_stats == null) return _buildErrorState();
    return _DashboardContent(
      key: const ValueKey('dashboard-content'),
      stats: _stats!,
      onNavigate: widget.onNavigate,
      refreshing: _isLoading,
    );
  }

  double _horizontalPadding(double availableWidth) {
    if (availableWidth < 600) return 16;
    if (availableWidth < 1200) return 28;
    return 40;
  }

  Widget _buildHeader(double availableWidth) {
    final compact = availableWidth < 600;
    final now = DateTime.now();
    final updated = _lastLoaded;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PANORAMICA',
          style: TextStyle(
            color: DashboardTokens.primary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Centro di Controllo Documentale',
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: DashboardTokens.deepNavy,
            fontSize: compact ? 24 : 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.9,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Stato e monitoraggio della documentazione · ${_formatLongDate(now)}',
              style: const TextStyle(
                color: DashboardTokens.textMuted,
                fontSize: 13.5,
              ),
            ),
            if (updated != null)
              _UpdatedPill(
                label:
                    'Dati aggiornati alle ${_twoDigits(updated.hour)}:${_twoDigits(updated.minute)}',
                refreshing: _isLoading,
              ),
          ],
        ),
      ],
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderButtonFrame(
          child: Tooltip(
            message: 'Aggiorna dati dashboard',
            child: Semantics(
              button: true,
              label: 'Aggiorna dati dashboard',
              child: IconButton(
                key: const ValueKey('dashboard-refresh-button'),
                onPressed: _isLoading ? null : _loadStats,
                padding: EdgeInsets.zero,
                iconSize: 20,
                color: DashboardTokens.primary,
                disabledColor: DashboardTokens.textSubtle,
                style: IconButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DashboardTokens.primary,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ),
          ),
        ),
        if (widget.headerAction != null) ...[
          const SizedBox(width: 10),
          widget.headerAction!,
        ],
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const Spacer(), actions],
          ),
          const SizedBox(height: 8),
          text,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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

/// Cornice coerente con la campanella notifiche fornita dalla shell.
class _HeaderButtonFrame extends StatelessWidget {
  final Widget child;

  const _HeaderButtonFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: DashboardTokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EEF8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _UpdatedPill extends StatelessWidget {
  final String label;
  final bool refreshing;

  const _UpdatedPill({required this.label, required this.refreshing});

  @override
  Widget build(BuildContext context) {
    final color =
        refreshing ? DashboardTokens.primary : DashboardTokens.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: DashboardTokens.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: DashboardTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            refreshing ? 'Aggiornamento in corso…' : label,
            style: const TextStyle(
              color: DashboardTokens.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CONTENUTO ──────────────────────────────────────────────────────────────

class _DashboardContent extends StatelessWidget {
  final Map<String, dynamic> stats;
  final DashboardNavigationCallback onNavigate;
  final bool refreshing;

  const _DashboardContent({
    super.key,
    required this.stats,
    required this.onNavigate,
    this.refreshing = false,
  });

  @override
  Widget build(BuildContext context) {
    final total = _asInt(stats['totale_utenze']);
    final active = _asInt(stats['totale_utenze_attive']);
    final covered = _asInt(stats['utenze_coperte']);
    final toComplete = _asInt(stats['utenze_da_completare']);
    final coverage = _mapValue(stats['copertura_scale']);
    final alertStats = _mapValue(stats['alert_stats']);
    final alertList = _listValue(stats['ultimi_alert']);
    final distributions = _listValue(stats['distribuzione_scale']);
    final demographics = _mapValue(stats['demographics']);

    final kpis = [
      DashboardKpiData(
        label: 'UTENZE ATTIVE',
        value: '$active',
        supportingText:
            total == 0 ? 'Nessuna utenza censita' : 'su $total censite',
        icon: Icons.people_alt_outlined,
        accent: DashboardTokens.primary,
        progress: total == 0 ? null : active / total,
        onTap: () => onNavigate(2),
        tooltip: 'Apri l’anagrafica utenti',
      ),
      DashboardKpiData(
        label: 'UTENZE COPERTE',
        value: '$covered',
        supportingText: active == 0
            ? 'Nessuna utenza attiva'
            : 'Tutte le scale richieste in validità',
        icon: Icons.verified_outlined,
        accent: DashboardTokens.success,
        progress: active == 0 ? null : covered / active,
        onTap: () => onNavigate(2, semanticFilter: 'coperti'),
        tooltip: 'Apri le utenze con documentazione completa',
      ),
      DashboardKpiData(
        label: 'UTENZE DA COMPLETARE',
        value: '$toComplete',
        supportingText: toComplete == 0
            ? 'Nessuna azione richiesta'
            : 'Almeno una scala richiesta non valida',
        icon: toComplete == 0
            ? Icons.check_circle_outline
            : Icons.assignment_late_outlined,
        accent:
            toComplete == 0 ? DashboardTokens.success : DashboardTokens.danger,
        progress: active == 0 ? null : toComplete / active,
        onTap: () => onNavigate(2, semanticFilter: 'da_completare'),
        tooltip: 'Apri le utenze con documentazione incompleta',
      ),
    ];

    final strip = _ComplianceStrip(
      overdue: _asInt(alertStats['totale_scaduti']),
      expiring: _asInt(alertStats['totale_in_scadenza']),
      incomplete: _asInt(alertStats['totale_incompleti']),
      neverEvaluated: _asInt(alertStats['totale_mai_valutati']),
      truncated: stats['is_truncated'] == true,
      onNavigate: onNavigate,
    );

    return AnimatedOpacity(
      opacity: refreshing ? 0.6 : 1,
      duration: DashboardTokens.motion,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = DashboardTokens.gap;
          final width = constraints.maxWidth;
          final desktop = width >= _kDesktopBreakpoint;

          // Larghezza utile interna della card copertura (padding 22×2 +
          // bordo): passata esplicitamente per non annidare LayoutBuilder
          // dentro IntrinsicHeight.
          final leftColumnWidth = desktop ? (width - gap) * 7 / 12 : width;
          final coverageContentWidth = leftColumnWidth - 46;

          final children = <Widget>[
            DashboardKpiGrid(items: kpis),
            const SizedBox(height: gap),
            strip,
            const SizedBox(height: gap),
          ];

          if (desktop) {
            // Le due colonne hanno sempre la stessa altezza: niente vuoti.
            children.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _CoverageCard(
                            coverage: coverage,
                            contentWidth: coverageContentWidth,
                          ),
                          const SizedBox(height: gap),
                          Expanded(
                            child: _DistributionCard(
                              distributions: distributions,
                              totalPatients: total,
                              fillHeight: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: gap),
                    Expanded(
                      flex: 5,
                      child: _AlertCenterCard(
                        alerts: alertList,
                        alertStats: alertStats,
                        onNavigate: onNavigate,
                        fillHeight: true,
                      ),
                    ),
                  ],
                ),
              ),
            );
          } else {
            children.addAll([
              _CoverageCard(
                coverage: coverage,
                contentWidth: coverageContentWidth,
              ),
              const SizedBox(height: gap),
              _AlertCenterCard(
                alerts: alertList,
                alertStats: alertStats,
                onNavigate: onNavigate,
              ),
              const SizedBox(height: gap),
              _DistributionCard(
                distributions: distributions,
                totalPatients: total,
              ),
            ]);
          }

          children.addAll([
            const SizedBox(height: gap),
            _DemographicsCard(demographics: demographics),
          ]);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        },
      ),
    );
  }
}

// ─── CODE DI LAVORO (strip conformità) ─────────────────────────────────────

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
        'Scale scadute',
        overdue,
        Icons.event_busy_outlined,
        DashboardTokens.danger,
        'scaduti',
      ),
      (
        'In scadenza',
        expiring,
        Icons.hourglass_bottom_rounded,
        DashboardTokens.warning,
        'in_scadenza',
      ),
      (
        'Documenti incompleti',
        incomplete,
        Icons.description_outlined,
        DashboardTokens.primary,
        'incompleti',
      ),
      (
        'Mai compilate',
        neverEvaluated,
        Icons.visibility_outlined,
        DashboardTokens.purple,
        'mai_valutati',
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
            const Align(
              alignment: Alignment.centerLeft,
              child: DashboardStatusPill(
                label: 'Dataset parziale',
                color: DashboardTokens.warning,
                icon: Icons.info_outline_rounded,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ComplianceItem extends StatefulWidget {
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
  State<_ComplianceItem> createState() => _ComplianceItemState();
}

class _ComplianceItemState extends State<_ComplianceItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // Le code vuote restano neutre: il colore segnala solo ciò che richiede
    // attenzione, riducendo il rumore visivo.
    final active = widget.value > 0;
    final color = active ? widget.color : DashboardTokens.neutral;
    final ink = active
        ? DashboardTokens.inkFor(widget.color)
        : DashboardTokens.textSubtle;

    return Semantics(
      button: true,
      label: '${widget.label}: ${widget.value}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(DashboardTokens.compactRadius),
            child: AnimatedContainer(
              duration: DashboardTokens.motion,
              constraints: const BoxConstraints(minHeight: 68),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: active
                    ? widget.color.withValues(alpha: _hover ? 0.09 : 0.05)
                    : (_hover
                        ? DashboardTokens.surfaceSecondary
                        : DashboardTokens.surface),
                borderRadius:
                    BorderRadius.circular(DashboardTokens.compactRadius),
                border: Border.all(
                  color: active
                      ? widget.color.withValues(alpha: 0.2)
                      : DashboardTokens.divider,
                ),
              ),
              child: Row(
                children: [
                  DashboardIconBadge(
                    icon: active ? widget.icon : Icons.check_rounded,
                    color: color,
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: DashboardTokens.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.value}',
                          style: TextStyle(
                            color: active ? ink : DashboardTokens.textSubtle,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSlide(
                    duration: DashboardTokens.motion,
                    offset: Offset(_hover ? 0.15 : 0, 0),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: active ? ink : DashboardTokens.textSubtle,
                      size: 20,
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
}

// ─── COPERTURA ──────────────────────────────────────────────────────────────

class _CoverageCard extends StatelessWidget {
  final Map<String, dynamic> coverage;

  /// Larghezza interna nota al genitore (evita LayoutBuilder annidati).
  final double contentWidth;

  const _CoverageCard({
    required this.coverage,
    required this.contentWidth,
  });

  @override
  Widget build(BuildContext context) {
    final valid = _asInt(coverage['coperti_count']);
    final missing = _asInt(coverage['scaduti_count']);
    final percent = _asDouble(coverage['coperti_percentuale'])
        .clamp(0.0, 100.0)
        .toDouble();
    final total = valid + missing;
    final missingPercent = total == 0 ? 0.0 : missing / total * 100;
    final compact = contentWidth < 480;

    final chart = _CoverageRing(
      percent: percent,
      valid: valid,
      missing: missing,
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _CoverageMetric(
          label: 'Scale valide',
          value: valid,
          percent: total == 0 ? 0.0 : percent,
          color: DashboardTokens.success,
        ),
        const SizedBox(height: 10),
        _CoverageMetric(
          label: 'Scale mancanti o scadute',
          value: missing,
          percent: missingPercent,
          color: DashboardTokens.danger,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(
              missing == 0 ? Icons.verified_outlined : Icons.flag_outlined,
              size: 15,
              color: missing == 0
                  ? DashboardTokens.successInk
                  : DashboardTokens.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                total == 0
                    ? 'Nessuna scala obbligatoria configurata'
                    : missing == 0
                        ? 'Piena conformità raggiunta'
                        : 'Mancano $missing compilazioni per la piena conformità',
                style: const TextStyle(
                  color: DashboardTokens.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return PremiumCoverageCard(
      semanticLabel:
          'Copertura documentale: ${_formatNumber(percent)} percento, $valid valide e $missing mancanti',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const DashboardSectionHeader(
            title: 'Copertura Documentale',
            subtitle:
                'Scale obbligatorie in corso di validità sulle utenze attive',
            icon: Icons.pie_chart_outline,
            accent: DashboardTokens.success,
          ),
          const SizedBox(height: 20),
          if (compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: chart),
                const SizedBox(height: 18),
                details,
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(width: 4),
                chart,
                const SizedBox(width: 28),
                Expanded(child: details),
              ],
            ),
        ],
      ),
    );
  }
}

class _CoverageRing extends StatelessWidget {
  final double percent;
  final int valid;
  final int missing;

  const _CoverageRing({
    required this.percent,
    required this.valid,
    required this.missing,
  });

  @override
  Widget build(BuildContext context) {
    const size = 152.0;
    const sliceRadius = 14.0;
    final total = valid + missing;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              centerSpaceRadius: 56,
              sectionsSpace: 3,
              sections: total == 0
                  ? [
                      PieChartSectionData(
                        value: 1,
                        color: DashboardTokens.track,
                        radius: sliceRadius,
                        showTitle: false,
                      ),
                    ]
                  : [
                      if (valid > 0)
                        PieChartSectionData(
                          value: valid.toDouble(),
                          color: DashboardTokens.success,
                          radius: sliceRadius,
                          showTitle: false,
                        ),
                      if (missing > 0)
                        PieChartSectionData(
                          value: missing.toDouble(),
                          color: const Color(0xFFF87171),
                          radius: sliceRadius,
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
                  color: DashboardTokens.text,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'COPERTURA',
                style: TextStyle(
                  color: DashboardTokens.textMuted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
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

  const _CoverageMetric({
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ink = DashboardTokens.inkFor(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: DashboardTokens.surfaceSecondary,
        borderRadius: BorderRadius.circular(DashboardTokens.compactRadius),
        border: Border.all(color: DashboardTokens.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DashboardTokens.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$value',
            style: const TextStyle(
              color: DashboardTokens.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 58,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_formatNumber(percent)}%',
              style: TextStyle(
                color: ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── AZIONI PRIORITARIE ─────────────────────────────────────────────────────

/// Stile coerente per stato alert, allineato ai colori della strip.
class _AlertStyle {
  final Color color;
  final IconData icon;
  final String text;
  final int priority;

  const _AlertStyle(this.color, this.icon, this.text, this.priority);

  static _AlertStyle of(String? status) {
    return switch (status) {
      'scaduto' => const _AlertStyle(
          DashboardTokens.danger, Icons.event_busy_outlined, 'scaduta', 0),
      'mai_valutato' => const _AlertStyle(DashboardTokens.purple,
          Icons.visibility_outlined, 'mai compilata', 1),
      'in_scadenza' => const _AlertStyle(DashboardTokens.warning,
          Icons.hourglass_bottom_rounded, 'in scadenza', 2),
      'incompleto' => const _AlertStyle(DashboardTokens.primary,
          Icons.description_outlined, 'incompleta', 3),
      _ => const _AlertStyle(DashboardTokens.slate,
          Icons.info_outline_rounded, 'da verificare', 4),
    };
  }
}

class _AlertCenterCard extends StatelessWidget {
  final List<dynamic> alerts;
  final Map<String, dynamic> alertStats;
  final DashboardNavigationCallback onNavigate;

  /// Se true il pulsante resta ancorato in fondo alla card.
  final bool fillHeight;

  const _AlertCenterCard({
    required this.alerts,
    required this.alertStats,
    required this.onNavigate,
    this.fillHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = alerts.map(_mapValue).toList()
      ..sort((a, b) {
        final priority = _AlertStyle.of(a['stato']?.toString())
            .priority
            .compareTo(_AlertStyle.of(b['stato']?.toString()).priority);
        if (priority != 0) return priority;
        return _asInt(b['giorni_da_ultima_valutazione'])
            .compareTo(_asInt(a['giorni_da_ultima_valutazione']));
      });

    final groupedByUser = <String, List<Map<String, dynamic>>>{};
    for (final item in sorted) {
      final id = item['paziente_id']?.toString() ??
          '${item['paziente_nome']}_${item['paziente_cognome']}';
      groupedByUser.putIfAbsent(id, () => []).add(item);
    }
    final userGroups = groupedByUser.values.toList();
    final visibleGroups = userGroups.take(_kMaxAlertUsers).toList();
    final hiddenUsers = userGroups.length - visibleGroups.length;

    final totalActions = _asInt(alertStats['totale_scaduti']) +
        _asInt(alertStats['totale_in_scadenza']) +
        _asInt(alertStats['totale_mai_valutati']) +
        _asInt(alertStats['totale_incompleti']);
    final previewActions = sorted.length;

    final subtitle = totalActions == 0
        ? 'Nessuna attività aperta'
        : totalActions > previewActions
            ? 'In evidenza $previewActions di $totalActions attività aperte, per urgenza'
            : '$totalActions attività aperte su ${userGroups.length} utenti, per urgenza';

    return PremiumAlertCard(
      semanticLabel:
          'Azioni prioritarie: $totalActions azioni totali, $previewActions in anteprima',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionHeader(
            title: 'Azioni prioritarie',
            subtitle: subtitle,
            icon: Icons.notifications_active_outlined,
            accent: totalActions > 0
                ? DashboardTokens.danger
                : DashboardTokens.success,
            trailing: DashboardStatusPill(
              label: '$totalActions',
              color: totalActions > 0
                  ? DashboardTokens.danger
                  : DashboardTokens.success,
              icon: totalActions > 0
                  ? Icons.priority_high_rounded
                  : Icons.check_rounded,
            ),
          ),
          const SizedBox(height: 14),
          if (visibleGroups.isEmpty)
            const DashboardEmptyState(
              icon: Icons.check_circle_outline,
              title: 'Nessuna azione prioritaria',
              message: 'Tutte le utenze risultano conformi e monitorate.',
            )
          else
            for (var index = 0; index < visibleGroups.length; index++) ...[
              if (index != 0)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: DashboardTokens.divider,
                ),
              _UserActionGroupTile(
                userAlerts: visibleGroups[index],
                onNavigate: onNavigate,
              ),
            ],
          if (hiddenUsers > 0) ...[
            const SizedBox(height: 8),
            Text(
              '+ $hiddenUsers ${hiddenUsers == 1 ? "altro utente" : "altri utenti"} con attività aperte',
              style: const TextStyle(
                color: DashboardTokens.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (fillHeight) const Spacer(),
          if (totalActions > 0) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: FilledButton.icon(
                // Apre tutte le utenze con almeno una scala non valida,
                // non solo la coda "scaduti" (che poteva risultare vuota).
                onPressed: () =>
                    onNavigate(2, semanticFilter: 'da_completare'),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(
                  totalActions > previewActions
                      ? 'Visualizza tutte le $totalActions attività'
                      : 'Gestisci tutte le priorità',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: DashboardTokens.primary,
                  foregroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserActionGroupTile extends StatelessWidget {
  final List<Map<String, dynamic>> userAlerts;
  final DashboardNavigationCallback onNavigate;

  const _UserActionGroupTile({
    required this.userAlerts,
    required this.onNavigate,
  });

  void _open(Map<String, dynamic> alert) {
    final surname = alert['paziente_cognome']?.toString().trim();
    onNavigate(
      2,
      searchFilter: surname == null || surname.isEmpty ? null : surname,
      semanticFilter: _semanticFilterForAlert(alert['stato']?.toString()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (userAlerts.isEmpty) return const SizedBox.shrink();
    final first = userAlerts.first;
    final firstName = first['paziente_nome']?.toString().trim() ?? '';
    final lastName = first['paziente_cognome']?.toString().trim() ?? '';
    final userName = '$firstName $lastName'.trim();
    final effectiveName = userName.isEmpty ? 'Utenza' : userName;
    final initials = [firstName, lastName]
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase())
        .join();

    // La lista è già ordinata per urgenza: il primo alert definisce il colore.
    final severity = _AlertStyle.of(first['stato']?.toString());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _open(first),
        borderRadius: BorderRadius.circular(10),
        hoverColor: DashboardTokens.surfaceSecondary,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: severity.color.withValues(alpha: 0.12),
                  border: Border.all(
                    color: severity.color.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: TextStyle(
                    color: DashboardTokens.inkFor(severity.color),
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            effectiveName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: DashboardTokens.text,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${userAlerts.length} ${userAlerts.length == 1 ? "azione" : "azioni"}',
                          style: const TextStyle(
                            color: DashboardTokens.textMuted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: DashboardTokens.textSubtle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final alert in userAlerts)
                          _AlertChip(
                            alert: alert,
                            onTap: () => _open(alert),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertChip extends StatelessWidget {
  final Map<String, dynamic> alert;
  final VoidCallback onTap;

  const _AlertChip({required this.alert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scale = alert['scala_nome']?.toString().trim();
    final style = _AlertStyle.of(alert['stato']?.toString());
    final ink = DashboardTokens.inkFor(style.color);
    final label =
        '${scale == null || scale.isEmpty ? "Scala" : scale} · ${style.text}';

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: style.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: style.color.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(style.icon, size: 12, color: ink),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── DISTRIBUZIONE ──────────────────────────────────────────────────────────

class _DistributionCard extends StatelessWidget {
  final List<dynamic> distributions;
  final int totalPatients;

  /// Se true le barre si distribuiscono sull'altezza disponibile.
  final bool fillHeight;

  const _DistributionCard({
    required this.distributions,
    required this.totalPatients,
    this.fillHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = distributions.map(_mapValue).toList()
      ..sort((a, b) =>
          _asDouble(b['percentuale']).compareTo(_asDouble(a['percentuale'])));

    final bars = <Widget>[];
    for (var index = 0; index < sorted.length; index++) {
      if (index != 0) bars.add(const SizedBox(height: 16));
      bars.add(_DistributionBar(item: sorted[index], total: totalPatients));
    }

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment:
          fillHeight ? MainAxisAlignment.spaceEvenly : MainAxisAlignment.start,
      children: bars,
    );

    return DashboardSurfaceCard(
      semanticLabel: 'Distribuzione delle scale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionHeader(
            title: 'Distribuzione Documentazione',
            subtitle:
                'Completamento per strumento sul totale di $totalPatients utenti',
            icon: Icons.bar_chart_rounded,
          ),
          const SizedBox(height: 20),
          if (sorted.isEmpty)
            const DashboardEmptyState(
              icon: Icons.bar_chart_rounded,
              title: 'Nessuna scala compilata',
              message: 'La copertura per strumento comparirà qui.',
            )
          else if (fillHeight)
            Expanded(child: list)
          else
            list,
        ],
      ),
    );
  }
}

class _DistributionBar extends StatelessWidget {
  final Map<String, dynamic> item;
  final int total;

  const _DistributionBar({required this.item, required this.total});

  @override
  Widget build(BuildContext context) {
    final name = item['scala_nome']?.toString().trim() ?? '';
    final effectiveName = name.isEmpty ? 'Scala senza nome' : name;
    final count = _asInt(item['count']);
    final percent = _asDouble(item['percentuale']).clamp(0, 100).toDouble();

    return Semantics(
      label:
          '$effectiveName, $count utenze, ${_formatNumber(percent)} per cento',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Tooltip(
                  message: effectiveName,
                  child: Text(
                    effectiveName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: DashboardTokens.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: total > 0 ? '$count/$total' : '$count',
                      style: const TextStyle(
                        color: DashboardTokens.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(text: '   '),
                    TextSpan(
                      text: '${_formatNumber(percent)}%',
                      style: const TextStyle(
                        color: DashboardTokens.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DashboardProgressBar(
            value: percent / 100,
            color: DashboardTokens.primary,
            secondaryColor: DashboardTokens.indigo,
            height: 8,
          ),
        ],
      ),
    );
  }
}

// ─── DEMOGRAFIA ─────────────────────────────────────────────────────────────

class _DemographicsCard extends StatelessWidget {
  final Map<String, dynamic> demographics;

  const _DemographicsCard({required this.demographics});

  @override
  Widget build(BuildContext context) {
    final gender = _mapValue(demographics['sesso']);
    final ages = _mapValue(demographics['fasce_eta']);

    final genderEntries = [
      ('Donne', _asInt(gender['F']), DashboardTokens.purple),
      ('Uomini', _asInt(gender['M']), DashboardTokens.primary),
      (
        'Altro / N.S.',
        _asInt(gender['Altro/Non specificato']),
        DashboardTokens.neutral,
      ),
    ];
    final ageEntries = <MapEntry<String, int>>[
      MapEntry('0–18', _asInt(ages['0-18'])),
      MapEntry('19–35', _asInt(ages['19-35'])),
      MapEntry('36–50', _asInt(ages['36-50'])),
      MapEntry('51+', _asInt(ages['51+'])),
      MapEntry('Non specificata', _asInt(ages['Non specificata'])),
    ];
    final total = genderEntries.fold<int>(0, (sum, entry) => sum + entry.$2);
    final maxAge = ageEntries.fold<int>(
      0,
      (current, entry) => current > entry.value ? current : entry.value,
    );

    return PremiumSocioDemoCard(
      semanticLabel: 'Profilo demografico',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardSectionHeader(
            title: 'Dati Socio-Demografici',
            subtitle: 'Distribuzione per genere e fasce d’età',
            icon: Icons.groups_outlined,
            accent: DashboardTokens.purple,
            trailing: total > 0
                ? DashboardStatusPill(
                    label: '$total utenti',
                    color: DashboardTokens.slate,
                    icon: Icons.person_outline_rounded,
                  )
                : null,
          ),
          const SizedBox(height: 22),
          if (demographics.isEmpty || total == 0)
            const DashboardEmptyState(
              icon: Icons.groups_outlined,
              title: 'Dati demografici assenti',
              message:
                  'Completa le anagrafiche per visualizzare la distribuzione.',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final genderSection = _GenderSection(
                  entries: genderEntries,
                  total: total,
                );
                final ageSection = _AgeSection(
                  entries: ageEntries,
                  maxValue: maxAge,
                );
                if (constraints.maxWidth < 760) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      genderSection,
                      const SizedBox(height: 24),
                      ageSection,
                    ],
                  );
                }
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 4, child: genderSection),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 28),
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: DashboardTokens.divider,
                        ),
                      ),
                      Expanded(flex: 6, child: ageSection),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SubsectionLabel extends StatelessWidget {
  final String text;

  const _SubsectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: DashboardTokens.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _GenderSection extends StatelessWidget {
  final List<(String, int, Color)> entries;
  final int total;

  const _GenderSection({required this.entries, required this.total});

  @override
  Widget build(BuildContext context) {
    final nonZero = entries.where((entry) => entry.$2 > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SubsectionLabel('Genere'),
        const SizedBox(height: 12),
        // Barra segmentata proporzionale.
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                for (var i = 0; i < nonZero.length; i++) ...[
                  if (i != 0) const SizedBox(width: 2),
                  Expanded(
                    flex: nonZero[i].$2,
                    child: ColoredBox(color: nonZero[i].$3),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: entry.$3,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.$1,
                    style: const TextStyle(
                      color: DashboardTokens.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${entry.$2}',
                  style: const TextStyle(
                    color: DashboardTokens.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 48,
                  child: Text(
                    '${_formatNumber(total == 0 ? 0.0 : entry.$2 / total * 100)}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: DashboardTokens.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AgeSection extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final int maxValue;

  const _AgeSection({required this.entries, required this.maxValue});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SubsectionLabel('Fasce d’età'),
        const SizedBox(height: 12),
        for (var i = 0; i < entries.length; i++) ...[
          if (i != 0) const SizedBox(height: 12),
          _AgeBar(entry: entries[i], maxValue: maxValue),
        ],
      ],
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
            width: 112,
            child: Text(
              entry.key,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: DashboardTokens.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: DashboardProgressBar(
              value: fraction,
              color: DashboardTokens.purple,
              secondaryColor: DashboardTokens.auroraViolet,
              height: 8,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 28,
            child: Text(
              '${entry.value}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: DashboardTokens.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── LOADING ────────────────────────────────────────────────────────────────

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = DashboardTokens.gap;
            final width = constraints.maxWidth;
            final kpiColumns = width >= 1100 ? 3 : (width >= 600 ? 2 : 1);
            final kpiWidth = (width - gap * (kpiColumns - 1)) / kpiColumns;
            final desktop = width >= _kDesktopBreakpoint;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: List.generate(
                    3,
                    (_) => SizedBox(
                      width: kpiWidth,
                      child: const _SkeletonBox(height: 176),
                    ),
                  ),
                ),
                const SizedBox(height: gap),
                const _SkeletonBox(height: 92),
                const SizedBox(height: gap),
                if (desktop)
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Column(
                          children: [
                            _SkeletonBox(height: 250),
                            SizedBox(height: gap),
                            _SkeletonBox(height: 340),
                          ],
                        ),
                      ),
                      SizedBox(width: gap),
                      Expanded(flex: 5, child: _SkeletonBox(height: 610)),
                    ],
                  )
                else
                  const Column(
                    children: [
                      _SkeletonBox(height: 300),
                      SizedBox(height: gap),
                      _SkeletonBox(height: 360),
                    ],
                  ),
                const SizedBox(height: gap),
                const _SkeletonBox(height: 240),
              ],
            );
          },
        ),
      ),
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

// ─── HELPER ─────────────────────────────────────────────────────────────────

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
