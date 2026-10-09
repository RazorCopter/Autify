import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/premium_dashboard_assets.dart';

export '../theme/premium_dashboard_assets.dart';

/// Token visivi locali della Dashboard 4.0.
///
/// Sono intenzionalmente indipendenti dal tema globale: la dashboard mantiene
/// una gerarchia sobria senza modificare l'aspetto delle altre aree dell'app.
abstract final class DashboardTokens {
  static const Color canvas = Color(0xFFF7F9FC);
  static const Color surface = Color(0xEFFFFFFF);
  static const Color text = Color(0xFF172033);
  static const Color textMuted = Color(0xFF667085);
  static const Color border = Color(0xB3E0E6EF);
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
  static const Color slate = Color(0xFF42536E);

  static const double radius = 18;
  static const double compactRadius = 12;
  static const double gap = 16;
  static const Duration motion = Duration(milliseconds: 180);

  static const List<BoxShadow> shadow = [
    BoxShadow(
      color: Color(0x1214213D),
      blurRadius: 22,
      offset: Offset(0, 8),
    ),
  ];
}

/// Sfondo del canvas operativo: l'immagine astratta
/// [PremiumDashboardAssets.canvasAbstractBackground], una composizione di
/// lastre traslucide con grana fine. Viene adattata con [BoxFit.cover], e
/// non avendo alcun soggetto riconoscibile sopporta qualunque ritaglio; la
/// base colorata sotto copre l'eventuale mancata decodifica.
class DashboardAuroraBackground extends StatelessWidget {
  const DashboardAuroraBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF4F7FC), Color(0xFFE9EEF7)],
          ),
        ),
        child: SizedBox.expand(
          child: Image(
            image: AssetImage(PremiumDashboardAssets.canvasAbstractBackground),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.medium,
            errorBuilder: _onAssetError,
          ),
        ),
      ),
    );
  }

  static Widget _onAssetError(
    BuildContext context,
    Object error,
    StackTrace? stackTrace,
  ) =>
      const SizedBox.shrink();
}

/// Macchia luminosa morbida, definita in coordinate frazionarie e dipinta a
/// runtime: a differenza di un PNG ritagliato a dimensione fissa si adatta a
/// qualunque larghezza e altezza della card senza ritagli ne' deformazioni.
class DashboardDecorBlob {
  /// Posizione del centro, espressa come allineamento sulla card.
  final Alignment center;

  /// Raggio come frazione del lato maggiore della card.
  final double radius;

  final Color color;

  /// Intensita' al centro della macchia; sfuma a zero sul bordo.
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

/// Dipinge l'insieme di macchie che fa da sfondo decorativo a una card.
class DashboardDecorPainter extends CustomPainter {
  final List<DashboardDecorBlob> blobs;

