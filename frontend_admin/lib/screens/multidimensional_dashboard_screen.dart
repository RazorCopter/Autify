import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/patient_model.dart';
import '../models/evaluation_model.dart';
import '../models/scale_model.dart';
import '../services/api_service.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';
import 'evaluation_detail_screen.dart';
import 'settings_screen.dart';
import 'package:fl_chart/fl_chart.dart';

class MultidimensionalDashboardScreen extends StatefulWidget {
  final PatientModel patient;

  const MultidimensionalDashboardScreen({super.key, required this.patient});

  @override
  State<MultidimensionalDashboardScreen> createState() => _MultidimensionalDashboardScreenState();
}

class _MultidimensionalDashboardScreenState extends State<MultidimensionalDashboardScreen> {
  final ApiService _apiService = ApiService();
  final GeminiService _geminiService = GeminiService();

  bool _isLoading = true;
  bool _isAnalyzing = false;
  bool _isCompareMode = false;

  String? _geminiKey;
  String _geminiModel = 'gemini-1.5-pro';

  List<ScaleModel> _availableScales = [];
  Map<String, AggregatedEvaluation> _latestEvaluations = {};
  Map<String, PsychometricAnalysis?> _analyses = {};
  String? _aiReport;
  String? _aiError;

  static const List<Color> _domainColors = [
    Color(0xFF60A5FA), Color(0xFFF59E0B), Color(0xFF34D399), Color(0xFFA78BFA),
    Color(0xFFF87171), Color(0xFF38BDF8), Color(0xFF86EFAC), Color(0xFFFB923C),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int? _calculateAge() {
    if (widget.patient.dataNascita == null) return null;
    try {
      final dob = DateTime.parse(widget.patient.dataNascita!);
      final now = DateTime.now();
      int age = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // 1. Carica configurazione AI
    final settings = await _apiService.getGeminiSettings();
    _geminiKey = settings['key'];
    _geminiModel = settings['model'] ?? 'gemini-1.5-pro';

    // 2. Carica scale disponibili
    _availableScales = await _apiService.getScales();

    // 3. Carica ultima valutazione + analisi psicometrica per ogni scala
    for (final scale in _availableScales) {
      final history = await _apiService.getAggregatedEvaluationHistory(widget.patient.id, scale.id);
      if (history.isNotEmpty) {
        history.sort((a, b) => b.dataCompilazione.compareTo(a.dataCompilazione));
        _latestEvaluations[scale.id] = history.first;
        // Carica analisi psicometrica
        try {
          final analysis = await _apiService.getEvaluationAnalysis(history.first.idValutazione);
          _analyses[scale.id] = analysis;
        } catch (_) {
          _analyses[scale.id] = null;
        }
      }
    }

    setState(() => _isLoading = false);
  }

  bool _isSanMartinScale(String scaleId, [String? scaleName]) {
    String normalize(String s) {
      return s.toLowerCase()
          .replaceAll(' ', '')
          .replaceAll('-', '')
          .replaceAll('_', '')
          .replaceAll('à', 'a')
          .replaceAll('á', 'a')
          .replaceAll('è', 'e')
          .replaceAll('é', 'e')
          .replaceAll('ì', 'i')
          .replaceAll('í', 'i')
          .replaceAll('ò', 'o')
          .replaceAll('ó', 'o')
          .replaceAll('ù', 'u')
          .replaceAll('ú', 'u');
    }
    final normalizedId = normalize(scaleId);
    final normalizedName = normalize(scaleName ?? '');
    return normalizedId.contains('sanmartin') ||
        normalizedId.contains('martin') ||
        normalizedName.contains('sanmartin') ||
        normalizedName.contains('martin');
  }

  Future<void> _runAiAnalysis() async {
    if (_geminiKey == null || _geminiKey!.isEmpty || _geminiKey == '***-HIDDEN') {
      setState(() => _aiError = 'Chiave API Gemini mancante. Configurala in Impostazioni.');
      return;
    }

    if (_latestEvaluations.isEmpty) {
      setState(() => _aiError = 'Nessuna valutazione disponibile per l\'analisi.');
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _aiError = null;
      _aiReport = null;
    });

    try {
      final report = await _geminiService.analyzePatientData(
        widget.patient,
        _latestEvaluations.values.toList(),
        _geminiKey!,
        _geminiModel,
      );
      setState(() {
        _aiReport = report;
        _isAnalyzing = false;
      });
    } catch (e) {
      setState(() {
        _aiError = 'Errore durante l\'analisi: $e';
        _isAnalyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('Analisi Utente', style: TextStyle(fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
              Tab(icon: Icon(Icons.psychology_outlined), text: 'Analisi IA'),
            ],
            indicatorColor: AppTheme.primaryColor,
            labelColor: AppTheme.primaryColor,
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildOverviewTab(),
                  _buildAiTab(),
                ],
              ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TAB 1: OVERVIEW
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildOverviewTab() {
    AggregatedEvaluation? posEval;
    AggregatedEvaluation? smEval;
    ScaleModel? posScale;
    ScaleModel? smScale;

    for (final scale in _availableScales) {
      if (!_latestEvaluations.containsKey(scale.id)) continue;
      final isSM = _isSanMartinScale(scale.id, scale.nome);
      if (isSM) {
        smEval = _latestEvaluations[scale.id];
        smScale = scale;
      } else {
        posEval = _latestEvaluations[scale.id];
        posScale = scale;
      }
    }

    final bool canCompare = posEval != null && smEval != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Patient Header Card ──────────────────────────────────────────
          _buildPatientHeader(),
          const SizedBox(height: 28),

          if (_latestEvaluations.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(48.0),
                child: Column(
                  children: [
                    Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade300),
                    const SizedBox(height: 16),
                    const Text('Nessuna valutazione compilata per questo utente.',
                      style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            )
          else ...[
            // ── Compare Toggle ──
            _buildCompareToggle(canCompare),
            const SizedBox(height: 24),

            // ── Scale cards or Unified Comparison ──
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.0, 0.04),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _isCompareMode && canCompare
                  ? _buildComparePanel(posEval!, smEval!)
                  : LayoutBuilder(
                      key: const ValueKey('standard_panels'),
                      builder: (context, constraints) {
                        final availableCards = _availableScales
                            .where((scale) => _latestEvaluations.containsKey(scale.id))
                            .toList();

                        if (constraints.maxWidth > 800 && availableCards.length >= 2) {
                          // Side by side - equal height stretching
                          final cards = availableCards.map((scale) => _buildScalePanel(scale, useExpanded: true)).toList();
                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: cards.map((c) => Expanded(child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: c,
                              ))).toList(),
                            ),
                          );
                        }
                        // Stacked - mobile/narrow screen view
                        final cards = availableCards.map((scale) => _buildScalePanel(scale, useExpanded: false)).toList();
                        return Column(
                          children: cards.map((c) => Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: c,
                          )).toList(),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompareToggle(bool canCompare) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EEF8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.compare_arrows,
                  color: AppTheme.primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Modalità Comparazione',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    canCompare
                        ? 'Confronta la scala POS e la scala San Martín in un grafico unificato.'
                        : 'Compila entrambe le scale per sbloccare la comparazione dei domini.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Switch.adaptive(
            value: _isCompareMode && canCompare,
            activeColor: AppTheme.primaryColor,
            onChanged: canCompare
                ? (value) {
                    setState(() {
                      _isCompareMode = value;
                    });
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildComparePanel(AggregatedEvaluation posEval, AggregatedEvaluation smEval) {
    final commonCodes = posEval.domini
        .map((d) => d.codice)
        .where((code) => smEval.domini.any((d) => d.codice == code))
        .toList();

    return Card(
      key: const ValueKey('compare_panel'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE8EEF8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.analytics_outlined, color: Colors.indigo.shade800),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Comparazione Multidimensionale',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Confronto diretto normalizzato (0-100%) dei domini comuni',
                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendItem('Scala POS', const Color(0xFF3B82F6)),
                const SizedBox(width: 28),
                _legendItem('Scala San Martín', const Color(0xFFF59E0B)),
              ],
            ),
            const SizedBox(height: 28),
            // Chart Container
            if (commonCodes.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text(
                    'Nessun dominio in comune trovato tra le scale.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 320,
                child: _buildGroupedBarChart(posEval, smEval, commonCodes),
              ),
              const SizedBox(height: 24),
              // Explanation text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE8EEF8)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.indigo, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'I punteggi dei singoli domini sono normalizzati in percentuale (0-100%) rispetto al rispettivo punteggio massimo teorico (numero domande × 3 per POS e numero domande × 4 per San Martín) per consentire una visualizzazione e un confronto coerente.',
                        style: TextStyle(fontSize: 12, height: 1.5, color: Colors.indigo.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupedBarChart(AggregatedEvaluation posEval, AggregatedEvaluation smEval, List<String> commonCodes) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: 100.0,
        minY: 0.0,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.grey.shade900,
            tooltipBorder: const BorderSide(color: Colors.white24, width: 0.5),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final code = commonCodes[group.x];
              final isPos = rodIndex == 0;
              final scaleName = isPos ? 'POS' : 'San Martín';
              
              final DomainScore ds = isPos
                  ? posEval.domini.firstWhere((d) => d.codice == code)
                  : smEval.domini.firstWhere((d) => d.codice == code);
                  
              final maxTheoretical = isPos ? ds.numDomande * 3 : ds.numDomande * 4;
              final percent = rod.toY.toStringAsFixed(1);
              
              return BarTooltipItem(
                '$scaleName\n',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                children: [
                  TextSpan(
                    text: 'Dominio: ${ds.etichetta} ($code)\n',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: 'Punteggio: ${ds.punteggio} / $maxTheoretical ($percent%)',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 75,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= commonCodes.length) return const SizedBox.shrink();
                final code = commonCodes[idx];
                final posDs = posEval.domini.firstWhere(
                  (d) => d.codice == code,
                  orElse: () => smEval.domini.firstWhere((d) => d.codice == code),
                );
                final name = posDs.etichetta;
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  space: 8,
                  child: Transform.rotate(
                    angle: -0.4,
                    child: SizedBox(
                      width: 85,
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 45,
              getTitlesWidget: (value, meta) {
                if (value % 20 != 0) return const SizedBox.shrink();
                return Text(
                  '${value.toInt()}%',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 20,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.shade200,
            strokeWidth: 0.8,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(commonCodes.length, (i) {
          final code = commonCodes[i];
          final posDs = posEval.domini.firstWhere((d) => d.codice == code);
          final smDs = smEval.domini.firstWhere((d) => d.codice == code);

          final double posMax = posDs.numDomande > 0 ? (posDs.numDomande * 3).toDouble() : 15.0;
          final double smMax = smDs.numDomande > 0 ? (smDs.numDomande * 4).toDouble() : 20.0;

          final double posPercent = posMax > 0 ? (posDs.punteggio / posMax) * 100.0 : 0.0;
          final double smPercent = smMax > 0 ? (smDs.punteggio / smMax) * 100.0 : 0.0;

          return BarChartGroupData(
            x: i,
            barsSpace: 6,
            barRods: [
              BarChartRodData(
                toY: posPercent,
                color: const Color(0xFF3B82F6),
                width: 14,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: 100,
                  color: Colors.grey.shade100,
                ),
              ),
              BarChartRodData(
                toY: smPercent,
                color: const Color(0xFFF59E0B),
                width: 14,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: 100,
                  color: Colors.grey.shade100,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }


  // ── Patient Header ──────────────────────────────────────────────────────────
  Widget _buildPatientHeader() {
    final age = _calculateAge();
    final p = widget.patient;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF3949AB), Color(0xFF5C6BC0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1A237E).withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
            ),
            child: Center(
              child: Text(
                '${p.nome.isNotEmpty ? p.nome[0] : ''}${p.cognome.isNotEmpty ? p.cognome[0] : ''}',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 24),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.nome} ${p.cognome}',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    if (age != null)
                      _headerChip(Icons.cake_outlined, '$age anni'),
                    if (p.sesso != null && p.sesso!.isNotEmpty)
                      _headerChip(Icons.person_outline, p.sesso!),
                    if (p.dataNascita != null)
                      _headerChip(Icons.calendar_today_outlined, p.dataNascita!.split('T')[0]),
                  ],
                ),
              ],
            ),
          ),
          // Scale compilate badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.assessment_outlined, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '${_latestEvaluations.length} Scale Compilate',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    );
  }

  // ── Scale Panel ──────────────────────────────────────────────────────────────
  Widget _buildScalePanel(ScaleModel scale, {bool useExpanded = false}) {
    final eval = _latestEvaluations[scale.id]!;
    final analysis = _analyses[scale.id];
    final isSM = _isSanMartinScale(scale.id, scale.nome);
    final accentGradient = isSM
        ? const [Color(0xFF1A237E), Color(0xFF3949AB)]
        : const [Color(0xFF0D47A1), Color(0xFF42A5F5)];

    final headerWidget = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: accentGradient),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSM ? '🧩 San Martín' : '📊 POS Eterovalutativo',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  isSM 
                      ? 'Valutazione osservativa della qualità di vita' 
                      : 'Valutazione degli esiti personali e della QQdV percepita',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.7)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => EvaluationDetailScreen(patient: widget.patient, scale: scale),
            )),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Dettaglio', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    Widget indicatorsWidget;
    if (isSM && analysis != null) {
      indicatorsWidget = _buildSanMartinIndicators(analysis);
    } else if (!isSM) {
      indicatorsWidget = _buildPosIndicators(eval);
    } else {
      indicatorsWidget = const SizedBox.shrink();
    }

    final bodyContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Metadata row ──
        _buildMetaRow(eval),
        const SizedBox(height: 20),

        // ── Indicatori multidimensionali (POS o SM) ──
        useExpanded ? Expanded(child: indicatorsWidget) : indicatorsWidget,

        const SizedBox(height: 20),

        // ── Chart ──
        if (eval.domini.isNotEmpty)
          SizedBox(
            height: 250,
            child: isSM && analysis != null && analysis.domini.isNotEmpty
                ? _buildRadarChartForPanel(analysis)
                : _buildBarChartForPanel(eval.domini, isSm: isSM),
          ),
      ],
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE8EEF8)),
      ),
      child: useExpanded
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                headerWidget,
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: bodyContent,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                headerWidget,
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: bodyContent,
                ),
              ],
            ),
    );
  }

