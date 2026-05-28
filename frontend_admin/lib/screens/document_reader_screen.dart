import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/patient_model.dart';
import '../theme/app_theme.dart';

enum ReaderTheme { clinical, warm, dark }

class DocumentReaderScreen extends StatefulWidget {
  final PatientModel patient;
  final String report;
  final VoidCallback onExportPdf;
  final bool isExportingPdf;

  const DocumentReaderScreen({
    super.key,
    required this.patient,
    required this.report,
    required this.onExportPdf,
    required this.isExportingPdf,
  });

  @override
  State<DocumentReaderScreen> createState() => _DocumentReaderScreenState();
}

class _DocumentReaderScreenState extends State<DocumentReaderScreen> {
  ReaderTheme _currentTheme = ReaderTheme.clinical;
  double _fontSize = 15.0;
  double _zoom = 1.0;

  // Splitta il report in pagine separate usando il tag standard markdown ---
  List<String> get _pages {
    final splitPages = widget.report.split(RegExp(r'\n---\s*\n|\n---\n'));
    return splitPages.where((p) => p.trim().isNotEmpty).toList();
  }

  // Definizioni dei colori in base al tema selezionato
  Color get _backgroundColor {
    switch (_currentTheme) {
      case ReaderTheme.clinical:
        return const Color(0xFFF1F5F9); // Grigio-azzurro slate 100
      case ReaderTheme.warm:
        return const Color(0xFFF7F5F0); // Crema caldo
      case ReaderTheme.dark:
        return const Color(0xFF0F172A); // Antracite profondo slate 900
    }
  }

  Color get _sheetColor {
    switch (_currentTheme) {
      case ReaderTheme.clinical:
        return Colors.white;
      case ReaderTheme.warm:
        return const Color(0xFFFFFDF9); // Avorio puro
      case ReaderTheme.dark:
        return const Color(0xFF1E293B); // Slate 800
    }
  }

  Color get _borderColor {
    switch (_currentTheme) {
      case ReaderTheme.clinical:
        return const Color(0xFFE2E8F0);
      case ReaderTheme.warm:
        return const Color(0xFFEFE9DC);
      case ReaderTheme.dark:
        return const Color(0xFF334155);
    }
  }

  Color get _textColor {
    switch (_currentTheme) {
      case ReaderTheme.clinical:
        return const Color(0xFF1E293B); // Slate 800
      case ReaderTheme.warm:
        return const Color(0xFF2C241E); // Espresso scuro
      case ReaderTheme.dark:
        return const Color(0xFFF1F5F9); // Slate 100
    }
  }

  Color get _headerFooterColor {
    switch (_currentTheme) {
      case ReaderTheme.clinical:
        return const Color(0xFF64748B);
      case ReaderTheme.warm:
        return const Color(0xFF8C7A6B);
      case ReaderTheme.dark:
        return const Color(0xFF94A3B8);
    }
  }

