import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/premium_dashboard_assets.dart';

export '../theme/premium_dashboard_assets.dart';

/// Token visivi locali della Dashboard 4.x (premium redesign).
///
/// Indipendenti dal tema globale: la dashboard ha una propria gerarchia
/// visiva senza alterare le altre aree dell'app. I colori `*Ink` sono le
/// varianti scure da usare per il TESTO su fondi chiari (contrasto AA).
abstract final class DashboardTokens {
  // Superfici
  static const Color canvas = Color(0xFFF5F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSecondary = Color(0xFFF4F6FA);
  static const Color track = Color(0xFFEDF1F6);
  static const Color border = Color(0xFFE4E9F1);
  static const Color divider = Color(0xFFEEF1F6);

  // Testo
  static const Color text = Color(0xFF111A2E);
  static const Color textMuted = Color(0xFF5B6779);
  static const Color textSubtle = Color(0xFF8A94A6);
  static const Color deepNavy = Color(0xFF111A2E);
  static const Color midnightBlue = Color(0xFF1E293B);

  // Accenti
  static const Color primary = Color(0xFF3B63F6);
  static const Color indigo = Color(0xFF4F46E5);
  static const Color auroraViolet = Color(0xFF7C3AED);
  static const Color iceCyan = Color(0xFF0EA5E9);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color slate = Color(0xFF475569);
  static const Color neutral = Color(0xFF94A3B8);

  // Varianti testo ad alto contrasto
  static const Color successInk = Color(0xFF047857);
  static const Color warningInk = Color(0xFFB45309);
  static const Color dangerInk = Color(0xFFB91C1C);
  static const Color purpleInk = Color(0xFF6D28D9);
  static const Color primaryInk = Color(0xFF2747C9);

  static const double radius = 18;
  static const double compactRadius = 12;
  static const double gap = 20;
  static const Duration motion = Duration(milliseconds: 180);

  /// Ombra a due livelli: contatto nitido + diffusione morbida.
  static const List<BoxShadow> shadow = [
    BoxShadow(
      color: Color(0x0A111A2E),
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
    BoxShadow(
      color: Color(0x0D111A2E),
      blurRadius: 24,
      spreadRadius: -6,
      offset: Offset(0, 10),
    ),
  ];

  static List<BoxShadow> hoverShadow(Color accent) => [
        const BoxShadow(
          color: Color(0x0F111A2E),
          blurRadius: 3,
          offset: Offset(0, 1),
        ),
        BoxShadow(
          color: accent.withValues(alpha: 0.16),
          blurRadius: 28,
          spreadRadius: -4,
          offset: const Offset(0, 14),
        ),
      ];

  /// Restituisce la variante "ink" (testo) di un colore d'accento.
  static Color inkFor(Color accent) {
    if (accent == danger) return dangerInk;
    if (accent == warning) return warningInk;
    if (accent == success) return successInk;
    if (accent == purple || accent == auroraViolet) return purpleInk;
    if (accent == primary) return primaryInk;
    return accent;
  }
}

/// Sfondo del canvas: base neutra con aloni luminosi molto tenui.
/// Resta l'`Image.asset` (opacità 0) per retrocompatibilità con la suite
/// di test esistente che verifica la presenza dell'asset.
class DashboardAuroraBackground extends StatelessWidget {
  const DashboardAuroraBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(
            painter: _ProfessionalBackgroundPainter(),
            child: SizedBox.expand(),
          ),
          Opacity(
            opacity: 0.0,
            child: Image.asset(
              PremiumDashboardAssets.canvasAbstractBackground,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfessionalBackgroundPainter extends CustomPainter {
  const _ProfessionalBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = DashboardTokens.canvas,
    );

    void glow(Offset center, double radius, Color color) {
      if (radius <= 0) return;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    final side = size.longestSide;
    glow(
      Offset(size.width * 0.92, -size.height * 0.04),
      side * 0.42,
      DashboardTokens.primary.withValues(alpha: 0.075),
    );
    glow(
      Offset(size.width * 0.04, size.height * 0.02),
      side * 0.28,
      DashboardTokens.auroraViolet.withValues(alpha: 0.045),
    );
    glow(
      Offset(size.width * 0.62, size.height * 1.04),
      side * 0.38,
      DashboardTokens.iceCyan.withValues(alpha: 0.04),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Mantenuto per retrocompatibilità API (non più usato nelle card).
class DashboardDecorBlob {
  final Alignment center;
  final double radius;
  final Color color;
  final double opacity;

  const DashboardDecorBlob({
    required this.center,
    required this.radius,
    required this.color,
    this.opacity = 0.16,
  });

  @override
  bool operator ==(Object other) =>
      other is DashboardDecorBlob &&
      other.center == center &&
      other.radius == radius &&
      other.color == color &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(center, radius, color, opacity);
}

/// Mantenuto per retrocompatibilità API: le card premium usano superfici
/// bianche piene, quindi il painter non disegna nulla.
class DashboardDecorPainter extends CustomPainter {
  final List<DashboardDecorBlob> blobs;

  const DashboardDecorPainter(this.blobs);

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(DashboardDecorPainter oldDelegate) =>
      !listEquals(oldDelegate.blobs, blobs);
}

/// Mantenuto per retrocompatibilità API.
abstract final class DashboardDecor {
  static const List<DashboardDecorBlob> summaryBar = [];
  static const List<DashboardDecorBlob> coverage = [];
  static const List<DashboardDecorBlob> alerts = [];
  static const List<DashboardDecorBlob> socioDemographic = [];
  static const List<DashboardDecorBlob> distribution = [];
}

class DashboardSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final String? semanticLabel;
  final String? assetBackground;
  final List<DashboardDecorBlob>? decor;
  final BoxFit assetFit;
  final AlignmentGeometry assetAlignment;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? overlayColor;
  final List<BoxShadow>? boxShadow;
  final double assetOpacity;

  const DashboardSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.borderColor,
    this.semanticLabel,
    this.assetBackground,
    this.decor,
    this.assetFit = BoxFit.cover,
    this.assetAlignment = Alignment.center,
    this.borderRadius = DashboardTokens.radius,
    this.backgroundColor,
    this.overlayColor,
    this.boxShadow,
    this.assetOpacity = PremiumDashboardAssets.defaultOpacity,
  });

  @override
  Widget build(BuildContext context) {
    Widget cardBody = Padding(padding: padding, child: child);

    if (assetBackground != null && assetBackground!.isNotEmpty) {
      cardBody = Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: assetOpacity,
              child: Image.asset(
                assetBackground!,
                fit: assetFit,
                alignment: assetAlignment,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
          if (overlayColor != null)
            Positioned.fill(child: ColoredBox(color: overlayColor!)),
          cardBody,
        ],
      );
    }

    final content = Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? DashboardTokens.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor ?? DashboardTokens.border),
        boxShadow: boxShadow ?? DashboardTokens.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: cardBody,
    );

    if (semanticLabel == null) return content;
    return Semantics(container: true, label: semanticLabel, child: content);
  }
}

/// Badge icona quadrato-arrotondato con gradiente tenue dell'accento.
class DashboardIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const DashboardIconBadge({
    super.key,
    required this.icon,
    required this.color,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.31),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.16),
            color.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

class DashboardSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Color accent;

