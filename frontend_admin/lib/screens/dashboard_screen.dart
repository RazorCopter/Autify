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
    final demographics = (_stats?['demographics'] as Map<String, dynamic>?) ?? {};

    // Calcolo dei contatori specifici per l'AlertBar
    final scadutiCount = alertList.where((item) {
      final isNever = item['stato'] == 'mai_valutato';
      final days = (item['giorni_da_ultima_valutazione'] ?? 0) as int;
      return !isNever && days > 395;
    }).length;

    final inScadenzaCount = alertList.where((item) {
      final isNever = item['stato'] == 'mai_valutato';
      final days = (item['giorni_da_ultima_valutazione'] ?? 0) as int;
      return !isNever && days <= 395;
    }).length;

    final maiValutatiCount = alertList.where((item) => item['stato'] == 'mai_valutato').length;
    final incompleteCount = (posMancanti as int) + (sanMartinMancanti as int) + (sisMancanti as int);

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
                      trendText: '+1',
                      isTrendPositive: true,
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
                      themeColor: const Color(0xFF10B981),
                      trendText: '+5.2%',
                      isTrendPositive: true,
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
                      themeColor: const Color(0xFFEF4444),
                      trendText: '-2',
                      isTrendPositive: true,
                      onTap: () => widget.onNavigate(2), // Vai a Utenza
                      tooltip: 'Scale Mancanti o Scadute:\n\nPOS: $posMancanti\nSan Martín: $sanMartinMancanti\nSIS: $sisMancanti',
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
                    trendText: '+1',
                    isTrendPositive: true,
                    onTap: () => widget.onNavigate(2),
                  ),
                  const SizedBox(height: 16),
                  _BentoKpiCard(
                    title: 'VALUTAZIONI ATTIVE',
                    value: coveredCount.toDouble(),
                    subtitle: 'Documentazione in corso di validità',
                    icon: Icons.verified_user_outlined,
                    themeColor: const Color(0xFF10B981),
                    trendText: '+5.2%',
                    isTrendPositive: true,
                    suffix: ' ($coveragePercent%)',
                    onTap: () => widget.onNavigate(2),
                  ),
                  const SizedBox(height: 16),
                  _BentoKpiCard(
                    title: 'DA VALUTARE / SCADUTI',
                    value: expiredCount.toDouble(),
                    subtitle: 'Documentazione scaduta o assente',
                    icon: Icons.warning_amber_rounded,
                    themeColor: const Color(0xFFEF4444),
                    trendText: '-2',
                    isTrendPositive: true,
                    onTap: () => widget.onNavigate(2),
                    tooltip: 'Scale Mancanti o Scadute:\n\nPOS: $posMancanti\nSan Martín: $sanMartinMancanti\nSIS: $sisMancanti',
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildDocumentCoverageCard(coveredCount, expiredCount, coveragePercent),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: _buildLineChartCard(trendData),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildDocumentCoverageCard(coveredCount, expiredCount, coveragePercent),
                  const SizedBox(height: 24),
                  _buildLineChartCard(trendData),
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

            const SizedBox(height: 24),

            // Row 4: Demographics
            _buildDemographicsCard(demographics),
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

  // ─── DOCUMENT COVERAGE CARD ────────────────────────────────────────────────
  Widget _buildDocumentCoverageCard(int covered, int expired, double percent) {
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
            const Spacer(),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$percent%',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF10B981),
                      letterSpacing: -1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'COPERTURA TOTALE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0.0, 1.0),
                backgroundColor: const Color(0xFFF1F5F9),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                minHeight: 12,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        'Documentazioni Valide',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        covered.toString(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  Container(width: 1, height: 28, color: const Color(0xFFE2E8F0)),
                  Column(
                    children: [
                      const Text(
                        'Documentazioni Mancanti',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        expired.toString(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── LINE CHART CARD ───────────────────────────────────────────────────────
  Widget _buildLineChartCard(List<dynamic> trend) {
    final spots = List.generate(trend.length, (index) {
      final item = trend[index];
      final count = (item['count'] ?? 0).toDouble();
      return FlSpot(index.toDouble(), count);
    });

    final maxY = _getMaxY(trend);

    String trendSub = 'Stabile';
    bool isTrendUp = true;
    if (trend.length >= 2) {
      final lastVal = (trend[trend.length - 1]['count'] ?? 0) as int;
      final prevVal = (trend[trend.length - 2]['count'] ?? 0) as int;
      final diff = lastVal - prevVal;
      if (diff > 0) {
        trendSub = '+$diff vs mese prec.';
        isTrendUp = true;
      } else if (diff < 0) {
        trendSub = '$diff vs mese prec.';
        isTrendUp = false;
      } else {
        trendSub = 'Stabile';
        isTrendUp = true;
      }
    }

    return _HoverBentoCard(
      height: 380,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    const Text(
                      'Attività Redazione Documentazione',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                    ),
                    if (trend.length >= 2)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isTrendUp ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isTrendUp ? Icons.trending_up : Icons.trending_down,
                              size: 14,
                              color: isTrendUp ? const Color(0xFF059669) : const Color(0xFFDC2626),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              trendSub,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isTrendUp ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Valutazioni multidimensionali eseguite negli ultimi 6 mesi',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Expanded(
              child: LineChart(
                LineChartData(
                  maxY: maxY,
                  minY: 0,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => AppTheme.textPrimary,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          return LineTooltipItem(
                            '${spot.y.toInt()} Valutazioni',
                            const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          );
                        }).toList();
                      },
                    ),
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
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: trend.length <= 6
                            ? 1.0
                            : (trend.length / 5).ceilToDouble(),
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx >= 0 && idx < trend.length) {
                            final rawMonth = trend[idx]['mese'] ?? '';
                            final parts = rawMonth.trim().split(' ');
                            String shortMonth = parts.isNotEmpty ? parts.first : '';
                            if (shortMonth.length > 3) {
                              shortMonth = shortMonth.substring(0, 3);
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                shortMonth,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
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
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: const Color(0xFF2563EB),
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF2563EB).withValues(alpha: 0.2),
                            const Color(0xFF2563EB).withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
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

  // ─── ALERT CENTER (AZIONI URGENTI) ─────────────────────────────────────────
  Widget _buildAlertListCard(List<dynamic> alerts) {
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

    return _HoverBentoCard(
      height: 420,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            Expanded(
              child: sortedAlerts.isEmpty
                ? const Center(
                    child: Text(
                      'Tutti gli utenti sono coperti e monitorati.',
                      style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  )
                : ListView.builder(
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
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFF1F5F9)),
                          ),
                          child: ListTile(
                            dense: true,
                            onTap: () {
                              widget.onNavigate(2, searchFilter: item['paziente_cognome']);
                            },
                            leading: CircleAvatar(
                              backgroundColor: badgeColor.withValues(alpha: 0.12),
                              radius: 16,
                              child: Icon(
                                leadIcon,
                                color: badgeColor,
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
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── DEMOGRAPHICS CARD ──────────────────────────────────────────────────
  Widget _buildDemographicsCard(Map<String, dynamic> demographics) {
    if (demographics.isEmpty) return const SizedBox();
    
    final sesso = demographics['sesso'] as Map<String, dynamic>? ?? {};
    final fasceEta = demographics['fasce_eta'] as Map<String, dynamic>? ?? {};
    
    final men = (sesso['M'] ?? 0) as int;
    final women = (sesso['F'] ?? 0) as int;
    final total = men + women;
    
    final double menPercent = total > 0 ? (men / total) : 0.5;
    final double womenPercent = total > 0 ? (women / total) : 0.5;
    
    return _HoverBentoCard(
      height: 220,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dati Socio-Demografici',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Distribuzione per genere e fasce d\'età degli utenti attivi',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Row(
                children: [
                  // Genere (progress bar orizzontale compatta)
                  Expanded(
                    flex: 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.man, color: Colors.blue, size: 18),
                                const SizedBox(width: 4),
                                Text('Uomini ($men)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                              ],
                            ),
                            Row(
                              children: [
                                Text('Donne ($women)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                const SizedBox(width: 4),
                                const Icon(Icons.woman, color: Colors.pink, size: 18),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            height: 10,
                            width: double.infinity,
                            child: Row(
                              children: [
                                Expanded(
                                  flex: (menPercent * 100).toInt().clamp(1, 99),
                                  child: Container(color: Colors.blue.shade400),
                                ),
                                Expanded(
                                  flex: (womenPercent * 100).toInt().clamp(1, 99),
                                  child: Container(color: Colors.pink.shade300),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: Text(
                            'Totale utenti attivi: $total',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, color: const Color(0xFFE2E8F0), margin: const EdgeInsets.symmetric(horizontal: 24)),
                  // Età (layout orizzontale compatto a griglia)
                  Expanded(
                    flex: 1,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildAgeRow('0-18 anni', fasceEta['0-18'] ?? 0)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildAgeRow('19-35 anni', fasceEta['19-35'] ?? 0)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildAgeRow('36-50 anni', fasceEta['36-50'] ?? 0)),
                            const SizedBox(width: 16),
                            Expanded(child: _buildAgeRow('51+ anni', fasceEta['51+'] ?? 0)),
                          ],
                        ),
                      ],
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

  Widget _buildAgeRow(String label, int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
          ),
        ),
      ],
    );
  }

  // ─── DISTRIBUTION CARD ─────────────────────────────────────────────────────
  Widget _buildDistributionCard(List<dynamic> distributions, int totalPatients) {
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
      height: 420,
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
              child: sortedDistributions.isEmpty
                ? const Center(
                    child: Text(
                      'Nessuna scala ancora compilata.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: sortedDistributions.length,
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
                        color = const Color(0xFFEF4444); // Rosso Premium
                      } else if (percent <= 70.0) {
                        color = const Color(0xFFF59E0B); // Arancio/Amber
                      } else {
                        color = const Color(0xFF10B981); // Verde
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
