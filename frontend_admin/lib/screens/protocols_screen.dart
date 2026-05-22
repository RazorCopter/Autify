import 'package:flutter/material.dart';
import '../models/scale_model.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ProtocolsScreen extends StatefulWidget {
  const ProtocolsScreen({super.key});

  @override
  State<ProtocolsScreen> createState() => _ProtocolsScreenState();
}

class _ProtocolsScreenState extends State<ProtocolsScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<ScaleModel>> _scalesFuture;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _refreshScales();
  }

  void _refreshScales() {
    setState(() {
      _scalesFuture = _apiService.getScales();
    });
  }

  Future<void> _showEditDialog(ScaleModel scale) async {
    final controller = TextEditingController(text: scale.nome);
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit, color: AppTheme.primaryColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Text('Rinomina Protocollo',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'Nome Protocollo',
                  prefixIcon: Icon(Icons.library_books_outlined),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () async {
                      final newName = controller.text.trim();
                      if (newName.isEmpty) return;
                      scale.nome = newName;
                      final success = await _apiService.updateScale(scale);
                      if (success && mounted) {
                        Navigator.pop(ctx);
                        _refreshScales();
                        _showSnack('Protocollo rinominato con successo', isError: false);
                      } else if (mounted) {
                        _showSnack('Errore durante l\'aggiornamento', isError: true);
                      }
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Salva'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(ScaleModel scale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.delete_outline, color: AppTheme.errorColor, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Text('Elimina Protocollo',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Sei sicuro di voler eliminare\n"${scale.nome}"?\n\nQuesta azione è irreversibile.',
                style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Annulla'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Elimina'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isDeleting = true);
      final success = await _apiService.deleteScale(scale.id);
      if (mounted) {
        setState(() => _isDeleting = false);
        if (success) {
          _refreshScales();
          _showSnack('Protocollo eliminato', isError: false);
        } else {
          _showSnack('Errore durante l\'eliminazione', isError: true);
        }
      }
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Text(msg),
        ],
      ),
      backgroundColor: isError ? AppTheme.errorColor : const Color(0xFF43A047),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(20),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Protocolli di Supporto',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text('Gestisci le scale di valutazione a sistema',
                          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _buildHeaderPuzzlePieces(),
                  const SizedBox(width: 12),
                  IconButton.outlined(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _refreshScales,
                    tooltip: 'Aggiorna lista',
                    style: IconButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE8EEF8)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              // Lista
              Expanded(
                child: FutureBuilder<List<ScaleModel>>(
                  future: _scalesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: AppTheme.primaryColor),
                            SizedBox(height: 16),
                            Text('Caricamento protocolli...', style: TextStyle(color: AppTheme.textSecondary)),
                          ],
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return _buildError(snapshot.error.toString());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return _buildEmpty();
                    }
                    return ListView.builder(
                      itemCount: snapshot.data!.length,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemBuilder: (ctx, i) => _buildProtocolCard(snapshot.data![i], i),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (_isDeleting)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  /// Card principale del protocollo con pulsanti CRUD sempre visibili
  Widget _buildProtocolCard(ScaleModel scale, int index) {
    final color = AppTheme.puzzleColorAt(index);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8EEF8)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header card (SEMPRE VISIBILE — NON dentro ExpansionTile title)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
            child: Row(
              children: [
                // Icona puzzle colorata
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.extension, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                // Titolo e descrizione
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(scale.nome,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(scale.descrizione,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // CRUD Buttons — SEMPRE VISIBILI
                _buildCrudButtons(scale, color),
              ],
            ),
          ),
          // Stats bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Row(
              children: [
                _statChip(Icons.folder_outlined, '${scale.sezioni.length} sezioni', color),
                const SizedBox(width: 8),
                _statChip(
                  Icons.quiz_outlined,
                  '${scale.sezioni.fold(0, (s, sec) => s + sec.domande.length)} domande',
                  AppTheme.puzzleColorAt(index + 1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Divider prima delle sezioni
          if (scale.sezioni.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFFF0F4FC)),
            // Lista sezioni espandibile
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                leading: Icon(Icons.expand_circle_down_outlined, color: color.withValues(alpha: 0.6), size: 20),
                title: Text(
                  'Mostra ${scale.sezioni.length} sezioni',
                  style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
                ),
                iconColor: color,
                collapsedIconColor: color.withValues(alpha: 0.5),
                children: scale.sezioni.map((sec) => _buildSectionTile(sec, color)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCrudButtons(ScaleModel scale, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Edit button
        Tooltip(
          message: 'Rinomina protocollo',
          child: InkWell(
            onTap: ApiService.isViewer ? null : () => _showEditDialog(scale),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ApiService.isViewer
                    ? Colors.grey.withValues(alpha: 0.08)
                    : AppTheme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.edit_outlined, 
                size: 18, 
                color: ApiService.isViewer ? Colors.grey : AppTheme.primaryColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Delete button
        Tooltip(
          message: 'Elimina protocollo',
          child: InkWell(
            onTap: ApiService.isViewer ? null : () => _confirmDelete(scale),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: ApiService.isViewer
                    ? Colors.grey.withValues(alpha: 0.08)
                    : AppTheme.errorColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.delete_outline, 
                size: 18, 
                color: ApiService.isViewer ? Colors.grey : AppTheme.errorColor,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildSectionTile(Section section, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EEF8)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          leading: Icon(Icons.folder_open_rounded, color: color.withValues(alpha: 0.7), size: 20),
          title: Text(section.titoloSezione,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary),
          ),
          subtitle: Text('${section.domande.length} domande',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          iconColor: color,
          children: section.domande.map((q) => _buildQuestionTile(q)).toList(),
        ),
      ),
    );
  }

  Widget _buildQuestionTile(Question question) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: AppTheme.primaryColor,
          shape: BoxShape.circle,
        ),
      ),
      title: Text(question.testoDomanda, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          question.opzioni.isNotEmpty ? '${question.opzioni.length} opzioni' : 'N/A',
          style: const TextStyle(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildHeaderPuzzlePieces() {
    return Row(
      children: List.generate(4, (i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Icon(Icons.extension, size: 16, color: AppTheme.puzzleColorAt(i).withValues(alpha: 0.4)),
      )),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 64, color: AppTheme.errorColor),
          const SizedBox(height: 16),
          const Text('Impossibile caricare i protocolli',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(error, style: const TextStyle(color: AppTheme.textSecondary), textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refreshScales,
            icon: const Icon(Icons.refresh),
            label: const Text('Riprova'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.library_books_outlined, size: 56, color: AppTheme.primaryColor),
          ),
          const SizedBox(height: 24),
          const Text('Nessun protocollo trovato',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 10),
          const Text('Vai in Impostazioni per importare\ni protocolli da file CSV',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.extension, size: 24, color: AppTheme.puzzleColorAt(i).withValues(alpha: 0.35)),
            )),
          ),
        ],
      ),
    );
  }
}
