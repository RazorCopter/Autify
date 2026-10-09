import 'package:flutter/material.dart';

/// Token visivi locali della Dashboard 4.0.
///
/// Sono intenzionalmente indipendenti dal tema globale: la dashboard mantiene
/// una gerarchia sobria senza modificare l'aspetto delle altre aree dell'app.
abstract final class DashboardTokens {
  static const Color canvas = Color(0xFFF5F7FF);
  static const Color surface = Color(0xEFFFFFFF);
  static const Color text = Color(0xFF172033);
  static const Color textMuted = Color(0xFF667085);
  static const Color border = Color(0x99DCE5F5);
  static const Color deepNavy = Color(0xFF101B3C);
  static const Color midnightBlue = Color(0xFF142653);
  static const Color primary = Color(0xFF356DFF);
  static const Color indigo = Color(0xFF635BFF);
  static const Color auroraViolet = Color(0xFF9370FF);
  static const Color iceCyan = Color(0xFF77E4F2);
  static const Color success = Color(0xFF20B67A);
  static const Color warning = Color(0xFFF5A623);
  static const Color danger = Color(0xFFF05262);
  static const Color purple = Color(0xFF7456B8);

  static const double radius = 18;
  static const double compactRadius = 12;
  static const double gap = 16;
  static const Duration motion = Duration(milliseconds: 180);

  static const List<BoxShadow> shadow = [
    BoxShadow(
      color: Color(0x0A14213D),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];
}

class DashboardAuroraBackground extends StatelessWidget {
  const DashboardAuroraBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: DashboardTokens.canvas,
          gradient: RadialGradient(
            center: Alignment(-0.75, -0.85),
            radius: 1.35,
            colors: [
              Color(0x6677E4F2),
              Color(0x339370FF),
              Color(0x00F5F7FF),
            ],
            stops: [0, 0.46, 1],
          ),
        ),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.95, -0.55),
              radius: 1.15,
              colors: [Color(0x55C5BED8), Color(0x00F5F7FF)],
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final String? semanticLabel;

  const DashboardSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderColor,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: DashboardTokens.surface,
        borderRadius: BorderRadius.circular(DashboardTokens.radius),
        border: Border.all(color: borderColor ?? DashboardTokens.border),
        boxShadow: DashboardTokens.shadow,
      ),
      child: child,
    );

    if (semanticLabel == null) return content;
    return Semantics(container: true, label: semanticLabel, child: content);
  }
}

class DashboardSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const DashboardSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: DashboardTokens.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: DashboardTokens.textMuted,
                  fontSize: 12.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class DashboardKpiData {
  final String label;
  final String value;
  final String supportingText;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;
  final String? tooltip;

  const DashboardKpiData({
    required this.label,
    required this.value,
    required this.supportingText,
    required this.icon,
    required this.accent,
    this.onTap,
    this.tooltip,
  });
}

/// Griglia KPI pura e testabile, allineata ai breakpoint della Dashboard 4.0.
class DashboardKpiGrid extends StatelessWidget {
  final List<DashboardKpiData> items;

  const DashboardKpiGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1100 ? 3 : (width >= 600 ? 2 : 1);
        const gap = DashboardTokens.gap;
        final itemWidth = (width - gap * (columns - 1)) / columns;
        final compact = width < 600;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var index = 0; index < items.length; index++)
              SizedBox(
                key: ValueKey('dashboard-kpi-slot-$index'),
                width: itemWidth,
                height: compact ? 174 : 162,
                child: DashboardKpiCard(
                  key: ValueKey('dashboard-kpi-card-$index'),
                  data: items[index],
                  compact: compact,
                ),
              ),
          ],
        );
      },
    );
  }
}

class DashboardKpiCard extends StatefulWidget {
  final DashboardKpiData data;
  final bool compact;

  const DashboardKpiCard({
    super.key,
    required this.data,
    this.compact = false,
  });

  @override
  State<DashboardKpiCard> createState() => _DashboardKpiCardState();
}

class _DashboardKpiCardState extends State<DashboardKpiCard> {
  bool _highlighted = false;

  void _setHighlighted(bool value) {
    if (_highlighted != value) setState(() => _highlighted = value);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final card = Semantics(
      button: data.onTap != null,
      label: '${data.label}: ${data.value}. ${data.supportingText}',
      child: FocusableActionDetector(
        mouseCursor:
            data.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onShowHoverHighlight: _setHighlighted,
        onShowFocusHighlight: _setHighlighted,
        child: AnimatedScale(
          scale: _highlighted ? 1.012 : 1,
          duration: DashboardTokens.motion,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: DashboardTokens.motion,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: DashboardTokens.surface,
              borderRadius: BorderRadius.circular(DashboardTokens.radius),
              border: Border.all(
                color: _highlighted
                    ? data.accent.withValues(alpha: 0.45)
                    : DashboardTokens.border,
              ),
              boxShadow: _highlighted
                  ? [
                      BoxShadow(
                        color: data.accent.withValues(alpha: 0.12),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : DashboardTokens.shadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DashboardTokens.radius - 1),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: data.onTap,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 4, color: data.accent),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          widget.compact ? 15 : 20,
                          widget.compact ? 14 : 18,
                          widget.compact ? 12 : 18,
                          widget.compact ? 14 : 18,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: widget.compact ? 36 : 40,
                                  height: widget.compact ? 36 : 40,
                                  decoration: BoxDecoration(
                                    color: data.accent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Icon(
                                    data.icon,
                                    size: widget.compact ? 19 : 21,
                                    color: data.accent,
                                  ),
                                ),
                                const Spacer(),
                                if (data.onTap != null)
                                  Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18,
                                    color: data.accent,
                                  ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              data.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: DashboardTokens.text,
                                fontSize: widget.compact ? 25 : 29,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              data.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: DashboardTokens.text,
                                fontSize: widget.compact ? 11.5 : 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              data.supportingText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: DashboardTokens.textMuted,
                                fontSize: 10.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (data.tooltip == null) return card;
    return Tooltip(message: data.tooltip!, child: card);
  }
}

class DashboardStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const DashboardStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.circle,
                size: icon == null ? 8 : 15, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const DashboardEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title. $message',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: DashboardTokens.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: DashboardTokens.primary, size: 24),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DashboardTokens.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DashboardTokens.textMuted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 14),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
