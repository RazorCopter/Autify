import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/patient_model.dart';
import '../models/scale_model.dart';
import '../services/api_service.dart';
import '../services/settings_notifier.dart';
import '../services/validity_calculator.dart';
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
  late Future<List<PatientModel>> _patientsFuture;
  final TextEditingController _searchController = TextEditingController();
  List<ScaleModel> _availableScales = [];
  bool _isLoading = false;
  bool _isGridView = true;
  String _statusFilter = 'active'; // 'active', 'archived', 'all'

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchQuery != null) {
      _searchController.text = widget.initialSearchQuery!;
    }
    _refreshPatients();
  }

  void _refreshPatients() {
    setState(() {
      _patientsFuture = _apiService.getPatients();
    });
    _loadScales();
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
    final altezzaController = TextEditingController(text: patient?.altezza?.toString() ?? '');
    final pesoController = TextEditingController(text: patient?.peso?.toString() ?? '');
    final dataNascitaController = TextEditingController(text: patient?.dataNascita != null ? _formatDateString(patient!.dataNascita!) : '');
    String? selectedSesso = patient?.sesso;
    final noteController = TextEditingController(text: patient?.note ?? '');
    bool attivoVal = patient?.attivo ?? true;

    final _formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          width: 500,
          padding: const EdgeInsets.all(28),
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
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: altezzaController,
                            decoration: const InputDecoration(labelText: 'Altezza (cm)', prefixIcon: Icon(Icons.height)),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.isEmpty) return null;
                              final n = int.tryParse(v.trim());
                              if (n == null || n <= 0) return 'Valore non valido';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
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
                        ),
                      ],
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
                        activeColor: AppTheme.primaryColor,
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
                                altezza: int.tryParse(altezzaController.text.trim()),
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
                        Text('Utenza',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text('Gestisci i dati degli utenti',
                          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
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
              ),
              const SizedBox(height: 20),
              // Search Bar
              Row(
                children: [
                  Expanded(
                    child: Container(
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
                              onChanged: (val) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: 'Cerca utente per nome, cognome o note...',
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
                              onPressed: () => setState(() {
                                _searchController.clear();
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE8EEF8)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _statusFilter,
                        icon: const Icon(Icons.filter_list_rounded, color: AppTheme.textSecondary),
                        dropdownColor: Colors.white,
                        items: const [
                          DropdownMenuItem(value: 'active', child: Text('Solo Attivi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary))),
                          DropdownMenuItem(value: 'archived', child: Text('Archiviati', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary))),
                          DropdownMenuItem(value: 'all', child: Text('Tutti gli utenti', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary))),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _statusFilter = val;
                            });
                          }
                        },
                      ),
                    ),
                  ),
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
              ),
              const SizedBox(height: 24),
              // Lista
              Expanded(
                child: FutureBuilder<List<PatientModel>>(
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
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text('Nessun utente trovato. Aggiungine uno.',
                            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                      );
                    }

                    // Filtra gli utenti in base alla query e allo stato attivo/archiviato
                    final query = _searchController.text.toLowerCase().trim();
                    var filteredList = List<PatientModel>.from(snapshot.data!);

                    // Filtro per stato attivo/archiviato
                    if (_statusFilter == 'active') {
                      filteredList = filteredList.where((p) => p.attivo).toList();
                    } else if (_statusFilter == 'archived') {
                      filteredList = filteredList.where((p) => !p.attivo).toList();
                    }

                    // Filtro per ricerca
                    if (query.isNotEmpty) {
                      filteredList = filteredList.where((p) {
                        final matchNome = p.nome.toLowerCase().contains(query);
                        final matchCognome = p.cognome.toLowerCase().contains(query);
                        final matchNote = (p.note ?? '').toLowerCase().contains(query);
                        return matchNome || matchCognome || matchNote;
                      }).toList();
                    }

                    // Ordina per Cognome (Primario) e Nome (Secondario)
                    filteredList.sort((a, b) {
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

                    if (_isGridView) {
                      return GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 280,
                          mainAxisExtent: 140,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: filteredList.length,
                        padding: const EdgeInsets.only(bottom: 24),
                        itemBuilder: (ctx, i) => _buildPatientCardCompact(filteredList[i], i),
                      );
                    } else {
                      return _buildPatientListView(filteredList);
                    }
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
                    '${patient.nome[0].toUpperCase()}${patient.cognome[0].toUpperCase()}',
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
                Row(
                  children: [
                    _buildScaleIndicator(patient.ultimoPosCompilato, "POS"),
                    const SizedBox(width: 6),
                    _buildScaleIndicator(patient.ultimoSanMartinCompilato, "SanMartín"),
                    const SizedBox(width: 6),
                    _buildScaleIndicator(patient.ultimoSisCompilato, "SIS"),
                  ],
                ),
                // Pulsanti Azione
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.analytics_outlined, size: 18, color: AppTheme.accentColor),
                      onPressed: () => _openMultidimensionalDashboard(patient),
                      tooltip: 'Analisi Utente',
                      constraints: const BoxConstraints(),
                      padding: const EdgeInsets.all(4),
                    ),
                    const SizedBox(width: 4),
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
        final months = isSM ? currentSettings.validityMonthsSanMartin : currentSettings.validityMonthsPOS;

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
              : scaleName == "SIS"
                  ? "SIS"
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

  Widget _buildPatientListView(List<PatientModel> list) {
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
              Expanded(flex: 2, child: Text('FISICO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary))),
              Expanded(flex: 3, child: Text('NOTE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary))),
              SizedBox(width: 120, child: Text('AZIONI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textSecondary), textAlign: TextAlign.right)),
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
                      child: Row(
                        children: [
                          _buildScaleIndicator(p.ultimoPosCompilato, "POS"),
                          const SizedBox(width: 6),
                          _buildScaleIndicator(p.ultimoSanMartinCompilato, "SanMartín"),
                          const SizedBox(width: 6),
                          _buildScaleIndicator(p.ultimoSisCompilato, "SIS"),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        [
                          if (p.altezza != null) '${p.altezza} cm',
                          if (p.peso != null) '${p.peso} kg',
                        ].join(' • '),
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
                      width: 120,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.analytics_outlined, size: 18, color: AppTheme.accentColor),
                            onPressed: () => _openMultidimensionalDashboard(p),
                            tooltip: 'Analisi Utente',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
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
}
