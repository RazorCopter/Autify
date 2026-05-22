import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shimmer/shimmer.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends StatefulWidget {
  final Function(int tabIndex, {String? searchFilter}) onNavigate;

  const DashboardScreen({
    super.key,
    required this.onNavigate,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _apiService.getDashboardStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadStats,
        color: AppTheme.primaryColor,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              if (_isLoading)
                _buildShimmerSkeleton()
              else if (_stats == null)
                _buildErrorWidget()
              else
                _buildBentoGrid(),
            ],
          ),
        ),
      ),
    );
  }

  // ─── HEADER ───────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final now = DateTime.now();
    final months = [
      'Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
      'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre'
    ];
    final formattedDate = '${now.day} ${months[now.month - 1]} ${now.year}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Centro di Controllo Documentale',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Stato e monitoraggio della documentazione',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EEF8), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, color: AppTheme.primaryColor, size: 16),
              const SizedBox(width: 8),
              Text(
                formattedDate,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── ERROR STATE ──────────────────────────────────────────────────────────
  Widget _buildErrorWidget() {
    return Center(
      child: Card(
        margin: const EdgeInsets.only(top: 60),
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppTheme.errorColor),
              const SizedBox(height: 16),
              const Text(
                'Errore nel caricamento dei dati',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                'Assicurati che il server backend sia attivo.',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadStats,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Riprova'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── SHIMMER SKELETON ──────────────────────────────────────────────────────
  Widget _buildShimmerSkeleton() {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE2E8F0),
      highlightColor: const Color(0xFFEDF2F7),
      child: Column(
        children: [
          // Top Row KPIs
          Row(
            children: List.generate(3, (i) => Expanded(
              child: Container(
                height: 140,
                margin: EdgeInsets.only(right: i == 2 ? 0 : 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            )),
          ),
          const SizedBox(height: 24),
          // Middle Row Charts
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  height: 380,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 3,
                child: Container(
                  height: 380,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Bottom Row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  height: 320,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
                child: Container(
                  height: 320,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── BENTO GRID ────────────────────────────────────────────────────────────
  Widget _buildBentoGrid() {
    final activePatients = _stats?['totale_utenze_attive'] ?? 0;
    final totalEvals = _stats?['totale_valutazioni_eseguite'] ?? 0;
    
    final coverage = _stats?['copertura_scale'] ?? {};
    final coveredCount = coverage['coperti_count'] ?? 0;
    final expiredCount = coverage['scaduti_count'] ?? 0;
    final coveragePercent = (coverage['coperti_percentuale'] ?? 0.0).toDouble();

    final alertList = (_stats?['ultimi_alert'] as List<dynamic>?) ?? [];
    final distributions = (_stats?['distribuzione_scale'] as List<dynamic>?) ?? [];
    final trendData = (_stats?['trend_somministrazioni'] as List<dynamic>?) ?? [];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 992;
        final isTablet = constraints.maxWidth > 650 && constraints.maxWidth <= 992;

        return Column(
          children: [
            // Row 1: KPI Cards
            if (isDesktop || isTablet)
              Row(
                children: [
                  Expanded(
                    child: _BentoKpiCard(
                      title: 'UTENZE ATTIVE',
                      value: activePatients.toDouble(),
                      subtitle: 'Utenti totali censiti',
                      icon: Icons.people_alt_outlined,
                      gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                      onTap: () => widget.onNavigate(2), // Vai a Utenza
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _BentoKpiCard(
                      title: 'VALUTAZIONI ATTIVE',
                      value: coveredCount.toDouble(),
                      subtitle: 'Documentazione in corso di validità',
                      icon: Icons.verified_user_outlined,
                      gradientColors: const [Color(0xFF065F46), Color(0xFF10B981)],
                      suffix: ' ($coveragePercent%)',
                      onTap: () => widget.onNavigate(2), // Vai a Utenza
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _BentoKpiCard(
                      title: 'DA VALUTARE / SCADUTI',
                      value: expiredCount.toDouble(),
                      subtitle: 'Documentazione scaduta o assente',
                      icon: Icons.warning_amber_rounded,
                      gradientColors: const [Color(0xFF9A3412), Color(0xFFF97316)],
                      onTap: () => widget.onNavigate(2), // Vai a Utenza
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _BentoKpiCard(
                    title: 'UTENZE ATTIVE',
                    value: activePatients.toDouble(),
                    subtitle: 'Utenti totali censiti',
                    icon: Icons.people_alt_outlined,
                    gradientColors: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                    onTap: () => widget.onNavigate(2),
                  ),
                  const SizedBox(height: 16),
                  _BentoKpiCard(
                    title: 'VALUTAZIONI ATTIVE',
                    value: coveredCount.toDouble(),
                    subtitle: 'Documentazione in corso di validità',
                    icon: Icons.verified_user_outlined,
                    gradientColors: const [Color(0xFF065F46), Color(0xFF10B981)],
                    suffix: ' ($coveragePercent%)',
                    onTap: () => widget.onNavigate(2),
                  ),
                  const SizedBox(height: 16),
                  _BentoKpiCard(
                    title: 'DA VALUTARE / SCADUTI',
                    value: expiredCount.toDouble(),
                    subtitle: 'Documentazione scaduta o assente',
                    icon: Icons.warning_amber_rounded,
                    gradientColors: const [Color(0xFF9A3412), Color(0xFFF97316)],
                    onTap: () => widget.onNavigate(2),
                  ),
                ],
              ),

            const SizedBox(height: 24),

            // Row 2: Charts (Doughnut e BarChart)
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildDoughnutChartCard(coveredCount, expiredCount, coveragePercent),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: _buildBarChartCard(trendData),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildDoughnutChartCard(coveredCount, expiredCount, coveragePercent),
                  const SizedBox(height: 24),
                  _buildBarChartCard(trendData),
                ],
              ),

            const SizedBox(height: 24),

            // Row 3: Alert list & Distribution
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildAlertListCard(alertList),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 2,
                    child: _buildDistributionCard(distributions, activePatients),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildAlertListCard(alertList),
                  const SizedBox(height: 24),
                  _buildDistributionCard(distributions, activePatients),
                ],
              ),
          ],
        );
      },
    );
  }

  // ─── DOUGHNUT CHART CARD ───────────────────────────────────────────────────
  Widget _buildDoughnutChartCard(int covered, int expired, double percent) {
    final hasData = (covered + expired) > 0;
    return _HoverBentoCard(
      height: 380,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Stato di Copertura Documentale',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Percentuale di utenti in corso di validità',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (hasData)
                    PieChart(
                      PieChartData(
                        sectionsSpace: 4,
                        centerSpaceRadius: 60,
                        startDegreeOffset: -90,
                        sections: [
                          PieChartSectionData(
                            color: const Color(0xFF10B981),
                            value: covered.toDouble(),
                            title: '',
                            radius: 20,
                          ),
                          PieChartSectionData(
                            color: const Color(0xFFF97316),
                            value: expired.toDouble(),
                            title: '',
                            radius: 20,
                          ),
                        ],
                      ),
                    )
                  else
                    PieChart(
                      PieChartData(
                        sectionsSpace: 0,
                        centerSpaceRadius: 60,
                        sections: [
                          PieChartSectionData(
                            color: Colors.grey.shade200,
                            value: 100,
                            title: '',
                            radius: 12,
                          ),
                        ],
                      ),
                    ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$percent%',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'COPERTURA',
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildChartLegendItem(color: const Color(0xFF10B981), label: 'Coperti ($covered)'),
                const SizedBox(width: 24),
                _buildChartLegendItem(color: const Color(0xFFF97316), label: 'Da Valutare ($expired)'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartLegendItem({required Color color, required String label}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ],
    );
  }

  // ─── BAR CHART CARD ────────────────────────────────────────────────────────
  Widget _buildBarChartCard(List<dynamic> trend) {
    return _HoverBentoCard(
      height: 380,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Attività Ultime Somministrazioni',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Valutazioni multidimensionali eseguite negli ultimi 6 mesi',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _getMaxY(trend),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => AppTheme.textPrimary,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${rod.toY.toInt()} Valutazioni',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx >= 0 && idx < trend.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                trend[idx]['mese'] ?? '',
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) => const FlLine(
                      color: Color(0xFFE2E8F0),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(trend.length, (index) {
                    final item = trend[index];
                    final count = (item['count'] ?? 0).toDouble();
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: count,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          width: 18,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: _getMaxY(trend),
                            color: const Color(0xFFF1F5F9),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _getMaxY(List<dynamic> trend) {
    double maxVal = 5.0;
    for (final item in trend) {
      final val = (item['count'] ?? 0).toDouble();
      if (val > maxVal) {
        maxVal = val;
      }
    }
    return maxVal + 1.0;
  }

  // ─── ALERT LIST CARD ───────────────────────────────────────────────────────
  Widget _buildAlertListCard(List<dynamic> alerts) {
    return _HoverBentoCard(
      height: 360,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Azioni Richieste Urgenti',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${alerts.length} Alert',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppTheme.errorColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Utenti che necessitano di somministrazione della scala',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: alerts.isEmpty
                ? const Center(
                    child: Text(
                      'Tutti gli utenti sono coperti e monitorati.',
                      style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: alerts.length,
                    itemBuilder: (context, index) {
                      final item = alerts[index];
                      final name = '${item['paziente_nome'] ?? ''} ${item['paziente_cognome'] ?? ''}'.trim();
                      final isNever = item['stato'] == 'mai_valutato';
                      final days = item['giorni_da_ultima_valutazione'];
                      final daysText = isNever
                          ? 'Mai valutato'
                          : '$days giorni fa (${item['scala_nome']})';

                      return TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: Duration(milliseconds: 300 + (index * 100)),
                        builder: (context, animValue, child) {
                          return Opacity(
                            opacity: animValue,
                            child: Transform.translate(
                              offset: Offset(0, 20 * (1 - animValue)),
                              child: child,
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                          ),
                          child: ListTile(
                            dense: true,
                            onTap: () {
                              // Naviga alla lista pazienti con il filtro di ricerca sul cognome!
                              widget.onNavigate(2, searchFilter: item['paziente_cognome']);
                            },
                            leading: CircleAvatar(
                              backgroundColor: (isNever ? AppTheme.errorColor : AppTheme.secondaryColor).withValues(alpha: 0.15),
                              radius: 16,
                              child: Icon(
                                isNever ? Icons.person_off_outlined : Icons.timer_outlined,
                                color: isNever ? AppTheme.errorColor : AppTheme.secondaryColor,
                                size: 16,
                              ),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                            ),
                            subtitle: Text(
                              daysText,
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (isNever ? AppTheme.errorColor : AppTheme.secondaryColor).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isNever ? 'MAI' : 'SCADUTO',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isNever ? AppTheme.errorColor : AppTheme.secondaryColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── DISTRIBUTION CARD ─────────────────────────────────────────────────────
  Widget _buildDistributionCard(List<dynamic> distributions, int totalPatients) {
    return _HoverBentoCard(
      height: 360,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Distribuzione Documentazione',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Completamento rispetto al totale di $totalPatients utenti',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: distributions.isEmpty
                ? const Center(
                    child: Text(
                      'Nessuna scala somministrata registrata.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: distributions.length,
                    itemBuilder: (context, index) {
                      final item = distributions[index];
                      final name = item['scala_nome'] ?? '';
                      final count = (item['count'] ?? 0) as int;
                      final color = AppTheme.puzzleColorAt(index);
                      // Calcola la percentuale client-side per garantire coerenza con totalPatients
                      final double percent = totalPatients > 0
                          ? double.parse((count / totalPatients * 100).toStringAsFixed(1))
                          : 0.0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '$count / $totalPatients ($percent%)',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: totalPatients > 0 ? (percent / 100).clamp(0.0, 1.0) : 0,
                                backgroundColor: const Color(0xFFF1F5F9),
                                valueColor: AlwaysStoppedAnimation<Color>(color),
                                minHeight: 8,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── CARD COMPONENT WITH HOVER EFFECT ────────────────────────────────────────
class _HoverBentoCard extends StatefulWidget {
  final Widget child;
  final double? height;

  const _HoverBentoCard({
    required this.child,
    this.height,
  });

  @override
  State<_HoverBentoCard> createState() => _HoverBentoCardState();
}

class _HoverBentoCardState extends State<_HoverBentoCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        height: widget.height,
        transform: Matrix4.translationValues(0.0, _isHovered ? -4.0 : 0.0, 0.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isHovered ? AppTheme.primaryColor.withValues(alpha: 0.3) : const Color(0xFFE8EEF8),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _isHovered ? 0.06 : 0.02),
              blurRadius: _isHovered ? 16 : 8,
              offset: Offset(0, _isHovered ? 8 : 4),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

// ─── KPI BENTO CARD WITH TWEEN ANIMATION ─────────────────────────────────────
class _BentoKpiCard extends StatefulWidget {
  final String title;
  final double value;
  final String subtitle;
  final IconData icon;
  final List<Color> gradientColors;
  final String suffix;
  final VoidCallback onTap;

  const _BentoKpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    this.suffix = '',
    required this.onTap,
  });

  @override
  State<_BentoKpiCard> createState() => _BentoKpiCardState();
}

class _BentoKpiCardState extends State<_BentoKpiCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0.0, _isHovered ? -4.0 : 0.0, 0.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: widget.gradientColors.last.withValues(alpha: _isHovered ? 0.28 : 0.15),
              blurRadius: _isHovered ? 18 : 10,
              offset: Offset(0, _isHovered ? 8 : 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            splashColor: Colors.white.withValues(alpha: 0.1),
            hoverColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white.withValues(alpha: 0.7),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: widget.value),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutCubic,
                          builder: (context, val, child) {
                            return Text(
                              '${val.toInt()}${widget.suffix}',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.icon,
                      color: Colors.white,
                      size: 28,
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
