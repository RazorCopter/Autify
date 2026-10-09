/// Centralized paths and metadata for Dashboard 4.0 premium glassmorphic
/// background assets.
abstract final class PremiumDashboardAssets {
  /// Trasparenza predefinita del 50% per gli sfondi grafici glassmorphic.
  static const double defaultOpacity = 0.50;

  /// Sfondo della barra laterale di navigazione principale.
  static const String sidebarBackground =
      'assets/images/01_sidebar_background.png';

  /// Sfondo dell\'intero canvas operativo della Dashboard.
  static const String mainCanvasBackground =
      'assets/images/02_main_canvas_background.png';

  /// Card metrica Utenze Attive.
  static const String activeUsersCardBackground =
      'assets/images/03_card_active_users.png';

  /// Card metrica Valutazioni Attive.
  static const String activeEvaluationsCardBackground =
      'assets/images/04_card_active_evaluations.png';

  /// Card metrica Scale Mancanti.
  static const String missingScalesCardBackground =
      'assets/images/05_card_missing_scales.png';

  /// Barra orizzontale riepilogativa dello stato di conformita.
  static const String statusSummaryBarBackground =
      'assets/images/06_status_summary_bar.png';

  /// Card Copertura Documentale con donut chart.
  static const String documentCoverageCardBackground =
      'assets/images/07_card_document_coverage.png';

  /// Card Centro Alert operativo per azioni urgenti.
  static const String urgentAlertCenterCardBackground =
      'assets/images/08_card_urgent_alert_center.png';

  /// Card Profilo Socio-Demografico.
  static const String socioDemographicCardBackground =
      'assets/images/09_card_socio_demographic.png';

  /// Elenco completo dei 9 asset premium per convalida o precaching selettivo.
  static const List<String> allAssets = [
    sidebarBackground,
    mainCanvasBackground,
    activeUsersCardBackground,
    activeEvaluationsCardBackground,
    missingScalesCardBackground,
    statusSummaryBarBackground,
    documentCoverageCardBackground,
    urgentAlertCenterCardBackground,
    socioDemographicCardBackground,
  ];
}
