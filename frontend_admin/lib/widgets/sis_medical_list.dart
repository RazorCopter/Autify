import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/scale_model.dart';

class SisMedicalList extends StatelessWidget {
  final List<Question> items;
  final Map<String, int> selections;
  final Function(String, int) onSelectionChanged;
  final String sectionTitle;
  final String? sectionNote;
  final bool isEditMode;

  const SisMedicalList({
    super.key,
    required this.items,
    required this.selections,
    required this.onSelectionChanged,
    required this.sectionTitle,
    this.sectionNote,
    this.isEditMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 650;

    // --- CALCOLO STATISTICHE E ALERT IN REAL-TIME ---
    int countParziale = 0;
    int countEstensivo = 0;
    for (final q in items) {
      final key = q.codice ?? q.idDomanda;
      final val = selections[key];
      if (val == 1) {
        countParziale++;
      } else if (val == 2) {
        countEstensivo++;
      }
    }
    final int totaleEccezionali = countParziale + countEstensivo;
    final bool hasAlert = totaleEccezionali > 5 || countEstensivo > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --- SEZIONE INTESTAZIONE ---
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sectionTitle,
                style: TextStyle(
                  fontSize: isTablet ? 20 : 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              if (sectionNote != null && sectionNote!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  sectionNote!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),

        // --- BANNER ALERT ANIMATO (SENZA LAYOUT SHIFTS INFIDI) ---
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: hasAlert
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F2), // Sfondo rosso ultra-light premium
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFFECDD3), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE11D48).withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFE11D48), // Rosso vivace
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Attenzione: Rilevati bisogni eccezionali",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF9F1239),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Richiede l'attivazione di un piano di sostegno specifico nel profilo finale. "
                                "Dettagli: $totaleEccezionali segnalati (Parziali: $countParziale, Estensivi: $countEstensivo).",
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFBE123C),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // --- LISTA DEGLI ITEM ---
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final q = items[index];
            final key = q.codice ?? q.idDomanda;
            final selectedScore = selections[key] ?? 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selectedScore > 0
                        ? (selectedScore == 2
                            ? const Color(0xFFFECDD3) // Red border
                            : const Color(0xFFFDE68A)) // Amber border
                        : const Color(0xFFE2E8F0),
                    width: selectedScore > 0 ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      // Testo del bisogno
                      Expanded(
                        child: Text(
                          q.testoDomanda,
                          style: TextStyle(
                            fontSize: isTablet ? 15 : 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // I 3 bottoni di scelta semantica [0, 1, 2]
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSemanticButton(
                            score: 0,
                            label: "0",
                            isSelected: selectedScore == 0,
                            selectedBg: const Color(0xFFE8F5E9), // Greenish grey
                            selectedFg: const Color(0xFF2E7D32),
                            onTap: (isEditMode) ? () => onSelectionChanged(key, 0) : null,
                          ),
                          const SizedBox(width: 6),
                          _buildSemanticButton(
                            score: 1,
                            label: "1",
                            isSelected: selectedScore == 1,
                            selectedBg: const Color(0xFFFFF8E1), // Amber
                            selectedFg: const Color(0xFFEF6C00),
                            onTap: (isEditMode) ? () => onSelectionChanged(key, 1) : null,
                          ),
                          const SizedBox(width: 6),
                          _buildSemanticButton(
                            score: 2,
                            label: "2",
                            isSelected: selectedScore == 2,
                            selectedBg: const Color(0xFFFFEBEE), // Soft Red
                            selectedFg: const Color(0xFFC62828),
                            onTap: (isEditMode) ? () => onSelectionChanged(key, 2) : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSemanticButton({
    required int score,
    required String label,
    required bool isSelected,
    required Color selectedBg,
    required Color selectedFg,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 38,
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? selectedFg : const Color(0xFFCBD5E1),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: selectedFg.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isSelected ? selectedFg : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