  Widget _buildMetaRow(AggregatedEvaluation eval) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _metaChip(Icons.calendar_today, 'Data', eval.dataCompilazione.split('T')[0]),
        _metaChip(Icons.person, 'Operatore', eval.nomeOperatore),
        if (eval.nomeIntervistato != null)
          _metaChip(Icons.record_voice_over, 'Intervistato', eval.nomeIntervistato!),
      ],
    );
  }

  Widget _metaChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EEF8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  // ── SAN MARTÍN indicators ────────────────────────────────────────────────────
  Widget _buildSanMartinIndicators(PsychometricAnalysis analysis) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _indicatorTile(
                title: 'Indice QV',
                value: analysis.indiceQv?.toString() ?? '—',
                subtitle: 'Scala centrata su 100',
                icon: Icons.favorite,
                color: Colors.pinkAccent,
              )),
              const SizedBox(width: 16),
              Expanded(child: _indicatorTile(
                title: 'Percentile',
                value: analysis.percentile != null ? '${analysis.percentile}°' : '—',
                subtitle: 'vs. campione normativo',
                icon: Icons.leaderboard,
                color: const Color(0xFFAED581),
              )),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _indicatorTile(
                title: 'Somma Std.',
                value: analysis.sommaPunteggiStandard?.toString() ?? '—',
                subtitle: 'Somma degli 8 domini',
                icon: Icons.functions,
                color: const Color(0xFF90CAF9),
              )),
              const SizedBox(width: 16),
              Expanded(child: _indicatorBadge(
                title: 'Fascia',
                value: analysis.fasciaQv ?? '—',
                subtitle: 'Fascia di Supporto',
                icon: Icons.verified,
              )),
            ],
          ),
          // ── Target normativo ──
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.flag_outlined, color: Colors.amberAccent, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Target normativo: Indice QV ≥ 100  |  Percentile ≥ 50°',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                if (analysis.indiceQv != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (analysis.indiceQv! >= 100)
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      (analysis.indiceQv! >= 100) ? '✓ Raggiunto' : '↑ Da raggiungere',
                      style: TextStyle(
                        color: (analysis.indiceQv! >= 100) ? Colors.greenAccent : Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _indicatorTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _indicatorBadge({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    Color bgColor;
    Color textColor;
    final lv = value.toLowerCase();
    if (lv.contains('significativa') || lv.contains('alta') || lv.contains('buon')) {
      bgColor = Colors.green.withValues(alpha: 0.2);
      textColor = Colors.greenAccent;
    } else if (lv.contains('media') || lv.contains('bassa') || lv.contains('marginale')) {
      bgColor = Colors.orange.withValues(alpha: 0.2);
      textColor = Colors.orangeAccent;
    } else {
      bgColor = Colors.blue.withValues(alpha: 0.2);
      textColor = Colors.lightBlueAccent;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.amberAccent, size: 16),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
            child: Text(value, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  // ── POS indicators ───────────────────────────────────────────────────────────
  Widget _buildPosIndicators(AggregatedEvaluation eval) {
    int total = 0;
    for (final d in eval.domini) {
      total += d.punteggio;
    }

    final legendWidget = Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.legend_toggle_outlined, color: Colors.amberAccent, size: 15),
              SizedBox(width: 8),
              Text(
                'Legenda Domini',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: eval.domini.map((d) {
              return Text(
                '${d.codice.toUpperCase()} = ${d.etichetta}: ${d.punteggio}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _indicatorTile(
                title: 'Punteggio Totale',
                value: total.toString(),
                subtitle: '${eval.domini.length} domini analizzati',
                icon: Icons.score,
                color: Colors.amberAccent,
              )),
              const SizedBox(width: 16),
              Expanded(child: _indicatorTile(
                title: 'Media per Dominio',
                value: eval.domini.isNotEmpty ? (total / eval.domini.length).toStringAsFixed(1) : '—',
                subtitle: 'Valore medio calcolato',
                icon: Icons.bar_chart,
                color: const Color(0xFF90CAF9),
              )),
            ],
          ),
          legendWidget,
        ],
      ),
    );
  }

  // ── Radar Chart (San Martín) ────────────────────────────────────────────────
  Widget _buildRadarChartForPanel(PsychometricAnalysis analysis) {
    final domini = analysis.domini;
    if (domini.isEmpty) return const SizedBox();

    final patientValues = domini
        .map((d) => ((d.punteggioStandard ?? d.punteggioDiretto ?? 0).clamp(0, 20)).toDouble())
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartSize = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox(
            width: chartSize,
            height: chartSize,
            child: Stack(
              children: [
                RadarChart(
                  RadarChartData(
                    radarShape: RadarShape.polygon,
                    tickCount: 4,
                    ticksTextStyle: const TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                    tickBorderData: const BorderSide(color: Color(0xFFE2E8F0), width: 0.8),
                    gridBorderData: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
                    radarBorderData: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                    radarBackgroundColor: const Color(0xFFF8FAFC),
                    titlePositionPercentageOffset: 0.15,
                    titleTextStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    getTitle: (index, _) {
                      if (index < 0 || index >= domini.length) return const RadarChartTitle(text: '');
                      return RadarChartTitle(text: domini[index].codice);
                    },
                    dataSets: [
                      // Max reference (20)
                      RadarDataSet(
                        dataEntries: List.generate(domini.length, (_) => const RadarEntry(value: 20)),
                        borderColor: Colors.transparent,
                        fillColor: Colors.transparent,
                        entryRadius: 0,
                      ),
                      // Range medio (12) - dataset green transparency
                      RadarDataSet(
                        dataEntries: List.generate(domini.length, (_) => const RadarEntry(value: 12)),
                        borderColor: const Color(0xFF22C55E).withValues(alpha: 0.35),
                        fillColor: const Color(0xFF22C55E).withValues(alpha: 0.08),
                        borderWidth: 1.5,
                        entryRadius: 0,
                      ),
                      // Media normativa (10) - dataset red transparency
                      RadarDataSet(
                        dataEntries: List.generate(domini.length, (_) => const RadarEntry(value: 10)),
                        borderColor: const Color(0xFFEF4444).withValues(alpha: 0.35),
                        fillColor: const Color(0xFFEF4444).withValues(alpha: 0.08),
                        borderWidth: 1.5,
                        entryRadius: 0,
                      ),
                      // Patient data
                      RadarDataSet(
                        dataEntries: domini.map((d) => RadarEntry(value: (d.punteggioStandard ?? d.punteggioDiretto).toDouble())).toList(),
                        borderColor: const Color(0xFFF97316),
                        fillColor: const Color(0xFFF97316).withValues(alpha: 0.2),
                        borderWidth: 2.5,
                        entryRadius: 4,
                      ),
                    ],
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    size: Size(chartSize, chartSize),
                    painter: _RadarLabelsPainter(
                      axisCount: domini.length,
                      patientValues: patientValues,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Bar Chart (POS) ─────────────────────────────────────────────────────────
  Widget _buildBarChartForPanel(List<DomainScore> domini, {bool isSm = false}) {
    if (domini.isEmpty) return const SizedBox();

    // Calcola il maxY dinamico basato sui dati reali
    double dynamicMaxY = 0;
    for (final d in domini) {
      final maxScore = d.numDomande * (isSm ? 4 : 3);
      final score = d.punteggio.toDouble();
      if (maxScore > dynamicMaxY) dynamicMaxY = maxScore.toDouble();
      if (score > dynamicMaxY) dynamicMaxY = score.toDouble();
    }
    if (dynamicMaxY <= 0) dynamicMaxY = 20;
    // Aggiungi un margine del 10% per estetica
    dynamicMaxY = (dynamicMaxY * 1.1).ceilToDouble();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: dynamicMaxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gIdx, rod, rIdx) {
              if (group.x < 0 || group.x >= domini.length) return null;
              return BarTooltipItem(
                '${domini[group.x].etichetta}\n${rod.toY.toInt()} pt',
                const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= domini.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    domini[idx].codice,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= domini.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${domini[idx].punteggio}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _domainColors[idx % _domainColors.length]),
                  ),
                );
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 3,
          getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 0.8),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(domini.length, (i) {
          final maxScore = domini[i].numDomande * (isSm ? 4 : 3);
          final double toYValue = domini[i].punteggio.toDouble();
          final double backYValue = maxScore.toDouble();
          
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: toYValue,
                color: _domainColors[i % _domainColors.length],
                width: 28,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: backYValue,
                  color: Colors.grey.shade100,
                ),
              ),
            ],
            showingTooltipIndicators: [],
          );
        }),
        extraLinesData: ExtraLinesData(horizontalLines: []),
      ),
    );
    // We overlay real bars on top — simplified: use single bar with backDrawRodData
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TAB 2: ANALISI IA
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildAiTab() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.psychology, color: Colors.white, size: 40),
                const SizedBox(width: 20),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Analisi Multidimensionale con Intelligenza Artificiale',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      SizedBox(height: 6),
                      Text('L\'IA analizza le valutazioni aggregate per individuare correlazioni, punti di forza/debolezza e suggerire linee guida di supporto personalizzate.',
                        style: TextStyle(fontSize: 13, color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _isAnalyzing ? null : _runAiAnalysis,
                  icon: _isAnalyzing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isAnalyzing ? 'Analisi in corso...' : 'Analizza con IA',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_aiError != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_aiError!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500))),
                  if (_aiError!.contains('mancante'))
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                      child: const Text('Vai a Impostazioni'),
                    ),
                ],
              ),
            ),

          if (_aiReport != null)
            Expanded(
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Markdown(
                    data: _aiReport!,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      h1: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 24),
                      h2: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 20),
                      h3: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
                      p: const TextStyle(fontSize: 15, height: 1.6),
                    ),
                  ),
                ),
              ),
            ),

          if (_aiReport == null && _aiError == null && !_isAnalyzing)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_outlined, size: 64, color: Colors.deepPurple.shade100),
                    const SizedBox(height: 16),
                    const Text('Premi "Analizza con IA" per generare il report multidimensionale.',
                      style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RadarLabelsPainter extends CustomPainter {
  final int axisCount;
  final List<double> patientValues;

  _RadarLabelsPainter({
    required this.axisCount,
    required this.patientValues,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (axisCount < 3) return;

    final center = Offset(size.width / 2, size.height / 2);
    // Use 0.73 as maxRadius factor since titlePositionPercentageOffset is 0.15.
    final maxRadius = (math.min(size.width, size.height) / 2) * 0.73;

    for (var index = 0; index < axisCount; index++) {
      final score = patientValues[index];
      final valFraction = score / 20.0;
      final valRadius = maxRadius * valFraction;
      final angle = (-math.pi / 2) + (2 * math.pi * index / axisCount);

      // Offset so we don't overlap the dots rendered by FL Chart
      final double offsetVal;
      if (score < 3) {
        offsetVal = 13.0;
      } else if (score > 18) {
        offsetVal = -13.0;
      } else {
        offsetVal = 11.0;
      }

      final pText = Offset(
        center.dx + ((valRadius + offsetVal) * math.cos(angle)),
        center.dy + ((valRadius + offsetVal) * math.sin(angle)),
      );

      final tp = TextPainter(
        text: TextSpan(
          text: score.toInt().toString(),
          style: const TextStyle(
            color: Color(0xFFE65100), // Dark orange for maximum readability
            fontSize: 9.0,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();

      final rect = Rect.fromCenter(
        center: pText,
        width: tp.width + 8,
        height: tp.height + 4,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

      // Badge background
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = const Color(0xFFFFF3E0) // Light orange background
          ..style = PaintingStyle.fill,
      );
      // Badge border
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = const Color(0xFFFFB74D) // Amber/orange border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
      // Paint text centered inside badge
      tp.paint(canvas, Offset(pText.dx - tp.width / 2, pText.dy - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarLabelsPainter oldDelegate) {
    return oldDelegate.axisCount != axisCount ||
        oldDelegate.patientValues != patientValues;
  }
}
