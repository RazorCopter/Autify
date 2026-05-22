// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/evaluation_model.dart';
import '../models/patient_model.dart';
import '../models/scale_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// ─── Entry point: naviga qui passando paziente e scala ───────────────────────
class EvaluationDetailScreen extends StatefulWidget {
  final PatientModel patient;
  final ScaleModel scale;

  const EvaluationDetailScreen({
    super.key,
    required this.patient,
    required this.scale,
  });

  @override
  State<EvaluationDetailScreen> createState() => _EvaluationDetailScreenState();
}

class _EvaluationDetailScreenState extends State<EvaluationDetailScreen> {
  final ApiService _api = ApiService();

  List<AggregatedEvaluation> _history = [];
  AggregatedEvaluation? _eval;
  PsychometricAnalysis? _analysis;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDownloading = false;
  bool _isLoadingAnalysis = false;

  // Teniamo una copia mutabile delle risposte per l'editing inline
  List<AnswerModel> _editableAnswers = [];
  final Map<String, TextEditingController> _noteControllers = {};
  
  bool _isEditMode = false;
  final TextEditingController _operatoreController = TextEditingController();
  final TextEditingController _intervistatoController = TextEditingController();

  static const List<Color> _domainColors = [
    Color(0xFF64B5F6), Color(0xFFFFB74D), Color(0xFF81C784), Color(0xFFCE93D8),
    Color(0xFFE57373), Color(0xFF4FC3F7), Color(0xFFAED581), Color(0xFFFF8A65),
  ];

  String _normalizeScaleIdentifier(String? value) {
    return (value ?? '')
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('-', '')
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

  bool get _isSanMartinScale {
    final normalizedName =
        _normalizeScaleIdentifier(_analysis?.scalaNome ?? widget.scale.nome);
    final normalizedId =
        _normalizeScaleIdentifier(_analysis?.idScala ?? widget.scale.id);
    return normalizedName.contains('sanmartin') ||
        normalizedId.contains('sanmartin');
  }

  bool get _hasStandardProfile =>
      _analysis?.domini.any((domain) => domain.punteggioStandard != null) ?? false;

  bool get _hasQvSummary =>
      _analysis != null &&
      (_analysis!.indiceQv != null ||
          _analysis!.percentile != null ||
          (_analysis!.fasciaQv?.isNotEmpty ?? false));

  bool get _forceSanMartinLayout => _isSanMartinScale || _hasQvSummary;

  bool get _shouldUseSanMartinUi =>
      _forceSanMartinLayout || _showSanMartinProfile;

  bool get _showSanMartinProfile =>
      _analysis != null &&
      _analysis!.domini.isNotEmpty &&
      (_forceSanMartinLayout || _hasStandardProfile);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    _operatoreController.dispose();
    _intervistatoController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final history = await _api.getAggregatedEvaluationHistory(
      widget.patient.id,
      widget.scale.id,
    );
    if (history.isNotEmpty && mounted) {
      setState(() {
        _history = history;
        _selectEvaluation(history.first);
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nessuna valutazione trovata per questo paziente e scala')),
        );
      }
    }
  }

  void _selectEvaluation(AggregatedEvaluation evaluation) {
    _eval = evaluation;
    _editableAnswers = evaluation.risposte
        .map((r) => AnswerModel(
              codiceDomanda: r.codiceDomanda,
              punteggio: r.punteggio,
              nota: r.nota,
            ))
        .toList();

    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    _noteControllers.clear();
    for (final r in evaluation.risposte) {
      _noteControllers[r.codiceDomanda] = TextEditingController(text: r.nota ?? '');
    }
    
    _operatoreController.text = evaluation.nomeOperatore;
    _intervistatoController.text = evaluation.nomeIntervistato ?? '';

    _loadAnalysis();
  }

