import 'package:flutter/widgets.dart';

/// Utility centralizzata per breakpoint responsive e valori adattivi.
/// 
/// Breakpoint:
/// - Mobile:  < 600px
/// - Tablet:  600px – 992px
/// - Desktop: > 992px
class ResponsiveHelper {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 992;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 992;

  /// Padding orizzontale standard per il contenuto principale
  static double horizontalPadding(BuildContext context) =>
      isMobile(context) ? 12.0 : 32.0;

  /// Padding verticale standard per il contenuto principale
  static double verticalPadding(BuildContext context) =>
      isMobile(context) ? 12.0 : 24.0;

  /// Font size per titoli di sezione
  static double titleFontSize(BuildContext context) =>
      isMobile(context) ? 22.0 : 28.0;

  /// Font size per sottotitoli di sezione
  static double subtitleFontSize(BuildContext context) =>
      isMobile(context) ? 12.0 : 14.0;

  /// Larghezza massima per dialog responsive
  static double dialogMaxWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 600) return screenWidth * 0.92;
    return 500;
  }
}
