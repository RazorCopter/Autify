import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class Sis3DItemCard extends StatelessWidget {
  final String itemId;
  final String title;
  final String? description;
  final int? selectedF;
  final int? selectedD;
  final int? selectedT;
  final List<int> disabledFrequencies;
  final List<int> disabledDurations;
  final List<int> disabledTypes;
  final ValueChanged<int>? onFChanged;
  final ValueChanged<int>? onDChanged;
  final ValueChanged<int>? onTChanged;
  final bool isEditMode;

  static const Map<int, String> legendaFrequenza = {
    0: "Nessuna o meno di una volta al mese",
    1: "Almeno una volta al mese, ma meno di una volta alla settimana",
    2: "Almeno una volta alla settimana, ma meno di una volta al giorno",
    3: "Almeno una volta al giorno, ma meno di una volta all'ora",
    4: "Ogni ora o con maggior frequenza",
  };

  static const Map<int, String> legendaDurata = {
    0: "Nessuno",
    1: "Meno di 30 minuti",
    2: "Da 30 minuti a meno di 2 ore",
    3: "Da 2 ore a meno di 4 ore",
    4: "4 ore o più",
  };

  static const Map<int, String> legendaTipo = {
    0: "Nessuno",
    1: "Monitoraggio",
    2: "Prompt verbale o gestuale",
    3: "Assistenza fisica parziale",
    4: "Assistenza fisica totale",
  };

  const Sis3DItemCard({
    super.key,
    required this.itemId,
    required this.title,
    this.description,
    this.selectedF,
    this.selectedD,
    this.selectedT,
    this.disabledFrequencies = const [],
    this.disabledDurations = const [],
    this.disabledTypes = const [],
    this.onFChanged,
    this.onDChanged,
    this.onTChanged,
    this.isEditMode = true,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width > 650;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
      ),
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- HEADER: CODICE + TITOLO + INFO ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    itemId,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: isTablet ? 18 : 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
                if (description != null && description!.isNotEmpty)
                  Tooltip(
                    message: description,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    showDuration: const Duration(seconds: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.textPrimary.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.4,
                    ),
                    triggerMode: TooltipTriggerMode.tap,
                    child: IconButton(
                      icon: const Icon(Icons.info_outline_rounded, color: AppTheme.textSecondary, size: 22),
                      onPressed: () {
                        // Consente l'apertura anche con tap su mobile
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0xFFF1F5F9), height: 1),
            const SizedBox(height: 16),

            // --- ROWS: F, D, T ---
            _buildDimensionRow(
              context: context,
              label: "Frequenza",
              selectedValue: selectedF,
              disabledValues: disabledFrequencies,
              onChanged: onFChanged,
              legends: legendaFrequenza,
              dimColor: const Color(0xFF1E88E5), // Blue
              icon: Icons.access_time_filled_rounded,
              isTablet: isTablet,
            ),
            const SizedBox(height: 18),
            _buildDimensionRow(
              context: context,
              label: "Durata quotidiana",
              selectedValue: selectedD,
              disabledValues: disabledDurations,
              onChanged: onDChanged,
              legends: legendaDurata,
              dimColor: const Color(0xFFFB8C00), // Orange
              icon: Icons.hourglass_full_rounded,
              isTablet: isTablet,
            ),
            const SizedBox(height: 18),
            _buildDimensionRow(
              context: context,
              label: "Tipo di sostegno",
              selectedValue: selectedT,
              disabledValues: disabledTypes,
              onChanged: onTChanged,
              legends: legendaTipo,
              dimColor: const Color(0xFF43A047), // Green
              icon: Icons.front_hand_rounded,
              isTablet: isTablet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDimensionRow({
    required BuildContext context,
    required String label,
    required int? selectedValue,
    required List<int> disabledValues,
    required ValueChanged<int>? onChanged,
    required Map<int, String> legends,
    required Color dimColor,
    required IconData icon,
    required bool isTablet,
  }) {
    final hasSelection = selectedValue != null;
    final feedbackText = hasSelection ? (legends[selectedValue] ?? '') : '';

    return LayoutBuilder(
      builder: (context, constraints) {
        final useHorizontal = isTablet && constraints.maxWidth > 550;

        final titleWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: dimColor, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        );

        final buttonsWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            final isDisabled = disabledValues.contains(index);
            final isSelected = selectedValue == index;

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _buildCompactButton(
                  value: index,
                  isSelected: isSelected,
                  isDisabled: isDisabled,
                  color: dimColor,
                  onTap: (isEditMode && !isDisabled && onChanged != null)
                      ? () => onChanged(index)
                      : null,
                ),
              ),
            );
          }),
        );

        final feedbackWidget = AnimatedOpacity(
          opacity: hasSelection ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Text(
            feedbackText,
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: dimColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        );

        if (useHorizontal) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 160,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    titleWidget,
                    const SizedBox(height: 4),
                    feedbackWidget,
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: buttonsWidget,
                ),
              ),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  titleWidget,
                  feedbackWidget,
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 40,
                child: buttonsWidget,
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildCompactButton({
    required int value,
    required bool isSelected,
    required bool isDisabled,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isDisabled
              ? const Color(0xFFF1F5F9)
              : isSelected
                  ? color
                  : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDisabled
                ? const Color(0xFFE2E8F0)
                : isSelected
                    ? color
                    : const Color(0xFFCBD5E1),
            width: isSelected ? 2.0 : 1.2,
          ),
          boxShadow: (isSelected && !isDisabled)
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Center(
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDisabled
                  ? const Color(0xFF94A3B8)
                  : isSelected
                      ? Colors.white
                      : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