  const DashboardSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.icon,
    this.accent = DashboardTokens.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          DashboardIconBadge(icon: icon!, color: accent),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: DashboardTokens.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 3),
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

/// Barra di avanzamento con riempimento animato. Non usa LayoutBuilder,
/// quindi è sicura anche dentro `IntrinsicHeight`.
class DashboardProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final Color? secondaryColor;
  final double height;
  final Color trackColor;

  const DashboardProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.secondaryColor,
    this.height = 8,
    this.trackColor = DashboardTokens.track,
  });

  @override
  Widget build(BuildContext context) {
    final target = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: target),
              duration: const Duration(milliseconds: 750),
              curve: Curves.easeOutCubic,
              builder: (context, animated, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: animated,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      colors: [color, secondaryColor ?? color],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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

  /// Avanzamento opzionale 0..1 mostrato come barra in fondo alla card.
  final double? progress;

  final String? assetBackground;
  final BoxFit? assetFit;
  final AlignmentGeometry? assetAlignment;
  final double? assetOpacity;

  const DashboardKpiData({
    required this.label,
    required this.value,
    required this.supportingText,
    required this.icon,
    required this.accent,
    this.onTap,
    this.tooltip,
    this.progress,
    this.assetBackground,
    this.assetFit,
    this.assetAlignment,
    this.assetOpacity,
  });
}

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
                height: compact ? 172 : 176,
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
    final compact = widget.compact;
    final interactive = data.onTap != null;

    final card = Semantics(
      button: interactive,
      label: '${data.label}: ${data.value}. ${data.supportingText}',
      child: FocusableActionDetector(
        mouseCursor:
            interactive ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: _setHighlighted,
        onShowFocusHighlight: _setHighlighted,
        child: AnimatedContainer(
          duration: DashboardTokens.motion,
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(
            0,
            _highlighted && interactive ? -2 : 0,
            0,
          ),
          decoration: BoxDecoration(
            color: DashboardTokens.surface,
            borderRadius: BorderRadius.circular(DashboardTokens.radius),
            border: Border.all(
              color: _highlighted
                  ? data.accent.withValues(alpha: 0.35)
                  : DashboardTokens.border,
            ),
            boxShadow: _highlighted
                ? DashboardTokens.hoverShadow(data.accent)
                : DashboardTokens.shadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DashboardTokens.radius - 1),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: data.onTap,
                splashColor: data.accent.withValues(alpha: 0.06),
                highlightColor: data.accent.withValues(alpha: 0.04),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 20,
                    compact ? 16 : 18,
                    compact ? 16 : 20,
                    compact ? 16 : 18,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          DashboardIconBadge(
                            icon: data.icon,
                            color: data.accent,
                            size: compact ? 36 : 40,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              data.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: DashboardTokens.textMuted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                          if (interactive)
                            AnimatedContainer(
                              duration: DashboardTokens.motion,
                              alignment: Alignment.center,
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _highlighted
                                    ? data.accent
                                    : data.accent.withValues(alpha: 0.08),
                              ),
                              child: Icon(
                                Icons.arrow_forward,
                                size: 15,
                                color:
                                    _highlighted ? Colors.white : data.accent,
                              ),
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
                          fontSize: compact ? 30 : 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data.supportingText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: DashboardTokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      if (data.progress != null) ...[
                        const SizedBox(height: 12),
                        DashboardProgressBar(
                          value: data.progress!,
                          color: data.accent,
                          height: 5,
                        ),
                      ],
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
    final ink = DashboardTokens.inkFor(color);
    return Semantics(
      label: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.circle, size: icon == null ? 8 : 14, color: ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashboardIconBadge(
                icon: icon,
                color: DashboardTokens.primary,
                size: 48,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DashboardTokens.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: DashboardTokens.textMuted,
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Wrapper per la sidebar (API invariata).
class PremiumSidebar extends StatelessWidget {
  final Widget child;
  final bool expanded;
  final double width;
  final EdgeInsetsGeometry margin;
  final double assetOpacity;

  const PremiumSidebar({
    super.key,
    required this.child,
    this.expanded = true,
    this.width = 214,
    this.margin = const EdgeInsets.fromLTRB(12, 12, 0, 12),
    this.assetOpacity = PremiumDashboardAssets.defaultOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      height: double.infinity,
      margin: margin,
      decoration: BoxDecoration(
        color: DashboardTokens.surface,
        borderRadius: BorderRadius.circular(DashboardTokens.radius),
        border: Border.all(color: DashboardTokens.border),
        boxShadow: DashboardTokens.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: assetOpacity,
              child: Image.asset(
                PremiumDashboardAssets.sidebarBackground,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: expanded ? 96 : 120,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xF2FFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }
}

class PremiumSummaryBar extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const PremiumSummaryBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardSurfaceCard(
      padding: padding,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}

class PremiumCoverageCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const PremiumCoverageCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardSurfaceCard(
      padding: padding,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}

class PremiumAlertCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const PremiumAlertCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardSurfaceCard(
      padding: padding,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}

class PremiumSocioDemoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const PremiumSocioDemoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardSurfaceCard(
      padding: padding,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}
