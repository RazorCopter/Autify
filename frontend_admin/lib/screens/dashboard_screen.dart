import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shimmer/shimmer.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
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
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.verticalPadding(context),
            horizontal: ResponsiveHelper.horizontalPadding(context),
          ),
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
    final isMobile = ResponsiveHelper.isMobile(context);
    final titleSize = ResponsiveHelper.titleFontSize(context);

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Centro di Controllo',
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Stato e monitoraggio documentale',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE8EEF8), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today_outlined, color: AppTheme.primaryColor, size: 14),
                const SizedBox(width: 6),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontSize: 12,
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Centro di Controllo Documentale',
              style: TextStyle(
                fontSize: titleSize,
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
    final totalPatients = _stats?['totale_utenze'] ?? activePatients;
    final totalEvals = _stats?['totale_valutazioni_eseguite'] ?? 0;
    
    final coverage = _stats?['copertura_scale'] ?? {};
    final coveredCount = coverage['coperti_count'] ?? 0;
    final expiredCount = coverage['scaduti_count'] ?? 0;
    final coveragePercent = (coverage['coperti_percentuale'] ?? 0.0).toDouble();
    final posMancanti = coverage['pos_mancanti'] ?? 0;
    final sanMartinMancanti = coverage['san_martin_mancanti'] ?? 0;
    final sisMancanti = coverage['sis_mancanti'] ?? 0;

    final alertList = (_stats?['ultimi_alert'] as List<dynamic>?) ?? [];
    final distributions = (_stats?['distribuzione_scale'] as List<dynamic>?) ?? [];
    final trendData = (_stats?['trend_somministrazioni'] as List<dynamic>?) ?? [];
    final forecastData = (_stats?['forecast_somministrazioni'] as List<dynamic>?) ?? [];
    final demographics = (_stats?['demographics'] as Map<String, dynamic>?) ?? {};

    // Calcolo dei contatori specifici per l'AlertBar dai dati globali reali del backend
    final alertStats = _stats?['alert_stats'] ?? {};
    final scadutiCount = (alertStats['totale_scaduti'] ?? 0) as int;
    final inScadenzaCount = (alertStats['totale_in_scadenza'] ?? 0) as int;
    final maiValutatiCount = (alertStats['totale_mai_valutati'] ?? 0) as int;
    final incompleteCount = (alertStats['totale_incompleti'] ?? 0) as int;

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
                      subtitle: 'su $totalPatients utenti censiti',
                      icon: Icons.people_alt_outlined,
                      themeColor: const Color(0xFF3B82F6),
                      onTap: () => widget.onNavigate(2),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _BentoKpiCard(
                      title: 'VALUTAZIONI ATTIVE',
                      value: coveredCount.toDouble(),
                      subtitle: 'Documentazione in corso di validità',
                      icon: Icons.verified_user_outlined,
                      themeColor: const Color(0xFF10B981),
                      suffix: ' ($coveragePercent%)',
                      onTap: () => widget.onNavigate(2),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _BentoKpiCard(
                      title: 'SCALE MANCANTI',
                      value: expiredCount.toDouble(),
                      subtitle: 'Scale scadute o mai compilate',
                      icon: Icons.warning_amber_rounded,
                      themeColor: const Color(0xFFEF4444),
                      onTap: () => widget.onNavigate(2),
                      tooltip: 'Dettaglio Scale Mancanti:\n\nPOS: $posMancanti\nSan Martín: $sanMartinMancanti\nSIS: $sisMancanti',
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
                    subtitle: 'su $totalPatients utenti censiti',
                    icon: Icons.people_alt_outlined,
                    themeColor: const Color(0xFF3B82F6),
                    onTap: () => widget.onNavigate(2),
                  ),
                  const SizedBox(height: 16),
                  _BentoKpiCard(
                    title: 'VALUTAZIONI ATTIVE',
                    value: coveredCount.toDouble(),
                    subtitle: 'Documentazione in corso di validità',
                    icon: Icons.verified_user_outlined,
                    themeColor: const Color(0xFF10B981),
                    suffix: ' ($coveragePercent%)',
                    onTap: () => widget.onNavigate(2),
                  ),
                  const SizedBox(height: 16),
                  _BentoKpiCard(
                    title: 'SCALE MANCANTI',
                    value: expiredCount.toDouble(),
                    subtitle: 'Scale scadute o mai compilate',
                    icon: Icons.warning_amber_rounded,
                    themeColor: const Color(0xFFEF4444),
                    onTap: () => widget.onNavigate(2),
                    tooltip: 'Dettaglio Scale Mancanti:\n\nPOS: $posMancanti\nSan Martín: $sanMartinMancanti\nSIS: $sisMancanti',
                  ),
                ],
              ),

            const SizedBox(height: 24),
            _buildAlertBar(
              scadutiCount: scadutiCount,
              inScadenzaCount: inScadenzaCount,
              incompleteCount: incompleteCount,
              maiValutatiCount: maiValutatiCount,
            ),
            const SizedBox(height: 24),

            // Row 2: Charts (Doughnut e LineChart)
            if (isDesktop)
              SizedBox(
                height: 340,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _buildDocumentCoverageCard(coveredCount, expiredCount, coveragePercent, height: 340),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 3,
                      child: _buildDistributionCard(distributions, activePatients, height: 340),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  _buildDocumentCoverageCard(coveredCount, expiredCount, coveragePercent, height: 380),
                  const SizedBox(height: 24),
                  _buildDistributionCard(distributions, activePatients, height: 420),
                ],
              ),

            const SizedBox(height: 24),

            // Row 3: Alert list & Demographics
            if (isDesktop)
              SizedBox(
                height: 440,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 7, // 70% width
                      child: _buildAlertListCard(alertList, height: 440),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 3, // 30% width
                      child: _buildDemographicsCard(demographics, height: 440),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  _buildAlertListCard(alertList, height: 420),
                  const SizedBox(height: 24),
                  _buildDemographicsCard(demographics, height: 220),
                ],
              ),

            // rimosso riga 4 (Demographics) poichè spostato in riga 3
          ],
        );
      },
    );
  }

  // ─── ALERT BAR ─────────────────────────────────────────────────────────────
  Widget _buildAlertBar({
    required int scadutiCount,
    required int inScadenzaCount,
    required int incompleteCount,
    required int maiValutatiCount,
  }) {
    final isMobile = ResponsiveHelper.isMobile(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              children: [
                _buildAlertBarItem(
                  label: 'Valutazioni scadute',
                  count: scadutiCount,
                  color: const Color(0xFFEF4444),
                  backgroundColor: const Color(0xFFFEE2E2),
                  icon: Icons.dangerous_outlined,
                  onTap: () => widget.onNavigate(2, searchFilter: 'scaduti'),
                ),
                const SizedBox(height: 8),
                _buildAlertBarItem(
                  label: 'In scadenza',
                  count: inScadenzaCount,
                  color: const Color(0xFFF59E0B),
                  backgroundColor: const Color(0xFFFEF3C7),
                  icon: Icons.warning_amber_rounded,
                  onTap: () => widget.onNavigate(2, searchFilter: 'in scadenza'),
                ),
                const SizedBox(height: 8),
                _buildAlertBarItem(
                  label: 'Documenti incompleti',
                  count: incompleteCount,
                  color: const Color(0xFF3B82F6),
                  backgroundColor: const Color(0xFFEFF6FF),
                  icon: Icons.assignment_late_outlined,
                  onTap: () => widget.onNavigate(2, searchFilter: 'incompleti'),
                ),
                const SizedBox(height: 8),
                _buildAlertBarItem(
                  label: 'Da verificare',
                  count: maiValutatiCount,
                  color: const Color(0xFF718096),
                  backgroundColor: const Color(0xFFF1F5F9),
                  icon: Icons.help_outline_rounded,
                  onTap: () => widget.onNavigate(2, searchFilter: 'mai valutati'),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: _buildAlertBarItem(
                    label: 'Valutazioni scadute',
                    count: scadutiCount,
                    color: const Color(0xFFEF4444),
                    backgroundColor: const Color(0xFFFEE2E2),
                    icon: Icons.dangerous_outlined,
                    onTap: () => widget.onNavigate(2, searchFilter: 'scaduti'),
                  ),
                ),
                Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
                Expanded(
                  child: _buildAlertBarItem(
                    label: 'In scadenza',
                    count: inScadenzaCount,
                    color: const Color(0xFFF59E0B),
                    backgroundColor: const Color(0xFFFEF3C7),
                    icon: Icons.warning_amber_rounded,
                    onTap: () => widget.onNavigate(2, searchFilter: 'in scadenza'),
                  ),
                ),
                Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
                Expanded(
                  child: _buildAlertBarItem(
                    label: 'Documenti incompleti',
                    count: incompleteCount,
                    color: const Color(0xFF3B82F6),
                    backgroundColor: const Color(0xFFEFF6FF),
                    icon: Icons.assignment_late_outlined,
                    onTap: () => widget.onNavigate(2, searchFilter: 'incompleti'),
                  ),
                ),
                Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
                Expanded(
                  child: _buildAlertBarItem(
                    label: 'Da verificare',
                    count: maiValutatiCount,
                    color: const Color(0xFF718096),
                    backgroundColor: const Color(0xFFF1F5F9),
                    icon: Icons.help_outline_rounded,
                    onTap: () => widget.onNavigate(2, searchFilter: 'mai valutati'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAlertBarItem({
    required String label,
    required int count,
    required Color color,
    required Color backgroundColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    count.toString(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── DOCUMENT COVERAGE CARD (DONUT CHART) ──────────────────────────────────
  Widget _buildDocumentCoverageCard(int covered, int expired, double percent, {double? height}) {
    final total = covered + expired;
    return _HoverBentoCard(
      height: height ?? 380,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Copertura Documentale',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Rapporto scale valide / mancanti',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 3,
                          centerSpaceRadius: 50,
                          startDegreeOffset: -90,
                          sections: [
                            PieChartSectionData(
                              value: covered.toDouble().clamp(0.01, double.infinity),
                              color: const Color(0xFF10B981),
                              radius: 24,
                              showTitle: false,
                            ),
                            PieChartSectionData(
                              value: expired.toDouble().clamp(0.01, double.infinity),
                              color: const Color(0xFFEF4444),
                              radius: 20,
                              showTitle: false,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${percent.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF10B981),
                              letterSpacing: -0.5,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'COPERTURA',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textSecondary,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildDonutLegendItem('Valide', covered, const Color(0xFF10B981)),
                Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
                _buildDonutLegendItem('Mancanti', expired, const Color(0xFFEF4444)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDonutLegendItem(String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
            ),
            Text(
              count.toString(),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ],
    );
  }

  // ─── FORECAST CARD (PILLOLE SOVRAPPOSTE) ───────────────────────────────────


  // ─── ALERT CENTER (AZIONI URGENTI) ─────────────────────────────────────────
  Widget _buildAlertListCard(List<dynamic> alerts, {double? height}) {
    // Ordina per gravità decrescente
    final sortedAlerts = List<dynamic>.from(alerts);
    sortedAlerts.sort((a, b) {
      final isNeverA = a['stato'] == 'mai_valutato';
      final isNeverB = b['stato'] == 'mai_valutato';
      final daysA = (a['giorni_da_ultima_valutazione'] ?? 0) as int;
      final daysB = (b['giorni_da_ultima_valutazione'] ?? 0) as int;

      int scoreA = isNeverA ? 0 : (daysA > 395 ? 2 : 1);
      int scoreB = isNeverB ? 0 : (daysB > 395 ? 2 : 1);

      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // Priorità maggiore in cima (Scaduto in cima)
      }
      return daysB.compareTo(daysA); // Più giorni prima
    });

    Widget listContent;
    if (sortedAlerts.isEmpty) {
      listContent = const Center(
        child: Text(
          'Tutti gli utenti sono coperti e monitorati.',
          style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
        ),
      );
      if (height == null) {
        listContent = Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: listContent,
        );
      }
    } else {
      listContent = ListView.builder(
        shrinkWrap: height == null,
        physics: height == null ? const NeverScrollableScrollPhysics() : null,
        itemCount: sortedAlerts.length,
        itemBuilder: (context, index) {
          final item = sortedAlerts[index];
          final name = '${item['paziente_nome'] ?? ''} ${item['paziente_cognome'] ?? ''}'.trim();
          final stato = item['stato'] ?? 'scaduto';
          final days = (item['giorni_da_ultima_valutazione'] ?? 0) as int;
          final scalaNome = item['scala_nome'] ?? '';
          
          Color badgeColor;
          Color badgeBg;
          String badgeText;
          IconData leadIcon;

          if (stato == 'mai_valutato') {
            badgeColor = const Color(0xFFDC2626); // Red
            badgeBg = const Color(0xFFFEE2E2);
            badgeText = 'MAI COMPILATA';
            leadIcon = Icons.dangerous_outlined;
          } else if (stato == 'in_scadenza') {
            badgeColor = const Color(0xFFEAB308); // Amber/Arancio
            badgeBg = const Color(0xFFFEF9C3);
            badgeText = 'IN SCADENZA';
            leadIcon = Icons.timer_outlined;
          } else {
            badgeColor = const Color(0xFFDC2626); // Red
            badgeBg = const Color(0xFFFEE2E2);
            badgeText = 'SCADUTA';
            leadIcon = Icons.warning_amber_rounded;
          }

          final daysText = stato == 'mai_valutato'
              ? 'Nessuna scala $scalaNome compilata a sistema'
              : 'Ultima compilazione $scalaNome $days giorni fa';

          return TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: Duration(milliseconds: (300 + (index * 100)).toInt()),
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
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: badgeColor, width: 3),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    onTap: () {
                      widget.onNavigate(2, searchFilter: item['paziente_cognome']);
                    },
                    leading: CircleAvatar(
                      backgroundColor: badgeColor.withValues(alpha: 0.10),
                      radius: 18,
                      child: Text(
                        _getInitials(name),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: badgeColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded, size: 16, color: AppTheme.primaryColor),
                          tooltip: 'Gestisci utente',
                          onPressed: () {
                            widget.onNavigate(2, searchFilter: item['paziente_cognome']);
                          },
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return _HoverBentoCard(
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Alert Center: Azioni Richieste Urgenti',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${sortedAlerts.length} Criticità',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFDC2626)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Utenti che necessitano di una nuova valutazione o rinnovo',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 18),
            height != null ? Expanded(child: listContent) : listContent,
          ],
        ),
      ),
    );
  }

  // ─── HELPER: Iniziali utente ──────────────────────────────────────────────
  String _getInitials(String fullName) {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  // ─── DEMOGRAPHICS CARD ──────────────────────────────────────────────────
  Widget _buildDemographicsCard(Map<String, dynamic> demographics, {double? height}) {
    if (demographics.isEmpty) return const SizedBox();
    
    final sesso = demographics['sesso'] as Map<String, dynamic>? ?? {};
    final fasceEta = demographics['fasce_eta'] as Map<String, dynamic>? ?? {};
    
    final men = (sesso['M'] ?? 0) as int;
    final women = (sesso['F'] ?? 0) as int;
    final total = men + women;
    
    // Calcola il massimo per le barre proporzionali delle fasce d'età
    final ageValues = [
      (fasceEta['0-18'] ?? 0) as int,
      (fasceEta['19-35'] ?? 0) as int,
      (fasceEta['36-50'] ?? 0) as int,
      (fasceEta['51+'] ?? 0) as int,
    ];
    final maxAge = ageValues.reduce((a, b) => a > b ? a : b).clamp(1, 9999);
    
    return _HoverBentoCard(
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Dati Socio-Demografici',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Distribuzione per genere e fasce d\'età ($total utenti)',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Genere: Mini PieChart ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 22,
                            startDegreeOffset: -90,
                            sections: [
                              PieChartSectionData(
                                value: men.toDouble().clamp(0.01, double.infinity),
                                color: const Color(0xFF3B82F6),
                                radius: 14,
                                showTitle: false,
                              ),
                              PieChartSectionData(
                                value: women.toDouble().clamp(0.01, double.infinity),
                                color: const Color(0xFFEC4899),
                                radius: 14,
                                showTitle: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFF3B82F6), borderRadius: BorderRadius.circular(3))),
                              const SizedBox(width: 6),
                              Text('Uomini $men', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 10, height: 10, decoration: BoxDecoration(color: const Color(0xFFEC4899), borderRadius: BorderRadius.circular(3))),
                              const SizedBox(width: 6),
                              Text('Donne $women', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // ── Fasce d'Età: Barre proporzionali ──
                  _buildAgeBar('0-18', ageValues[0], maxAge),
                  const SizedBox(height: 8),
                  _buildAgeBar('19-35', ageValues[1], maxAge),
                  const SizedBox(height: 8),
                  _buildAgeBar('36-50', ageValues[2], maxAge),
                  const SizedBox(height: 8),
                  _buildAgeBar('51+', ageValues[3], maxAge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgeBar(String label, int count, int maxCount) {
    final barFraction = maxCount > 0 ? (count / maxCount).clamp(0.05, 1.0) : 0.05;
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: barFraction,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 20,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
          ),
        ),
      ],
    );
  }

  // ─── DISTRIBUTION CARD ─────────────────────────────────────────────────────
  Widget _buildDistributionCard(List<dynamic> distributions, int totalPatients, {double? height}) {
    // Ordina una copia locale delle scale dalla copertura più bassa (più critica) alla più alta
    final sortedDistributions = List<dynamic>.from(distributions);
    sortedDistributions.sort((a, b) {
      final countA = (a['count'] ?? 0) as int;
      final countB = (b['count'] ?? 0) as int;
      final percentA = totalPatients > 0 ? (countA / totalPatients) : 0.0;
      final percentB = totalPatients > 0 ? (countB / totalPatients) : 0.0;
      return percentA.compareTo(percentB);
    });

    return _HoverBentoCard(
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
              child: sortedDistributions.isEmpty
                ? const Center(
                    child: Text(
                      'Nessuna scala ancora compilata.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        itemCount: sortedDistributions.length,
                        padding: const EdgeInsets.only(bottom: 20),
                        itemBuilder: (context, index) {
                          final item = sortedDistributions[index];
                          final name = item['scala_nome'] ?? '';
                          final count = (item['count'] ?? 0) as int;
                          
                          // Calcola la percentuale client-side
                          final double percent = totalPatients > 0
                              ? double.parse((count / totalPatients * 100).toStringAsFixed(1))
                              : 0.0;

                          // Colore progress bar semantico (Rosso 0-20%, Arancio 21-70%, Verde 71-100%)
                          Color color;
                          if (percent <= 20.0) {
                            color = const Color(0xFFEF4444);
                          } else if (percent <= 70.0) {
                            color = const Color(0xFFF59E0B);
                          } else {
                            color = const Color(0xFF10B981);
                          }

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
                      // Fade gradient in basso per indicare scrollabilità
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 28,
                        child: IgnorePointer(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
  final Color themeColor;
  final String suffix;
  final VoidCallback onTap;
  final String? tooltip;
  final String? trendText;
  final bool isTrendPositive;

  const _BentoKpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.themeColor,
    this.suffix = '',
    required this.onTap,
    this.tooltip,
    this.trendText,
    this.isTrendPositive = true,
  });

  @override
  State<_BentoKpiCard> createState() => _BentoKpiCardState();
}

class _BentoKpiCardState extends State<_BentoKpiCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Widget cardContent = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0.0, _isHovered ? -4.0 : 0.0, 0.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isHovered ? widget.themeColor.withValues(alpha: 0.35) : const Color(0xFFE2E8F0),
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
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            splashColor: widget.themeColor.withValues(alpha: 0.05),
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
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.textSecondary,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            TweenAnimationBuilder<double>(
                              tween: Tween<double>(begin: 0, end: widget.value),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeOutCubic,
                              builder: (context, val, child) {
                                return Text(
                                  '${val.toInt()}${widget.suffix}',
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.textPrimary,
                                    height: 1.0,
                                  ),
                                );
                              },
                            ),
                            if (widget.trendText != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: widget.isTrendPositive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      widget.isTrendPositive ? Icons.arrow_upward : Icons.arrow_downward,
                                      size: 10,
                                      color: widget.isTrendPositive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      widget.trendText!,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: widget.isTrendPositive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.themeColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.icon,
                      color: widget.themeColor,
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

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        triggerMode: TooltipTriggerMode.tap,
        child: cardContent,
      );
    }

    return cardContent;
  }
}
