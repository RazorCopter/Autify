import 'package:flutter/material.dart';
import '../models/scale_model.dart';
import '../models/evaluation_model.dart';
import '../services/api_service.dart';
import '../widgets/question_builder.dart';

class WizardScreen extends StatefulWidget {
  final String patientId;
  final int year;

  const WizardScreen({
    super.key,
    required this.patientId,
    required this.year,
  });

  @override
  State<WizardScreen> createState() => _WizardScreenState();
}

class _WizardScreenState extends State<WizardScreen> {
  final ApiService _apiService = ApiService();
  final PageController _pageController = PageController();
  final TextEditingController _operatoreController = TextEditingController(text: 'Gigliola');
  
  bool _isLoading = true;
  bool _isSubmitting = false;
  ScaleModel? _scale;
  
  // Lista piatta di tutte le domande per navigazione facile
  List<Question> _allQuestions = [];
  
  // Mappa idDomanda -> valore risposta
  final Map<String, dynamic> _answers = {};
  
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchScale();
  }

  Future<void> _fetchScale() async {
    try {
      final scales = await _apiService.getScales();
      if (scales.isNotEmpty) {
        final scale = scales.first; // Usiamo la prima mockata
        List<Question> questions = [];
        for (var section in scale.sezioni) {
          questions.addAll(section.domande);
        }
        
        setState(() {
          _scale = scale;
          _allQuestions = questions;
          _isLoading = false;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore nel caricamento scala: $e')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _submitEvaluation() async {
    setState(() {
      _isSubmitting = true;
    });

    final evaluation = EvaluationModel(
      idPaziente: widget.patientId,
      anno: widget.year,
      idScala: _scale!.id,
      nomeOperatore: _operatoreController.text,
      risposte: _answers.entries.map((e) {
        return Answer(
          idDomanda: e.key,
          valoreRisposta: e.value,
        );
      }).toList(),
    );

    try {
      final success = await _apiService.createEvaluation(evaluation);
      if (success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Valutazione salvata con successo!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Ritorna true per indicare un refresh
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore durante il salvataggio: $e')),
      );
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _nextPage() {
    if (_currentIndex < _allQuestions.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Controlla se tutte le risposte sono date
      if (_answers.length == _allQuestions.length) {
        _submitEvaluation();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rispondi a tutte le domande per completare.')),
        );
      }
    }
  }

  void _prevPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_scale == null) {
      return const Scaffold(
        body: Center(child: Text('Nessuna scala disponibile')),
      );
    }

    final progress = (_currentIndex + 1) / _allQuestions.length;
    final isLastPage = _currentIndex == _allQuestions.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(_scale!.nome, style: const TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              color: Theme.of(context).colorScheme.primary,
              minHeight: 8,
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Domanda ${_currentIndex + 1} di ${_allQuestions.length}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Disabilita lo swipe manuale
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemCount: _allQuestions.length,
                itemBuilder: (context, index) {
                  final question = _allQuestions[index];
                  // AnimatedSwitcher per animare il contenuto della pagina se lo desideriamo
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Padding(
                      key: ValueKey(question.idDomanda),
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                      child: Center(
                        child: QuestionBuilder(
                          question: question,
                          currentValue: _answers[question.idDomanda],
                          onChanged: (val) {
                            setState(() {
                              _answers[question.idDomanda] = val;
                            });
                            // Auto advance se non è l'ultima e abbiamo risposto
                            Future.delayed(const Duration(milliseconds: 400), () {
                              if (_currentIndex < _allQuestions.length - 1) {
                                _nextPage();
                              }
                            });
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton(
                    onPressed: _currentIndex > 0 && !_isSubmitting ? _prevPage : null,
                    child: const Text('Indietro'),
                  ),
                  FilledButton(
                    onPressed: _isSubmitting ? null : _nextPage,
                    child: _isSubmitting 
                        ? const SizedBox(
                            width: 20, 
                            height: 20, 
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          )
                        : Text(isLastPage ? 'Salva Valutazione' : 'Avanti'),
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
