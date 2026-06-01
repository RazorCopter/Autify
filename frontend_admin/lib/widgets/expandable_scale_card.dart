import 'package:flutter/material.dart';

/// Widget accordion premium per la pagina "Analisi Utente".
///
/// Stato Chiuso → header colorato con gradiente + summary chips di punteggi.
/// Stato Aperto  → animazione fluida (AnimatedSize) che rivela il contenuto completo.
class ExpandableScaleCard extends StatefulWidget {
  /// Titolo visualizzato nell'header (nome della scala)
  final String title;

  /// Sottotitolo/descrizione breve della scala
  final String subtitle;

  /// Icona dell'header
  final IconData icon;

  /// Colori del gradiente dell'header
  final List<Color> gradientColors;

  /// Widget summary mostrati SOLO nello stato chiuso (chips, valori principali)
  final List<Widget> summaryChips;

  /// Contenuto completo mostrato quando espanso
  final Widget expandedContent;

  /// Callback opzionale per i pulsanti dell'header (Dettaglio, Storico)
  final List<Widget> headerActions;

  /// Se true, la card parte espansa di default
  final bool initiallyExpanded;

  const ExpandableScaleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradientColors,
    required this.summaryChips,
    required this.expandedContent,
    this.headerActions = const [],
    this.initiallyExpanded = false,
  });

  @override
  State<ExpandableScaleCard> createState() => _ExpandableScaleCardState();
}

class _ExpandableScaleCardState extends State<ExpandableScaleCard>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _rotationController;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.easeInOutCubic),
    );
    if (_isExpanded) _rotationController.forward();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _rotationController.forward();
      } else {
        _rotationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: _isExpanded
              ? widget.gradientColors.first.withValues(alpha: 0.3)
              : const Color(0xFFE8EEF8),
          width: _isExpanded ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header (sempre visibile) ────────────────────────────────────
          _buildHeader(),

          // ── Summary chips (visibili solo quando chiuso) ─────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            child: _isExpanded
                ? const SizedBox.shrink()
                : _buildSummaryBar(),
          ),

          // ── Contenuto espanso ───────────────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: widget.expandedContent,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return InkWell(
      onTap: _toggle,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: widget.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            // Icona in cerchio semi-trasparente
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(widget.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),

            // Titolo e sottotitolo
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Azioni header (Storico, Dettaglio)
            ...widget.headerActions.map((a) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: a,
                )),

            // Chevron animato
            const SizedBox(width: 4),
            RotationTransition(
              turns: _rotationAnimation,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryBar() {
    if (widget.summaryChips.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: widget.gradientColors.first.withValues(alpha: 0.04),
        border: Border(
          top: BorderSide(
            color: widget.gradientColors.first.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: widget.summaryChips,
      ),
    );
  }
}

/// Chip di summary per lo stato chiuso della ExpandableScaleCard.
class ScaleSummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color accentColor;
  final IconData? icon;

  const ScaleSummaryChip({
    super.key,
    required this.label,
    required this.value,
    required this.accentColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: accentColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: accentColor.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: accentColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
