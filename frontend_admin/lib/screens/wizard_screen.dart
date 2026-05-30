import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/scale_model.dart';
import '../models/evaluation_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

typedef SectionModel = Section;
typedef QuestionModel = Question;
typedef OptionModel = Option;

class WizardScreen extends StatefulWidget {
  final String patientId;
  final String scaleId;

  const WizardScreen({
    super.key,
    required this.patientId,
    required this.scaleId,
  });

  @override
  State<WizardScreen> createState() => _WizardScreenState();
}

class _WizardItem {
  final String sezione;
  final QuestionModel domanda;

  _WizardItem(this.sezione, this.domanda);
}

class _WizardScreenState extends State<WizardScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final PageController _pageController = PageController();
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'wizard_keyboard_focus');

  bool _allowPop = false;
  bool _isLoading = true;
  String? _scaleNome;
  List<_WizardItem> _questions = [];
  Map<String, dynamic> _answers = {};   // codice_domanda -> punteggio
  Map<String, String> _notes = {};  // codice_domanda -> nota
  bool _noteVisible = false;

  int _currentIndex = 0;
  int _prevIndex = 0; // Per direzione animazione

  bool _preliminaryDone = false;
  final TextEditingController _dataController = TextEditingController();
  final TextEditingController _operatoreController = TextEditingController();
  final TextEditingController _intervistatoController = TextEditingController();

  // --- CONTROLLER E STATO DATI SOCIO-DEMOGRAFICI ---
  bool _demographicsDone = false;
  final _demographicsFormKey = GlobalKey<FormState>();

  // Persona Esaminata
  String? _livelloAssistenza; // 'Esteso' | 'Generalizzato'
  String? _livelloDipendenza; // 'Grado I' | 'Grado II' | 'Grado III'
  final TextEditingController _percentualeDisabilitaController = TextEditingController();
  final TextEditingController _annoCertificatoController = TextEditingController();

  // Altre condizioni (checkboxes)
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
  final TextEditingController _altroCondizioniController = TextEditingController();

  // Informatore 1
  final TextEditingController _inf1NomeController = TextEditingController();
  final TextEditingController _inf1AnniController = TextEditingController();
  final TextEditingController _inf1MesiController = TextEditingController();
  String? _inf1Frequenza;
  String? _inf1Relazione;
  final TextEditingController _inf1RelazioneAltroController = TextEditingController();

  // Informatore 2
  bool _inf2Abilitato = false;
  final TextEditingController _inf2NomeController = TextEditingController();
  final TextEditingController _inf2AnniController = TextEditingController();
  final TextEditingController _inf2MesiController = TextEditingController();
  String? _inf2Frequenza;
  String? _inf2Relazione;
  final TextEditingController _inf2RelazioneAltroController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dataController.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _loadScale();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestKeyboardFocus());
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _focusNode.dispose();
    _noteController.dispose();
    _pageController.dispose();
    _dataController.dispose();
    _operatoreController.dispose();
    _intervistatoController.dispose();

    // Dispose nuovi controller
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
    super.dispose();
  }

  String get _currentKey {
    if (_questions.isEmpty) return '';
    final q = _questions[_currentIndex].domanda;
    return q.codice ?? q.idDomanda;
  }

  void _requestKeyboardFocus() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focusNode.hasFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  bool _isTypingInTextField() {
    final focusedChild = FocusManager.instance.primaryFocus;
    final widget = focusedChild?.context?.widget;
    return widget is EditableText;
  }

  void _selectOptionByHotkey(int optionIndex) {
    if (_questions.isEmpty || _currentIndex >= _questions.length) return;

    final options = _questions[_currentIndex].domanda.opzioni;
    if (optionIndex < 0 || optionIndex >= options.length) return;

    final selectedOption = options[optionIndex];
    setState(() {
      _answers[_currentKey] = selectedOption.punteggio;
    });
    _requestKeyboardFocus();
  }

  void _goForward() {
    if (!_answers.containsKey(_currentKey)) return;

    final isLast = _currentIndex == _questions.length - 1;
    if (isLast) {
      _saveEvaluation();
      return;
    }
    _navigate(_currentIndex + 1);
  }

  void _goBack() {
    if (_currentIndex <= 0) return;
    _navigate(_currentIndex - 1);
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    final result = _handleKeyEvent(_focusNode, event);
    return result == KeyEventResult.handled;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isLoading || !_preliminaryDone || _questions.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (_isTypingInTextField()) {
      return KeyEventResult.ignored;
    }

    final isSanMartin = widget.scaleId.toLowerCase().contains('martin') ||
        widget.scaleId.toLowerCase().contains('san') ||
        widget.scaleId.toLowerCase().contains('sanmartin') ||
        (_scaleNome ?? '').toLowerCase().contains('martin') ||
        (_scaleNome ?? '').toLowerCase().contains('san') ||
        (_scaleNome ?? '').toLowerCase().contains('sanmartin');

    if (isSanMartin && !_demographicsDone) {
      return KeyEventResult.ignored;
    }

    final is3D = _isSis3DQuestion(widget.scaleId, _currentKey);
    
    if (is3D) {
      final sisHotkeys = <LogicalKeyboardKey, int>{
        LogicalKeyboardKey.digit0: 0,
        LogicalKeyboardKey.numpad0: 0,
        LogicalKeyboardKey.digit1: 1,
        LogicalKeyboardKey.numpad1: 1,
        LogicalKeyboardKey.digit2: 2,
        LogicalKeyboardKey.numpad2: 2,
        LogicalKeyboardKey.digit3: 3,
        LogicalKeyboardKey.numpad3: 3,
        LogicalKeyboardKey.digit4: 4,
        LogicalKeyboardKey.numpad4: 4,
      };

      final pressedValue = sisHotkeys[event.logicalKey];
      if (pressedValue != null) {
        final isA3 = _currentKey.toUpperCase() == 'A3';
        
        final current = _answers[_currentKey];
        int? f;
        int? d;
        int? t;
        if (current is Map) {
          f = current['F'] as int?;
          d = current['D'] as int?;
          t = current['T'] as int?;
        }

        setState(() {
          if (f == null) {
            if (isA3 && pressedValue > 3) {
              f = 3;
            } else {
              f = pressedValue;
            }
          } else if (d == null) {
            d = pressedValue;
          } else if (t == null) {
            t = pressedValue;
          } else {
            if (isA3 && pressedValue > 3) {
              f = 3;
            } else {
              f = pressedValue;
            }
            d = null;
            t = null;
          }
          _answers[_currentKey] = {'F': f, 'D': d, 'T': t};
        });
        _requestKeyboardFocus();
        return KeyEventResult.handled;
      }

      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        final current = _answers[_currentKey];
        if (current is Map) {
          int? f = current['F'] as int?;
          int? d = current['D'] as int?;
          int? t = current['T'] as int?;

          setState(() {
            if (t != null) {
              t = null;
            } else if (d != null) {
              d = null;
            } else if (f != null) {
              f = null;
            }
            _answers[_currentKey] = {'F': f, 'D': d, 'T': t};
          });
          _requestKeyboardFocus();
          return KeyEventResult.handled;
        }
      }

      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        final current = _answers[_currentKey];
        final hasAll3 = current is Map &&
            current['F'] != null &&
            current['D'] != null &&
            current['T'] != null;
        if (hasAll3) {
          _goForward();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _goBack();
        return KeyEventResult.handled;
      }

      return KeyEventResult.ignored;
    }

    final optionHotkeys = <LogicalKeyboardKey, int>{
      LogicalKeyboardKey.digit1: 0,
      LogicalKeyboardKey.numpad1: 0,
      LogicalKeyboardKey.digit2: 1,
      LogicalKeyboardKey.numpad2: 1,
      LogicalKeyboardKey.digit3: 2,
      LogicalKeyboardKey.numpad3: 2,
      LogicalKeyboardKey.digit4: 3,
      LogicalKeyboardKey.numpad4: 3,
    };

    final optionIndex = optionHotkeys[event.logicalKey];
    if (optionIndex != null) {
      _selectOptionByHotkey(optionIndex);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_answers.containsKey(_currentKey)) {
        _goForward();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goBack();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _loadScale() async {
    setState(() => _isLoading = true);
    final scale = await _apiService.getScaleById(widget.scaleId);

    if (scale != null) {
      final List<_WizardItem> flat = [];
      for (var sec in scale.sezioni) {
        for (var q in sec.domande) {
          flat.add(_WizardItem(sec.titoloSezione, q));
        }
      }
      setState(() {
        _scaleNome = scale.nome;
        _questions = flat;
        _isLoading = false;
      });
      _requestKeyboardFocus();
    } else {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Errore nel caricamento del protocollo')),
        );
        Navigator.pop(context);
      }
    }
  }

  void _navigate(int newIndex) {
    if (newIndex < 0 || newIndex >= _questions.length) return;

    // Salva nota corrente prima di cambiare pagina
    _notes[_currentKey] = _noteController.text;

    setState(() {
      _prevIndex = _currentIndex;
      _currentIndex = newIndex;
      _noteVisible = false;
    });

    // Aggiorna controller nota per il nuovo indice
    final newKey = _questions[newIndex].domanda.codice ??
        _questions[newIndex].domanda.idDomanda;
    _noteController.text = _notes[newKey] ?? '';

    if (_pageController.hasClients) {
      _pageController.animateToPage(
        newIndex,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
    _requestKeyboardFocus();
  }

  Future<void> _saveEvaluation() async {
    if (ApiService.isViewer) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Azione non consentita in modalità Sola Lettura'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Controlla che tutte le risposte siano state date
    if (_scale != null) {
      for (final sec in _scale!.sezioni) {
        for (final q in sec.domande) {
          final k = q.codice ?? q.idDomanda;
          if (!_answers.containsKey(k) || _answers[k] == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Rispondi a tutte le domande prima di salvare. Manca: ${q.testoDomanda}"),
                backgroundColor: Colors.redAccent,
                duration: const Duration(seconds: 4),
              ),
            );
            return;
          }
        }
      }
    }

    // Salva nota pagina corrente
    _notes[_currentKey] = _noteController.text;

    setState(() => _isLoading = true);

    final answersList = _answers.entries.map((e) {
      return AnswerModel(
        codiceDomanda: e.key,
        punteggio: e.value,
        nota: _notes[e.key]?.isNotEmpty == true ? _notes[e.key] : null,
      );
    }).toList();

    // Raccoglie i dati socio-demografici se la scala è San Martín
    Map<String, dynamic>? demographicsData;
    final isSanMartin = widget.scaleId.toLowerCase().contains('martin') ||
        widget.scaleId.toLowerCase().contains('san') ||
        widget.scaleId.toLowerCase().contains('sanmartin') ||
        (_scaleNome ?? '').toLowerCase().contains('martin') ||
        (_scaleNome ?? '').toLowerCase().contains('san') ||
        (_scaleNome ?? '').toLowerCase().contains('sanmartin');
    if (isSanMartin) {
      demographicsData = {
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
        } : null
      };
    }

    final evaluation = EvaluationModel(
      idPaziente: widget.patientId,
      idScala: widget.scaleId,
      anno: DateTime.now().year,
      nomeOperatore: _operatoreController.text.isNotEmpty
          ? _operatoreController.text
          : 'Operatore',
      nomeIntervistato: _intervistatoController.text.isNotEmpty
          ? _intervistatoController.text
          : null,
      dataCompilazione: _dataController.text.isNotEmpty
          ? _dataController.text
          : null,
      demographics: demographicsData,
      risposte: answersList,
    );

    final success = await _apiService.saveEvaluation(evaluation);
    setState(() => _isLoading = false);
    _requestKeyboardFocus();

    if (success && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primaryColor, AppTheme.accentColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 48),
              ),
              const SizedBox(height: 24),
              const Text('Valutazione Salvata',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text(
                'I dati sono stati registrati correttamente nel sistema.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.home_outlined),
                label: const Text('Torna alla Home'),
              ),
            ],
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Errore durante il salvataggio')),
      );
    }
  }

  Future<bool> _showExitConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Annullare la valutazione?'),
        content: const Text(
            'Se esci ora, tutte le risposte inserite andranno perse. Vuoi uscire comunque?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Continua Compilazione'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Esci e Elimina'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    Widget buildContent() {
      if (_isLoading) {
        return Scaffold(
          body: Focus(
            focusNode: _focusNode,
            autofocus: true,
            child: Container(
              decoration: _gradientDecoration(),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
        );
      }

      if (!_preliminaryDone) {
        return Scaffold(
          body: Focus(
            focusNode: _focusNode,
            autofocus: true,
            child: Container(
              decoration: _gradientDecoration(),
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: _buildPreliminaryCard(),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      final isSanMartin = widget.scaleId.toLowerCase().contains('martin') ||
          widget.scaleId.toLowerCase().contains('san') ||
          widget.scaleId.toLowerCase().contains('sanmartin') ||
          (_scaleNome ?? '').toLowerCase().contains('martin') ||
          (_scaleNome ?? '').toLowerCase().contains('san') ||
          (_scaleNome ?? '').toLowerCase().contains('sanmartin');

      if (isSanMartin && !_demographicsDone) {
        return Scaffold(
          body: Container(
            decoration: _gradientDecoration(),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildDemographicsCard(),
                ),
              ),
            ),
          ),
        );
      }

      if (_questions.isEmpty) {
        return Scaffold(
          body: Focus(
            focusNode: _focusNode,
            autofocus: true,
            child: Container(
              decoration: _gradientDecoration(),
              child: const Center(
                child: Text('Nessuna domanda disponibile per questa scala',
                    style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
              ),
            ),
          ),
        );
      }
      final currentQ = _questions[_currentIndex];
      final isLast = _currentIndex == _questions.length - 1;
      final is3D = _isSis3DQuestion(widget.scaleId, _currentKey);
      final hasAnswered = is3D
          ? (_answers[_currentKey] is Map &&
              _answers[_currentKey]['F'] != null &&
              _answers[_currentKey]['D'] != null &&
              _answers[_currentKey]['T'] != null)
          : _answers.containsKey(_currentKey);
      final totalQ = _questions.length;

      return Scaffold(
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          child: Container(
            decoration: _gradientDecoration(),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isTablet = constraints.maxWidth > 650;
                  final maxW = isTablet ? 720.0 : double.infinity;
                  final hPad = isTablet ? 0.0 : 0.0;

                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxW),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPad),
                        child: Column(
                          children: [
                            _buildHeader(currentQ, isTablet, totalQ),
                            _buildProgressBar(totalQ),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 32 : 20,
                                  vertical: 20,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildQuestionCard(currentQ, isTablet),
                                    const SizedBox(height: 12),
                                    _buildQuestionNote(currentQ.domanda, isTablet),
                                    const SizedBox(height: 8),
                                    _buildOptionsList(currentQ, isTablet),
                                    const SizedBox(height: 12),
                                    _buildNoteSection(currentQ, isTablet),
                                    const SizedBox(height: 24),
                                  ],
                                ),
                              ),
                            ),
                            _buildNavBar(hasAnswered, isLast, isTablet),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showExitConfirmationDialog();
        if (shouldPop && mounted) {
          setState(() {
            _allowPop = true;
          });
          Navigator.of(context).pop();
        }
      },
      child: buildContent(),
    );
  }

  // â”€â”€â”€ Scheda preliminare â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildPreliminaryCard() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.assignment_ind_outlined, size: 48, color: AppTheme.primaryColor),
                const SizedBox(height: 16),
                const Text(
                  'Dati Valutazione',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Compila i dati generali prima di iniziare',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 28),
                // Data compilazione
                TextField(
                  controller: _dataController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Data compilazione',
                    prefixIcon: const Icon(Icons.calendar_today, color: AppTheme.primaryColor),
                    filled: true,
                    fillColor: const Color(0xFFF3F8FF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
                    ),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.tryParse(_dataController.text) ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      helpText: 'Seleziona data compilazione',
                    );
                    if (picked != null) {
                      _dataController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    }
                    _requestKeyboardFocus();
                  },
                ),
                const SizedBox(height: 16),
                // Nome Operatore
                TextField(
                  controller: _operatoreController,
                  decoration: InputDecoration(
                    labelText: 'Nome Operatore',
                    hintText: 'Inserisci il tuo nome',
                    prefixIcon: const Icon(Icons.badge_outlined, color: AppTheme.primaryColor),
                    filled: true,
                    fillColor: const Color(0xFFF3F8FF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Nome Intervistata/o
                TextField(
                  controller: _intervistatoController,
                  decoration: InputDecoration(
                    labelText: 'Nome Intervistata/o',
                    hintText: 'Nome della persona intervistata',
                    prefixIcon: const Icon(Icons.person_outline, color: AppTheme.primaryColor),
                    filled: true,
                    fillColor: const Color(0xFFF3F8FF),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () {
                      setState(() => _preliminaryDone = true);
                      _requestKeyboardFocus();
                    },
                    icon: const Icon(Icons.play_circle_outline, size: 22),
                    label: const Text(
                      'Inizia Compilazione',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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

  // â”€â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildHeader(_WizardItem currentQ, bool isTablet, int total) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.4), width: 1),
            ),
          ),
          child: Row(
            children: [
              // Chiudi
              _glassIconButton(
                icon: Icons.close,
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(width: 12),
              // Sezione + contatore
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      currentQ.sezione.toUpperCase(),
                      style: TextStyle(
                        fontSize: isTablet ? 12 : 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                        letterSpacing: 1.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_currentIndex + 1} / $total',
                      style: TextStyle(
                        fontSize: isTablet ? 20 : 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 52), // Bilancia il bottone close
            ],
          ),
        ),
      ),
    );
  }

  // â”€â”€â”€ Progress bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildProgressBar(int total) {
    final progress = (_currentIndex + 1) / total;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (_, value, __) => LinearProgressIndicator(
        value: value,
        minHeight: 4,
        backgroundColor: Colors.white.withValues(alpha: 0.3),
        valueColor: const AlwaysStoppedAnimation(AppTheme.primaryColor),
      ),
    );
  }

  // â”€â”€â”€ Question card (Glassmorphism) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildQuestionCard(_WizardItem item, bool isTablet) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      transitionBuilder: (child, animation) {
        final slideAnim = Tween<Offset>(
          begin: _currentIndex >= _prevIndex
              ? const Offset(0.12, 0)
              : const Offset(-0.12, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slideAnim, child: child),
        );
      },
      child: ClipRRect(
        key: ValueKey(_currentIndex),
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(isTablet ? 36 : 24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.68),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.10),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Text(
              item.domanda.testoDomanda,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isTablet ? 24 : 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // â”€â”€â”€ Banner Note Domanda â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildQuestionNote(QuestionModel question, bool isTablet) {
    if (question.note == null || question.note!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD), // Azzurro chiaro tenue
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBDEFB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info, color: Color(0xFF1976D2), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              question.note!,
              style: TextStyle(
                fontSize: isTablet ? 15 : 14,
                color: const Color(0xFF0D47A1),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSis3DQuestion(String scaleId, String questionId) {
    final isSis = scaleId.toLowerCase().contains('sis');
    if (!isSis) return false;
    final id = questionId.toUpperCase();
    return id.startsWith('A') ||
        id.startsWith('B') ||
        (id.startsWith('C') && !id.startsWith('BC')) ||
        id.startsWith('D') ||
        id.startsWith('E') ||
        id.startsWith('F') ||
        id.startsWith('P');
  }

  void _updateSis3DAnswer(String dim, int value) {
    setState(() {
      final current = _answers[_currentKey];
      Map<String, int> map;
      if (current is Map) {
        map = Map<String, int>.from(current);
      } else {
        map = {};
      }
      map[dim] = value;
      _answers[_currentKey] = map;
    });
    _requestKeyboardFocus();
  }

  Widget _buildSis3DSelector(bool isTablet) {
    final currentVal = _answers[_currentKey];
    int? selF;
    int? selD;
    int? selT;

    if (currentVal is Map) {
      selF = currentVal['F'] as int?;
      selD = currentVal['D'] as int?;
      selT = currentVal['T'] as int?;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSisDimensionRow('F', 'Frequenza', selF, Icons.access_time_filled_rounded, isTablet),
        const SizedBox(height: 16),
        _buildSisDimensionRow('D', 'Durata quotidiana', selD, Icons.hourglass_full_rounded, isTablet),
        const SizedBox(height: 16),
        _buildSisDimensionRow('T', 'Tipo di sostegno', selT, Icons.front_hand_rounded, isTablet),
      ],
    );
  }

  Widget _buildSisDimensionRow(
    String dim,
    String label,
    int? selectedValue,
    IconData icon,
    bool isTablet,
  ) {
    // Gestione eccezione A3: F_max = 3
    final isA3 = _currentKey.toUpperCase() == 'A3';
    final maxVal = (dim == 'F' && isA3) ? 3 : 4;

    final legends = dim == 'F'
        ? _sisLegendaFrequenza
        : dim == 'D'
            ? _sisLegendaDurata
            : _sisLegendaTipo;

    final dimColor = dim == 'F'
        ? const Color(0xFF1E88E5)
        : dim == 'D'
            ? const Color(0xFFFB8C00)
            : const Color(0xFF43A047);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDDE7F8), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: dimColor, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: isTablet ? 16 : 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (selectedValue != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: dimColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Punteggio: $selectedValue',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: dimColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(maxVal + 1, (index) {
              final isSelected = selectedValue == index;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () => _updateSis3DAnswer(dim, index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 48,
                      decoration: BoxDecoration(
                        color: isSelected ? dimColor : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? dimColor : const Color(0xFFDDE7F8),
                          width: isSelected ? 2.5 : 1.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: dimColor.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                )
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          '$index',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          if (selectedValue != null) ...[
            const SizedBox(height: 8),
            Text(
              legends[selectedValue] ?? '',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: dimColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static const _sisLegendaFrequenza = {
    0: "Nessuna o meno di una volta al mese",
    1: "Almeno una volta al mese, ma meno di una volta alla settimana",
    2: "Almeno una volta alla settimana, ma meno di una volta al giorno",
    3: "Almeno una volta al giorno, ma meno di una volta all'ora",
    4: "Ogni ora o con maggior frequenza",
  };

  static const _sisLegendaDurata = {
    0: "Nessuno",
    1: "Meno di 30 minuti",
    2: "Da 30 minuti a meno di 2 ore",
    3: "Da 2 ore a meno di 4 ore",
    4: "4 ore o più",
  };

  static const _sisLegendaTipo = {
    0: "Nessuno",
    1: "Monitoraggio",
    2: "Prompt verbale o gestuale",
    3: "Assistenza fisica parziale",
    4: "Assistenza fisica totale",
  };

  // ——— Options list (dynamic & animated) ————————————————————————————
  Widget _buildOptionsList(_WizardItem item, bool isTablet) {
    if (_isSis3DQuestion(widget.scaleId, _currentKey)) {
      return _buildSis3DSelector(isTablet);
    }

    if (item.domanda.opzioni.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Nessuna opzione disponibile per questa domanda.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return Column(
      children: item.domanda.opzioni.map((opt) {
        return _buildOptionButton(opt, isTablet);
      }).toList(),
    );
  }

  Widget _buildOptionButton(OptionModel opt, bool isTablet) {
    final isSelected = _answers[_currentKey] == opt.punteggio;
    final color = _colorForScore(opt.punteggio, item: _questions[_currentIndex].domanda.opzioni.length);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          setState(() => _answers[_currentKey] = opt.punteggio);
          _requestKeyboardFocus();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          transform: Matrix4.identity(),
          padding: EdgeInsets.symmetric(
            vertical: isTablet ? 18 : 14,
            horizontal: isTablet ? 28 : 20,
          ),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.80),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFDDE7F8),
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.30),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ],
          ),
          child: Row(
            children: [
              // Testo opzione
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        opt.testoRisposta,
                        style: TextStyle(
                          fontSize: isTablet ? 18 : 16,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (opt.descrizione != null && opt.descrizione!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.info_outline,
                            size: 20,
                            color: isSelected ? Colors.white70 : AppTheme.textSecondary,
                          ),
                          onPressed: () => _showOptionDescription(opt),
                        ),
                      ),
                  ],
                ),
              ),
              // Checkmark
              AnimatedOpacity(
                opacity: isSelected ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.check_circle_rounded,
                    color: Colors.white.withValues(alpha: 0.9),
                    size: isTablet ? 26 : 22),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOptionDescription(OptionModel opt) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(opt.testoRisposta, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(opt.descrizione ?? ''),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _requestKeyboardFocus();
            },
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  // â”€â”€â”€ Note section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildNoteSection(_WizardItem item, bool isTablet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle button
        GestureDetector(
          onTap: () {
            setState(() => _noteVisible = !_noteVisible);
            _requestKeyboardFocus();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _noteVisible ? Icons.edit_note : Icons.add_comment_outlined,
                  size: 18,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  _noteVisible ? 'Nascondi nota' : 'Aggiungi nota (opzionale)',
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Expanding field
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: _noteVisible
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: TextField(
                        controller: _noteController,
                        maxLines: 3,
                        style: const TextStyle(
                            fontSize: 15, color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          hintText:
                              'Es. "Oggi era molto collaborativo, ha risposto con calma..."',
                          hintStyle: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.75),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.8)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.8)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: const BorderSide(
                                color: AppTheme.primaryColor, width: 2),
                          ),
                          contentPadding: const EdgeInsets.all(16),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(left: 12, right: 8, top: 12),
                            child: Icon(Icons.notes_rounded,
                                color: AppTheme.textSecondary, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // â”€â”€â”€ Nav bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildNavBar(bool hasAnswered, bool isLast, bool isTablet) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 40 : 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Indietro
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _currentIndex > 0 ? 1 : 0.3,
                child: _glassIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  label: 'Indietro',
                  onTap: _currentIndex > 0 ? _goBack : null,
                ),
              ),
              // Avanti / Salva
              AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: hasAnswered ? 1.0 : 0.95,
                child: FilledButton.icon(
                  onPressed: hasAnswered
                      ? _goForward
                      : null,
                  icon: Icon(isLast
                      ? Icons.save_alt_rounded
                      : Icons.arrow_forward_ios_rounded,
                      size: 18),
                  label: Text(isLast ? 'Salva Valutazione' : 'Avanti'),
                  style: FilledButton.styleFrom(
                    backgroundColor: isLast
                        ? AppTheme.accentColor
                        : AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 32 : 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // â”€â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  BoxDecoration _gradientDecoration() {
    return const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFFE8F4FD), Color(0xFFF0F9FF), Color(0xFFEEF5FB)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: [0.0, 0.5, 1.0],
      ),
    );
  }

  Color _colorForScore(int score, {int item = 3}) {
    final palette = [
      const Color(0xFFE57373), // rosso
      const Color(0xFFFFB74D), // arancio
      const Color(0xFF4FC3F7), // azzurro
      const Color(0xFF81C784), // verde
    ];
    // assegna i colori scalarmente dal peggiore al migliore
    final idx = (score - 1).clamp(0, palette.length - 1);
    return palette[idx];
  }

  Widget _buildDemographicsCard() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 650),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Form(
              key: _demographicsFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.analytics_outlined, size: 48, color: AppTheme.primaryColor),
                  const SizedBox(height: 16),
                  const Text(
                    'Dati Socio-Demografici',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Informazioni richieste dal protocollo Scala San Martín',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  
                  // --- SEZIONE 1: PERSONA ESAMINATA ---
                  _buildSectionHeader('DATI DELLA PERSONA ESAMINATA'),
                  const SizedBox(height: 16),
                  
                  DropdownButtonFormField<String>(
                    value: _livelloAssistenza,
                    decoration: _inputDecoration('Livello di necessità di assistenza', Icons.assistant_direction_outlined),
                    items: const [
                      DropdownMenuItem(value: 'Esteso', child: Text('Esteso')),
                      DropdownMenuItem(value: 'Generalizzato', child: Text('Generalizzato')),
                    ],
                    onChanged: (val) => setState(() => _livelloAssistenza = val),
                    validator: (val) => val == null ? 'Campo richiesto' : null,
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    value: _livelloDipendenza,
                    decoration: _inputDecoration('Livello di dipendenza riconosciuto', Icons.accessible_forward_outlined),
                    items: const [
                      DropdownMenuItem(value: 'Grado I', child: Text('Grado I - Dipendenza moderata')),
                      DropdownMenuItem(value: 'Grado II', child: Text('Grado II - Dipendenza grave')),
                      DropdownMenuItem(value: 'Grado III', child: Text('Grado III - Dipendenza elevata')),
                    ],
                    onChanged: (val) => setState(() => _livelloDipendenza = val),
                    validator: (val) => val == null ? 'Campo richiesto' : null,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _percentualeDisabilitaController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration('Disabilità (%)', Icons.percent),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Richiesto';
                            final n = int.tryParse(val);
                            if (n == null || n < 0 || n > 100) return '0-100';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _annoCertificatoController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration('Anno certificato', Icons.calendar_today_outlined),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Richiesto';
                            final n = int.tryParse(val);
                            if (n == null || n < 1900 || n > DateTime.now().year) return 'Anno non valido';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    'Altre condizioni della persona esaminata:',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 8),

                  _buildModernCheckbox('Disabilità fisica', _disFisica, (val) {
                    setState(() {
                      _disFisica = val ?? false;
                      if (!_disFisica) {
                        _limArtiSuperiori = false;
                        _limArtiInferiori = false;
                      }
                    });
                  }),
                  if (_disFisica) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 24.0, bottom: 8),
                      child: Column(
                        children: [
                          _buildModernCheckbox('Limitazioni funzionali degli arti superiori', _limArtiSuperiori, (val) {
                            setState(() => _limArtiSuperiori = val ?? false);
                          }),
                          _buildModernCheckbox('Limitazioni funzionali degli arti inferiori', _limArtiInferiori, (val) {
                            setState(() => _limArtiInferiori = val ?? false);
                          }),
                        ],
                      ),
                    ),
                  ],

                  _buildModernCheckbox('Disabilità sensoriale', _disSensoriale, (val) {
                    setState(() {
                      _disSensoriale = val ?? false;
                      if (!_disSensoriale) {
                        _uditoSordita = false;
                        _visiva = false;
                      }
                    });
                  }),
                  if (_disSensoriale) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 24.0, bottom: 8),
                      child: Column(
                        children: [
                          _buildModernCheckbox('Uditiva/sordità', _uditoSordita, (val) {
                            setState(() => _uditoSordita = val ?? false);
                          }),
                          _buildModernCheckbox('Visiva', _visiva, (val) {
                            setState(() => _visiva = val ?? false);
                          }),
                        ],
                      ),
                    ),
                  ],

                  _buildModernCheckbox('Paralisi cerebrale', _paralisiCerebrale, (val) {
                    setState(() => _paralisiCerebrale = val ?? false);
                  }),
                  _buildModernCheckbox('Epilessia', _epilessia, (val) {
                    setState(() => _epilessia = val ?? false);
                  }),
                  _buildModernCheckbox('Problemi di salute mentale/disturbi emotivi', _saluteMentale, (val) {
                    setState(() => _saluteMentale = val ?? false);
                  }),
                  _buildModernCheckbox('Disturbo dello spettro autistico', _spettroAutistico, (val) {
                    setState(() => _spettroAutistico = val ?? false);
                  }),
                  _buildModernCheckbox('Sindrome di Down', _sindromeDown, (val) {
                    setState(() => _sindromeDown = val ?? false);
                  }),
                  _buildModernCheckbox('Gravi problemi di salute', _graviProblemiSalute, (val) {
                    setState(() => _graviProblemiSalute = val ?? false);
                  }),
                  _buildModernCheckbox('Disturbi della condotta', _disturbiCondotta, (val) {
                    setState(() => _disturbiCondotta = val ?? false);
                  }),

                  TextFormField(
                    controller: _altroCondizioniController,
                    decoration: _inputDecoration('Altre condizioni specifiche / Note', Icons.more_horiz),
                  ),
                  const SizedBox(height: 28),

                  // --- SEZIONE 2: INFORMATORE 1 ---
                  _buildSectionHeader('DATI DELL\'INFORMATORE 1'),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _inf1NomeController,
                    decoration: _inputDecoration('Nome e Cognome Informatore 1', Icons.person_outline),
                    validator: (val) => val == null || val.isEmpty ? 'Campo richiesto' : null,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _inf1AnniController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration('Periodo contatto (anni)', Icons.date_range),
                          validator: (val) => val == null || val.isEmpty ? 'Richiesto' : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _inf1MesiController,
                          keyboardType: TextInputType.number,
                          decoration: _inputDecoration('Mesi', Icons.timelapse),
                          validator: (val) => val == null || val.isEmpty ? 'Richiesto' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    value: _inf1Frequenza,
                    decoration: _inputDecoration('Frequenza di contatto', Icons.loop),
                    items: const [
                      DropdownMenuItem(value: 'Varie volte alla settimana', child: Text('Varie volte alla settimana')),
                      DropdownMenuItem(value: 'Una volta alla settimana', child: Text('Una volta alla settimana')),
                      DropdownMenuItem(value: 'Una volta ogni due settimane', child: Text('Una volta ogni due settimane')),
                      DropdownMenuItem(value: 'Una volta al mese', child: Text('Una volta al mese')),
                    ],
                    onChanged: (val) => setState(() => _inf1Frequenza = val),
                    validator: (val) => val == null ? 'Campo richiesto' : null,
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    value: _inf1Relazione,
                    decoration: _inputDecoration('Relazione con la persona esaminata', Icons.people_outline),
                    items: const [
                      DropdownMenuItem(value: 'Professionale', child: Text('Professionale')),
                      DropdownMenuItem(value: 'Madre /Padre', child: Text('Madre / Padre')),
                      DropdownMenuItem(value: 'Fratello/Sorella', child: Text('Fratello / Sorella')),
                      DropdownMenuItem(value: 'Tutore/tutrice legale', child: Text('Tutore / tutrice legale')),
                      DropdownMenuItem(value: 'Altro', child: Text('Altro (specificare)')),
                    ],
                    onChanged: (val) => setState(() => _inf1Relazione = val),
                    validator: (val) => val == null ? 'Campo richiesto' : null,
                  ),
                  if (_inf1Relazione == 'Altro') ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _inf1RelazioneAltroController,
                      decoration: _inputDecoration('Specificare relazione', Icons.edit_note),
                      validator: (val) => val == null || val.isEmpty ? 'Specificare la relazione' : null,
                    ),
                  ],
                  const SizedBox(height: 28),

                  // --- SEZIONE 3: INFORMATORE 2 (OPZIONALE) ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionHeader('DATI DELL\'INFORMATORE 2 (OPZIONALE)'),
                      Switch(
                        value: _inf2Abilitato,
                        activeColor: AppTheme.primaryColor,
                        onChanged: (val) => setState(() => _inf2Abilitato = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_inf2Abilitato) ...[
                    TextFormField(
                      controller: _inf2NomeController,
                      decoration: _inputDecoration('Nome e Cognome Informatore 2', Icons.person_outline),
                      validator: (val) => _inf2Abilitato && (val == null || val.isEmpty) ? 'Campo richiesto' : null,
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _inf2AnniController,
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration('Periodo contatto (anni)', Icons.date_range),
                            validator: (val) => _inf2Abilitato && (val == null || val.isEmpty) ? 'Richiesto' : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _inf2MesiController,
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration('Mesi', Icons.timelapse),
                            validator: (val) => _inf2Abilitato && (val == null || val.isEmpty) ? 'Richiesto' : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      value: _inf2Frequenza,
                      decoration: _inputDecoration('Frequenza di contatto', Icons.loop),
                      items: const [
                        DropdownMenuItem(value: 'Varie volte alla settimana', child: Text('Varie volte alla settimana')),
                        DropdownMenuItem(value: 'Una volta alla settimana', child: Text('Una volta alla settimana')),
                        DropdownMenuItem(value: 'Una volta ogni due settimane', child: Text('Una volta ogni due settimane')),
                        DropdownMenuItem(value: 'Una volta al mese', child: Text('Una volta al mese')),
                      ],
                      onChanged: (val) => setState(() => _inf2Frequenza = val),
                      validator: (val) => _inf2Abilitato && val == null ? 'Campo richiesto' : null,
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      value: _inf2Relazione,
                      decoration: _inputDecoration('Relazione con la persona esaminata', Icons.people_outline),
                      items: const [
                        DropdownMenuItem(value: 'Professionale', child: Text('Professionale')),
                        DropdownMenuItem(value: 'Madre /Padre', child: Text('Madre / Padre')),
                        DropdownMenuItem(value: 'Fratello/Sorella', child: Text('Fratello / Sorella')),
                        DropdownMenuItem(value: 'Tutore/tutrice legale', child: Text('Tutore / tutrice legale')),
                        DropdownMenuItem(value: 'Altro', child: Text('Altro (specificare)')),
                      ],
                      onChanged: (val) => setState(() => _inf2Relazione = val),
                      validator: (val) => _inf2Abilitato && val == null ? 'Campo richiesto' : null,
                    ),
                    if (_inf2Relazione == 'Altro') ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _inf2RelazioneAltroController,
                        decoration: _inputDecoration('Specificare relazione', Icons.edit_note),
                        validator: (val) => _inf2Abilitato && (val == null || val.isEmpty) ? 'Specificare la relazione' : null,
                      ),
                    ],
                  ],
                  const SizedBox(height: 32),

                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () {
                        if (_demographicsFormKey.currentState?.validate() == true) {
                          setState(() => _demographicsDone = true);
                          _requestKeyboardFocus();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Correggi gli errori nel modulo prima di procedere')),
                          );
                        }
                      },
                      icon: const Icon(Icons.arrow_forward_rounded, size: 22),
                      label: const Text(
                        'Procedi alle Domande',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
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

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppTheme.primaryColor,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildModernCheckbox(String title, bool value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppTheme.primaryColor),
      filled: true,
      fillColor: const Color(0xFFF3F8FF),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
      ),
    );
  }

  Widget _glassIconButton({
    required IconData icon,
    String? label,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: label != null
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
            : const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
        ),
        child: label != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(label,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600)),
                ],
              )
            : Icon(icon, size: 20, color: AppTheme.textSecondary),
      ),
    );
  }
}
