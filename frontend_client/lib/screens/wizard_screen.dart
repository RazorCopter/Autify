import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

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

  bool _isLoading = true;
  List<_WizardItem> _questions = [];
  Map<String, int> _answers = {};   // codice_domanda -> punteggio
  Map<String, String> _notes = {};  // codice_domanda -> nota
  bool _noteVisible = false;

  int _currentIndex = 0;
  int _prevIndex = 0; // Per direzione animazione

  bool _preliminaryDone = false;
  final TextEditingController _dataController = TextEditingController();
  final TextEditingController _operatoreController = TextEditingController();
  final TextEditingController _intervistatoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dataController.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _loadScale();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _pageController.dispose();
    _dataController.dispose();
    _operatoreController.dispose();
    _intervistatoController.dispose();
    super.dispose();
  }

  String get _currentKey {
    if (_questions.isEmpty) return '';
    final q = _questions[_currentIndex].domanda;
    return q.codice ?? q.idDomanda;
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
        _questions = flat;
        _isLoading = false;
      });
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

    _pageController.animateToPage(
      newIndex,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _saveEvaluation() async {
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
      risposte: answersList,
    );

    final success = await _apiService.saveEvaluation(evaluation);
    setState(() => _isLoading = false);

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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Container(
          decoration: _gradientDecoration(),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (!_preliminaryDone) {
      return Scaffold(
        body: Container(
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
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        body: Container(
          decoration: _gradientDecoration(),
          child: const Center(
            child: Text('Nessuna domanda disponibile per questa scala',
                style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
          ),
        ),
      );
    }

    final currentQ = _questions[_currentIndex];
    final isLast = _currentIndex == _questions.length - 1;
    final hasAnswered = _answers.containsKey(_currentKey);
    final totalQ = _questions.length;

    return Scaffold(
      body: Container(
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
    );
  }

  // ─── Scheda preliminare ─────────────────────────────────────────────────
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
                    onPressed: () => setState(() => _preliminaryDone = true),
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

  // ─── Header ────────────────────────────────────────────────────────────────
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

  // ─── Progress bar ──────────────────────────────────────────────────────────
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

  // ─── Question card (Glassmorphism) ─────────────────────────────────────────
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

  // ─── Banner Note Domanda ───────────────────────────────────────────────────
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

  // ─── Options list (dynamic & animated) ────────────────────────────────────
  Widget _buildOptionsList(_WizardItem item, bool isTablet) {
    if (item.domanda.opzioni.isEmpty) {
      return const Text(
        'Nessuna opzione disponibile per questa domanda.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textSecondary),
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
        onTap: () => setState(() => _answers[_currentKey] = opt.punteggio),
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
              // Score badge
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: isTablet ? 44 : 38,
                height: isTablet ? 44 : 38,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    opt.punteggio.toString(),
                    style: TextStyle(
                      fontSize: isTablet ? 18 : 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  // ─── Note section ──────────────────────────────────────────────────────────
  Widget _buildNoteSection(_WizardItem item, bool isTablet) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle button
        GestureDetector(
          onTap: () => setState(() => _noteVisible = !_noteVisible),
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
                  _noteVisible ? 'Nascondi nota' : '📝  Aggiungi nota (opzionale)',
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

  // ─── Nav bar ───────────────────────────────────────────────────────────────
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
                  onTap: _currentIndex > 0
                      ? () => _navigate(_currentIndex - 1)
                      : null,
                ),
              ),
              // Avanti / Salva
              AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: hasAnswered ? 1.0 : 0.95,
                child: FilledButton.icon(
                  onPressed: hasAnswered
                      ? () {
                          if (isLast) {
                            _saveEvaluation();
                          } else {
                            _navigate(_currentIndex + 1);
                          }
                        }
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

  // ─── Helpers ───────────────────────────────────────────────────────────────
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
