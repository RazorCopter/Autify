// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/patient_model.dart';
import '../models/evaluation_model.dart';
import '../models/scale_model.dart';
import '../services/api_service.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_helper.dart';
import '../widgets/expandable_scale_card.dart';
import 'evaluation_detail_screen.dart';
import 'settings_screen.dart';
import 'document_reader_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:ui' as ui;

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
  String _geminiModel = 'gemini-2.5-pro';
  bool _viewerAiEnabled = false;
  String? _geminiPrompt;

  List<ScaleModel> _availableScales = [];
  Map<String, AggregatedEvaluation> _latestEvaluations = {};
  Map<String, List<AggregatedEvaluation>> _evaluationsHistory = {};
  Map<String, PsychometricAnalysis?> _analyses = {};
  String? _aiReport;
  String? _aiError;

  final TextEditingController _aiNotesController = TextEditingController();
  PlatformFile? _aiAttachment;
  bool _isExportingPdf = false;

  List<Map<String, dynamic>> _savedAnalyses = [];
  final List<String> _selectedAnalysesIdsForContext = [];
  bool _isSavingAnalysis = false;

  bool _includePos = true;
  bool _includeSm = true;
  bool _includeSis = true;
  bool _includeHistory = true;
  bool _includeSavedAnalyses = true;

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
    _geminiKey = settings['key'] as String?;
    _viewerAiEnabled = (settings['viewer_ai_enabled'] as bool?) ?? false;
    _geminiPrompt = settings['prompt'] as String?;
    final String rawModel = (settings['model'] as String?) ?? 'gemini-1.5-pro';
    if (rawModel.contains('1.5-pro') || rawModel == 'gemini-1.5-pro') {
      _geminiModel = 'gemini-2.5-pro';
    } else if (rawModel.contains('1.5-flash') || rawModel == 'gemini-1.5-flash') {
      _geminiModel = 'gemini-2.5-flash';
    } else {
      if (rawModel != 'gemini-2.5-pro' && rawModel != 'gemini-2.5-flash' && rawModel != 'gemini-3.5-flash') {
        _geminiModel = 'gemini-2.5-pro';
      } else {
        _geminiModel = rawModel;
      }
    }

    // 2. Carica scale disponibili
    _availableScales = await _apiService.getScales();

    // 3. Carica ultima valutazione + analisi psicometrica per ogni scala
    for (final scale in _availableScales) {
      final history = await _apiService.getAggregatedEvaluationHistory(widget.patient.id, scale.id);
      if (history.isNotEmpty) {
        history.sort((a, b) => b.dataCompilazione.compareTo(a.dataCompilazione));
        _latestEvaluations[scale.id] = history.first;
        _evaluationsHistory[scale.id] = history;
        // Carica analisi psicometrica
        try {
          final analysis = await _apiService.getEvaluationAnalysis(history.first.idValutazione);
          _analyses[scale.id] = analysis;
        } catch (_) {
          _analyses[scale.id] = null;
        }
      }
    }

    await _loadSavedAnalyses();

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

  bool _isBehaviorScale(String id, String nome) {
    final lowerId = id.toLowerCase();
    final lowerNome = nome.toLowerCase();
    return lowerId.contains('sabs') || lowerId.contains('behavior') || lowerId.contains('comportament') || lowerId.contains('odflab') ||
           lowerNome.contains('sabs') || lowerNome.contains('behavior') || lowerNome.contains('comportament') || lowerNome.contains('odflab');
  }

  bool _isSisScale(String scaleId, [String? scaleName]) {
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
    return normalizedId.contains('sis') ||
        normalizedName.contains('sis') ||
        normalizedId.contains('supportsintensity') ||
        normalizedName.contains('supportsintensity');
  }

  Future<void> _runAiAnalysis() async {
    if (_geminiKey == null || _geminiKey!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chiave API Gemini non configurata nelle impostazioni.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _aiReport = null;
      _aiError = null;
    });

    try {
      final List<AggregatedEvaluation> evaluationsToInclude = [];

      for (final scale in _availableScales) {
        final isSM = _isSanMartinScale(scale.id, scale.nome);
        final isSIS = _isSisScale(scale.id, scale.nome);
        final isPOS = !isSM && !isSIS;

        if (isPOS && !_includePos) continue;
        if (isSM && !_includeSm) continue;
        if (isSIS && !_includeSis) continue;

        if (_includeHistory) {
          final history = _evaluationsHistory[scale.id];
          if (history != null) {
            evaluationsToInclude.addAll(history);
          }
        } else {
          final latest = _latestEvaluations[scale.id];
          if (latest != null) {
            evaluationsToInclude.add(latest);
          }
        }
      }

      if (evaluationsToInclude.isEmpty &&
          _aiNotesController.text.trim().isEmpty &&
          _aiAttachment == null) {
        throw Exception('Nessun dato (valutazione, note o allegato) selezionato per l\'analisi.');
      }

      Map<String, dynamic>? attachmentMap;
      if (_aiAttachment != null && _aiAttachment!.bytes != null) {
        attachmentMap = {
          'bytes': _aiAttachment!.bytes!,
          'extension': _aiAttachment!.extension ?? 'pdf',
        };
      }

      final historyToInclude = _includeSavedAnalyses
          ? _savedAnalyses
              .where((a) => _selectedAnalysesIdsForContext.contains(a['id']?.toString()))
              .toList()
          : <Map<String, dynamic>>[];

      final report = await _geminiService.analyzePatientData(
        widget.patient,
        evaluationsToInclude,
        _geminiKey!,
        _geminiModel,
        systemPrompt: _geminiPrompt,
        notes: _aiNotesController.text,
        attachment: attachmentMap,
        historyToInclude: historyToInclude,
        analyses: _analyses,
      );

      setState(() {
        _aiReport = report;
      });

      // Auto-salvataggio in background
      await _autoSaveAnalysis();

    } catch (e) {
      String cleanError = e.toString();
      if (cleanError.startsWith('Exception: ')) {
        cleanError = cleanError.substring(11);
      }
      setState(() {
        _aiError = cleanError;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore: $cleanError'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  Future<void> _autoSaveAnalysis() async {
    if (_aiReport == null || _isSavingAnalysis) return;
    setState(() => _isSavingAnalysis = true);
    try {
      final notes = _aiNotesController.text;
      
      final result = await _apiService.savePatientAiAnalysis(
        widget.patient.id,
        _aiReport!,
        notes: notes,
        evaluationsUsed: _latestEvaluations.values.map((e) => e.idValutazione).toList(),
      );
      if (result != null) {
        // Puliamo i campi temporanei
        _aiNotesController.clear();
        _aiAttachment = null;
        _selectedAnalysesIdsForContext.clear();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Relazione elaborata e salvata automaticamente!'),
            backgroundColor: Colors.teal,
          ),
        );
        await _loadSavedAnalyses();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Errore durante il salvataggio automatico della relazione.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore auto-salvataggio: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      setState(() => _isSavingAnalysis = false);
    }
  }

  Future<void> _pickAiAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _aiAttachment = result.files.first;
      });
    }
  }

  Future<void> _loadSavedAnalyses() async {
    try {
      final analyses = await _apiService.getPatientAiAnalyses(widget.patient.id);
      setState(() {
        _savedAnalyses = analyses;
      });
    } catch (e) {
      debugPrint('Errore caricamento storico analisi: $e');
    }
  }

  Future<void> _renameSavedAnalysisLabel(String id, String currentLabel) async {
    final controller = TextEditingController(text: currentLabel);
    final newLabel = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rinomina Nota Relazione'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nota / Label Relazione',
            hintText: 'Esempio: Inserimento scala 1a e 2a',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Salva'),
          ),
        ],
      ),
    );

    if (newLabel != null) {
      try {
        final success = await _apiService.updateAiAnalysisLabel(id, newLabel);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nota della relazione aggiornata con successo.'),
              backgroundColor: Colors.teal,
            ),
          );
          await _loadSavedAnalyses();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impossibile aggiornare la nota.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _deleteSavedAnalysis(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conferma Eliminazione'),
        content: const Text('Sei sicuro di voler eliminare questa analisi dallo storico? Questa azione non può essere annullata.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final success = await _apiService.deleteAiAnalysis(id);
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Analisi eliminata con successo.'),
              backgroundColor: Colors.teal,
            ),
          );
          _selectedAnalysesIdsForContext.remove(id);
          await _loadSavedAnalyses();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impossibile eliminare l\'analisi.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _exportAiPdf() async {
    if (_aiReport == null || _isExportingPdf) return;
    setState(() => _isExportingPdf = true);
    
    try {
      final bytes = await _apiService.downloadAiAnalysisPdf(
        widget.patient,
        _aiReport!,
      );

      if (bytes != null) {
        final b64 = base64Encode(bytes);
        final dataUrl = 'data:application/pdf;base64,$b64';
        html.AnchorElement(href: dataUrl)
          ..setAttribute(
              'download', 'analisi_ai_${widget.patient.cognome}.pdf')
          ..click();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Errore generazione PDF AI')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppTheme.backgroundColor,
            appBar: AppBar(
              title: const Text('Analisi Utente', style: TextStyle(fontWeight: FontWeight.bold)),
              bottom: TabBar(
                tabs: const [
                  Tab(icon: Icon(Icons.self_improvement_outlined), text: 'Qualità della Vita'),
                  Tab(icon: Icon(Icons.accessibility_new_outlined), text: 'Comp. Adattivo'),
                  Tab(icon: Icon(Icons.psychology_outlined), text: 'Analisi IA'),
                ],
                indicatorColor: AppTheme.primaryColor,
                labelColor: AppTheme.primaryColor,
                unselectedLabelColor: AppTheme.textSecondary,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                indicatorWeight: 3,
                dividerColor: const Color(0xFFE8EEF8),
              ),
            ),
            body: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _buildQualitaVitaTab(),
                      _buildBehaviorTab(),
                      _buildAiTab(),
                    ],
                  ),
          ),
          if (_isAnalyzing)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    color: Colors.black.withValues(alpha: 0.55),
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Card(
                          elevation: 20,
                          shadowColor: AppTheme.primaryColor.withValues(alpha: 0.25),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white,
                                  AppTheme.primaryColor.withValues(alpha: 0.04),
                                ],
                              ),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 48, horizontal: 36),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _SlothPuzzleLoader(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TAB 1: QUALITÀ DELLA VITA (POS + San Martín + SIS)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildQualitaVitaTab() {
    final lifeScales = _availableScales
        .where((s) => _latestEvaluations.containsKey(s.id) && !_isBehaviorScale(s.id, s.nome))
        .toList();

    // Ordina le scale per stabilità di visualizzazione: POS, San Martín, SIS
    lifeScales.sort((a, b) {
      final isASis = _isSisScale(a.id, a.nome);
      final isBSis = _isSisScale(b.id, b.nome);
      final isASM = _isSanMartinScale(a.id, a.nome);
      final isBSM = _isSanMartinScale(b.id, b.nome);
      
      int valA = isASis ? 2 : (isASM ? 1 : 0);
      int valB = isBSis ? 2 : (isBSM ? 1 : 0);
      return valA.compareTo(valB);
    });

    // Rileva se POS e SM entrambi presenti per il compare toggle
    AggregatedEvaluation? posEval;
    AggregatedEvaluation? smEval;
    for (final scale in lifeScales) {
      final isSM = _isSanMartinScale(scale.id, scale.nome);
      if (isSM) {
        smEval = _latestEvaluations[scale.id];
      } else if (!_isSisScale(scale.id, scale.nome)) {
        posEval = _latestEvaluations[scale.id];
      }
    }
    final bool canCompare = posEval != null && smEval != null;
    final isMobile = ResponsiveHelper.isMobile(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header utente fisso ──────────────────────────────────────────
          _buildPatientHeader(),
          const SizedBox(height: 20),

          if (lifeScales.isEmpty) ...[
            _buildEmptyScalesPlaceholder(
              icon: Icons.self_improvement_outlined,
              message: 'Nessuna scala di Qualità della Vita compilata.',
            ),
          ] else ...[
            // ── Compare Toggle (solo se POS + SM presenti) ──────────────
            if (canCompare) ...[
              _buildCompareToggle(canCompare),
              const SizedBox(height: 16),
            ],

            // ── Compare Panel o Accordion Cards ─────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation),
                  child: child,
                ),
              ),
              child: _isCompareMode && posEval != null && smEval != null
                  ? _buildComparePanel(posEval, smEval)
                  : (!isMobile
                      ? Row(
                          key: const ValueKey('qdv_row_desktop'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: lifeScales.map((scale) {
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: _buildExpandableScaleCard(scale, initiallyExpanded: true),
                              ),
                            );
                          }).toList(),
                        )
                      : Column(
                          key: const ValueKey('qdv_accordion_mobile'),
                          children: lifeScales.map((scale) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildExpandableScaleCard(scale),
                            );
                          }).toList(),
                        )),
            ),
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // TAB 2: COMPORTAMENTO ADATTIVO (ODFLAB + SABS)
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildBehaviorTab() {
    final behaviorScales = _availableScales
        .where((s) => _latestEvaluations.containsKey(s.id) && _isBehaviorScale(s.id, s.nome))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header compatto per comportamento adattivo ──────────────────
          _buildBehaviorTabHeader(),
          const SizedBox(height: 20),

          if (behaviorScales.isEmpty) ...[
            _buildEmptyScalesPlaceholder(
              icon: Icons.accessibility_new_outlined,
              message: 'Nessuna scala di Comportamento Adattivo compilata.',
            ),
          ] else ...[
            ...behaviorScales.map((scale) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildExpandableScaleCard(scale),
            )),
          ],
        ],
      ),
    );
  }

  /// Header compatto per il tab Comportamento Adattivo
  Widget _buildBehaviorTabHeader() {
    final p = widget.patient;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF3949AB), Color(0xFF5C6BC0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Center(
              child: Text(
                '${p.nome.isNotEmpty ? p.nome[0] : ''}${p.cognome.isNotEmpty ? p.cognome[0] : ''}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.nome} ${p.cognome}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Comportamento Adattivo — Scale di valutazione funzionale',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.assessment_outlined, color: Colors.white70, size: 14),
                const SizedBox(width: 6),
                Text(
                  '${_availableScales.where((s) => _latestEvaluations.containsKey(s.id) && _isBehaviorScale(s.id, s.nome)).length} scale',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Costruisce una ExpandableScaleCard per qualsiasi scala
  Widget _buildExpandableScaleCard(ScaleModel scale, {bool initiallyExpanded = false}) {
    final eval = _latestEvaluations[scale.id]!;
    final analysis = _analyses[scale.id];
    final isSM = _isSanMartinScale(scale.id, scale.nome);
    final isSis = _isSisScale(scale.id, scale.nome);
    final isBehavior = _isBehaviorScale(scale.id, scale.nome);

    final List<Color> gradientColors = isSis
        ? const [Color(0xFF00695C), Color(0xFF26A69A)]
        : isBehavior
            ? const [Color(0xFFFFB300), Color(0xFFF57C00)] // Gradiente dal giallo all'arancio
            : isSM
                ? const [Color(0xFF1A237E), Color(0xFF3949AB)]
                : const [Color(0xFF0D47A1), Color(0xFF1565C0)];

    // Icona per tipo di scala
    final IconData scaleIcon = isSis
        ? Icons.support_outlined
        : isBehavior
            ? Icons.accessibility_new_outlined
            : isSM
                ? Icons.psychology_alt_outlined
                : Icons.self_improvement_outlined;

    // Summary chips per stato chiuso
    final List<Widget> summaryChips = _buildSummaryChips(eval, analysis, isSM, isSis, isBehavior, gradientColors.first);

    // Azioni header (Storico + Dettaglio)
    final List<Widget> headerActions = [
      if ((_evaluationsHistory[scale.id]?.length ?? 0) > 1)
        _headerActionButton(
          icon: Icons.timeline,
          label: 'Storico',
          color: Colors.amber.shade700,
          onTap: () => _showTimelineDialog(scale),
        ),
      _headerActionButton(
        icon: Icons.open_in_new,
        label: 'Dettaglio',
        color: Colors.white.withValues(alpha: 0.18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EvaluationDetailScreen(patient: widget.patient, scale: scale)),
        ),
      ),
    ];

    // Contenuto espanso (riusa esattamente i widget già esistenti)
    final Widget expandedContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMetaRow(eval),
        const SizedBox(height: 20),
        if (isSis)
          _buildSisIndicators(eval, analysis)
        else if (isSM && analysis != null)
          _buildSanMartinIndicators(analysis)
        else if (!isSM)
          _buildPosIndicators(eval),
        const SizedBox(height: 20),
        if (eval.domini.isNotEmpty)
          SizedBox(
            height: (isSM && analysis != null && analysis.domini.isNotEmpty) ? 250 : (eval.domini.length > 10 ? 295 : 250),
            child: isSM && analysis != null && analysis.domini.isNotEmpty
                ? _buildRadarChartForPanel(analysis)
                : _buildBarChartForPanel(
                    eval.domini,
                    isSm: isSM,
                    isSis: isSis,
                    isSabs: scale.id.toLowerCase().contains("sabs") || scale.nome.toLowerCase().contains("sabs"),
                  ),
          ),
      ],
    );

    return ExpandableScaleCard(
      title: isSis
          ? 'Supports Intensity Scale (SIS)'
          : isSM
              ? 'Scala San Martín'
              : scale.nome,
      subtitle: isBehavior
          ? 'Valutazione comportamenti adattivi e abilità funzionali'
          : isSis
              ? 'Valutazione dell\'intensità dei bisogni di sostegno'
              : isSM
                  ? 'Valutazione osservativa della qualità di vita'
                  : 'Valutazione degli esiti personali e della QdV percepita',
      icon: scaleIcon,
      gradientColors: gradientColors,
      summaryChips: summaryChips,
      expandedContent: expandedContent,
      headerActions: headerActions,
      initiallyExpanded: initiallyExpanded,
    );
  }

  /// Costruisce i chip di summary per lo stato chiuso della card
  List<Widget> _buildSummaryChips(
    AggregatedEvaluation eval,
    PsychometricAnalysis? analysis,
    bool isSM,
    bool isSis,
    bool isBehavior,
    Color accentColor,
  ) {
    final List<Widget> chips = [];

    if (isSM && analysis != null) {
      if (analysis.indiceQv != null) {
        chips.add(ScaleSummaryChip(
          label: 'Indice QV',
          value: analysis.indiceQv.toString(),
          accentColor: accentColor,
          icon: Icons.favorite_outline,
        ));
      }
      if (analysis.percentile != null) {
        chips.add(ScaleSummaryChip(
          label: 'Percentile',
          value: '${analysis.percentile}°',
          accentColor: accentColor,
          icon: Icons.leaderboard_outlined,
        ));
      }
      if (analysis.fasciaQv != null) {
        chips.add(ScaleSummaryChip(
          label: 'Fascia',
          value: analysis.fasciaQv!,
          accentColor: accentColor,
          icon: Icons.verified_outlined,
        ));
      }
    } else if (isSis) {
      int total = eval.domini.fold(0, (s, d) => s + d.punteggio);
      chips.add(ScaleSummaryChip(
        label: analysis != null && analysis.indiceQv != null ? 'Indice SIS' : 'Punteggio',
        value: analysis != null && analysis.indiceQv != null
            ? analysis.indiceQv.toString()
            : total.toString(),
        accentColor: accentColor,
        icon: Icons.analytics_outlined,
      ));
      if (analysis != null && analysis.percentile != null) {
        chips.add(ScaleSummaryChip(
          label: 'Percentile',
          value: '${analysis.percentile}°',
          accentColor: accentColor,
          icon: Icons.speed_outlined,
        ));
      }
      chips.add(ScaleSummaryChip(
        label: 'Domini',
        value: '${eval.domini.length}',
        accentColor: accentColor,
        icon: Icons.grid_view_outlined,
      ));
    } else {
      // POS o scale behavior (SABS, ODFLAB)
      int total = eval.domini.fold(0, (s, d) => s + d.punteggio);
      chips.add(ScaleSummaryChip(
        label: 'Totale',
        value: total.toString(),
        accentColor: accentColor,
        icon: Icons.score_outlined,
      ));
      if (eval.domini.isNotEmpty) {
        chips.add(ScaleSummaryChip(
          label: 'Media',
          value: (total / eval.domini.length).toStringAsFixed(1),
          accentColor: accentColor,
          icon: Icons.bar_chart_outlined,
        ));
      }
      chips.add(ScaleSummaryChip(
        label: 'Compilata il',
        value: _formatDateReadable(eval.dataCompilazione.split('T')[0]),
        accentColor: accentColor,
        icon: Icons.calendar_today_outlined,
      ));
    }

    // ── Sparkline trend (ultime ≤3 compilazioni) ──────────────────────────
    final history = _evaluationsHistory[eval.idScala];
    if (history != null && history.length >= 2) {
      final sorted = List<AggregatedEvaluation>.from(history)
        ..sort((a, b) => a.dataCompilazione.compareTo(b.dataCompilazione));
      final recent = sorted.length > 3 ? sorted.sublist(sorted.length - 3) : sorted;

      // Calcola il totale punteggio per ogni valutazione storica
      final totals = recent.map((e) => e.domini.fold(0, (s, d) => s + d.punteggio).toDouble()).toList();

      // Trend: confronta l'ultima con la penultima
      final trend = totals.length >= 2 ? totals.last - totals[totals.length - 2] : 0.0;
      final trendIcon = trend > 0 ? '↑' : (trend < 0 ? '↓' : '→');
      final trendColor = trend > 0
          ? const Color(0xFF4ADE80)
          : (trend < 0 ? const Color(0xFFF87171) : Colors.white60);

      chips.add(ScaleSummaryChip(
        label: 'Trend',
        value: '$trendIcon ${trend.abs().toStringAsFixed(0)}pt',
        accentColor: trendColor,
        icon: Icons.show_chart_outlined,
      ));
    }

    return chips;
  }

  /// Bottone azione compatto per l'header della ExpandableScaleCard
  Widget _headerActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 4),
              Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  /// Placeholder quando un tab non ha scale compilate
  Widget _buildEmptyScalesPlaceholder({required IconData icon, required String message}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 64),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppTheme.primaryColor.withValues(alpha: 0.3)),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
                    'Compara POS & San Martín',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    canCompare
                        ? 'Confronto domini comuni normalizzati (0–100%). SIS esclusa.'
                        : 'Compila POS e San Martín per sbloccare la comparazione.',
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
            activeThumbColor: AppTheme.primaryColor,
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
                        'Comparazione',
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
    final isMobile = ResponsiveHelper.isMobile(context);

    final avatar = Container(
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
    );

    final info = Column(
      crossAxisAlignment: isMobile ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          '${p.nome} ${p.cognome}',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.5),
          textAlign: isMobile ? TextAlign.center : TextAlign.left,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          alignment: isMobile ? WrapAlignment.center : WrapAlignment.start,
          children: [
            if (age != null)
              _headerChip(Icons.cake_outlined, '$age anni'),
            if (p.sesso != null && p.sesso!.isNotEmpty)
              _headerChip(Icons.person_outline, p.sesso!),
            if (p.dataNascita != null)
              _headerChip(Icons.calendar_today_outlined, _formatDateReadable(p.dataNascita!.split('T')[0])),
          ],
        ),
      ],
    );

    final badge = Container(
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
    );

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
      child: isMobile
          ? Column(
              children: [
                avatar,
                const SizedBox(height: 16),
                info,
                const SizedBox(height: 24),
                badge,
              ],
            )
          : Row(
              children: [
                avatar,
                const SizedBox(width: 24),
                Expanded(child: info),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [badge],
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

  void _showTimelineDialog(ScaleModel scale) {
    final history = _evaluationsHistory[scale.id]!;
    // Sort ascending for chart (oldest first)
    final sorted = List<AggregatedEvaluation>.from(history)..sort((a, b) => a.dataCompilazione.compareTo(b.dataCompilazione));

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 800,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timeline, color: AppTheme.primaryColor),
                        const SizedBox(width: 12),
                        Text('Storico Punteggi: ${scale.nome}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Visualizzazione dell\'andamento dei domini nel tempo (normalizzato a 100%).', style: TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 24),
                SizedBox(
                  height: 400,
                  child: _buildTimelineChart(sorted, scale),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildTimelineChart(List<AggregatedEvaluation> sorted, ScaleModel scale) {
    // Collect all domain codes and their labels
    final Map<String, String> codeToLabel = {};
    for (var eval in sorted) {
      for (var d in eval.domini) {
        if (!codeToLabel.containsKey(d.codice)) {
          codeToLabel[d.codice] = d.etichetta;
        }
      }
    }
    final codeList = codeToLabel.keys.toList();

    return Column(
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              minX: -0.5,
              maxX: sorted.isNotEmpty ? sorted.length - 0.5 : 0.5,
              minY: 0,
              maxY: 100,
              lineBarsData: codeList.map((code) {
                int colorIndex = codeList.indexOf(code) % _domainColors.length;
                final color = _domainColors[colorIndex];
                return LineChartBarData(
                  spots: sorted.asMap().entries.map((e) {
                    final idx = e.key;
                    final eval = e.value;
                    final domain = eval.domini.firstWhere(
                      (d) => d.codice == code, 
                      orElse: () => DomainScore(codice: code, etichetta: '', punteggio: 0, numDomande: 0)
                    );
                    
                    if (domain.numDomande == 0) {
                       return FlSpot(idx.toDouble(), 0);
                    }

                    // Normalize to 100%
                    final isPos = scale.nome.toLowerCase().contains('pos');
                    final isSM = scale.nome.toLowerCase().contains('martin');
                    final isSis = scale.nome.toLowerCase().contains('sis');
                    
                    double maxTheoretical = domain.numDomande.toDouble();
                    if (isPos) {
                      maxTheoretical *= 3;
                    } else if (isSM) {
                      maxTheoretical *= 4;
                    } else if (isSis) {
                      if (code == 'SEZ3M' || code == 'SEZ3C') {
                        maxTheoretical *= 2;
                      } else {
                        maxTheoretical *= 12; // A, B, C, D, E, F, SEZ2
                      }
                    } else {
                      maxTheoretical = 100; // Default fallback
                    }
                    
                    if (maxTheoretical == 0) maxTheoretical = 1;
                    final percent = (domain.punteggio / maxTheoretical) * 100.0;
                    return FlSpot(idx.toDouble(), percent);
                  }).toList(),
                  isCurved: true,
                  color: color,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                );
              }).toList(),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 60,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= sorted.length || value != idx.toDouble()) return const SizedBox.shrink();
                      
                      final dateParts = sorted[idx].dataCompilazione.split('T')[0].split('-');
                      final dateStr = dateParts.length == 3 ? '${dateParts[2]}/${dateParts[1]}/${dateParts[0]}' : sorted[idx].dataCompilazione.split('T')[0];
                      
                      return Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Transform.rotate(
                          angle: -0.6,
                          child: Text(dateStr, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      return Text('${value.toInt()}%', style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary));
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: 20,
                getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade300, strokeWidth: 1, dashArray: [5, 5]),
                getDrawingVerticalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => Colors.blueGrey.shade900.withValues(alpha: 0.9),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final code = codeList[spot.barIndex];
                      final eval = sorted[spot.x.toInt()];
                      final domain = eval.domini.firstWhere((d) => d.codice == code, orElse: () => DomainScore(codice: code, etichetta: code, punteggio: 0, numDomande: 0));
                      return LineTooltipItem(
                        '${domain.etichetta}\n${spot.y.toStringAsFixed(1)}%',
                        TextStyle(color: _domainColors[spot.barIndex % _domainColors.length], fontWeight: FontWeight.bold, fontSize: 12),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Legend
        Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: codeList.map((code) {
            int colorIndex = codeList.indexOf(code) % _domainColors.length;
            final color = _domainColors[colorIndex];
            final label = codeToLabel[code] ?? code;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Converte una data ISO (2026-05-14) in formato leggibile (14 Mag 2026)
  /// e aggiunge "X giorni fa" se meno di 60 giorni.
  static String _formatDateReadable(String isoDate) {
    try {
      final parts = isoDate.split('T')[0].split('-');
      if (parts.length != 3) return isoDate;
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);
      final date = DateTime(year, month, day);
      const months = ['Gen', 'Feb', 'Mar', 'Apr', 'Mag', 'Giu', 'Lug', 'Ago', 'Set', 'Ott', 'Nov', 'Dic'];
      final formatted = '$day ${months[month - 1]} $year';
      final diff = DateTime.now().difference(date).inDays;
      if (diff == 0) return '$formatted (oggi)';
      if (diff <= 60) return '$formatted (${diff}gg fa)';
      return formatted;
    } catch (_) {
      return isoDate;
    }
  }

  Widget _buildMetaRow(AggregatedEvaluation eval) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        _metaChip(Icons.calendar_today, 'Data', _formatDateReadable(eval.dataCompilazione.split('T')[0])),
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

  /// Restituisce colori semantici per fascia interpretativa.
  /// Supporta: Molto Basso/Basso/Medio/Alto/Molto Alto (SM) e Livello I/II/III/IV (SIS).
  static ({Color bg, Color text, IconData icon}) _fasciaColors(String value) {
    final lv = value.toLowerCase();
    // Fasce SM
    if (lv.contains('molto alto')) return (bg: const Color(0xFF14532D).withValues(alpha: 0.35), text: const Color(0xFF86EFAC), icon: Icons.arrow_upward_rounded);
    if (lv.contains('alto')) return (bg: const Color(0xFF166534).withValues(alpha: 0.3), text: const Color(0xFF4ADE80), icon: Icons.trending_up_rounded);
    if (lv.contains('medio')) return (bg: const Color(0xFF854D0E).withValues(alpha: 0.3), text: const Color(0xFFFBBF24), icon: Icons.trending_flat_rounded);
    if (lv.contains('molto basso')) return (bg: const Color(0xFF7F1D1D).withValues(alpha: 0.35), text: const Color(0xFFFCA5A5), icon: Icons.arrow_downward_rounded);
    if (lv.contains('basso')) return (bg: const Color(0xFF991B1B).withValues(alpha: 0.3), text: const Color(0xFFF87171), icon: Icons.trending_down_rounded);
    // Livelli SIS (I = basso bisogno, IV = alto bisogno)
    if (lv.contains('livello iv')) return (bg: const Color(0xFF7F1D1D).withValues(alpha: 0.35), text: const Color(0xFFFCA5A5), icon: Icons.arrow_upward_rounded);
    if (lv.contains('livello iii')) return (bg: const Color(0xFF854D0E).withValues(alpha: 0.3), text: const Color(0xFFFBBF24), icon: Icons.trending_up_rounded);
    if (lv.contains('livello ii')) return (bg: const Color(0xFF166534).withValues(alpha: 0.3), text: const Color(0xFF4ADE80), icon: Icons.trending_flat_rounded);
    if (lv.contains('livello i')) return (bg: const Color(0xFF14532D).withValues(alpha: 0.35), text: const Color(0xFF86EFAC), icon: Icons.trending_down_rounded);
    // Default
    return (bg: Colors.blue.withValues(alpha: 0.2), text: Colors.lightBlueAccent, icon: Icons.info_outline_rounded);
  }

  Widget _indicatorBadge({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    final colors = _fasciaColors(value);

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
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.text.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(colors.icon, color: colors.text, size: 14),
                const SizedBox(width: 6),
                Text(value, style: TextStyle(color: colors.text, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
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

    return Container(
      padding: const EdgeInsets.all(16),
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
          _buildPosLegend(eval),
        ],
      ),
    );
  }

  Widget _buildPosLegend(AggregatedEvaluation eval) {
    final domains = eval.domini;
    if (domains.isEmpty) return const SizedBox.shrink();

    // Dividiamo i domini in 2 colonne
    final int itemsPerCol = (domains.length / 2).ceil();
    final List<List<DomainScore>> columns = [[], []];
    
    for (int i = 0; i < domains.length; i++) {
      final colIndex = i ~/ itemsPerCol;
      if (colIndex < 2) {
        columns[colIndex].add(domains[i]);
      } else {
        columns[1].add(domains[i]);
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.legend_toggle_outlined, color: Colors.amberAccent, size: 14),
              SizedBox(width: 6),
              Text(
                'Legenda Domini',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(2, (colIdx) {
              final colItems = columns[colIdx];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: colItems.map((d) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '• ',
                              style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.2),
                                  children: [
                                    TextSpan(
                                      text: '${d.codice.toUpperCase()}: ',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                    ),
                                    TextSpan(text: d.etichetta),
                                    TextSpan(
                                      text: ' (${d.punteggio})',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── SIS indicators ───────────────────────────────────────────────────────────
  Widget _buildSisIndicators(AggregatedEvaluation eval, PsychometricAnalysis? analysis) {
    int totalGrezzo = 0;
    for (final d in eval.domini) {
      totalGrezzo += d.punteggio;
    }
    
    final String mainTitle1 = analysis != null ? 'Indice SIS' : 'Punteggio Grezzo';
    final String mainValue1 = analysis != null && analysis.indiceQv != null ? analysis.indiceQv.toString() : totalGrezzo.toString();
    final String sub1 = analysis != null ? 'Somma standard: ${analysis.sommaPunteggiStandard ?? 0}' : '${eval.domini.length} domini analizzati';
    
    final String mainTitle2 = analysis != null ? 'Percentile Globale' : 'Media per Dominio';
    final String mainValue2 = analysis != null && analysis.percentile != null
        ? '${analysis.percentile}°'
        : (eval.domini.isNotEmpty ? (totalGrezzo / eval.domini.length).toStringAsFixed(1) : '—');
    final String sub2 = 'vs. campione normativo';

    // Classificazione intensità SIS come badge colorato
    final String? classificazione = analysis?.fasciaQv;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF004D40), Color(0xFF00897B)],
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
                title: mainTitle1,
                value: mainValue1,
                subtitle: sub1,
                icon: Icons.analytics,
                color: Colors.amberAccent,
              )),
              const SizedBox(width: 16),
              Expanded(child: _indicatorTile(
                title: mainTitle2,
                value: mainValue2,
                subtitle: sub2,
                icon: Icons.speed,
                color: const Color(0xFF80CBC4),
              )),
            ],
          ),
          if (classificazione != null) ...[
            const SizedBox(height: 12),
            _indicatorBadge(
              title: 'Classificazione Intensità',
              value: classificazione,
              subtitle: 'Livello di intensità del supporto richiesto',
              icon: Icons.verified,
            ),
          ],
          _buildSisLegend(eval),
        ],
      ),
    );
  }

  Widget _buildSisLegend(AggregatedEvaluation eval) {
    final domains = eval.domini;
    if (domains.isEmpty) return const SizedBox.shrink();

    // Separa Sezione 1 (A-F) dalle sezioni supplementari (SEZ2, SEZ3M, SEZ3C)
    final sez1 = domains.where((d) {
      final c = d.codice.toUpperCase();
      return c.length == 1 && 'ABCDEF'.contains(c);
    }).toList();
    final sezSuppl = domains.where((d) {
      final c = d.codice.toUpperCase();
      return !('ABCDEF'.contains(c) && c.length == 1);
    }).toList();

    Widget _legendRow(DomainScore d, Color bullet) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: bullet, fontSize: 13, fontWeight: FontWeight.bold)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.2),
                children: [
                  TextSpan(text: '${d.codice.toUpperCase()}: ', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  TextSpan(text: d.etichetta),
                  TextSpan(text: ' (${d.punteggio})', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Sezione 1: Domini A-F ──────────────────────────────────────
          const Row(
            children: [
              Icon(Icons.legend_toggle_outlined, color: Colors.amberAccent, size: 14),
              SizedBox(width: 6),
              Text('Sezione 1 — Attività (A–F)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          if (sez1.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: sez1.sublist(0, (sez1.length / 2).ceil()).map((d) => _legendRow(d, Colors.amberAccent)).toList())),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: sez1.sublist((sez1.length / 2).ceil()).map((d) => _legendRow(d, Colors.amberAccent)).toList())),
              ],
            ),

          // ── Sezioni supplementari ──────────────────────────────────────
          if (sezSuppl.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 8),
            const Row(
              children: [
                Icon(Icons.add_circle_outline_rounded, color: Color(0xFF80CBC4), size: 13),
                SizedBox(width: 6),
                Text('Sezioni Supplementari (Sez. 2 & 3)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            ...sezSuppl.map((d) => _legendRow(d, const Color(0xFF80CBC4))),
          ],
        ],
      ),
    );
  }

  // ── Radar Chart (San Martín) ────────────────────────────────────────────────
  Widget _buildRadarChartForPanel(PsychometricAnalysis analysis) {
    final domini = analysis.domini;
    if (domini.isEmpty) return const SizedBox();

    final patientValues = domini
        .map((d) => ((d.punteggioStandard ?? d.punteggioDiretto).clamp(0, 20)).toDouble())
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

  Widget _buildBarChartForPanel(List<DomainScore> domini, {bool isSm = false, bool isSis = false, bool isSabs = false}) {
    if (domini.isEmpty) return const SizedBox();

    // Calcola il maxY dinamico basato sul punteggio massimo + 5
    double maxVal = 0;
    for (final d in domini) {
      final double score = d.punteggio.toDouble();
      if (score > maxVal) maxVal = score;
    }
    double dynamicMaxY = maxVal + 5.0;
    if (dynamicMaxY < 10.0) dynamicMaxY = 10.0;

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
                reservedSize: domini.length > 10 ? 75 : 40,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= domini.length) return const SizedBox.shrink();
                  
                  final titleWidget = Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      domini[idx].codice,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      textAlign: TextAlign.center,
                    ),
                  );

                  if (domini.length > 10) {
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 2,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: titleWidget,
                      ),
                    );
                  }

                  return titleWidget;
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
            final double toYValue = domini[i].punteggio.toDouble();
            final double backYValue = dynamicMaxY;
            
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

  Widget _buildPatientDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color iconBgColor,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compactCheckbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: CheckboxListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        value: value,
        activeColor: AppTheme.primaryColor,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildAttachmentTile() {
    return InkWell(
      onTap: _isAnalyzing ? null : _pickAiAttachment,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _aiAttachment == null
              ? Colors.deepPurple.shade50.withValues(alpha: 0.3)
              : Colors.deepPurple.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _aiAttachment == null
                ? Colors.deepPurple.shade100
                : Colors.deepPurple.shade200,
            width: 1,
          ),
        ),
        child: _aiAttachment == null
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_upload_outlined, color: Colors.deepPurple.shade300, size: 20),
                  const SizedBox(width: 10),
                  const Text(
                    'Allega Documentazione (PDF, TXT, Immagini)',
                    style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ],
              )
            : Row(
                children: [
                  const Icon(Icons.insert_drive_file, color: Colors.deepPurple, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _aiAttachment!.name,
                      style: const TextStyle(fontSize: 12, color: Colors.deepPurple, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                    onPressed: () => setState(() => _aiAttachment = null),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAiTab() {
    final Widget leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ═══ CARD UNIFICATA: Configurazione & Avvio Analisi ═══
        Card(
          elevation: 2,
          shadowColor: Colors.indigo.shade100.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE8EEF8)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Sezione 1: Profilo Utente ──
                _buildSectionHeader(
                  icon: Icons.account_circle_outlined,
                  title: 'Profilo Utente',
                  subtitle: '${widget.patient.cognome} ${widget.patient.nome}',
                  iconBgColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                  iconColor: AppTheme.primaryColor,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 32,
                  runSpacing: 12,
                  children: [
                    _buildPatientDetailItem('Sesso', widget.patient.sesso ?? '—'),
                    _buildPatientDetailItem('Età', _calculateAge() != null ? '${_calculateAge()} anni' : '—'),
                    _buildPatientDetailItem('Data di Nascita', widget.patient.dataNascita != null ? _formatDateReadable(widget.patient.dataNascita!.split('T')[0]) : '—'),
                  ],
                ),
                if (widget.patient.note != null && widget.patient.note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade100),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.amber.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.patient.note!,
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade900, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                const Divider(height: 1, color: Color(0xFFE8EEF8)),
                const SizedBox(height: 28),

                // ── Sezione 2: Scale da Includere ──
                _buildSectionHeader(
                  icon: Icons.tune_outlined,
                  title: 'Scale da Includere',
                  subtitle: 'Seleziona quali dati inviare a Gemini per l\'analisi',
                  iconBgColor: Colors.indigo.shade50,
                  iconColor: Colors.indigo.shade600,
                ),
                const SizedBox(height: 12),
                _compactCheckbox('Scala POS (Qualità della Vita)', _includePos, (v) => setState(() => _includePos = v ?? true)),
                _compactCheckbox('Scala San Martín', _includeSm, (v) => setState(() => _includeSm = v ?? true)),
                _compactCheckbox('Scala SIS (Supports Intensity Scale)', _includeSis, (v) => setState(() => _includeSis = v ?? true)),

                const SizedBox(height: 24),
                const Divider(height: 1, color: Color(0xFFE8EEF8)),
                const SizedBox(height: 24),

                // ── Sezione 3: Opzioni Contesto ──
                _buildSectionHeader(
                  icon: Icons.history_rounded,
                  title: 'Contesto Aggiuntivo',
                  subtitle: 'Arricchisci l\'analisi con dati storici e relazioni pregresse',
                  iconBgColor: Colors.teal.shade50,
                  iconColor: Colors.teal.shade700,
                ),
                const SizedBox(height: 12),
                _compactCheckbox('Storico Scale (trend temporale)', _includeHistory, (v) => setState(() => _includeHistory = v ?? true)),
                _compactCheckbox('Storico Valutazioni IA (relazioni pregresse)', _includeSavedAnalyses, (v) => setState(() => _includeSavedAnalyses = v ?? true)),

                const SizedBox(height: 24),
                const Divider(height: 1, color: Color(0xFFE8EEF8)),
                const SizedBox(height: 24),

                // ── Sezione 4: Note e Allegato ──
                _buildSectionHeader(
                  icon: Icons.add_circle_outline,
                  title: 'Dati Aggiuntivi',
                  subtitle: 'Note testuali e documentazione allegata (opzionale)',
                  iconBgColor: Colors.deepPurple.shade50,
                  iconColor: Colors.deepPurple.shade400,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _aiNotesController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Osservazioni, contesto familiare o scolastico...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 12),
                _buildAttachmentTile(),

                const SizedBox(height: 28),
                const Divider(height: 1, color: Color(0xFFE8EEF8)),
                const SizedBox(height: 24),

                // ── Pulsante Avvia Analisi ──
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: (_isAnalyzing || (ApiService.isViewer && !_viewerAiEnabled))
                          ? [Colors.grey.shade400, Colors.grey.shade400]
                          : [Colors.deepPurple.shade700, Colors.indigo.shade600],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: (_isAnalyzing || (ApiService.isViewer && !_viewerAiEnabled)) ? null : _runAiAnalysis,
                    icon: _isAnalyzing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
                    label: Text(
                      _isAnalyzing ? 'Elaborazione in corso...' : 'Avvia Analisi con IA',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Premium Success State Card ──
        if (_aiReport != null && !_isAnalyzing) ...[
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.teal.shade200, width: 1.5),
            ),
            color: Colors.teal.shade50.withValues(alpha: 0.3),
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
                          color: Colors.teal.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, color: Colors.teal, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text(
                          'Sintesi Generata!',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'La nuova relazione è stata completata con successo ed è stata salvata automaticamente nello storico.',
                    style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DocumentReaderScreen(
                                  patient: widget.patient,
                                  report: _aiReport!,
                                  onExportPdf: _exportAiPdf,
                                  isExportingPdf: _isExportingPdf,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.chrome_reader_mode_outlined),
                          label: const Text(
                            'Apri Relazione (Lettura A4)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.deepPurple.shade900,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isExportingPdf ? null : _exportAiPdf,
                        icon: _isExportingPdf
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.picture_as_pdf),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    final Widget rightColumn = Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8EEF8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_toggle_off_rounded, color: Colors.teal.shade700, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Storico Relazioni IA',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ),
                if (_selectedAnalysesIdsForContext.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Text(
                      '${_selectedAnalysesIdsForContext.length} selezionate',
                      style: TextStyle(color: Colors.teal.shade800, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_savedAnalyses.isEmpty) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.archive_outlined, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      const Text(
                        'Nessuna relazione in archivio.',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'I report generati appariranno qui automaticamente.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: Colors.teal.shade700, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Seleziona le relazioni passate dell\'utente per iniettarle come contesto nella prossima analisi di Gemini, valutando l\'andamento educativo e di supporto nel tempo.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.teal.shade900,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _savedAnalyses.length,
                separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, index) {
                  final analysis = _savedAnalyses[index];
                  final String id = analysis['id']?.toString() ?? '';
                  final String report = analysis['report']?.toString() ?? '';
                  final String? notes = analysis['notes']?.toString();
                  final String rawTimestamp = analysis['timestamp']?.toString() ?? '';

                  String formattedTimestamp = rawTimestamp;
                  try {
                    final parsed = DateTime.parse(rawTimestamp).toLocal();
                    final day = parsed.day.toString().padLeft(2, '0');
                    final month = parsed.month.toString().padLeft(2, '0');
                    final year = parsed.year;
                    final hour = parsed.hour.toString().padLeft(2, '0');
                    final minute = parsed.minute.toString().padLeft(2, '0');
                    formattedTimestamp = '$day/$month/$year $hour:$minute';
                  } catch (_) {}

                  final isChecked = _selectedAnalysesIdsForContext.contains(id);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Checkbox(
                          value: isChecked,
                          activeColor: Colors.teal.shade700,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (bool? val) {
                            setState(() {
                              if (val == true) {
                                _selectedAnalysesIdsForContext.add(id);
                              } else {
                                _selectedAnalysesIdsForContext.remove(id);
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Relazione del $formattedTimestamp',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              if (notes != null && notes.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Note: $notes',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Leggi Relazione',
                          icon: Icon(Icons.chrome_reader_mode_outlined, color: Colors.indigo.shade600, size: 20),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => DocumentReaderScreen(
                                  patient: widget.patient,
                                  report: report,
                                  onExportPdf: () async {
                                    if (_isExportingPdf) return;
                                    setState(() => _isExportingPdf = true);
                                    try {
                                      final bytes = await _apiService.downloadAiAnalysisPdf(
                                        widget.patient,
                                        report,
                                      );
                                      if (bytes != null) {
                                        final b64 = base64Encode(bytes);
                                        final dataUrl = 'data:application/pdf;base64,$b64';
                                        html.AnchorElement(href: dataUrl)
                                          ..setAttribute(
                                              'download', 'analisi_ai_${widget.patient.cognome}_$formattedTimestamp.pdf')
                                          ..click();
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Errore generazione PDF AI')));
                                      }
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
                                    } finally {
                                      setState(() => _isExportingPdf = false);
                                    }
                                  },
                                  isExportingPdf: _isExportingPdf,
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Rinomina Nota/Label',
                          icon: Icon(Icons.edit_outlined, color: Colors.blue.shade700, size: 20),
                          onPressed: () => _renameSavedAnalysisLabel(id, notes ?? ''),
                        ),
                        IconButton(
                          tooltip: 'Elimina Relazione',
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          onPressed: () => _deleteSavedAnalysis(id),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ApiService.isViewer && !_viewerAiEnabled) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'L\'accesso alle funzionalità IA di analisi dei dati utente è attualmente disabilitato per il profilo Viewer. Contatta un amministratore per abilitarlo.',
                      style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple.shade700, Colors.deepPurple.shade400],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.psychology, color: Colors.white, size: 40),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Analisi con Intelligenza Artificiale',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'L\'IA analizza le valutazioni aggregate per individuare correlazioni, punti di forza/debolezza e suggerire linee guida di supporto personalizzate.',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          if (_aiError != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _aiError!,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (_aiError!.contains('mancante') ||
                      _aiError!.contains('Chiave API') ||
                      _aiError!.contains('API key') ||
                      _aiError!.contains('non valida'))
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                      child: const Text('Vai a Impostazioni'),
                    ),
                ],
              ),
            ),
          ],

          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth > 1000) {
                // Desktop two-column layout
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: leftColumn,
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 2,
                      child: rightColumn,
                    ),
                  ],
                );
              } else {
                // Mobile single-column layout
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leftColumn,
                    const SizedBox(height: 24),
                    rightColumn,
                  ],
                );
              }
            },
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

class _SlothPuzzleLoader extends StatefulWidget {
  const _SlothPuzzleLoader();

  @override
  State<_SlothPuzzleLoader> createState() => _SlothPuzzleLoaderState();
}

class _SlothPuzzleLoaderState extends State<_SlothPuzzleLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_PuzzlePiece> _pieces = [];
  final math.Random _random = math.Random();
  
  int _textIndex = 0;
  late final List<String> _loadingTexts;
  
  final int N = 5; // 5x5 grid = 25 pezzi
  final double imageSize = 280.0;
  late final double tileSize;
  
  @override
  void initState() {
    super.initState();
    tileSize = imageSize / N;

    _loadingTexts = [
      'Inizializzazione modulo psicometrico...',
      'Elaborazione correlazioni POS e San Martín...',
      'Definizione del profilo...',
      'Generazione raccomandazioni psico-educative...',
      'Stesura del referto di sintesi tramite IA...',
    ];

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    // Inizializza i pezzi del puzzle
    for (int i = 0; i < N; i++) {
      for (int j = 0; j < N; j++) {
        _pieces.add(_PuzzlePiece(
          row: i,
          col: j,
          startDx: (_random.nextDouble() - 0.5) * 400, // Dispersione ampia
          startDy: (_random.nextDouble() - 0.5) * 400,
          startAngle: (_random.nextDouble() - 0.5) * 4 * math.pi, // Rotazione casuale
          delay: _random.nextDouble() * 0.4, // Iniziano ad assemblarsi tra 0.0 e 0.4
        ));
      }
    }

    _cycleTexts();
  }

  void _cycleTexts() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 2500));
      if (mounted) {
        setState(() {
          _textIndex = (_textIndex + 1) % _loadingTexts.length;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 420,
          height: 420,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final double t = _controller.value;
              
              // Pulsazione e bagliore quando assemblato
              double masterScale = 1.0;
              double glowOpacity = 0.0;
              if (t >= 0.7 && t <= 0.85) {
                final pulse = math.sin((t - 0.7) / 0.15 * math.pi);
                masterScale = 1.0 + pulse * 0.05;
                glowOpacity = pulse;
              }

              return Stack(
                alignment: Alignment.center,
                children: [
                  // Bagliore dietro al puzzle
                  if (glowOpacity > 0.01)
                    Opacity(
                      opacity: glowOpacity * 0.4,
                      child: Container(
                        width: imageSize + 20,
                        height: imageSize + 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryColor,
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Scala principale
                  Transform.scale(
                    scale: masterScale,
                    child: Stack(
                      alignment: Alignment.center,
                      children: _pieces.map((piece) {
                        // Calcolo progresso pezzo (p)
                        double p = 0.0;
                        if (t < 0.7) {
                           double start = piece.delay;
                           double end = start + 0.3; // ogni pezzo ci mette 30% del tempo
                           double localT = ((t - start) / (end - start)).clamp(0.0, 1.0);
                           p = Curves.easeOutBack.transform(localT); // effetto aggancio magnetico
                        } else if (t < 0.85) {
                           p = 1.0;
                        } else {
                           double explodeT = ((t - 0.85) / 0.15).clamp(0.0, 1.0);
                           p = 1.0 - Curves.easeInQuint.transform(explodeT); // esplosione veloce
                        }

                        // Posizione base (assemblata)
                        final double baseX = (piece.col - (N - 1) / 2) * tileSize;
                        final double baseY = (piece.row - (N - 1) / 2) * tileSize;

                        // Posizione attuale (interpolata tra start e base)
                        final double dx = piece.startDx * (1.0 - p);
                        final double dy = piece.startDy * (1.0 - p);
                        final double angle = piece.startAngle * (1.0 - p);

                        // Opacità
                        final double opacity = p < 0.1 ? (p / 0.1) : 1.0;

                        // Bordo che svanisce quando agganciato
                        final double borderOpacity = (1.0 - p).clamp(0.0, 1.0);

                        return Transform.translate(
                          offset: Offset(baseX + dx, baseY + dy),
                          child: Transform.rotate(
                            angle: angle,
                            child: Opacity(
                              opacity: opacity,
                              child: Container(
                                width: tileSize,
                                height: tileSize,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: borderOpacity * 0.5),
                                    width: 1.0,
                                  ),
                                ),
                                child: ClipRect(
                                  child: OverflowBox(
                                    maxWidth: imageSize,
                                    maxHeight: imageSize,
                                    alignment: Alignment(
                                      -1.0 + (2.0 / (N - 1)) * piece.col,
                                      -1.0 + (2.0 / (N - 1)) * piece.row,
                                    ),
                                    child: Image.asset(
                                      'assets/images/avatar_bradipo_hd..png',
                                      width: imageSize,
                                      height: imageSize,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 32),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.2),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Text(
            _loadingTexts[_textIndex],
            key: ValueKey<String>(_loadingTexts[_textIndex]),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryColor,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _PuzzlePiece {
  final int row;
  final int col;
  final double startDx;
  final double startDy;
  final double startAngle;
  final double delay;

  _PuzzlePiece({
    required this.row,
    required this.col,
    required this.startDx,
    required this.startDy,
    required this.startAngle,
    required this.delay,
  });
}
