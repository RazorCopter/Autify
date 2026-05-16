import 'package:flutter/material.dart';
import '../models/patient_model.dart';
import '../models/scale_model.dart';
import 'evaluation_detail_screen.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class AnagraficaScreen extends StatefulWidget {
  const AnagraficaScreen({super.key});

  @override
  State<AnagraficaScreen> createState() => _AnagraficaScreenState();
}

class _AnagraficaScreenState extends State<AnagraficaScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<PatientModel>> _patientsFuture;
  List<ScaleModel> _availableScales = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
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
    final noteController = TextEditingController(text: patient?.note ?? '');

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
                    Text(isEdit ? 'Modifica Paziente' : 'Nuovo Paziente',
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
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: pesoController,
                        decoration: const InputDecoration(labelText: 'Peso (kg)', prefixIcon: Icon(Icons.monitor_weight_outlined)),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                            note: noteController.text.trim(),
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
                            _showSnack(isEdit ? 'Paziente aggiornato' : 'Paziente creato', isError: false);
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
                  const Text('Elimina Paziente',
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
        _showSnack('Paziente eliminato', isError: false);
      } else {
        _showSnack('Errore durante l\'eliminazione', isError: true);
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
                        Text('Anagrafica Pazienti',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text('Gestisci i dati dei pazienti',
                          style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showPatientDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Aggiungi Paziente'),
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
              const SizedBox(height: 28),
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
                            Text('Caricamento pazienti...', style: TextStyle(color: AppTheme.textSecondary)),
                          ],
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Errore: ${snapshot.error}'));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text('Nessun paziente trovato. Aggiungine uno.',
                            style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                      );
                    }
                    return GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 400,
                        mainAxisExtent: 180,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: snapshot.data!.length,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemBuilder: (ctx, i) => _buildPatientCard(snapshot.data![i], i),
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

  Widget _buildPatientCard(PatientModel patient, int index) {
    final color = AppTheme.puzzleColorAt(index);
    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Text(
                    '${patient.nome[0].toUpperCase()}${patient.cognome[0].toUpperCase()}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${patient.nome} ${patient.cognome}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (patient.altezza != null) '${patient.altezza} cm',
                          if (patient.peso != null) '${patient.peso} kg',
                        ].join(' • '),
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (patient.note != null && patient.note!.isNotEmpty)
              Expanded(
                child: Text(patient.note!,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.analytics_outlined, size: 20, color: AppTheme.accentColor),
                  onPressed: () {
                    if (_availableScales.isEmpty) {
                      _showSnack('Nessun protocollo disponibile', isError: true);
                      return;
                    }
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: const Text('Scegli Protocollo', style: TextStyle(fontWeight: FontWeight.bold)),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _availableScales.length,
                            itemBuilder: (context, index) {
                              final scale = _availableScales[index];
                              return ListTile(
                                leading: const Icon(Icons.description_outlined, color: AppTheme.primaryColor),
                                title: Text(scale.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(scale.id, style: const TextStyle(fontSize: 12)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EvaluationDetailScreen(
                                        patient: patient,
                                        scale: scale,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Annulla'),
                          ),
                        ],
                      ),
                    );
                  },
                  tooltip: 'Analisi Valutazione',
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20, color: AppTheme.primaryColor),
                  onPressed: () => _showPatientDialog(patient: patient),
                  tooltip: 'Modifica',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.errorColor),
                  onPressed: () => _confirmDelete(patient),
                  tooltip: 'Elimina',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
