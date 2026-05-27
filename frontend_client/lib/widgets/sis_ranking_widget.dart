import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

class SisRankingWidget extends StatefulWidget {
  final List<QuestionModel> items;
  final Map<String, dynamic> answers;
  final ValueChanged<List<String>> onRankingChanged;
  final List<String>? initialRanking;

  const SisRankingWidget({
    super.key,
    required this.items,
    required this.answers,
    required this.onRankingChanged,
    this.initialRanking,
  });

  @override
  State<SisRankingWidget> createState() => _SisRankingWidgetState();
}

class _SisRankingWidgetState extends State<SisRankingWidget> {
  List<QuestionModel> _top4Items = [];
  List<String> _rankedIds = [];

  @override
  void initState() {
    super.initState();
    _calculateTop4();
  }

  @override
  void didUpdateWidget(covariant SisRankingWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ricalcola se cambiano le risposte o le domande
    if (oldWidget.answers != widget.answers || oldWidget.items != widget.items) {
      _calculateTop4();
    }
  }

  void _calculateTop4() {
    // 1. Calcola F+D+T per ciascun item di Sezione 2
    final List<Map<String, dynamic>> scoredItems = [];
    for (final q in widget.items) {
      final key = q.codice ?? q.idDomanda;
      final ans = widget.answers[key];

      int score = 0;
      if (ans is Map) {
        score += (ans['F'] as int? ?? 0);
        score += (ans['D'] as int? ?? 0);
        score += (ans['T'] as int? ?? 0);
      }

      scoredItems.add({
        'question': q,
        'score': score,
      });
    }

    // 2. Ordina per punteggio decrescente
    scoredItems.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    // 3. Estrae i Top 4
    final top4 = scoredItems.take(4).map((e) => e['question'] as QuestionModel).toList();

    setState(() {
      _top4Items = top4;
      
      // Se abbiamo un ordinamento iniziale precedentemente salvato ed è compatibile coi nuovi top 4, lo preserviamo
      if (widget.initialRanking != null && 
          widget.initialRanking!.length == top4.length && 
          widget.initialRanking!.every((id) => top4.any((q) => (q.codice ?? q.idDomanda) == id))) {
        _rankedIds = List<String>.from(widget.initialRanking!);
        // Riordina _top4Items in base all'ordine di initialRanking
        _top4Items.sort((a, b) {
          final idA = a.codice ?? a.idDomanda;
          final idB = b.codice ?? b.idDomanda;
          return _rankedIds.indexOf(idA).compareTo(_rankedIds.indexOf(idB));
        });
      } else {
        _rankedIds = top4.map((q) => q.codice ?? q.idDomanda).toList();
      }
    });

    widget.onRankingChanged(_rankedIds);
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 650;

    if (_top4Items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Nessun dato sufficiente per calcolare il ranking. Compila prima gli item di Sezione 2.",
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- INTESTAZIONE BANNER BENESSERE / PRIORITA ---
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.25), width: 1.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.sort_rounded, color: AppTheme.primaryColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Prioritarizzazione dei bisogni di Protezione & Tutela",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Ecco i 4 ambiti con maggiore necessità di sostegno rilevati al volo. Trascinali tenendo premuta l'icona a destra ☰ per confermare l'ordine esatto di criticità (1 = più critico).",
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // --- LISTA INTERATTIVA TRASCINABILE ---
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _top4Items.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (oldIndex < newIndex) {
                newIndex -= 1;
              }
              final item = _top4Items.removeAt(oldIndex);
              _top4Items.insert(newIndex, item);
              
              _rankedIds = _top4Items.map((q) => q.codice ?? q.idDomanda).toList();
            });
            widget.onRankingChanged(_rankedIds);
          },
          itemBuilder: (context, index) {
            final q = _top4Items[index];
            final key = q.codice ?? q.idDomanda;
            final ans = widget.answers[key];
            
            int totalScore = 0;
            if (ans is Map) {
              totalScore += (ans['F'] as int? ?? 0);
              totalScore += (ans['D'] as int? ?? 0);
              totalScore += (ans['T'] as int? ?? 0);
            }

            return Card(
              key: ValueKey(key),
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
              ),
              color: Colors.white,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primaryColor,
                  radius: 16,
                  child: Text(
                    "${index + 1}",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                title: Text(
                  q.testoDomanda,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          "Punteggio grezzo totale: $totalScore (F:${ans is Map ? ans['F'] : 0} D:${ans is Map ? ans['D'] : 0} T:${ans is Map ? ans['T'] : 0})",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                trailing: const Icon(
                  Icons.drag_handle_rounded,
                  color: AppTheme.textSecondary,
                  size: 24,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