  Future<void> _loadAnalysis() async {
    if (_eval == null) return;
    setState(() => _isLoadingAnalysis = true);
    try {
      print('DEBUG AUTANALYSIS - loadAnalysis start: evaluation=${_eval!.idValutazione}');
      print('DEBUG AUTANALYSIS - scale widget name: ${widget.scale.nome}');

      final analysis = await _api.getEvaluationAnalysis(_eval!.idValutazione);

      print('DEBUG AUTANALYSIS - analysis loaded: ${analysis != null}');
      if (analysis != null) {
        print('DEBUG AUTANALYSIS - scalaNome: ${analysis.scalaNome}');
        print('DEBUG AUTANALYSIS - scalaNome normalized: ${_normalizeScaleIdentifier(analysis.scalaNome)}');
        print('DEBUG AUTANALYSIS - widget scale normalized: ${_normalizeScaleIdentifier(widget.scale.nome)}');
        print('DEBUG AUTANALYSIS - indiceQv: ${analysis.indiceQv}');
        print('DEBUG AUTANALYSIS - percentile: ${analysis.percentile}');
        print('DEBUG AUTANALYSIS - fasciaQv: ${analysis.fasciaQv}');
        print('DEBUG AUTANALYSIS - sommaPunteggiStandard: ${analysis.sommaPunteggiStandard}');
        print('DEBUG AUTANALYSIS - domini: ${analysis.domini.map((d) => '${d.codice}[raw=${d.punteggioDiretto},std=${d.punteggioStandard}]').join(', ')}');
        print('DEBUG AUTANALYSIS - isSanMartinScale: $_isSanMartinScale');
        print('DEBUG AUTANALYSIS - shouldUseSanMartinUi: $_shouldUseSanMartinUi');
      } else {
        print('DEBUG AUTANALYSIS - analysis is null');
      }

      if (mounted) {
        setState(() {
          _analysis = analysis;
        });
      }
    } catch (e, stackTrace) {
      print('DEBUG AUTANALYSIS - loadAnalysis error: $e');
      print('DEBUG AUTANALYSIS - loadAnalysis stackTrace: $stackTrace');
      if (mounted) {
        setState(() {
          _analysis = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAnalysis = false;
        });
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_eval == null) return;
    setState(() => _isSaving = true);
    final updated = await _api.updateEvaluationAnswers(
      _eval!.idValutazione,
      _editableAnswers,
      nomeOperatore: _operatoreController.text.isNotEmpty ? _operatoreController.text : null,
      nomeIntervistato: _intervistatoController.text.isNotEmpty ? _intervistatoController.text : null,
    );
    if (updated != null && mounted) {
      setState(() {
        final idx = _history.indexWhere((e) => e.idValutazione == updated.idValutazione);
        if (idx != -1) {
          _history[idx] = updated;
        }
        _selectEvaluation(updated);
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Modifiche salvate con successo'),
          backgroundColor: AppTheme.accentColor,
        ),
      );
    } else {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Errore nel salvataggio')),
        );
      }
    }
  }

  Future<void> _downloadPdf() async {
    if (_eval == null) return;
    setState(() => _isDownloading = true);
    final bytes = await _api.downloadEvaluationPdf(_eval!.idValutazione);
    setState(() => _isDownloading = false);
    if (bytes != null) {
      final b64 = base64Encode(bytes);
      final dataUrl = 'data:application/pdf;base64,$b64';
      html.AnchorElement(href: dataUrl)
        ..setAttribute(
            'download', 'valutazione_${widget.patient.cognome}.pdf')
        ..click();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore nella generazione del PDF')),
      );
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _eval == null
              ? _buildEmptyState()
              : _buildContent(),
    );
  }

  String _formatEvaluationDate(String rawDate) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed == null) return rawDate;
    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.patient.nome} ${widget.patient.cognome}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(
            widget.scale.nome,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
      actions: [
        if (_isSaving)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else ...[
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _isEditMode = !_isEditMode;
                if (!_isEditMode && _eval != null) {
                  _selectEvaluation(_eval!);
                }
              });
            },
            icon: Icon(_isEditMode ? Icons.cancel_outlined : Icons.edit_outlined, size: 18),
            label: Text(_isEditMode ? 'Annulla' : 'Edit'),
          ),
          const SizedBox(width: 8),
          if (_isEditMode)
            TextButton.icon(
              onPressed: _saveChanges,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Salva modifiche'),
            ),
        ],
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _isDownloading ? null : _downloadPdf,
          icon: _isDownloading
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: Text(_isDownloading ? 'Generazione...' : 'Esporta PDF'),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          const Text('Nessuna valutazione trovata',
              style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Torna indietro'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHistoryCard(),
              const SizedBox(height: 20),
              if (_shouldUseSanMartinUi) ...[
                _buildQvSummaryCard(),
                const SizedBox(height: 20),
                _buildQvGraphicTable(),
                const SizedBox(height: 20),
              ],
              _buildMetaCard(),
              const SizedBox(height: 20),
              _buildClinicalCard(),
              const SizedBox(height: 20),
              _buildChartCard(),
              const SizedBox(height: 20),
              _buildDomainTable(),
              const SizedBox(height: 20),
              _buildAnswersList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryCard() {
    final selectedId = _eval?.idValutazione;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Storico Valutazioni',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _history.map((evaluation) {
                final isSelected = evaluation.idValutazione == selectedId;
                return ChoiceChip(
                  selected: isSelected,
                  label: Text('Valutazione del ${_formatEvaluationDate(evaluation.dataCompilazione)}'),
                  onSelected: (_) {
                    setState(() => _selectEvaluation(evaluation));
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Metadati paziente ─────────────────────────────────────────────────────
  Widget _buildMetaCard() {
    final e = _eval!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 32,
          runSpacing: 12,
          children: [
            _metaItem('Paziente', '${widget.patient.nome} ${widget.patient.cognome}'),
            _metaItem('Scala', widget.scale.nome),
            _metaItem('Data', _formatEvaluationDate(e.dataCompilazione)),
            _metaItem('Anno', e.anno.toString()),
            
            _isEditMode 
                ? SizedBox(width: 200, child: TextField(controller: _operatoreController, decoration: const InputDecoration(labelText: 'Operatore', border: UnderlineInputBorder()), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)))
                : _metaItem('Operatore', e.nomeOperatore),
                
            _isEditMode
                ? SizedBox(width: 200, child: TextField(controller: _intervistatoController, decoration: const InputDecoration(labelText: 'Intervistato/a', border: UnderlineInputBorder()), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)))
                : (e.nomeIntervistato != null && e.nomeIntervistato!.isNotEmpty ? _metaItem('Intervistato/a', e.nomeIntervistato!) : const SizedBox()),
                
            _metaItem('ID', e.idValutazione.length > 8 ? '${e.idValutazione.substring(0, 8)}…' : e.idValutazione),
          ],
        ),
      ),
    );
  }

  Widget _metaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // ─── Pannello Clinico ────────────────────────────────────────────────────────
  Widget _buildClinicalCard() {
    final p = widget.patient;
    final noteLines = (p.note != null && p.note!.isNotEmpty)
        ? p.note!.split('\n').where((l) => l.trim().isNotEmpty).toList()
        : <String>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_ind_outlined, size: 20, color: AppTheme.primaryColor),
                const SizedBox(width: 8),
                const Text('Quadro Clinico',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              ],
            ),
            const SizedBox(height: 16),
            if (p.altezza != null || p.peso != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    if (p.altezza != null)
                      _clinicalChip(Icons.height, 'Altezza', '${p.altezza} cm'),
                    if (p.peso != null)
                      _clinicalChip(Icons.monitor_weight_outlined, 'Peso', '${p.peso} kg'),
                  ],
                ),
              ),
            if (noteLines.isNotEmpty) ...[
              const Text('Note Cliniche',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              ...noteLines.map((line) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                        Expanded(
                          child: Text(line.trim(),
                              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.4)),
                        ),
                      ],
                    ),
                  )),
            ],
            if (p.altezza == null && p.peso == null && noteLines.isEmpty)
              const Text('Nessun dato clinico aggiuntivo registrato.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _clinicalChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  // ─── Card Riepilogo QV ──────────────────────────────────────────────────────
  Widget _buildQvSummaryCard() {
    final a = _analysis!;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 32),
        child: Wrap(
          spacing: 28,
          runSpacing: 20,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            _summaryMetric(
              title: 'Indice Qualità della Vita',
              value: a.indiceQv?.toString() ?? '—',
              hint: 'Scala normativa centrata su 100',
              color: Colors.white,
              large: true,
            ),
            _summaryMetric(
              title: 'Percentile',
              value: a.percentile != null ? '${a.percentile}°' : '—',
              hint: 'Posizionamento rispetto al campione',
              color: const Color(0xFFAED581),
              large: true,
            ),
            _summaryMetric(
              title: 'Somma Punteggi Standard',
              value: a.sommaPunteggiStandard?.toString() ?? '—',
              hint: 'Somma degli 8 domini',
              color: const Color(0xFF90CAF9),
              large: true,
            ),
            if (a.fasciaQv != null)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Fascia interpretativa',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 44, // Allinea l'altezza del badge con il testo grande delle altre metriche
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _fasciaBadge(a.fasciaQv!),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Classificazione clinica',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Grafico visivo Qualità della Vita (CustomPainter) ─────────────────────
  Widget _buildQvGraphicTable() {
    if (!_shouldUseSanMartinUi || _analysis == null) return const SizedBox();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tabella Visiva Qualità della Vita',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            const Text(
              'Punteggi standard per dominio — fasce normative 1-20',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  width: constraints.maxWidth,
                  height: 480.0,
                  child: _QualityOfLifeHorizontalPainter(
                    domains: _analysis!.domini,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }


  Widget _summaryMetric({
    required String title,
    required String value,
    required String hint,
    required Color color,
    bool large = false,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, color: Colors.white70)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: large ? 38 : 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  static const _fasciaColorMap = {
    'Molto Basso': Color(0xFFD32F2F),
    'Basso':       Color(0xFFF57C00),
    'Medio':       Color(0xFFFBC02D),
    'Alto':        Color(0xFF7CB342),
    'Molto Alto':  Color(0xFF388E3C),
  };

  Widget _fasciaBadge(String? fascia, [Color? color]) {
    final text = fascia ?? '—';
    final resolvedColor = color ?? _fasciaColorMap[text] ?? AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: resolvedColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: resolvedColor,
        ),
      ),
    );
  }
  Widget _buildChartCard() {
    final hasAnalysis = _analysis != null && _analysis!.domini.isNotEmpty;
    final useRadar = hasAnalysis && _shouldUseSanMartinUi;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              useRadar
                  ? 'Profilo della Qualità della Vita'
                  : 'Profilo Punteggi per Dominio',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              useRadar
                  ? 'Radar chart a 8 assi, scala 0–20, con media normativa fissata a 10'
                  : 'Fallback automatico per scale senza tabelle di conversione',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            if (_isLoadingAnalysis)
              const SizedBox(
                height: 400,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_shouldUseSanMartinUi && !hasAnalysis)
              const SizedBox(
                height: 220,
                child: Center(
                  child: Text(
                    'Contesto San Martin rilevato, ma l\'analisi non contiene ancora i dati necessari per il radar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                  ),
                ),
              )
            else
              SizedBox(
                height: useRadar ? 520 : 320,
                child: useRadar ? _buildRadarChart() : _buildBarChart(),
              ),
          ],
        ),
      ),
    );
  }

  // ─── Radar Chart (San Martín e scale con scoring_tables) ──────────────────
  Widget _buildRadarChart() {
    final domains = _analysis!.domini;
    final patientValues = domains
        .map((d) => ((d.punteggioStandard ?? 0).clamp(0, 20)).toDouble())
        .toList();
    final maxValues = List<double>.filled(domains.length, 20.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final chartSize =
            math.min(availableWidth - 36, 430.0).clamp(280.0, 430.0).toDouble();

        return Column(
          children: [
            Expanded(
              child: Center(
                child: SizedBox(
                  width: chartSize,
                  height: chartSize,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      RadarChart(
                        RadarChartData(
                          radarShape: RadarShape.polygon,
                          tickCount: 4,
                          ticksTextStyle: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.bold,
                          ),
                          tickBorderData: const BorderSide(color: Color(0xFFE2E8F0), width: 0.8),
                          gridBorderData: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
                          radarBorderData: const BorderSide(color: Color(0xFF94A3B8), width: 1.5),
                          radarBackgroundColor: const Color(0xFFF8FAFC),
                          titlePositionPercentageOffset: 0,
                          titleTextStyle: const TextStyle(color: Colors.transparent),
                          getTitle: (index, _) => const RadarChartTitle(text: ''),
                          dataSets: [
                            RadarDataSet(
                              dataEntries: maxValues
                                  .map((value) => RadarEntry(value: value))
                                  .toList(),
                              borderColor: Colors.transparent,
                              borderWidth: 0,
                              fillColor: Colors.transparent,
                              entryRadius: 0,
                            ),
                            RadarDataSet(
                              dataEntries: patientValues
                                  .map((value) => RadarEntry(value: value))
                                  .toList(),
                              borderColor: const Color(0xFFF97316), // Arancione/Corallo vibrante infografica
                              borderWidth: 4.0,
                              fillColor: const Color(0xFFF97316).withValues(alpha: 0.28),
                              entryRadius: 6.5,
                            ),
                          ],
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          size: Size(chartSize, chartSize),
                          painter: _DashedRadarMeanPainter(
                            axisCount: domains.length,
                            color: const Color(0xFFE57373),
                            levelFraction: 0.5,
                            patientValues: patientValues,
                          ),
                        ),
                      ),
                      ..._buildRadarAxisLabels(domains, chartSize),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: const [
                _LegendItem(
                  color: Color(0xFFF97316),
                  label: 'Profilo paziente',
                ),
                _LegendItem(
                  color: Color(0xFFE57373),
                  label: 'Media normativa (10)',
                  dashed: true,
                ),
                _LegendItem(
                  color: Color(0x1C4CAF50),
                  label: 'Range Medio (8–12)',
                  isSquare: true,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildRadarAxisLabels(List<DomainAnalysis> domains, double chartSize) {
    final center = chartSize / 2;
    final labelRadius = (chartSize / 2) + 24;
    const labelWidth = 130.0;

    return List<Widget>.generate(domains.length, (index) {
      final angle = (-math.pi / 2) + (2 * math.pi * index / domains.length);
      final dx = center + (labelRadius * math.cos(angle));
      final dy = center + (labelRadius * math.sin(angle));

      return Positioned(
        left: dx - (labelWidth / 2),
        top: dy - 20,
        width: labelWidth,
        child: Text(
          domains[index].etichetta,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            height: 1.1,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      );
    });
  }

  // ─── Istogramma Barre (fallback per scale senza scoring_tables) ────────────
  Widget _buildBarChart() {
    final hasAnalysis = _analysis != null && _analysis!.domini.isNotEmpty;
    final items = hasAnalysis ? _analysis!.domini : _eval!.domini;
    final isPos = widget.scale.id.toLowerCase().contains("pos") || widget.scale.nome.toLowerCase().contains("pos");
    final maxY = isPos ? 18.0 : 60.0;

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIdx, rod, rodIdx) {
              if (group.x < 0 || group.x >= items.length) return null;
              final item = items is List<DomainAnalysis>
                  ? items[group.x]
                  : (items as List<DomainScore>)[group.x];
              final label = item is DomainAnalysis ? item.etichetta : (item as DomainScore).etichetta;
              final suffix = ' pt';
              return BarTooltipItem(
                '$label\n${rod.toY.toInt()}$suffix',
                const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (val, _) {
                final idx = val.toInt();
                if (idx < 0 || idx >= items.length) return const SizedBox();
                final name = items is List<DomainAnalysis>
                    ? items[idx].etichetta
                    : (items as List<DomainScore>)[idx].etichetta;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 70,
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: isPos ? 3.0 : 10.0,
              getTitlesWidget: (val, _) => Text(
                val.toInt().toString(),
                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
              ),
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: const Color(0xFFE8EEF8), strokeWidth: 1),
        ),
        barGroups: items.asMap().entries.map((e) {
          final color = _domainColors[e.key % _domainColors.length];
          final value = items is List<DomainAnalysis>
              ? items[e.key].punteggioDiretto
              : (items as List<DomainScore>)[e.key].punteggio;
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: value.toDouble(),
                color: color,
                width: 28,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: color.withValues(alpha: 0.08),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ─── Tabella riepilogo domini ───────────────────────────────────────────────
  Widget _buildDomainTable() {
    if (_isLoadingAnalysis) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final List<dynamic> domainsList = (_shouldUseSanMartinUi && _analysis != null)
        ? _analysis!.domini
        : (_eval?.domini ?? <DomainScore>[]);

    final List<DataColumn> columns = [
      const DataColumn(
        label: Text(
          'Metrica',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 13),
        ),
      ),
      ...domainsList.map((d) {
        final code = (d is DomainAnalysis) ? d.codice : (d as DomainScore).codice;
        final labelText = (d is DomainAnalysis) ? d.etichetta : (d as DomainScore).etichetta;
        
        // Abbreviazioni per far rientrare la tabella nello schermo
        String displayLabel = labelText;
        final upperCode = code.toUpperCase();
        if (upperCode == 'AU') {
          displayLabel = 'Autodeter.';
        } else if (upperCode == 'BE') {
          displayLabel = 'Ben. Emotivo';
        } else if (upperCode == 'BF') {
          displayLabel = 'Ben. Fisico';
        } else if (upperCode == 'BM') {
          displayLabel = 'Ben. Materiale';
        } else if (upperCode == 'DI') {
          displayLabel = 'Diritti';
        } else if (upperCode == 'SP') {
          displayLabel = 'Svilup. Pers.';
        } else if (upperCode == 'IS') {
          displayLabel = 'Inclus. Soc.';
        } else if (upperCode == 'RI') {
          displayLabel = 'Relaz. Interp.';
        }

        return DataColumn(
          label: SizedBox(
            width: 80,
            child: Text(
              displayLabel,
              softWrap: true,
              maxLines: 2,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
                fontSize: 12,
                height: 1.1,
              ),
            ),
          ),
        );
      }),
    ];

    final List<DataRow> rows = [];

    // 1. Punteggio Grezzo
    rows.add(DataRow(
      cells: [
        const DataCell(Text('Punteggio Grezzo', style: TextStyle(fontWeight: FontWeight.bold))),
        ...domainsList.map((d) {
          final val = (d is DomainAnalysis) ? d.punteggioDiretto : (d as DomainScore).punteggio;
          return DataCell(Text(val.toString(), style: const TextStyle(fontSize: 13)));
        }),
      ],
    ));

    // Se abbiamo i dati della Scala San Martín (con conversione)
    if (_shouldUseSanMartinUi && _analysis != null) {
      // 2. Punteggio Standard
      rows.add(DataRow(
        cells: [
          const DataCell(Text('Punteggio Standard', style: TextStyle(fontWeight: FontWeight.bold))),
          ...domainsList.map((d) {
            final val = (d as DomainAnalysis).punteggioStandard;
            final fasciaColor = _getFasciaColor(d.fascia);
            return DataCell(_standardScoreBadge(val, fasciaColor));
          }),
        ],
      ));

      // 3. Percentile
      rows.add(DataRow(
        cells: [
          const DataCell(Text('Percentile', style: TextStyle(fontWeight: FontWeight.bold))),
          ...domainsList.map((d) {
            final val = (d as DomainAnalysis).percentileDominio;
            final fasciaColor = _getFasciaColor(d.fascia);
            final valText = val != null ? '$val°' : '—';
            return DataCell(Text(
              valText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: val != null ? fasciaColor : AppTheme.textSecondary,
              ),
            ));
          }),
        ],
      ));

      // 4. Fascia
      rows.add(DataRow(
        cells: [
          const DataCell(Text('Fascia', style: TextStyle(fontWeight: FontWeight.bold))),
          ...domainsList.map((d) {
            final val = (d as DomainAnalysis).fascia;
            final fasciaColor = _getFasciaColor(d.fascia);
            return DataCell(_fasciaBadge(val, fasciaColor));
          }),
        ],
      ));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Riepilogo per Dominio',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: constraints.maxWidth,
                    ),
                    child: DataTable(
                      columnSpacing: 14.0,
                      horizontalMargin: 12.0,
                      headingRowColor: WidgetStatePropertyAll(
                        AppTheme.primaryColor.withValues(alpha: 0.08),
                      ),
                      columns: columns,
                      rows: rows,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _standardScoreBadge(int? stdScore, Color fasciaColor) {
    if (stdScore == null) {
      return const Text('—', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary));
    }
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fasciaColor.withValues(alpha: 0.14),
        border: Border.all(color: fasciaColor, width: 2.2),
      ),
      child: Center(
        child: Text(
          stdScore.toString(),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: fasciaColor,
          ),
        ),
      ),
    );
  }

  Color _getFasciaColor(String? fascia) {
    switch (fascia) {
      case 'Molto Basso': return const Color(0xFFD32F2F);
      case 'Basso':       return const Color(0xFFF57C00);
      case 'Medio':       return const Color(0xFFFBC02D);
      case 'Alto':        return const Color(0xFF7CB342);
      case 'Molto Alto':  return const Color(0xFF388E3C);
      default:            return AppTheme.textSecondary;
    }
  }

  // ─── Lista risposte con editing inline ─────────────────────────────────────
  Widget _buildAnswersList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Dettaglio Risposte',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                Text('${_editableAnswers.length} domande',
                    style: const TextStyle(color: AppTheme.textSecondary)),
              ],
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _editableAnswers.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFFE8EEF8)),
              itemBuilder: (context, idx) => _buildAnswerRow(idx),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerRow(int idx) {
    final answer = _editableAnswers[idx];
    final question = _findQuestion(answer.codiceDomanda);
    final availableScores = _getAvailableScores(answer.codiceDomanda);

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          answer.codiceDomanda,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: AppTheme.primaryColor,
          ),
        ),
      ),
      subtitle: question != null
          ? Text(
              question.testoDomanda,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textSecondary),
            )
          : null,
      title: Row(
        children: [
          ...availableScores.map((score) {
            final isSelected = answer.punteggio == score;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _isEditMode ? () => setState(() => _editableAnswers[idx].punteggio = score) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryColor : const Color(0xFFDDE7F8),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      score.toString(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          // Etichetta testuale della risposta selezionata
          if (question != null) ...[
            const SizedBox(width: 8),
            const Text('—', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(width: 8),
            Flexible(
              child: Builder(builder: (context) {
                final selectedOption = question.opzioni
                    .cast<Option?>()
                    .firstWhere(
                      (o) => o?.punteggio == answer.punteggio,
                      orElse: () => null,
                    );
                if (selectedOption == null) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.20),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    selectedOption.testoRisposta,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ),
          ],
          const SizedBox(width: 8),
          if (answer.nota != null && answer.nota!.isNotEmpty)
            const Icon(Icons.notes_rounded, size: 16, color: AppTheme.textSecondary),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            controller: _noteControllers.putIfAbsent(
                answer.codiceDomanda,
                () => TextEditingController(text: answer.nota ?? '')),
            onChanged: (val) => _editableAnswers[idx].nota = val,
            maxLines: 2,
            readOnly: !_isEditMode,
            decoration: InputDecoration(
              hintText: 'Aggiungi una nota per questa risposta...',
              prefixIcon: const Icon(Icons.notes_outlined, size: 18),
              filled: true,
              fillColor: const Color(0xFFF3F8FF),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
              ),
            ),
          ),
        ),
        if (question?.note != null && question!.note!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Nota item: ${question.note!}',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }

  Question? _findQuestion(String codiceDomanda) {
    for (final section in widget.scale.sezioni) {
      for (final question in section.domande) {
        if (question.codice == codiceDomanda) {
          return question;
        }
      }
    }
    return null;
  }

  List<int> _getAvailableScores(String codiceDomanda) {
    final question = _findQuestion(codiceDomanda);
    final scores = question?.opzioni.map((option) => option.punteggio).toSet().toList() ?? <int>[];
    scores.sort();
    return scores.isNotEmpty ? scores : <int>[1, 2, 3];
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  final bool isSquare;

  const _LegendItem({
    required this.color,
    required this.label,
    this.dashed = false,
    this.isSquare = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomPaint(
          size: const Size(24, 12),
          painter: _LegendLinePainter(
            color: color, 
            dashed: dashed, 
            isSquare: isSquare,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LegendLinePainter extends CustomPainter {
  final Color color;
  final bool dashed;
  final bool isSquare;

  const _LegendLinePainter({
    required this.color,
    required this.dashed,
    this.isSquare = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isSquare) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(4, 0, size.width - 8, size.height),
          const Radius.circular(2),
        ),
        paint,
      );
      return;
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final start = Offset(0, size.height / 2);
    final end = Offset(size.width, size.height / 2);

    if (dashed) {
      _DashedRadarMeanPainter.drawDashedSegment(
        canvas,
        start,
        end,
        paint,
      );
      return;
    }

    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(covariant _LegendLinePainter oldDelegate) {
    return oldDelegate.color != color || 
        oldDelegate.dashed != dashed || 
        oldDelegate.isSquare != isSquare;
  }
}

class _DashedRadarMeanPainter extends CustomPainter {
  final int axisCount;
  final Color color;
  final double levelFraction;
  final List<double>? patientValues;

  const _DashedRadarMeanPainter({
    required this.axisCount,
    required this.color,
    required this.levelFraction,
    this.patientValues,
  });

  static void drawDashedSegment(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    const dashLength = 7.0;
    const gapLength = 4.0;
    final totalLength = (end - start).distance;
    if (totalLength == 0) return;

    final direction = (end - start) / totalLength;
    double distance = 0;

    while (distance < totalLength) {
      final currentStart = start + (direction * distance);
      final currentEnd = start + (direction * math.min(distance + dashLength, totalLength));
      canvas.drawLine(currentStart, currentEnd, paint);
      distance += dashLength + gapLength;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (axisCount < 3) return;

    final center = Offset(size.width / 2, size.height / 2);

    // 1. Disegna la fascia normativa verde traslucida tra punteggio 8 e 12 (frazioni 0.4 e 0.6)
    final pathOuter = Path();
    final pathInner = Path();
    final rOuter = (math.min(size.width, size.height) / 2) * 0.92 * 0.6; // Score 12
    final rInner = (math.min(size.width, size.height) / 2) * 0.92 * 0.4; // Score 8

    for (var index = 0; index < axisCount; index++) {
      final angle = (-math.pi / 2) + (2 * math.pi * index / axisCount);
      final pOuter = Offset(
        center.dx + (rOuter * math.cos(angle)),
        center.dy + (rOuter * math.sin(angle)),
      );
      final pInner = Offset(
        center.dx + (rInner * math.cos(angle)),
        center.dy + (rInner * math.sin(angle)),
      );
      if (index == 0) {
        pathOuter.moveTo(pOuter.dx, pOuter.dy);
        pathInner.moveTo(pInner.dx, pInner.dy);
      } else {
        pathOuter.lineTo(pOuter.dx, pOuter.dy);
        pathInner.lineTo(pInner.dx, pInner.dy);
      }
    }
    pathOuter.close();
    pathInner.close();

    final bandPaint = Paint()
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.11)
      ..style = PaintingStyle.fill;
    final combinedPath = Path.combine(PathOperation.difference, pathOuter, pathInner);
    canvas.drawPath(combinedPath, bandPaint);

    // 2. Disegna la linea media normativa tratteggiata (Score 10)
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final radius = (math.min(size.width, size.height) / 2) * 0.92 * levelFraction;
    final points = List<Offset>.generate(axisCount, (index) {
      final angle = (-math.pi / 2) + (2 * math.pi * index / axisCount);
      return Offset(
        center.dx + (radius * math.cos(angle)),
        center.dy + (radius * math.sin(angle)),
      );
    });

    for (var index = 0; index < points.length; index++) {
      final start = points[index];
      final end = points[(index + 1) % points.length];
      drawDashedSegment(canvas, start, end, paint);
    }

    // 3. Disegna i badge numerici per ogni punto del profilo del paziente
    if (patientValues != null && patientValues!.length == axisCount) {
      for (var index = 0; index < axisCount; index++) {
        final score = patientValues![index];
        final valFraction = score / 20.0;
        final valRadius = (math.min(size.width, size.height) / 2) * 0.92 * valFraction;
        final angle = (-math.pi / 2) + (2 * math.pi * index / axisCount);

        // Offset per non sovrapporsi al dot di FL Chart
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
              color: Color(0xFF1A237E),
              fontSize: 8.5,
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
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

        // Background badge
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = const Color(0xFFF5F7FA)
            ..style = PaintingStyle.fill,
        );
        // Bordo badge
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = const Color(0xFFDDE7F8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
        // Testo
        tp.paint(canvas, Offset(pText.dx - tp.width / 2, pText.dy - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRadarMeanPainter oldDelegate) {
    return oldDelegate.axisCount != axisCount ||
        oldDelegate.color != color ||
        oldDelegate.levelFraction != levelFraction ||
        oldDelegate.patientValues != patientValues;
  }
}

class _QualityOfLifeHorizontalPainter extends StatelessWidget {
  final List<DomainAnalysis> domains;

  const _QualityOfLifeHorizontalPainter({required this.domains});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _QolHorizontalTablePainter(domains: domains),
    );
  }
}

class _QolHorizontalTablePainter extends CustomPainter {
  final List<DomainAnalysis> domains;

  _QolHorizontalTablePainter({required this.domains});

  @override
  void paint(Canvas canvas, Size size) {
    const double leftMargin = 80.0;
    const double rightMargin = 24.0;
    const double topMargin = 24.0;
    const double bottomMargin = 88.0;
    final double chartHeight = size.height - topMargin - bottomMargin;
    final double chartWidth = size.width - leftMargin - rightMargin;

    final gridPaint = Paint()
      ..color = const Color(0xFFDDE7F8)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    // Helper per convertire il punteggio standard (1-20) in coordinata Y (verticale)
    double getValY(double score) {
      final fraction = (score - 1.0) / 19.0;
      return (topMargin + chartHeight) - (fraction * chartHeight);
    }

    // 1. Disegna le 5 fasce normative orizzontali di sfondo
    final bandItems = [
      (label: 'Molto Alto',  minScore: 15.5, maxScore: 20.0, color: const Color(0xFF388E3C)),
      (label: 'Alto',        minScore: 12.5, maxScore: 15.5, color: const Color(0xFF7CB342)),
      (label: 'Medio',       minScore: 7.5,  maxScore: 12.5, color: const Color(0xFFFBC02D)),
      (label: 'Basso',       minScore: 4.5,  maxScore: 7.5,  color: const Color(0xFFF57C00)),
      (label: 'Molto Basso', minScore: 1.0,  maxScore: 4.5,  color: const Color(0xFFD32F2F)),
    ];

    for (final band in bandItems) {
      final topY = getValY(band.maxScore);
      final bottomY = getValY(band.minScore);
      
      final rect = Rect.fromLTRB(leftMargin, topY, size.width - rightMargin, bottomY);
      final bandPaint = Paint()
        ..color = band.color.withValues(alpha: 0.14)
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, bandPaint);

      // Scrive l'etichetta della fascia sul lato sinistro all'interno della banda
      final bandLabelStyle = TextStyle(
        color: band.color.withValues(alpha: 0.7),
        fontSize: 8.5,
        fontWeight: FontWeight.bold,
      );
      _drawText(canvas, band.label, leftMargin + 8, (topY + bottomY) / 2, bandLabelStyle, anchor: Alignment.centerLeft);
    }

    // 2. Disegna le linee griglia orizzontali per i punteggi chiave (1, 5, 10, 15, 20)
    final gridScores = [1.0, 5.0, 10.0, 15.0, 20.0];
    for (final score in gridScores) {
      final y = getValY(score);
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(size.width - rightMargin, y),
        gridPaint,
      );

      final scoreStyle = const TextStyle(
        color: Color(0xFF718096),
        fontSize: 10,
        fontWeight: FontWeight.bold,
      );
      _drawText(canvas, score.toInt().toString(), leftMargin - 12, y, scoreStyle, anchor: Alignment.centerRight);
    }

    // 3. Calcola colonne dei domini
    if (domains.isEmpty) return;
    final double colWidth = chartWidth / domains.length;

    // Disegna separatori verticali griglia e scritte
    for (var i = 0; i < domains.length; i++) {
      final d = domains[i];
      final colX = leftMargin + (i * colWidth) + (colWidth / 2);

      // Separatore verticale (tra le colonne)
      if (i > 0) {
        final separatorX = leftMargin + (i * colWidth);
        canvas.drawLine(
          Offset(separatorX, topMargin),
          Offset(separatorX, topMargin + chartHeight),
          gridPaint,
        );
      }

      // Codice del dominio (es. AU) sotto l'asse X
      final domainColor = _getDomainColor(i);
      final codeStyle = TextStyle(
        color: domainColor,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      );
      _drawText(canvas, d.codice, colX, topMargin + chartHeight + 14, codeStyle, anchor: Alignment.center);

      // Nome completo esteso (es. Autodeterminazione) con wrapping intelligente
      final labelStyle = const TextStyle(
        color: Color(0xFF2D3748),
        fontSize: 9.0,
        fontWeight: FontWeight.w600,
        height: 1.1,
      );
      _drawWrappedText(canvas, d.etichetta, colX, topMargin + chartHeight + 28, colWidth - 6, labelStyle);
    }

    // 4. Collega i punteggi con una linea di profilo blue/navy semi-trasparente
    final profilePoints = <Offset>[];
    for (var i = 0; i < domains.length; i++) {
      final d = domains[i];
      final stdScore = d.punteggioStandard;
      if (stdScore != null) {
        final colX = leftMargin + (i * colWidth) + (colWidth / 2);
        final scoreY = getValY(stdScore.toDouble());
        profilePoints.add(Offset(colX, scoreY));
      }
    }

    if (profilePoints.length > 1) {
      final linePaint = Paint()
        ..color = const Color(0xFF1A237E).withValues(alpha: 0.45)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      path.moveTo(profilePoints[0].dx, profilePoints[0].dy);
      for (var i = 1; i < profilePoints.length; i++) {
        path.lineTo(profilePoints[i].dx, profilePoints[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // 5. Disegna i cerchietti punteggio (Badge) per ciascun dominio
    for (var i = 0; i < domains.length; i++) {
      final d = domains[i];
      final stdScore = d.punteggioStandard;
      if (stdScore != null) {
        final colX = leftMargin + (i * colWidth) + (colWidth / 2);
        final scoreY = getValY(stdScore.toDouble());
        final bandColor = _getFasciaColor(d.fascia);

        final circlePaint = Paint()
          ..color = bandColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(colX, scoreY), 13, circlePaint);

        final circleBorderPaint = Paint()
          ..color = bandColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5;
        canvas.drawCircle(Offset(colX, scoreY), 16, circleBorderPaint);

        final whiteCirclePaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(colX, scoreY), 11, whiteCirclePaint);
        canvas.drawCircle(Offset(colX, scoreY), 11, circleBorderPaint);

        final scoreTextStyle = TextStyle(
          color: bandColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        );
        _drawText(canvas, stdScore.toString(), colX, scoreY, scoreTextStyle, anchor: Alignment.center);
      }
    }

    // 6. Disegna la legenda in fondo
    final legendY = size.height - 18.0;
    const legendItems = [
      ('Molto Basso', Color(0xFFD32F2F)),
      ('Basso',       Color(0xFFF57C00)),
      ('Medio',       Color(0xFFFBC02D)),
      ('Alto',        Color(0xFF7CB342)),
      ('Molto Alto',  Color(0xFF388E3C)),
    ];

    var legendX = leftMargin + (chartWidth - 5 * 84) / 2;
    for (final item in legendItems) {
      final legendPaint = Paint()
        ..color = item.$2
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(legendX, legendY, 10, 10), const Radius.circular(2)),
        legendPaint,
      );
      final legendStyle = const TextStyle(
        color: Color(0xFF718096),
        fontSize: 9,
        fontWeight: FontWeight.w600,
      );
      _drawText(canvas, item.$1, legendX + 16, legendY + 5, legendStyle, anchor: Alignment.centerLeft);
      legendX += 84;
    }
  }

  void _drawText(Canvas canvas, String text, double x, double y, TextStyle style, {Alignment anchor = Alignment.center}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    double dx = x;
    double dy = y - tp.height / 2;
    if (anchor == Alignment.center) dx -= tp.width / 2;
    if (anchor == Alignment.centerRight) dx -= tp.width;
    tp.paint(canvas, Offset(dx, dy));
  }

  void _drawWrappedText(Canvas canvas, String text, double x, double y, double maxWidth, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, Offset(x - tp.width / 2, y));
  }

  Color _getDomainColor(int index) {
    const colors = [
      Color(0xFF1A237E), Color(0xFFE53935), Color(0xFF43A047),
      Color(0xFFFB8C00), Color(0xFF8E24AA), Color(0xFF00ACC1),
      Color(0xFF3949AB), Color(0xFFF4511E),
    ];
    return colors[index % colors.length];
  }

  Color _getFasciaColor(String? fascia) {
    switch (fascia) {
      case 'Molto Basso': return const Color(0xFFD32F2F);
      case 'Basso':       return const Color(0xFFF57C00);
      case 'Medio':       return const Color(0xFFFBC02D);
      case 'Alto':        return const Color(0xFF7CB342);
      case 'Molto Alto':  return const Color(0xFF388E3C);
      default:            return const Color(0xFF718096);
    }
  }

  @override
  bool shouldRepaint(covariant _QolHorizontalTablePainter oldDelegate) {
    return oldDelegate.domains != domains;
  }
}
