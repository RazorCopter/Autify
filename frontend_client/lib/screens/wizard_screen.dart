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

class _WizardScreenState extends State<WizardScreen> {
  final ApiService _apiService = ApiService();
  final PageController _pageController = PageController();

  bool _isLoading = true;
  ScaleModel? _scale;
  List<_WizardItem> _questions = [];
  Map<String, int> _answers = {}; // id_domanda -> score

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadScale();
  }

  Future<void> _loadScale() async {
    setState(() => _isLoading = true);
    final scale = await _apiService.getScaleById(widget.scaleId);
    
    if (scale != null) {
      final List<_WizardItem> flatQuestions = [];
      for (var sec in scale.sezioni) {
        for (var q in sec.domande) {
          flatQuestions.add(_WizardItem(sec.titoloSezione, q));
        }
      }

      setState(() {
        _scale = scale;
        _questions = flatQuestions;
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

  void _nextPage() {
    if (_currentIndex < _questions.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentIndex++);
    } else {
      _saveEvaluation();
    }
  }

  void _prevPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentIndex--);
    }
  }

  Future<void> _saveEvaluation() async {
    setState(() => _isLoading = true);

    final answersList = _answers.entries.map((e) {
      return AnswerModel(idDomanda: e.key, valoreRisposta: e.value);
    }).toList();

    final evaluation = EvaluationModel(
      idPaziente: widget.patientId,
      idScala: widget.scaleId,
      anno: DateTime.now().year,
      nomeOperatore: 'Operatore', // Future: get from auth
      risposte: answersList,
    );

    final success = await _apiService.saveEvaluation(evaluation);

    setState(() => _isLoading = false);

    if (success && mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline, color: AppTheme.primaryColor, size: 64),
              const SizedBox(height: 24),
              const Text('Valutazione Salvata',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('I dati sono stati registrati correttamente nel sistema.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx); // Chiudi dialog
                  Navigator.pop(context); // Torna alla home
                },
                child: const Text('Torna alla Home'),
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
      return const Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(title: const Text('Errore'), backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(child: Text('Nessuna domanda disponibile per questa scala')),
      );
    }

    final currentQ = _questions[_currentIndex];
    final isLast = _currentIndex == _questions.length - 1;
    final hasAnsweredCurrent = _answers.containsKey(currentQ.domanda.idDomanda);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header: Categoria e Contatore
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          currentQ.sezione.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Domanda ${_currentIndex + 1} di ${_questions.length}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 48), // bilancia l'icona close
                ],
              ),
            ),
            
            // Corpo: Domanda
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Disabilita swipe
                itemCount: _questions.length,
                itemBuilder: (context, index) {
                  final q = _questions[index];
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(
                      child: Text(
                        q.domanda.testoDomanda,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Input: Bottoni di risposta (1, 2, 3)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildScoreButton(1, '1', AppTheme.errorColor),
                  const SizedBox(width: 16),
                  _buildScoreButton(2, '2', AppTheme.secondaryColor),
                  const SizedBox(width: 16),
                  _buildScoreButton(3, '3', const Color(0xFF43A047)),
                ],
              ),
            ),
            
            const SizedBox(height: 32),

            // Legenda
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8EEF8)),
              ),
              child: const Column(
                children: [
                  Text('3: Sempre / Pienamente Autonomo', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  SizedBox(height: 4),
                  Text('2: A volte / Con aiuto (Prompting)', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  SizedBox(height: 4),
                  Text('1: Mai / Non Autonomo', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Navigazione: Indietro / Avanti
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _currentIndex > 0 ? _prevPage : null,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Indietro'),
                  ),
                  FilledButton.icon(
                    onPressed: hasAnsweredCurrent ? _nextPage : null,
                    icon: Icon(isLast ? Icons.save : Icons.arrow_forward),
                    label: Text(isLast ? 'Salva Valutazione' : 'Avanti'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      backgroundColor: isLast ? AppTheme.primaryColor : AppTheme.secondaryColor,
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

  Widget _buildScoreButton(int score, String label, Color color) {
    final currentQId = _questions[_currentIndex].domanda.idDomanda;
    final isSelected = _answers[currentQId] == score;

    return GestureDetector(
      onTap: () {
        setState(() {
          _answers[currentQId] = score;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE8EEF8),
            width: 2,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            )
          ] : [],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : color,
            ),
          ),
        ),
      ),
    );
  }
}
