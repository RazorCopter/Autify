import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/scale_model.dart';
import '../models/patient_model.dart';
import '../models/evaluation_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sis_3d_item_card.dart';
import '../widgets/sis_medical_list.dart';
import '../widgets/sis_ranking_widget.dart';

class SisWizardScreen extends StatefulWidget {
  final String patientId;
  final String scaleId;

  const SisWizardScreen({
    super.key,
    required this.patientId,
    required this.scaleId,
  });

  @override
  State<SisWizardScreen> createState() => _SisWizardScreenState();
}

class _SisWizardScreenState extends State<SisWizardScreen> with TickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  ScaleModel? _scale;
  PatientModel? _patient;

  // --- STATE MANAGEMENT ---
  // answers: codice_domanda -> Map {"F": int, "D": int, "T": int} (for A-F & SEZ2) OR int (for SEZ3)
  final Map<String, dynamic> _answers = {};
  final Map<String, String> _notes = {}; // codice_domanda -> nota text
  List<String> _customTop4Ranking = [];

  // --- NAVIGATION STATE ---
  int _activeMacroStep = 0; // 0: Intake, 1: Sez 1 (A-F), 2: Sez 2 (Protezione), 3: Sez 3 (Eccezionali), 4: Riepilogo
  int _activeSubscaleIndex = 0; // 0 to 5 for A-F subscales in Sez 1

  // --- CONTROLLER & INTAKE STATES ---
  final _dataController = TextEditingController();
  final _operatoreController = TextEditingController();
  final _intervistatoController = TextEditingController();

  // Socio-demographics
  String? _livelloAssistenza; // 'Esteso' | 'Generalizzato'
  String? _livelloDipendenza; // 'Grado I' | 'Grado II' | 'Grado III'
  final _percentualeDisabilitaController = TextEditingController();
  final _annoCertificatoController = TextEditingController();

  // Conditions
  bool _disFisica = false;
  bool _limArtiSuperiori = false;
  bool _limArtiInferiori = false;
  bool _disSensoriale = false;
  bool _uditoSordita = false;
  bool _visiva = false;
  bool _paralisiCerebrale = false;
  bool _epilessia = false;
  bool _saluteMentale = false;
  bool _spettroAutistico = false;
  bool _sindromeDown = false;
  bool _graviProblemiSalute = false;
  bool _disturbiCondotta = false;
  final _altroCondizioniController = TextEditingController();

  // Informatori
  final _inf1NomeController = TextEditingController();
  final _inf1AnniController = TextEditingController();
  final _inf1MesiController = TextEditingController();
  String? _inf1Frequenza;
  String? _inf1Relazione;
  final _inf1RelazioneAltroController = TextEditingController();

  bool _inf2Abilitato = false;
  final _inf2NomeController = TextEditingController();
  final _inf2AnniController = TextEditingController();
  final _inf2MesiController = TextEditingController();
  String? _inf2Frequenza;
  String? _inf2Relazione;
  final _inf2RelazioneAltroController = TextEditingController();

  late TabController _subscaleTabController;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dataController.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _subscaleTabController = TabController(length: 6, vsync: this);
    _subscaleTabController.addListener(() {
      setState(() {
        _activeSubscaleIndex = _subscaleTabController.index;
      });
    });
    _loadData();
  }

  @override
  void dispose() {
    _dataController.dispose();
    _operatoreController.dispose();
    _intervistatoController.dispose();
    _percentualeDisabilitaController.dispose();
    _annoCertificatoController.dispose();
    _altroCondizioniController.dispose();
    _inf1NomeController.dispose();
    _inf1AnniController.dispose();
    _inf1MesiController.dispose();
    _inf1RelazioneAltroController.dispose();
    _inf2NomeController.dispose();
    _inf2AnniController.dispose();
    _inf2MesiController.dispose();
    _inf2RelazioneAltroController.dispose();
    _subscaleTabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getScaleById(widget.scaleId),
        _apiService.getPatients(),
      ]);

      _scale = results[0] as ScaleModel?;
      final patients = results[1] as List<PatientModel>;
      _patient = patients.firstWhere((p) => p.id == widget.patientId);

      // Pre-compila nome operatore di default se noto
      _operatoreController.text = "Operatore AutAnalysis";

      // Correggi i codici di SEZ3C per evitare la collisione con la Sottoscala C
      if (_scale != null) {
        for (final sec in _scale!.sezioni) {
          if (sec.codiceSezione == 'SEZ3C') {
            for (int i = 0; i < sec.domande.length; i++) {
              final q = sec.domande[i];
              final cod = q.codice ?? q.idDomanda;
              if (cod.startsWith('C') && !cod.startsWith('BC')) {
                final newCod = 'BC${cod.substring(1)}';
                sec.domande[i] = Question(
                  idDomanda: newCod,
                  codice: newCod,
                  testoDomanda: q.testoDomanda,
                  note: q.note,
                  opzioni: q.opzioni,
                );
              }
            }
          }
        }
      }

      // Pre-inizializza TUTTE le risposte SEZ3M e SEZ3C a 0 ("Assente").
      // Il valore 0 è una risposta valida e deve essere incluso nel salvataggio.
      // Questo evita il bug per cui la sezione appare come "0/N completata"
      // se l'utente non tocca nessun bottone.
      if (_scale != null) {
        for (final sec in _scale!.sezioni) {
          if (sec.codiceSezione == 'SEZ3M' || sec.codiceSezione == 'SEZ3C') {
            for (final q in sec.domande) {
              final k = q.codice ?? q.idDomanda;
              if (!_answers.containsKey(k)) {
                _answers[k] = 0;
              }
            }
          }
        }
      }
    } catch (e) {
      print("Errore caricamento wizard: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- BUSINESS LOGIC ---
  List<Question> _getQuestionsForSubscale(String code) {
    if (_scale == null) return [];
    final sec = _scale!.sezioni.firstWhere(
      (s) => s.codiceSezione?.toUpperCase() == code.toUpperCase(),
      orElse: () => Section(titoloSezione: '', domande: []),
    );
    return sec.domande;
  }

  int _getSubscaleRawScore(String code) {
    final questions = _getQuestionsForSubscale(code);
    int total = 0;
    for (final q in questions) {
      final key = q.codice ?? q.idDomanda;
      final ans = _answers[key];
      if (ans is Map) {
        total += (ans['F'] as int? ?? 0);
        total += (ans['D'] as int? ?? 0);
        total += (ans['T'] as int? ?? 0);
      }
    }
    return total;
  }

  int _getSezioneCompletedCount(String sectionCode) {
    final questions = _getQuestionsForSubscale(sectionCode);
    // SEZ3M e SEZ3C: il valore 0 ("Assente") è una risposta valida;
    // pre-inizializziamo tutte le domande a 0 al caricamento, quindi
    // contiamo semplicemente quante chiavi esistono in _answers.
    // In questo modo la sezione è sempre considerata completa non appena
    // la scala è caricata (comportamento corretto per la SIS).
    if (sectionCode == 'SEZ3M' || sectionCode == 'SEZ3C') {
      return questions.length; // Sempre completata
    }
    int count = 0;
    for (final q in questions) {
      final key = q.codice ?? q.idDomanda;
      final ans = _answers[key];
      if (ans is Map && ans['F'] != null && ans['D'] != null && ans['T'] != null) {
        count++;
      }
    }
    return count;
  }

  bool _isSubscaleComplete(String code) {
    final questions = _getQuestionsForSubscale(code);
    if (questions.isEmpty) return false;
    return _getSezioneCompletedCount(code) == questions.length;
  }

  List<int> _getDisabledFrequenciesForQuestion(Question q) {
    final note = q.note?.toLowerCase() ?? '';
    if (note.contains('frequenza max = 3') || note.contains('frequenza max=3') || q.codice == 'A3') {
      return [4]; // Disable the '4' option
    }
    return [];
  }

  void _saveEvaluation() async {
    if (ApiService.isViewer) return;
    
    // Validate Operator Name
    if (_operatoreController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Inserire il nome dell'operatore per salvare."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Build demographicsData
    final Map<String, dynamic> demographicsData = {
      'persona': {
        'livello_assistenza': _livelloAssistenza,
        'livello_dipendenza': _livelloDipendenza,
        'percentuale_disabilita': int.tryParse(_percentualeDisabilitaController.text),
        'anno_certificato': int.tryParse(_annoCertificatoController.text),
        'condizioni': {
          'disabilita_fisica': _disFisica,
          'lim_arti_superiori': _limArtiSuperiori,
          'lim_arti_inferiori': _limArtiInferiori,
          'disabilita_sensoriale': _disSensoriale,
          'udito_sordita': _uditoSordita,
          'visiva': _visiva,
          'paralisi_cerebrale': _paralisiCerebrale,
          'epilessia': _epilessia,
          'salute_mentale': _saluteMentale,
          'spettro_autistico': _spettroAutistico,
          'sindrome_down': _sindromeDown,
          'gravi_problemi_salute': _graviProblemiSalute,
          'disturbi_condotta': _disturbiCondotta,
          'altro_specifica': _altroCondizioniController.text,
        }
      },
      'informatore1': {
        'nome_cognome': _inf1NomeController.text,
        'contatto_anni': int.tryParse(_inf1AnniController.text),
        'contatto_mesi': int.tryParse(_inf1MesiController.text),
        'frequenza_contatto': _inf1Frequenza,
        'relazione': _inf1Relazione,
        'relazione_altro': _inf1RelazioneAltroController.text,
      },
      'informatore2': _inf2Abilitato ? {
        'nome_cognome': _inf2NomeController.text,
        'contatto_anni': int.tryParse(_inf2AnniController.text),
        'contatto_mesi': int.tryParse(_inf2MesiController.text),
        'frequenza_contatto': _inf2Frequenza,
        'relazione': _inf2Relazione,
        'relazione_altro': _inf2RelazioneAltroController.text,
      } : null,
      'top4_tutela': _customTop4Ranking,
    };

    // Flatten answers
    final List<AnswerModel> answersList = [];
    _answers.forEach((key, val) {
      answersList.add(AnswerModel(
        codiceDomanda: key,
        punteggio: val,
        nota: _notes[key],
      ));
    });

    // Make sure we include all items (prefilled with default zeros if not answered, to ensure API computes scores)
    final allKeys = <String>[];
    for (final sec in _scale!.sezioni) {
      for (final q in sec.domande) {
        final k = q.codice ?? q.idDomanda;
        allKeys.add(k);
        if (!_answers.containsKey(k)) {
          final is3D = sec.codiceSezione == 'A' || sec.codiceSezione == 'B' || sec.codiceSezione == 'C' || 
                       sec.codiceSezione == 'D' || sec.codiceSezione == 'E' || sec.codiceSezione == 'F' || 
                       sec.codiceSezione == 'SEZ2';
          answersList.add(AnswerModel(
            codiceDomanda: k,
            punteggio: is3D ? {"F": 0, "D": 0, "T": 0} : 0,
            nota: null,
          ));
        }
      }
    }

    final evaluation = EvaluationModel(
      idPaziente: widget.patientId,
      idScala: widget.scaleId,
      anno: DateTime.now().year,
      nomeOperatore: _operatoreController.text.trim(),
      nomeIntervistato: _intervistatoController.text.trim().isNotEmpty ? _intervistatoController.text.trim() : null,
      dataCompilazione: _dataController.text.isNotEmpty ? _dataController.text : null,
      demographics: demographicsData,
      risposte: answersList,
    );

    final success = await _apiService.saveEvaluation(evaluation);
    setState(() => _isLoading = false);

    if (success && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 44),
              ),
              const SizedBox(height: 20),
              const Text('Valutazione Completata',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              const Text(
                'Tutti i punteggi standard ed eccezionali per la SIS sono stati salvati ed elaborati.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx); // Close dialog
                    Navigator.pop(context, true); // Return to list with success
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Ritorna all\'Anagrafica'),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Impossibile salvare la valutazione. Riprovare."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // --- RENDER HELPERS ---
  @override
  Widget build(BuildContext context) {
    if (_isLoading || _scale == null || _patient == null) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryColor)),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${_patient!.nome} ${_patient!.cognome}",
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppTheme.textPrimary),
            ),
            Text(
              _scale!.nome,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        shape: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Annullare la compilazione?'),
                content: const Text('Tutte le risposte inserite finora andranno perse.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Continua compilazione'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Annulla e esci'),
                  ),
                ],
              ),
            );
            if (confirm == true && mounted) {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: isWide ? _buildWideLayout() : _buildCompactLayout(),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // NavigationRail
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          width: 240,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            children: [
              _buildRailItem(0, Icons.info_outline_rounded, "1. Anagrafica / Intake"),
              _buildRailItem(1, Icons.dashboard_customize_rounded, "2. Sottoscale A-F", progressCode: "A-F"),
              _buildRailItem(2, Icons.shield_outlined, "3. Protezione & Tutela", progressCode: "SEZ2"),
              _buildRailItem(3, Icons.local_hospital_outlined, "4. Bisogni Eccezionali", progressCode: "SEZ3"),
              _buildRailItem(4, Icons.playlist_add_check_rounded, "5. Riepilogo & Salva"),
            ],
          ),
        ),
        // Central View
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(28.0),
            child: _buildActiveStepContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout() {
    return Column(
      children: [
        // Horizontal Macro Navigation
        Container(
          color: Colors.white,
          height: 60,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _buildHorizontalTabItem(0, "Intake"),
              _buildHorizontalTabItem(1, "A-F"),
              _buildHorizontalTabItem(2, "Tutela"),
              _buildHorizontalTabItem(3, "Eccezionali"),
              _buildHorizontalTabItem(4, "Riepilogo"),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        // Central content scrollable
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildActiveStepContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildRailItem(int index, IconData icon, String title, {String? progressCode}) {
    final isActive = _activeMacroStep == index;
    int completed = 0;
    int total = 0;

    if (progressCode == "A-F") {
      for (final dom in ["A", "B", "C", "D", "E", "F"]) {
        total += _getQuestionsForSubscale(dom).length;
        completed += _getSezioneCompletedCount(dom);
      }
    } else if (progressCode == "SEZ2") {
      total = _getQuestionsForSubscale("SEZ2").length;
      completed = _getSezioneCompletedCount("SEZ2");
    } else if (progressCode == "SEZ3") {
      total = _getQuestionsForSubscale("SEZ3M").length + _getQuestionsForSubscale("SEZ3C").length;
      completed = _getSezioneCompletedCount("SEZ3M") + _getSezioneCompletedCount("SEZ3C");
    }

    final hasProgress = total > 0;
    final isDone = hasProgress && completed == total;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () => setState(() => _activeMacroStep = index),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.primaryColor.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isActive
                    ? AppTheme.primaryColor
                    : isDone
                        ? const Color(0xFF16A34A)
                        : AppTheme.textSecondary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                        color: isActive ? AppTheme.primaryColor : AppTheme.textPrimary,
                      ),
                    ),
                    if (hasProgress) ...[
                      const SizedBox(height: 2),
                      Text(
                        isDone ? "Completato" : "$completed / $total comp.",
                        style: TextStyle(
                          fontSize: 11,
                          color: isDone ? const Color(0xFF16A34A) : AppTheme.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isDone)
                const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalTabItem(int index, String title) {
    final isActive = _activeMacroStep == index;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive ? Colors.white : AppTheme.textPrimary,
          ),
        ),
        selected: isActive,
        onSelected: (val) {
          if (val) {
            setState(() => _activeMacroStep = index);
          }
        },
        selectedColor: AppTheme.primaryColor,
        backgroundColor: const Color(0xFFF1F5F9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide.none,
        showCheckmark: false,
      ),
    );
  }

  // --- FLOATING BOTTOM ACTION BAR ---
  Widget _buildBottomActions() {
    final isLastStep = _activeMacroStep == 4;
    final isFirstStep = _activeMacroStep == 0;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Indietro
          if (!isFirstStep)
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _activeMacroStep--;
                });
              },
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Indietro'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
            )
          else
            const SizedBox.shrink(),

          // Procedi o Salva
          FilledButton.icon(
            onPressed: isLastStep ? _saveEvaluation : () {
              setState(() {
                _activeMacroStep++;
              });
            },
            icon: Icon(isLastStep ? Icons.save_rounded : Icons.arrow_forward_rounded, size: 18),
            label: Text(isLastStep ? 'Salva Valutazione' : 'Procedi'),
            style: FilledButton.styleFrom(
              backgroundColor: isLastStep ? const Color(0xFF16A34A) : AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // --- RENDERING ROUTER FOR ACTIVE STEP ---
  Widget _buildActiveStepContent() {
    switch (_activeMacroStep) {
      case 0:
        return _buildIntakeStep();
      case 1:
        return _buildSezione1Step();
      case 2:
        return _buildSezione2Step();
      case 3:
        return _buildSezione3Step();
      case 4:
        return _buildSummaryStep();
      default:
        return const SizedBox.shrink();
    }
  }

  // 1. INTAKE STEP
  Widget _buildIntakeStep() {
    final isTablet = MediaQuery.of(context).size.width > 650;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          const Text(
            "Anagrafica & Dati Preliminari (Intake)",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.textPrimary, letterSpacing: -0.5),
          ),
          const SizedBox(height: 6),
          const Text(
            "Compila i metadati dell'operatore, informatori e i dati clinici socio-demografici del soggetto.",
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),

          // Bento Card: Info Generali
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE2E8F0))),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.assignment_ind_outlined, color: AppTheme.primaryColor, size: 20),
                      SizedBox(width: 8),
                      Text("1. Informazioni di Valutazione", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dataController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Data Compilazione',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.tryParse(_dataController.text) ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() {
                                _dataController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _operatoreController,
                          decoration: InputDecoration(
                            labelText: 'Operatore compilante *',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            prefixIcon: const Icon(Icons.badge_outlined, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _intervistatoController,
                    decoration: InputDecoration(
                      labelText: 'Soggetto intervistato / Relatore secondario',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.people_alt_outlined, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bento Card: Persona Esaminata & Stato Clinico
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE2E8F0))),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.local_hospital_outlined, color: Color(0xFFFB8C00), size: 20),
                      SizedBox(width: 8),
                      Text("2. Persona Esaminata (Dati Socio-Demografici)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _livelloAssistenza,
                          decoration: InputDecoration(
                            labelText: 'Livello Assistenza Richiesto',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Esteso', child: Text('Esteso')),
                            DropdownMenuItem(value: 'Generalizzato', child: Text('Generalizzato')),
                          ],
                          onChanged: (val) => setState(() => _livelloAssistenza = val),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _livelloDipendenza,
                          decoration: InputDecoration(
                            labelText: 'Grado di Dipendenza',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Grado I', child: Text('Grado I')),
                            DropdownMenuItem(value: 'Grado II', child: Text('Grado II')),
                            DropdownMenuItem(value: 'Grado III', child: Text('Grado III')),
                          ],
                          onChanged: (val) => setState(() => _livelloDipendenza = val),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _percentualeDisabilitaController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Percentuale Disabilità (%)',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _annoCertificatoController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Anno del Certificato',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Divider(color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 12),
                  const Text("Condizioni cliniche associate (Selezionare tutte quelle applicabili):",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary)),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: isTablet ? 3 : 2,
                    childAspectRatio: 4.5,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildCheckboxTile("Disabilità Fisica", _disFisica, (v) => setState(() => _disFisica = v!)),
                      _buildCheckboxTile("Limitazioni arti sup.", _limArtiSuperiori, (v) => setState(() => _limArtiSuperiori = v!)),
                      _buildCheckboxTile("Limitazioni arti inf.", _limArtiInferiori, (v) => setState(() => _limArtiInferiori = v!)),
                      _buildCheckboxTile("Disabilità Sensoriale", _disSensoriale, (v) => setState(() => _disSensoriale = v!)),
                      _buildCheckboxTile("Sordità / Ipoacusia", _uditoSordita, (v) => setState(() => _uditoSordita = v!)),
                      _buildCheckboxTile("Minorazione Visiva", _visiva, (v) => setState(() => _visiva = v!)),
                      _buildCheckboxTile("Paralisi Cerebrale", _paralisiCerebrale, (v) => setState(() => _paralisiCerebrale = v!)),
                      _buildCheckboxTile("Epilessia", _epilessia, (v) => setState(() => _epilessia = v!)),
                      _buildCheckboxTile("Salute Mentale / Psichiatrica", _saluteMentale, (v) => setState(() => _saluteMentale = v!)),
                      _buildCheckboxTile("Spettro Autistico", _spettroAutistico, (v) => setState(() => _spettroAutistico = v!)),
                      _buildCheckboxTile("Sindrome di Down", _sindromeDown, (v) => setState(() => _sindromeDown = v!)),
                      _buildCheckboxTile("Gravi probl. salute medica", _graviProblemiSalute, (v) => setState(() => _graviProblemiSalute = v!)),
                      _buildCheckboxTile("Disturbi della condotta", _disturbiCondotta, (v) => setState(() => _disturbiCondotta = v!)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _altroCondizioniController,
                    decoration: InputDecoration(
                      labelText: 'Altre condizioni specifiche',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bento Card: Informatore 1
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE2E8F0))),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.face_retouching_natural_rounded, color: Color(0xFF43A047), size: 20),
                      SizedBox(width: 8),
                      Text("3. Informatore Primario (Relatore)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _inf1NomeController,
                    decoration: InputDecoration(
                      labelText: 'Nome e Cognome dell\'Informatore',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inf1AnniController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Tempo di contatto (Anni)',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _inf1MesiController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Tempo di contatto (Mesi)',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _inf1Frequenza,
                          decoration: InputDecoration(
                            labelText: 'Frequenza del contatto',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Quotidiano', child: Text('Quotidiano')),
                            DropdownMenuItem(value: 'Settimanale', child: Text('Settimanale')),
                            DropdownMenuItem(value: 'Mensile', child: Text('Mensile')),
                          ],
                          onChanged: (val) => setState(() => _inf1Frequenza = val),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _inf1Relazione,
                          decoration: InputDecoration(
                            labelText: 'Relazione col soggetto',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Educatore', child: Text('Educatore')),
                            DropdownMenuItem(value: 'Genitore', child: Text('Genitore')),
                            DropdownMenuItem(value: 'Curatore', child: Text('Curatore / Tutore')),
                            DropdownMenuItem(value: 'Altro', child: Text('Altro')),
                          ],
                          onChanged: (val) => setState(() => _inf1Relazione = val),
                        ),
                      ),
                    ],
                  ),
                  if (_inf1Relazione == 'Altro') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _inf1RelazioneAltroController,
                      decoration: InputDecoration(
                        labelText: 'Specificare relazione altro',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ]
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Bento Card: Informatore 2 (Abilitabile)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE2E8F0))),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.face_retouching_natural_rounded, color: Color(0xFF1E88E5), size: 20),
                          SizedBox(width: 8),
                          Text("4. Informatore Secondario (Opzionale)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ),
                      Switch(
                        value: _inf2Abilitato,
                        activeColor: AppTheme.primaryColor,
                        onChanged: (v) => setState(() => _inf2Abilitato = v),
                      ),
                    ],
                  ),
                  if (_inf2Abilitato) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _inf2NomeController,
                      decoration: InputDecoration(
                        labelText: 'Nome e Cognome dell\'Informatore 2',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _inf2AnniController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Tempo di contatto (Anni)',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _inf2MesiController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Tempo di contatto (Mesi)',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _inf2Frequenza,
                            decoration: InputDecoration(
                              labelText: 'Frequenza del contatto',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Quotidiano', child: Text('Quotidiano')),
                              DropdownMenuItem(value: 'Settimanale', child: Text('Settimanale')),
                              DropdownMenuItem(value: 'Mensile', child: Text('Mensile')),
                            ],
                            onChanged: (val) => setState(() => _inf2Frequenza = val),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _inf2Relazione,
                            decoration: InputDecoration(
                              labelText: 'Relazione col soggetto',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Educatore', child: Text('Educatore')),
                              DropdownMenuItem(value: 'Genitore', child: Text('Genitore')),
                              DropdownMenuItem(value: 'Curatore', child: Text('Curatore / Tutore')),
                              DropdownMenuItem(value: 'Altro', child: Text('Altro')),
                            ],
                            onChanged: (val) => setState(() => _inf2Relazione = val),
                          ),
                        ),
                      ],
                    ),
                    if (_inf2Relazione == 'Altro') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _inf2RelazioneAltroController,
                        decoration: InputDecoration(
                          labelText: 'Specificare relazione altro',
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ]
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCheckboxTile(String label, bool value, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      title: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppTheme.primaryColor,
    );
  }

  // 2. SEZIONE 1 (Sottoscale A-F) STEP
  Widget _buildSezione1Step() {
    final subscaleLetters = ["A", "B", "C", "D", "E", "F"];
    final subscaleNames = [
      "Vita Domestica",
      "Comunità",
      "Apprendimento",
      "Occupazione",
      "Salute/Sicurezza",
      "Sociale"
    ];

    final questions = _getQuestionsForSubscale(subscaleLetters[_activeSubscaleIndex]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Subscale Horizonal TabBar Sub-Menu
        Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _subscaleTabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppTheme.primaryColor,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorColor: AppTheme.primaryColor,
                indicatorWeight: 3,
                tabs: List.generate(6, (index) {
                  final code = subscaleLetters[index];
                  final name = subscaleNames[index];
                  final comp = _getSezioneCompletedCount(code);
                  final tot = _getQuestionsForSubscale(code).length;
                  final isDone = tot > 0 && comp == tot;

                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("$code. $name"),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDone ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "$comp/$tot",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isDone ? const Color(0xFF16A34A) : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                        if (isDone) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 14),
                        ]
                      ],
                    ),
                  );
                }),
              ),
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // List of questions for the selected subscale
        Expanded(
          child: ListView.builder(
            itemCount: questions.length,
            padding: const EdgeInsets.only(bottom: 40),
            itemBuilder: (context, index) {
              final q = questions[index];
              final key = q.codice ?? q.idDomanda;
              final ans = _answers[key] as Map?;

              return Sis3DItemCard(
                itemId: key,
                title: q.testoDomanda,
                description: q.note,
                selectedF: ans?['F'],
                selectedD: ans?['D'],
                selectedT: ans?['T'],
                disabledFrequencies: _getDisabledFrequenciesForQuestion(q),
                onFChanged: (val) {
                  setState(() {
                    _answers[key] = {
                      'F': val,
                      'D': ans?['D'],
                      'T': ans?['T'],
                    };
                  });
                },
                onDChanged: (val) {
                  setState(() {
                    _answers[key] = {
                      'F': ans?['F'],
                      'D': val,
                      'T': ans?['T'],
                    };
                  });
                },
                onTChanged: (val) {
                  setState(() {
                    _answers[key] = {
                      'F': ans?['F'],
                      'D': ans?['D'],
                      'T': val,
                    };
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // 3. SEZIONE 2 (Protezione e tutela) STEP
  Widget _buildSezione2Step() {
    final questions = _getQuestionsForSubscale("SEZ2");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.shield_outlined, color: AppTheme.primaryColor, size: 24),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Sezione 2: Scala Supplementare di Protezione e Tutela Legale",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.textPrimary, letterSpacing: -0.5),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "Compila gli item tridimensionali. Verranno usati per estrarre le Top 4 priorità di tutela.",
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "${_getSezioneCompletedCount('SEZ2')} / ${questions.length} comp.",
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        Expanded(
          child: ListView.builder(
            itemCount: questions.length,
            padding: const EdgeInsets.only(bottom: 40),
            itemBuilder: (context, index) {
              final q = questions[index];
              final key = q.codice ?? q.idDomanda;
              final ans = _answers[key] as Map?;

              return Sis3DItemCard(
                itemId: key,
                title: q.testoDomanda,
                description: q.note,
                selectedF: ans?['F'],
                selectedD: ans?['D'],
                selectedT: ans?['T'],
                onFChanged: (val) {
                  setState(() {
                    _answers[key] = {
                      'F': val,
                      'D': ans?['D'],
                      'T': ans?['T'],
                    };
                  });
                },
                onDChanged: (val) {
                  setState(() {
                    _answers[key] = {
                      'F': ans?['F'],
                      'D': val,
                      'T': ans?['T'],
                    };
                  });
                },
                onTChanged: (val) {
                  setState(() {
                    _answers[key] = {
                      'F': ans?['F'],
                      'D': ans?['D'],
                      'T': val,
                    };
                  });
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // 4. SEZIONE 3 (Eccezionali medici e comportamentali) STEP
  Widget _buildSezione3Step() {
    final medQuestions = _getQuestionsForSubscale("SEZ3M");
    final compQuestions = _getQuestionsForSubscale("SEZ3C");

    // Build sub maps for selections
    final Map<String, int> medSelections = {};
    for (final q in medQuestions) {
      final key = q.codice ?? q.idDomanda;
      if (_answers[key] is int) {
        medSelections[key] = _answers[key] as int;
      }
    }

    final Map<String, int> compSelections = {};
    for (final q in compQuestions) {
      final key = q.codice ?? q.idDomanda;
      if (_answers[key] is int) {
        compSelections[key] = _answers[key] as int;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section 3 Medica List
          SisMedicalList(
            items: medQuestions,
            selections: medSelections,
            onSelectionChanged: (key, val) {
              setState(() {
                _answers[key] = val;
              });
            },
            sectionTitle: "Sezione 3A: Eccezionali bisogni di sostegno di tipo medico",
            sectionNote: "Seleziona 0 (Assente), 1 (Parziale) o 2 (Estensivo) per ciascun bisogno medico.",
          ),
          const SizedBox(height: 32),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 16),

          // Section 3 Comportamentale List
          SisMedicalList(
            items: compQuestions,
            selections: compSelections,
            onSelectionChanged: (key, val) {
              setState(() {
                _answers[key] = val;
              });
            },
            sectionTitle: "Sezione 3B: Eccezionali bisogni di sostegno di tipo comportamentale",
            sectionNote: "Seleziona 0 (Assente), 1 (Parziale) o 2 (Estensivo) per ciascun bisogno comportamentale.",
          ),
        ],
      ),
    );
  }

  // 5. SUMMARY STEP
  Widget _buildSummaryStep() {
    final questionsSez2 = _getQuestionsForSubscale("SEZ2");

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Riepilogo & Ranking Tutela",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.textPrimary, letterSpacing: -0.5),
          ),
          const SizedBox(height: 6),
          const Text(
            "Rivedi i punteggi complessivi e trascina i bisogni di Protezione per stabilire l'ordine di priorità clinica finale.",
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),

          // Subscales raw scores summary Bento Card
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFE2E8F0))),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.analytics_outlined, color: AppTheme.primaryColor, size: 20),
                      SizedBox(width: 8),
                      Text("Punteggi Grezzi Rilevati nei Domini", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildDomainSummaryRow("A", "Domestica", _getSubscaleRawScore("A"), _isSubscaleComplete("A"))),
                      const SizedBox(width: 10),
                      Expanded(child: _buildDomainSummaryRow("B", "Comunità", _getSubscaleRawScore("B"), _isSubscaleComplete("B"))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildDomainSummaryRow("C", "Apprendimento", _getSubscaleRawScore("C"), _isSubscaleComplete("C"))),
                      const SizedBox(width: 10),
                      Expanded(child: _buildDomainSummaryRow("D", "Occupazione", _getSubscaleRawScore("D"), _isSubscaleComplete("D"))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _buildDomainSummaryRow("E", "Salute/Sicurezza", _getSubscaleRawScore("E"), _isSubscaleComplete("E"))),
                      const SizedBox(width: 10),
                      Expanded(child: _buildDomainSummaryRow("F", "Sociale", _getSubscaleRawScore("F"), _isSubscaleComplete("F"))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Interattivo Drag & Drop Ranking Widget
          SisRankingWidget(
            items: questionsSez2,
            answers: _answers,
            initialRanking: _customTop4Ranking.isNotEmpty ? _customTop4Ranking : null,
            onRankingChanged: (rankedIds) {
              _customTop4Ranking = rankedIds;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDomainSummaryRow(String letter, String name, int score, bool complete) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                radius: 12,
                child: Text(letter, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
              ),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            children: [
              Text(
                "Grezzo: $score",
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppTheme.textPrimary),
              ),
              const SizedBox(width: 6),
              Icon(
                complete ? Icons.check_circle_rounded : Icons.pending_rounded,
                color: complete ? const Color(0xFF16A34A) : Colors.amber,
                size: 14,
              ),
            ],
          )
        ],
      ),
    );
  }
}