  Color get _toolbarColor {
    switch (_currentTheme) {
      case ReaderTheme.clinical:
        return Colors.white;
      case ReaderTheme.warm:
        return const Color(0xFFFFFDF9);
      case ReaderTheme.dark:
        return const Color(0xFF1E293B);
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.report));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            const Text('Testo della relazione copiato negli appunti!'),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reportPages = _pages.isEmpty ? [widget.report] : _pages;

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: _backgroundColor,
      ),
      child: Scaffold(
        appBar: _buildAppBar(),
        body: Column(
          children: [
            _buildToolbar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
                child: Center(
                  child: Column(
                    children: List.generate(reportPages.length, (index) {
                      return Column(
                        children: [
                          _buildA4Sheet(
                            content: reportPages[index],
                            pageNumber: index + 1,
                            totalPages: reportPages.length,
                          ),
                          if (index < reportPages.length - 1)
                            const SizedBox(height: 24.0), // Spazio tra i fogli A4
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lettore Relazione Multidimensionale',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          Text(
            'Paziente: ${widget.patient.cognome} ${widget.patient.nome}',
            style: TextStyle(
              fontSize: 12,
              color: _currentTheme == ReaderTheme.dark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      elevation: 0,
      backgroundColor: _toolbarColor,
      foregroundColor: _textColor,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(
          color: _borderColor,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        color: _toolbarColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _currentTheme == ReaderTheme.dark ? 0.2 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(bottom: BorderSide(color: _borderColor, width: 1.0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Sezione 1: Regolazione Font e Zoom
          Row(
            children: [
              const Icon(Icons.text_fields, size: 20),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: _fontSize > 12
                    ? () => setState(() => _fontSize--)
                    : null,
                color: _textColor,
                tooltip: 'Riduci carattere',
              ),
              Text(
                '${_fontSize.toInt()}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _textColor,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: _fontSize < 24
                    ? () => setState(() => _fontSize++)
                    : null,
                color: _textColor,
                tooltip: 'Aumenta carattere',
              ),
              const SizedBox(width: 16),
              const VerticalDivider(width: 1, indent: 8, endIndent: 8),
              const SizedBox(width: 16),
              // Regolazione Zoom Fogli
              const Icon(Icons.zoom_in, size: 20),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.zoom_out_map, size: 20),
                onPressed: _zoom > 0.8
                    ? () => setState(() => _zoom -= 0.1)
                    : null,
                color: _textColor,
                tooltip: 'Rimpicciolisci fogli',
              ),
              Text(
                '${(_zoom * 100).toInt()}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _textColor,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in_map, size: 20),
                onPressed: _zoom < 1.3
                    ? () => setState(() => _zoom += 0.1)
                    : null,
                color: _textColor,
                tooltip: 'Ingrandisci fogli',
              ),
            ],
          ),

          // Sezione 2: Scelta del Tema (Clinical, Warm, Dark)
          Row(
            children: [
              _buildThemeButton(
                theme: ReaderTheme.clinical,
                icon: Icons.brightness_high,
                label: 'Chiaro',
              ),
              const SizedBox(width: 8),
              _buildThemeButton(
                theme: ReaderTheme.warm,
                icon: Icons.coffee_outlined,
                label: 'Warm',
              ),
              const SizedBox(width: 8),
              _buildThemeButton(
                theme: ReaderTheme.dark,
                icon: Icons.dark_mode_outlined,
                label: 'Dark',
              ),
              const SizedBox(width: 16),
              const VerticalDivider(width: 1, indent: 8, endIndent: 8),
              const SizedBox(width: 16),
              // Pulsanti Azione
              OutlinedButton.icon(
                onPressed: _copyToClipboard,
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copia Testo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textColor,
                  side: BorderSide(color: _borderColor),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: widget.isExportingPdf ? null : widget.onExportPdf,
                icon: widget.isExportingPdf
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf, size: 18),
                label: Text(widget.isExportingPdf ? 'Esportazione...' : 'Esporta PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeButton({
    required ReaderTheme theme,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _currentTheme == theme;
    return InkWell(
      onTap: () => setState(() => _currentTheme = theme),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.transparent,
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppTheme.primaryColor : _textColor.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppTheme.primaryColor : _textColor.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildA4Sheet({
    required String content,
    required int pageNumber,
    required int totalPages,
  }) {
    final dynamicWidth = 800.0 * _zoom;
    final dynamicMinHeight = 1130.0 * _zoom;
    final marginPadding = 48.0 * _zoom;

    return Container(
      width: dynamicWidth,
      constraints: BoxConstraints(
        minHeight: dynamicMinHeight,
      ),
      padding: EdgeInsets.symmetric(horizontal: marginPadding, vertical: marginPadding),
      decoration: BoxDecoration(
        color: _sheetColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _currentTheme == ReaderTheme.dark ? 0.35 : 0.06),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Intestazione clinica
          _buildClinicalHeader(),
          SizedBox(height: 24.0 * _zoom),

          // 2. Contenuto Markdown
          Expanded(
            child: MarkdownBody(
              data: content,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                h1: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: (_fontSize + 8) * _zoom, height: 1.4),
                h2: TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: (_fontSize + 4) * _zoom, height: 1.4),
                h3: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: (_fontSize + 2) * _zoom, height: 1.4),
                p: TextStyle(color: _textColor, fontSize: _fontSize * _zoom, height: 1.6),
                strong: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: _fontSize * _zoom),
                em: TextStyle(color: _textColor, fontStyle: FontStyle.italic, fontSize: _fontSize * _zoom),
                listBullet: TextStyle(color: _textColor, fontSize: _fontSize * _zoom),
                blockquote: TextStyle(color: _textColor.withValues(alpha: 0.8), fontSize: _fontSize * _zoom),
                blockquoteDecoration: BoxDecoration(
                  color: _borderColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border(left: BorderSide(color: AppTheme.primaryColor, width: 4 * _zoom)),
                ),
                tableBody: TextStyle(color: _textColor, fontSize: (_fontSize - 2) * _zoom),
                tableHead: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: (_fontSize - 2) * _zoom),
                tableBorder: TableBorder.all(color: _borderColor, width: 0.8),
                horizontalRuleDecoration: BoxDecoration(
                  border: Border(top: BorderSide(color: _borderColor, width: 1.0)),
                ),
              ),
            ),
          ),
          
          SizedBox(height: 24.0 * _zoom),
          // 3. Piè di pagina clinico
          _buildClinicalFooter(pageNumber: pageNumber, totalPages: totalPages),
        ],
      ),
    );
  }

  Widget _buildClinicalHeader() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.extension_outlined,
                  color: AppTheme.primaryColor,
                  size: 16 * _zoom,
                ),
                const SizedBox(width: 6),
                Text(
                  'FONDAZIONE IL TIGLIO ONLUS',
                  style: TextStyle(
                    fontSize: 10 * _zoom,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            Text(
              'Relazione Multidimensionale: ${widget.patient.cognome.toUpperCase()} ${widget.patient.nome}',
              style: TextStyle(
                fontSize: 10 * _zoom,
                fontWeight: FontWeight.bold,
                color: _headerFooterColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Divider(color: _borderColor, height: 1.0, thickness: 1.0),
      ],
    );
  }

  Widget _buildClinicalFooter({required int pageNumber, required int totalPages}) {
    return Column(
      children: [
        Divider(color: _borderColor, height: 1.0, thickness: 1.0),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Autify - Modulo AI Support',
              style: TextStyle(
                fontSize: 9 * _zoom,
                color: _headerFooterColor,
                fontStyle: FontStyle.italic,
              ),
            ),
            Text(
              'Pagina $pageNumber di $totalPages',
              style: TextStyle(
                fontSize: 9 * _zoom,
                fontWeight: FontWeight.bold,
                color: _headerFooterColor,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