  const DashboardDecorPainter(this.blobs);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final side = size.longestSide;
    for (final blob in blobs) {
      final radius = blob.radius * side;
      if (radius <= 0) continue;
      final rect = Rect.fromCircle(
        center: blob.center.alongSize(size),
        radius: radius,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              blob.color.withValues(alpha: blob.opacity),
              blob.color.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(DashboardDecorPainter oldDelegate) =>
      !listEquals(oldDelegate.blobs, blobs);
}

/// Palette decorative delle card della Dashboard 4.0. Hanno sostituito i PNG
/// di sfondo ritagliati, che su card di proporzioni variabili venivano
/// ritagliati in modo imprevedibile.
abstract final class DashboardDecor {
  static const List<DashboardDecorBlob> summaryBar = [
    DashboardDecorBlob(
      center: Alignment(-0.95, -0.7),
      radius: 0.6,
      color: DashboardTokens.primary,
      opacity: 0.1,
    ),
    DashboardDecorBlob(
      center: Alignment(0.95, 1.2),
      radius: 0.6,
      color: DashboardTokens.slate,
      opacity: 0.09,
    ),
  ];

  static const List<DashboardDecorBlob> coverage = [
    DashboardDecorBlob(
      center: Alignment(-0.85, 0.95),
      radius: 0.6,
      color: DashboardTokens.primary,
      opacity: 0.13,
    ),
    DashboardDecorBlob(
      center: Alignment(1.05, -0.95),
      radius: 0.5,
      color: DashboardTokens.slate,
      opacity: 0.11,
    ),
  ];

  static const List<DashboardDecorBlob> alerts = [
    DashboardDecorBlob(
      center: Alignment(1.05, -1.0),
      radius: 0.55,
      color: DashboardTokens.danger,
      opacity: 0.1,
    ),
    DashboardDecorBlob(
      center: Alignment(-1.0, 1.05),
      radius: 0.5,
      color: DashboardTokens.slate,
      opacity: 0.11,
    ),
  ];

  static const List<DashboardDecorBlob> socioDemographic = [
    DashboardDecorBlob(
      center: Alignment(1.1, 0.85),
      radius: 0.6,
      color: DashboardTokens.primary,
      opacity: 0.12,
    ),
    DashboardDecorBlob(
      center: Alignment(-0.95, -1.0),
      radius: 0.48,
      color: DashboardTokens.slate,
      opacity: 0.1,
    ),
  ];

  static const List<DashboardDecorBlob> distribution = [
    DashboardDecorBlob(
      center: Alignment(-1.05, -0.95),
      radius: 0.55,
      color: DashboardTokens.slate,
      opacity: 0.11,
    ),
    DashboardDecorBlob(
      center: Alignment(1.05, 1.05),
      radius: 0.55,
      color: DashboardTokens.primary,
      opacity: 0.11,
    ),
  ];
}

class DashboardSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final String? semanticLabel;
  final String? assetBackground;

  /// Decorazione dipinta alternativa all'asset PNG: responsive per
  /// costruzione, si ridisegna a ogni cambio di dimensione della card.
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
    this.padding = const EdgeInsets.all(20),
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
    final effectiveBackground = backgroundColor ?? DashboardTokens.surface;
    final effectiveBorder = borderColor ?? DashboardTokens.border;
    final effectiveShadow = boxShadow ?? DashboardTokens.shadow;

    Widget cardBody = Padding(
      padding: padding,
      child: child,
    );

    if (decor != null && decor!.isNotEmpty) {
      cardBody = Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius - 1),
              child: CustomPaint(painter: DashboardDecorPainter(decor!)),
            ),
          ),
          cardBody,
        ],
      );
    }

    if (assetBackground != null && assetBackground!.isNotEmpty) {
      cardBody = Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius - 1),
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
          ),
          if (overlayColor != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius - 1),
                child: ColoredBox(color: overlayColor!),
              ),
            ),
          cardBody,
        ],
      );
    }

    final content = Container(
      decoration: BoxDecoration(
        color: backgroundColor == null ? null : effectiveBackground,
        // Senza un colore esplicito la superficie usa una sfumatura appena
        // percepibile: evita l'effetto "bianco piatto" delle card.
        gradient: backgroundColor == null
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFFFFF), Color(0xFFF6F8FC)],
              )
            : null,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: effectiveBorder),
        boxShadow: effectiveShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: cardBody,
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
    this.assetBackground,
    this.assetFit,
    this.assetAlignment,
    this.assetOpacity,
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
                      Positioned.fill(
                        child: CustomPaint(
                          painter: DashboardDecorPainter([
                            DashboardDecorBlob(
                              center: const Alignment(1.0, 0.9),
                              radius: 0.7,
                              color: data.accent,
                              opacity: _highlighted ? 0.18 : 0.13,
                            ),
                          ]),
                        ),
                      ),
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

/// Wrapper modulare per la barra laterale di navigazione della Dashboard 4.0,
/// integrata con lo sfondo illustrato ad alta risoluzione [PremiumDashboardAssets.sidebarBackground].
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
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF356DFF).withValues(alpha: 0.10),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
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
                // L'asset e' un pannello completo di sidebar: con cover il suo
                // bordo dipinto cadeva a metà card, lasciando il footer fuori
                // dalla superficie illustrata.
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
          // Velo bianco sulla fascia superiore: il logo cade sulla zona piu'
          // carica dell'illustrazione ancorata in alto.
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

/// Contenitore modulare per la barra di riepilogo conformità con asset
/// [PremiumDashboardAssets.statusSummaryBarBackground].
class PremiumSummaryBar extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const PremiumSummaryBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardSurfaceCard(
      decor: DashboardDecor.summaryBar,
      padding: padding,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}

/// Contenitore modulare per la card di copertura documentale con asset
/// [PremiumDashboardAssets.documentCoverageCardBackground].
class PremiumCoverageCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const PremiumCoverageCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardSurfaceCard(
      decor: DashboardDecor.coverage,
      padding: padding,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}

/// Contenitore modulare per l'Alert Center con asset
/// [PremiumDashboardAssets.urgentAlertCenterCardBackground].
class PremiumAlertCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const PremiumAlertCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardSurfaceCard(
      decor: DashboardDecor.alerts,
      padding: padding,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}

/// Contenitore modulare per il profilo socio-demografico con asset
/// [PremiumDashboardAssets.socioDemographicCardBackground].
class PremiumSocioDemoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const PremiumSocioDemoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return DashboardSurfaceCard(
      decor: DashboardDecor.socioDemographic,
      padding: padding,
      semanticLabel: semanticLabel,
      child: child,
    );
  }
}
