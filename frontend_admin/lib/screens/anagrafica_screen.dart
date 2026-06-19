import 'dart:async';
import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/patient_model.dart';
import '../models/scale_model.dart';
import '../services/api_service.dart';
import '../services/settings_notifier.dart';
import '../services/validity_calculator.dart';
import '../utils/responsive_helper.dart';
import '../theme/app_theme.dart';
import 'multidimensional_dashboard_screen.dart';

class AnagraficaScreen extends StatefulWidget {
  final String? initialSearchQuery;

  const AnagraficaScreen({
    super.key,
    this.initialSearchQuery,
  });

  @override
  State<AnagraficaScreen> createState() => _AnagraficaScreenState();
}

class _AnagraficaScreenState extends State<AnagraficaScreen> {
  final ApiService _apiService = ApiService();
  late Future<PaginatedPatientsResult> _patientsFuture;
  final TextEditingController _searchController = TextEditingController();
  List<ScaleModel> _availableScales = [];
  bool _isLoading = false;
  bool _isGridView = true;
  bool _isExporting = false;
  String _statusFilter = 'active'; // 'active', 'archived', 'all'
  String? _semanticFilter; // null | 'scaduti' | 'in_scadenza' | 'incompleti' | 'mai_valutati'
  int _currentPage = 1;
  static const int _pageSize = 50;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchQuery != null) {
      _searchController.text = widget.initialSearchQuery!;
    }
    _refreshPatients();
    _loadScales();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _refreshPatients({bool resetPage = true}) {
    if (resetPage) _currentPage = 1;
    setState(() {
      _patientsFuture = _apiService.getPatients(
        page: _currentPage,
        pageSize: _pageSize,
        search: _searchController.text.trim().isEmpty ? null : _searchController.text.trim(),
        status: _statusFilter,
        filter: _semanticFilter,
      );
    });
  }

  void _setSemanticFilter(String? value) {
    if (_semanticFilter == value) return;
    setState(() => _semanticFilter = value);
    _refreshPatients();
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      _refreshPatients();
    });
  }

  Future<void> _exportCsv() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final bytes = await _apiService.exportPatientsCsv();
      if (bytes != null) {
        final base64Data = base64Encode(bytes);
        final dataUrl = 'data:text/csv;base64,$base64Data';
        final now = DateTime.now();
        final filename = 'autify_utenti_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv';
        html.AnchorElement(href: dataUrl)
          ..setAttribute('download', filename)
          ..click();
      }
    } catch (e) {
      debugPrint('Export error: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _loadScales() async {
    final scales = await _apiService.getScales();
    if (mounted) {
      setState(() => _availableScales = scales);
    }
  }

  Future<void> _showPatientDialog({PatientModel? patient}) async {
    final bool isEdit = patient != null;
    final nomeController = TextEditingController(text: patient?.nome ?? '');
    final cognomeController = TextEditingController(text: patient?.cognome ?? '');
    final pesoController = TextEditingController(text: patient?.peso?.toString() ?? '');
    final dataNascitaController = TextEditingController(text: patient?.dataNascita != null ? _formatDateString(patient!.dataNascita!) : '');
    String? selectedSesso = patient?.sesso;
    final noteController = TextEditingController(text: patient?.note ?? '');
    bool attivoVal = patient?.attivo ?? true;

    final _formKey = GlobalKey<FormState>();

    try {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
      width: ResponsiveHelper.dialogMaxWidth(context),
      padding: EdgeInsets.all(ResponsiveHelper.isMobile(context) ? 20 : 28),
          child: Form(
            key: _formKey,
            child: StatefulBuilder(
              builder: (ctx, setStateDialog) => SingleChildScrollView(
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
                          child: Icon(isEdit ? Icons.edit : Icons.person_add, color: AppTheme.primaryColor, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Text(isEdit ? 'Modifica Utente' : 'Nuovo Utente',
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (ResponsiveHelper.isMobile(context)) ...[
                      TextFormField(
                        controller: nomeController,
                        decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => v == null || v.isEmpty ? 'Campo richiesto' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: cognomeController,
                        decoration: const InputDecoration(labelText: 'Cognome'),
                        validator: (v) => v == null || v.isEmpty ? 'Campo richiesto' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: pesoController,
                        decoration: const InputDecoration(labelText: 'Peso (kg)', prefixIcon: Icon(Icons.monitor_weight_outlined)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          final n = double.tryParse(v.trim().replaceAll(',', '.'));
                          if (n == null || n <= 0) return 'Valore non valido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: dataNascitaController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Data di Nascita',
                          prefixIcon: Icon(Icons.cake_outlined),
                          hintText: 'Seleziona...',
                        ),
                        onTap: () async {
                          DateTime initialDate = DateTime(1990);
                          if (dataNascitaController.text.isNotEmpty) {
                            try {
                              final parts = dataNascitaController.text.split('/');
                              if (parts.length == 3) {
                                initialDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                              }
                            } catch (_) {}
                          }
                          final DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: initialDate,
                            firstDate: DateTime(1900),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            final day = picked.day.toString().padLeft(2, '0');
                            final month = picked.month.toString().padLeft(2, '0');
                            final year = picked.year.toString();
                            dataNascitaController.text = '$day/$month/$year';
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedSesso,
                        decoration: const InputDecoration(
                          labelText: 'Sesso',
                          prefixIcon: Icon(Icons.wc_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'M', child: Text('M')),
                          DropdownMenuItem(value: 'F', child: Text('F')),
                        ],
                        onChanged: (val) {
                          setStateDialog(() {
                            selectedSesso = val;
                          });
                        },
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: nomeController,
                              decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person_outline)),
                              validator: (v) => v == null || v.isEmpty ? 'Campo richiesto' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: cognomeController,
                              decoration: const InputDecoration(labelText: 'Cognome'),
                              validator: (v) => v == null || v.isEmpty ? 'Campo richiesto' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: pesoController,
                        decoration: const InputDecoration(labelText: 'Peso (kg)', prefixIcon: Icon(Icons.monitor_weight_outlined)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        validator: (v) {
                          if (v == null || v.isEmpty) return null;
                          final n = double.tryParse(v.trim().replaceAll(',', '.'));
                          if (n == null || n <= 0) return 'Valore non valido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: dataNascitaController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Data di Nascita',
                                prefixIcon: Icon(Icons.cake_outlined),
                                hintText: 'Seleziona...',
                              ),
                              onTap: () async {
                                DateTime initialDate = DateTime(1990);
                                if (dataNascitaController.text.isNotEmpty) {
                                  try {
                                    final parts = dataNascitaController.text.split('/');
                                    if (parts.length == 3) {
                                      initialDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                                    }
                                  } catch (_) {}
                                }
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: initialDate,
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  final day = picked.day.toString().padLeft(2, '0');
                                  final month = picked.month.toString().padLeft(2, '0');
                                  final year = picked.year.toString();
                                  dataNascitaController.text = '$day/$month/$year';
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: selectedSesso,
                              decoration: const InputDecoration(
                                labelText: 'Sesso',
                                prefixIcon: Icon(Icons.wc_outlined),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'M', child: Text('M')),
                                DropdownMenuItem(value: 'F', child: Text('F')),
                              ],
                              onChanged: (val) {
                                setStateDialog(() {
                                  selectedSesso = val;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: noteController,
                      decoration: const InputDecoration(labelText: 'Note', prefixIcon: Icon(Icons.notes)),
                      maxLines: 3,
                    ),
                    if (isEdit) ...[
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Utente Attivo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        subtitle: const Text('Disattiva per archiviare l\'utente e rimuoverlo dalla lista attiva', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                        value: attivoVal,
                        activeThumbColor: AppTheme.primaryColor,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          setStateDialog(() {
                            attivoVal = val;
                          });
                        },
                      ),
                    ],
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
                            if (_formKey.currentState!.validate()) {
                              final newPatient = PatientModel(
                                id: patient?.id ?? '', // backend generates if empty and creating
                                nome: nomeController.text.trim(),
                                cognome: cognomeController.text.trim(),
                                altezza: patient?.altezza,
                                peso: double.tryParse(pesoController.text.trim().replaceAll(',', '.')),
                                dataNascita: _parseDateString(dataNascitaController.text.trim()),
                                sesso: selectedSesso,
                                note: noteController.text.trim(),
                                attivo: attivoVal,
                              );

                              setState(() => _isLoading = true);
                              bool success;
                              if (isEdit) {
                                success = await _apiService.updatePatient(newPatient);
                              } else {
                                success = await _apiService.createPatient(newPatient);
                              }
                              setState(() => _isLoading = false);

                              if (success && mounted) {
                                Navigator.pop(ctx);
                                _refreshPatients();
                                _showSnack(isEdit ? 'Utente aggiornato' : 'Utente creato', isError: false);
                              } else if (mounted) {
                                _showSnack('Errore di salvataggio', isError: true);
                              }
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
          ),
        ),
      ),
    );
    } finally {
      nomeController.dispose();
      cognomeController.dispose();
      pesoController.dispose();
      dataNascitaController.dispose();
      noteController.dispose();
    }
  }

  Future<void> _confirmDelete(PatientModel patient) async {
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
                  const Text('Elimina Utente',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Sei sicuro di voler eliminare\n"${patient.nome} ${patient.cognome}"?\n\nQuesta azione è irreversibile.',
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
      setState(() => _isLoading = true);
      final success = await _apiService.deletePatient(patient.id);
      setState(() => _isLoading = false);
      if (success) {
        _refreshPatients();
        _showSnack('Utente eliminato', isError: false);
      } else {
        _showSnack('Errore durante l\'eliminazione', isError: true);
      }
    }
  }

  void _openMultidimensionalDashboard(PatientModel patient) {
    if (_availableScales.isEmpty) {
      _showSnack('Nessun protocollo disponibile nel sistema', isError: true);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MultidimensionalDashboardScreen(patient: patient),
      ),
    );
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
    // Listen to SettingsNotifier to reactively rebuild when validity settings change
    context.watch<SettingsNotifier>();

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.all(ResponsiveHelper.horizontalPadding(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header — responsive
              _buildResponsiveHeader(context),
              const SizedBox(height: 16),
              // Search Bar — responsive
              _buildResponsiveSearchBar(context),
              const SizedBox(height: 16),
              // Lista
              Expanded(
                child: FutureBuilder<PaginatedPatientsResult>(
                  future: _patientsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: AppTheme.primaryColor),
                            SizedBox(height: 16),
                            Text('Caricamento utenti...', style: TextStyle(color: AppTheme.textSecondary)),
                          ],
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Errore: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.items.isEmpty) {
                      return const Center(
                        child: Text('Nessun utente trovato. Aggiungine uno.',
                            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                      );
                    }

                    final result = snapshot.data!;
                    // Tutti i filtri sono già applicati server-side; il server restituisce
                    // solo i pazienti che corrispondono a status + search + filter semantico.
                    final filteredList = List<PatientModel>.from(result.items)
                      ..sort((a, b) {
                        final comp = a.cognome.toLowerCase().compareTo(b.cognome.toLowerCase());
                        if (comp != 0) return comp;
                        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
                      });

                    if (filteredList.isEmpty) {
                      return const Center(
                        child: Text('Nessun utente corrisponde ai criteri di ricerca.',
                            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
                      );
                    }

                    Widget listWidget;
                    if (_isGridView && !ResponsiveHelper.isMobile(context)) {
                      listWidget = GridView.builder(
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: ResponsiveHelper.isTablet(context) ? 260 : 280,
                          mainAxisExtent: 165,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: filteredList.length,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemBuilder: (ctx, i) => _buildPatientCardCompact(filteredList[i], i),
                      );
                    } else {
                      listWidget = _buildPatientListView(filteredList);
                    }

                    return Column(
                      children: [
                        Expanded(child: listWidget),
                        if (result.totalPages > 1)
                          _buildPaginationBar(result),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (_isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildPaginationBar(PaginatedPatientsResult result) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: result.hasPrevPage
                ? () {
                    _currentPage--;
                    _refreshPatients(resetPage: false);
                  }
                : null,
            color: AppTheme.primaryColor,
          ),
          Text(
            'Pagina $_currentPage di ${result.totalPages}  (${result.total} utenti)',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: result.hasNextPage
                ? () {
                    _currentPage++;
                    _refreshPatients(resetPage: false);
                  }
                : null,
            color: AppTheme.primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildPatientCardCompact(PatientModel patient, int index) {
    final color = AppTheme.puzzleColorAt(index);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EEF8)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Text(
                    '${patient.nome.isNotEmpty ? patient.nome[0].toUpperCase() : '?'}${patient.cognome.isNotEmpty ? patient.cognome[0].toUpperCase() : '?'}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${patient.nome} ${patient.cognome}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (patient.dataNascita != null && patient.dataNascita!.isNotEmpty)
                            _formatDateString(patient.dataNascita!),
                          if (patient.sesso != null) patient.sesso,
                        ].join(' • '),
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildIaIndicator(patient),
              ],
            ),
            const SizedBox(height: 6),
            if (patient.note != null && patient.note!.isNotEmpty)
              Text(
                patient.note!,
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else
              const Spacer(),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Indicatori delle scale multidimensionali compilate
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildScaleIndicator(patient.ultimoOgvaCompilato, "OGVA"),
                          const SizedBox(width: 4),
                          _buildScaleIndicator(patient.ultimoSabsCompilato, "SABS"),
                          const SizedBox(width: 4),
                          _buildScaleIndicator(patient.ultimoOsoCompilato, "OSO"),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildScaleIndicator(patient.ultimoPosCompilato, "POS"),
                          const SizedBox(width: 4),
                          _buildScaleIndicator(patient.ultimoSanMartinCompilato, "SanMartín"),
                          const SizedBox(width: 4),
                          _buildScaleIndicator(patient.ultimoSisCompilato, "SIS"),
                        ],
                      ),
                    ],
                  ),
                ),
                // Pulsanti Azione (Modifica/Elimina)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primaryColor),
                      onPressed: ApiService.isViewer ? null : () => _showPatientDialog(patient: patient),
                      tooltip: 'Modifica',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
                      onPressed: ApiService.isViewer ? null : () => _confirmDelete(patient),
                      tooltip: 'Elimina',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: ElevatedButton.icon(
                onPressed: () => _openMultidimensionalDashboard(patient),
                icon: const Icon(Icons.analytics_outlined, size: 16),
                label: const Text('Analisi', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentColor.withValues(alpha: 0.1),
                  foregroundColor: AppTheme.accentColor,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScaleIndicator(String? dateStr, String scaleName) {
    Color badgeColor = Colors.grey.shade100;
    Color textColor = Colors.grey.shade400;
    String status = "Non compilata";
    String formattedDate = "";

    if (dateStr != null && dateStr.isNotEmpty) {
      try {
        final date = DateTime.parse(dateStr);
        formattedDate = "${date.day}/${date.month}/${date.year}";

        final currentSettings = context.read<SettingsNotifier>().settings;
        final statusEnum = ValidityCalculator.getStatus(
          completionDate: date,
          scaleType: scaleName,
          currentSettings: currentSettings,
        );

        final color = ValidityCalculator.getColor(
          completionDate: date,
          scaleType: scaleName,
          currentSettings: currentSettings,
        );

        badgeColor = color.withValues(alpha: 0.12);
        textColor = color;

        final isSM = scaleName.toLowerCase().contains('martin') || scaleName.toLowerCase().contains('san');
        final isSIS = scaleName.toLowerCase().contains('sis');
        final months = isSM 
            ? currentSettings.validityMonthsSanMartin 
            : (isSIS ? currentSettings.validityMonthsSIS : currentSettings.validityMonthsPOS);

        switch (statusEnum) {
          case EvaluationStatus.expired:
            status = "Scaduta (compilata il $formattedDate - validità: $months mesi)";
            break;
          case EvaluationStatus.expiring:
            status = "Prossima alla scadenza (compilata il $formattedDate - validità: $months mesi)";
            break;
          case EvaluationStatus.valid:
            status = "Attiva (compilata il $formattedDate - validità: $months mesi)";
            break;
        }
      } catch (_) {
        badgeColor = Colors.grey.shade100;
        textColor = Colors.grey.shade400;
      }
    }

    return Tooltip(
      message: "$scaleName: $status",
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          scaleName == "SanMartín"
              ? "SM"
              : (scaleName == "SIS" || scaleName == "OGVA" || scaleName == "SABS" || scaleName == "OSO")
                  ? scaleName
                  : "POS",
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            color: textColor,
          ),
        ),
      ),
    );
  }

  Widget _buildIaIndicator(PatientModel patient) {
    Color badgeColor = Colors.grey.shade100;
    Color iconColor = Colors.grey.shade400;
    String status = "Nessuna analisi IA";

    final dateStr = patient.ultimaAnalisiIa;
    if (dateStr != null && dateStr.isNotEmpty) {
      try {
        final date = DateTime.parse(dateStr);
        final now = DateTime.now();
        final monthsDiff = (now.year - date.year) * 12 + (now.month - date.month);
        if (monthsDiff < 6) {
          badgeColor = Colors.purple.shade50;
          iconColor = Colors.purple.shade700;
          status = "Analisi IA recente (${date.day}/${date.month}/${date.year})";
        } else {
          badgeColor = Colors.orange.shade50;
          iconColor = Colors.orange.shade800;
          status = "Analisi IA datata (${date.day}/${date.month}/${date.year} - oltre 6 mesi)";
        }
      } catch (_) {
        badgeColor = Colors.grey.shade100;
        iconColor = Colors.grey.shade400;
      }
    }

    return Tooltip(
      message: status,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.psychology_outlined,
          size: 13,
          color: iconColor,
        ),
      ),
    );
  }

  Widget _buildPatientListView(List<PatientModel> list) {
    if (list.isEmpty) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 64, color: AppTheme.primaryColor.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              const Text('Nessun utente trovato.', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
    }

    final isMobile = ResponsiveHelper.isMobile(context);

    if (isMobile) {
      return Expanded(
        child: ListView.builder(
          itemCount: list.length,
          padding: const EdgeInsets.only(bottom: 24),
          itemBuilder: (ctx, i) {
            final p = list[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8EEF8)),
                boxShadow: [
                  BoxShadow(color: AppTheme.primaryColor.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${p.cognome} ${p.nome}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.primaryColor),
                            onPressed: ApiService.isViewer ? null : () => _showPatientDialog(patient: p),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.errorColor),
                            onPressed: ApiService.isViewer ? null : () => _confirmDelete(p),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.cake_outlined, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(p.dataNascita != null && p.dataNascita!.isNotEmpty ? _formatDateString(p.dataNascita!) : '-', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                      const SizedBox(width: 16),
                      const Icon(Icons.wc_outlined, size: 14, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(p.sesso ?? '-', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    ],
                  ),
                  if (p.peso != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.monitor_weight_outlined, size: 14, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          '${p.peso} kg',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildScaleIndicator(p.ultimoOgvaCompilato, "OGVA"),
                          _buildScaleIndicator(p.ultimoSabsCompilato, "SABS"),
                          _buildScaleIndicator(p.ultimoOsoCompilato, "OSO"),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildScaleIndicator(p.ultimoPosCompilato, "POS"),
                          _buildScaleIndicator(p.ultimoSanMartinCompilato, "SanMartín"),
                          _buildScaleIndicator(p.ultimoSisCompilato, "SIS"),
                          _buildIaIndicator(p),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: () => _openMultidimensionalDashboard(p),
                      icon: const Icon(Icons.analytics_outlined, size: 18),
                      label: const Text('Analisi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentColor.withValues(alpha: 0.1),
                        foregroundColor: AppTheme.accentColor,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7FC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Expanded(flex: 2, child: Text('COGNOME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary))),
              Expanded(flex: 2, child: Text('NOME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary))),
              Expanded(flex: 2, child: Text('DATA NASCITA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary))),
              Expanded(flex: 1, child: Text('SESSO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary))),
              Expanded(flex: 2, child: Text('DOCUMENTI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary))),
              Expanded(flex: 2, child: Text('PESO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary))),
              Expanded(flex: 3, child: Text('NOTE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary))),
              SizedBox(width: 200, child: Text('AZIONI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary), textAlign: TextAlign.right)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Table Body
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            padding: const EdgeInsets.only(bottom: 24),
            itemBuilder: (ctx, i) {
              final p = list[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFFE8EEF8))),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(p.cognome, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary))),
                    Expanded(flex: 2, child: Text(p.nome, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary))),
                    Expanded(
                      flex: 2,
                      child: Text(
                        p.dataNascita != null && p.dataNascita!.isNotEmpty ? _formatDateString(p.dataNascita!) : '-',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        p.sesso ?? '-',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildScaleIndicator(p.ultimoOgvaCompilato, "OGVA"),
                              const SizedBox(width: 4),
                              _buildScaleIndicator(p.ultimoSabsCompilato, "SABS"),
                              const SizedBox(width: 4),
                              _buildScaleIndicator(p.ultimoOsoCompilato, "OSO"),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildScaleIndicator(p.ultimoPosCompilato, "POS"),
                              const SizedBox(width: 4),
                              _buildScaleIndicator(p.ultimoSanMartinCompilato, "SanMartín"),
                              const SizedBox(width: 4),
                              _buildScaleIndicator(p.ultimoSisCompilato, "SIS"),
                              const SizedBox(width: 4),
                              _buildIaIndicator(p),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        p.peso != null ? '${p.peso} kg' : '-',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        p.note ?? '',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => _openMultidimensionalDashboard(p),
                            icon: const Icon(Icons.analytics_outlined, size: 16),
                            label: const Text('Analisi', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accentColor.withValues(alpha: 0.1),
                              foregroundColor: AppTheme.accentColor,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                              minimumSize: const Size(0, 32),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: AppTheme.primaryColor),
                            onPressed: ApiService.isViewer ? null : () => _showPatientDialog(patient: p),
                            tooltip: 'Modifica',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.errorColor),
                            onPressed: ApiService.isViewer ? null : () => _confirmDelete(p),
                            tooltip: 'Elimina',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDateString(String yyyymmdd) {
    try {
      final parts = yyyymmdd.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    } catch (_) {}
    return yyyymmdd;
  }

  String _parseDateString(String ddmmyyyy) {
    if (ddmmyyyy.isEmpty) return '';
    try {
      final parts = ddmmyyyy.split('/');
      if (parts.length == 3) {
        return '${parts[2]}-${parts[1]}-${parts[0]}';
      }
    } catch (_) {}
    return ddmmyyyy;
  }

  // ─── RESPONSIVE WIDGETS ──────────────────────────────────────────────────

  Widget _buildResponsiveHeader(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final titleSize = ResponsiveHelper.titleFontSize(context);

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Utenti',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              IconButton.outlined(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _refreshPatients,
                tooltip: 'Aggiorna lista',
                style: IconButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE8EEF8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Gestisci i dati degli utenti',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: ApiService.isViewer ? null : () => _showPatientDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi Utente'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isExporting ? null : _exportCsv,
              icon: _isExporting ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download),
              label: Text(_isExporting ? 'Esportazione...' : 'Esporta (CSV)'),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Utenti',
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text('Gestisci i dati degli utenti',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: _isExporting ? null : _exportCsv,
          icon: _isExporting ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download),
          label: Text(_isExporting ? 'Esportazione...' : 'Esporta (CSV)'),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: ApiService.isViewer ? null : () => _showPatientDialog(),
          icon: const Icon(Icons.add),
          label: const Text('Aggiungi Utente'),
        ),
        const SizedBox(width: 12),
        IconButton.outlined(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _refreshPatients,
          tooltip: 'Aggiorna lista',
          style: IconButton.styleFrom(
            side: const BorderSide(color: Color(0xFFE8EEF8)),
          ),
        ),
      ],
    );
  }

  Widget _buildResponsiveSearchBar(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    Widget searchField = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EEF8)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Cerca utente per nome o cognome...',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () {
                _searchController.clear();
                _refreshPatients();
              },
            ),
        ],
      ),
    );

    Widget filters = Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8EEF8)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _statusFilter,
                isExpanded: true,
                icon: const Icon(Icons.filter_list_rounded, color: AppTheme.textSecondary),
                dropdownColor: Colors.white,
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Solo Attivi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary))),
                  DropdownMenuItem(value: 'archived', child: Text('Archiviati', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary))),
                  DropdownMenuItem(value: 'all', child: Text('Tutti gli utenti', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary))),
                ],
                onChanged: (val) {
                  if (val != null && val != _statusFilter) {
                    _statusFilter = val;
                    _refreshPatients();
                  }
                },
              ),
            ),
          ),
        ),
        if (!isMobile) ...[
          const SizedBox(width: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8EEF8)),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.grid_view_rounded, size: 20),
                  color: _isGridView ? AppTheme.primaryColor : AppTheme.textSecondary,
                  onPressed: () => setState(() => _isGridView = true),
                  tooltip: 'Vista Griglia',
                ),
                IconButton(
                  icon: const Icon(Icons.view_list_rounded, size: 20),
                  color: !_isGridView ? AppTheme.primaryColor : AppTheme.textSecondary,
                  onPressed: () => setState(() => _isGridView = false),
                  tooltip: 'Vista Elenco',
                ),
              ],
            ),
          ),
        ],
      ],
    );

    final semanticChips = _buildSemanticFilterChips();

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          searchField,
          const SizedBox(height: 12),
          filters,
          const SizedBox(height: 10),
          semanticChips,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 16),
            filters,
          ],
        ),
        const SizedBox(height: 10),
        semanticChips,
      ],
    );
  }

  Widget _buildSemanticFilterChips() {
    const chips = [
      ('scaduti', 'Scaduti', Icons.warning_amber_rounded, Color(0xFFD32F2F)),
      ('in_scadenza', 'In scadenza', Icons.schedule_rounded, Color(0xFFF57C00)),
      ('incompleti', 'Incompleti', Icons.incomplete_circle_rounded, Color(0xFF1565C0)),
      ('mai_valutati', 'Mai valutati', Icons.person_search_rounded, Color(0xFF6A1B9A)),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: chips.map((chip) {
        final (value, label, icon, color) = chip;
        final selected = _semanticFilter == value;
        return FilterChip(
          label: Text(label, style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : color,
          )),
          avatar: Icon(icon, size: 14, color: selected ? Colors.white : color),
          selected: selected,
          onSelected: (_) => _setSemanticFilter(selected ? null : value),
          selectedColor: color,
          backgroundColor: color.withValues(alpha: 0.08),
          side: BorderSide(color: selected ? color : color.withValues(alpha: 0.3)),
          checkmarkColor: Colors.white,
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        );
      }).toList(),
    );
  }
}
