import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/scale_model.dart';
import '../models/patient_model.dart';
import '../services/api_service.dart';
import 'wizard_screen.dart';
import 'sis_wizard_screen.dart';


class SelectionScreen extends StatefulWidget {
  const SelectionScreen({super.key});

  @override
  State<SelectionScreen> createState() => _SelectionScreenState();
}

class _SelectionScreenState extends State<SelectionScreen> {
  final ApiService _apiService = ApiService();
  
  bool _isLoading = true;
  List<PatientModel> _patients = [];
  List<ScaleModel> _scales = [];

  String? _selectedPatientId;
  String? _selectedScaleId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    final results = await Future.wait([
      _apiService.getPatients(),
      _apiService.getScales(),
    ]);

    setState(() {
      _patients = results[0] as List<PatientModel>;
      _scales = results[1] as List<ScaleModel>;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header con logo
            _buildHeader(context),
            // Corpo principale
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 24),
                          // Logo bradipo decorativo
                          _buildSlothLogo(),
                          const SizedBox(height: 32),
                          const Text(
                            'Nuova Valutazione',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Seleziona l\'utente e la scala\ndi valutazione da compilare',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 48),
                          
                          // Dropdown Utente
                          _buildDropdownCard<String>(
                            icon: Icons.person_outline,
                            label: 'Utente',
                            hint: 'Seleziona utente...',
                            color: AppTheme.primaryColor,
                            value: _selectedPatientId,
                            items: _patients.map((p) => DropdownMenuItem(
                              value: p.id,
                              child: Text('${p.nome} ${p.cognome}', style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary)),
                            )).toList(),
                            onChanged: (val) => setState(() => _selectedPatientId = val),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Dropdown Scala
                          _buildDropdownCard<String>(
                            icon: Icons.library_books_outlined,
                            label: 'Scala di Valutazione',
                            hint: 'Seleziona protocollo...',
                            color: AppTheme.secondaryColor,
                            value: _selectedScaleId,
                            items: _scales.map((s) => DropdownMenuItem(
                              value: s.id,
                              child: Text(s.nome, style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary)),
                            )).toList(),
                            onChanged: (val) => setState(() => _selectedScaleId = val),
                          ),
                          
                          const SizedBox(height: 40),
                          
                          // Pulsante avvia
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton.icon(
                              onPressed: ApiService.isViewer
                                  ? null
                                  : (_selectedPatientId != null && _selectedScaleId != null) 
                                      ? () {
                                          final isSis = _selectedScaleId!.toLowerCase().contains('sis');
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => isSis
                                                  ? SisWizardScreen(
                                                      patientId: _selectedPatientId!,
                                                      scaleId: _selectedScaleId!,
                                                    )
                                                  : WizardScreen(
                                                      patientId: _selectedPatientId!,
                                                      scaleId: _selectedScaleId!,
                                                    ),
                                            ),
                                          );
                                        } 
                                      : null,
                              icon: Icon(
                                ApiService.isViewer ? Icons.block : Icons.play_circle_outline,
                                size: 24,
                              ),
                              label: Text(
                                ApiService.isViewer
                                    ? 'Sola Lettura - Compilazione Disabilitata'
                                    : 'Inizia Compilazione',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primaryColor,
                                disabledBackgroundColor: ApiService.isViewer
                                    ? Colors.grey.withValues(alpha: 0.12)
                                    : AppTheme.textSecondary.withValues(alpha: 0.3),
                                disabledForegroundColor: ApiService.isViewer
                                    ? Colors.grey
                                    : null,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
            ),
            // Footer puzzle decoration
            _buildPuzzleFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownCard<T>({
    required IconData icon,
    required String label,
    required String hint,
    required Color color,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EEF8)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<T>(
                    isExpanded: true,
                    value: value,
                    hint: Text(hint, style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
                    icon: const Icon(Icons.expand_more, color: AppTheme.textSecondary),
                    items: items,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.psychology, color: AppTheme.primaryColor, size: 28),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Autify',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primaryColor,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Valutazione Multidimensionale',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSlothLogo() {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withValues(alpha: 0.15),
            AppTheme.purpleColor.withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _puzzlePiece(AppTheme.primaryColor),
              const SizedBox(width: 4),
              _puzzlePiece(AppTheme.secondaryColor),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _puzzlePiece(AppTheme.accentColor),
              const SizedBox(width: 4),
              _puzzlePiece(AppTheme.purpleColor),
            ],
          ),
        ],
      ),
    );
  }

  Widget _puzzlePiece(Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.extension, size: 16, color: Colors.white.withValues(alpha: 0.9)),
    );
  }

  Widget _buildPuzzleFooter() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final colors = [
            AppTheme.primaryColor,
            AppTheme.secondaryColor,
            AppTheme.accentColor,
            AppTheme.purpleColor,
          ];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.extension,
              size: 20,
              color: colors[i].withValues(alpha: 0.4),
            ),
          );
        }),
      ),
    );
  }
}
