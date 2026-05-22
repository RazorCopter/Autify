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
  
  String? _geminiKey;
  String _geminiModel = 'gemini-1.5-pro';
  
  List<ScaleModel> _availableScales = [];
  Map<String, AggregatedEvaluation> _latestEvaluations = {};
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

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    // 1. Carica configurazione AI
    final settings = await _apiService.getGeminiSettings();
    _geminiKey = settings['key'];
    _geminiModel = settings['model'] ?? 'gemini-1.5-pro';

    // 2. Carica scale disponibili
    _availableScales = await _apiService.getAvailableScales();
    
    // 3. Carica ultima valutazione per ogni scala
    for (final scale in _availableScales) {
      final history = await _apiService.getAggregatedEvaluationHistory(widget.patient.id, scale.id);
      if (history.isNotEmpty) {
        _latestEvaluations[scale.id] = history.first;
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _runAiAnalysis() async {
    if (_geminiKey == null || _geminiKey!.isEmpty) {
      setState(() => _aiError = 'Chiave API Gemini mancante. Configurala in Impostazioni.');
      return;
    }

    if (_latestEvaluations.isEmpty) {
      setState(() => _aiError = 'Nessun dato clinico disponibile per l\'analisi.');
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
          title: Text('Analisi Multidimensionale: ${widget.patient.nome} ${widget.patient.cognome}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview Dati'),
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

  Widget _buildOverviewTab() {
    if (_latestEvaluations.isEmpty) {
      return const Center(child: Text('Nessuna valutazione compilata per questo utente.'));
    }

    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: _availableScales.map((scale) {
        final eval = _latestEvaluations[scale.id];
        if (eval == null) return const SizedBox.shrink();
        
        return Card(
          margin: const EdgeInsets.only(bottom: 24.0),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      scale.nome,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EvaluationDetailScreen(patient: widget.patient, scale: scale),
                          ),
                        );
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Dettaglio Completo'),
                    )
                  ],
                ),
                const Divider(height: 32),
                
                // Mostra un grafico o metriche in base ai dati disponibili
                if (eval.analisi != null && eval.analisi!.domini.isNotEmpty)
                  SizedBox(
                    height: 300,
                    child: _buildChartForEval(eval),
                  )
                else
                  Text(
                    'Punteggio Totale: ${eval.punteggioTotale ?? "N/D"}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  
                if (eval.analisi?.indiceQv != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text('Indice QV: ${eval.analisi!.indiceQv}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                  )
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChartForEval(AggregatedEvaluation eval) {
    final isSanMartin = eval.scalaNome.toLowerCase().contains('sanmartin') || eval.idScala.toLowerCase().contains('sanmartin');
    final domini = eval.analisi!.domini;
    
    if (isSanMartin && domini.any((d) => d.punteggioStandard != null)) {
      // Radar Chart per San Martin (semplificato per overview)
      return RadarChart(
        RadarChartData(
          radarShape: RadarShape.polygon,
          tickCount: 5,
          ticksTextStyle: const TextStyle(color: Colors.transparent),
          gridBorderData: BorderSide(color: Colors.grey.shade300, width: 1),
          titlePositionPercentageOffset: 0.1,
          getTitle: (index, angle) {
            final text = domini[index].codice ?? '';
            return RadarChartTitle(text: text, angle: 0, positionPercentageOffset: 0.2);
          },
          dataSets: [
            RadarDataSet(
              fillColor: AppTheme.primaryColor.withOpacity(0.3),
              borderColor: AppTheme.primaryColor,
              entryRadius: 4,
              dataEntries: domini.map((d) => RadarEntry(value: (d.punteggioStandard ?? 0).toDouble())).toList(),
              borderWidth: 2,
            )
          ],
        ),
      );
    } else {
      // Bar Chart per POS o altri (semplificato)
      return BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: 20,
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  if (value.toInt() < 0 || value.toInt() >= domini.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(domini[value.toInt()].codice ?? '', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(
            domini.length,
            (i) => BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: (domini[i].punteggioTotale ?? domini[i].punteggioDiretto ?? 0).toDouble(),
                  color: _domainColors[i % _domainColors.length],
                  width: 30,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                )
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildAiTab() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'L\'Analisi IA utilizza i dati clinici aggregati per fornire un referto specialistico, individuare correlazioni tra i vari domini e suggerire linee guida terapeutiche ed educative personalizzate.',
                  style: TextStyle(fontSize: 16, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(width: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
                onPressed: _isAnalyzing ? null : _runAiAnalysis,
                icon: _isAnalyzing 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.psychology, color: Colors.white),
                label: Text(_isAnalyzing ? 'L\'esperto IA sta analizzando...' : 'Analizza con IA', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          if (_aiError != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_aiError!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500))),
                  if (_aiError!.contains('mancante'))
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                      child: const Text('Vai a Impostazioni'),
                    )
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
                      p: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
