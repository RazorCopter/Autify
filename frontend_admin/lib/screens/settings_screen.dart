// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../services/settings_notifier.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _apiKeyController = TextEditingController();
  
  bool _isLoading = false;
  bool _isExporting = false;
  bool _isImporting = false;
  String? _uploadStatus;
  String? _dbStatus;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  String _selectedModel = 'gemini-1.5-pro';

  Future<void> _loadSettings() async {
    final settings = await _apiService.getGeminiSettings();
    if (settings['key'] != null && settings['key']!.isNotEmpty) {
      _apiKeyController.text = settings['key']!;
    }
    final rawModel = settings['model'] ?? 'gemini-1.5-pro';
    setState(() {
      if (rawModel == 'gemini-1.5-pro' || rawModel == 'gemini-1.5-flash' || rawModel == 'gemini-1.5-pro-latest') {
        _selectedModel = rawModel;
      } else if (rawModel.contains('flash')) {
        _selectedModel = 'gemini-1.5-flash';
      } else {
        _selectedModel = 'gemini-1.5-pro';
      }
    });
  }

  Future<void> _pickAndUploadJSON() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result != null) {
      setState(() {
        _isLoading = true;
        _uploadStatus = 'Caricamento in corso...';
      });

      final success = await _apiService.uploadProtocolJSON(
        result.files.single,
      );

      setState(() {
        _isLoading = false;
        if (success) {
          _uploadStatus = 'Protocollo caricato con successo!';
        } else {
          _uploadStatus = 'Errore durante il caricamento o formato non ancora supportato.';
        }
      });
    }
  }

  Future<void> _exportDatabase() async {
    setState(() {
      _isExporting = true;
      _dbStatus = 'Esportazione in corso...';
    });
    final bytes = await _apiService.exportDatabase();
    setState(() => _isExporting = false);
    if (bytes != null) {
      final b64 = base64Encode(bytes);
      final dataUrl = 'data:application/json;base64,$b64';
      final timestamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-').substring(0, 19);
      html.AnchorElement(href: dataUrl)
        ..setAttribute('download', 'autanalysis_backup_$timestamp.json')
        ..click();
      setState(() => _dbStatus = 'Backup esportato con successo!');
    } else {
      setState(() => _dbStatus = 'Errore durante l\'esportazione.');
    }
  }

  Future<void> _importDatabase() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );

    if (result != null) {
      setState(() {
        _isImporting = true;
        _dbStatus = 'Importazione in corso...';
      });

      final success = await _apiService.importDatabase(result.files.single);

      setState(() {
        _isImporting = false;
        if (success) {
          _dbStatus = 'Database importato con successo!';
        } else {
          _dbStatus = 'Errore durante l\'importazione. Verifica il formato del file.';
        }
      });
    }
  }

  Future<void> _saveAIConfig() async {
    setState(() => _isLoading = true);
    final success = await _apiService.saveGeminiSettings(_apiKeyController.text, _selectedModel);
    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Configurazione AI salvata!' : 'Errore nel salvataggio')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Impostazioni di Sistema', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          
          // Sezione Protocolli
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Protocolli di Supporto', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Importa le scale di valutazione da file JSON.'),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading || ApiService.isViewer ? null : _pickAndUploadJSON,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Carica Protocollo JSON'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (_isLoading) const CircularProgressIndicator(),
                      if (_isLoading) const SizedBox(width: 16),
                      if (_uploadStatus != null) 
                        Expanded(child: Text(_uploadStatus!, style: TextStyle(color: _uploadStatus!.contains('Errore') ? Colors.red : Colors.green))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Sezione AI
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Configurazione AI (Gemini)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Inserisci la tua API Key e seleziona il modello per abilitare le funzionalità di analisi intelligente dei dati.'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          enabled: !ApiService.isViewer,
                          decoration: const InputDecoration(
                            labelText: 'Gemini API Key',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.key),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          value: _selectedModel,
                          decoration: const InputDecoration(
                            labelText: 'Modello',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.psychology),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'gemini-1.5-pro', child: Text('Gemini 1.5 Pro (Consigliato)')),
                            DropdownMenuItem(value: 'gemini-1.5-flash', child: Text('Gemini 1.5 Flash (Veloce)')),
                            DropdownMenuItem(value: 'gemini-1.5-pro-latest', child: Text('Gemini 1.5 Pro Latest')),
                          ],
                          onChanged: ApiService.isViewer ? null : (value) {
                            if (value != null) {
                              setState(() {
                                _selectedModel = value;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(minimumSize: const Size(0, 56)),
                        onPressed: _isLoading || ApiService.isViewer ? null : _saveAIConfig,
                        icon: const Icon(Icons.save),
                        label: const Text('Salva'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),

          // Sezione Parametri di Validità Scale (Gestione reattiva)
          Consumer<SettingsNotifier>(
            builder: (context, notifier, child) {
              final settings = notifier.settings;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Parametri di Validità Scale',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Configura la validità temporale delle valutazioni e la soglia di preavviso per gli indicatori di scadenza.',
                        style: TextStyle(color: Color(0xFF718096)),
                      ),
                      const SizedBox(height: 24),
                      
                      // Validità POS Slider
                      _buildSliderRow(
                        title: 'Validità Scala POS',
                        value: settings.validityMonthsPOS.toDouble(),
                        min: 1,
                        max: 24,
                        unit: 'mesi',
                        icon: Icons.calendar_month,
                        onChanged: (val) {
                          notifier.updateSettings(validityMonthsPOS: val.toInt());
                        },
                      ),
                      const Divider(height: 32, color: Color(0xFFE8EEF8)),
                      
                      // Validità San Martín Slider
                      _buildSliderRow(
                        title: 'Validità Scala San Martín',
                        value: settings.validityMonthsSanMartin.toDouble(),
                        min: 1,
                        max: 24,
                        unit: 'mesi',
                        icon: Icons.edit_calendar,
                        onChanged: (val) {
                          notifier.updateSettings(validityMonthsSanMartin: val.toInt());
                        },
                      ),
                      const Divider(height: 32, color: Color(0xFFE8EEF8)),
                      
                      // Preavviso Alert Slider
                      _buildSliderRow(
                        title: 'Preavviso Alert di Scadenza',
                        value: settings.alertThresholdDays.toDouble(),
                        min: 0,
                        max: 60,
                        unit: 'giorni',
                        icon: Icons.notification_important,
                        onChanged: (val) {
                          notifier.updateSettings(alertThresholdDays: val.toInt());
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          
          const SizedBox(height: 24),
          
          // Sezione Database
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Database', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Esporta l\'intero database in un file JSON o ripristina un backup precedente.'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _isExporting || _isImporting || ApiService.isViewer ? null : _exportDatabase,
                          icon: _isExporting
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.download_rounded),
                          label: Text(_isExporting ? 'Esportazione...' : 'Esporta Database'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _isExporting || _isImporting || ApiService.isViewer ? null : _importDatabase,
                          icon: _isImporting
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.upload_file),
                          label: Text(_isImporting ? 'Importazione...' : 'Importa Database'),
                        ),
                      ),
                    ],
                  ),
                  if (_dbStatus != null) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (_isImporting || _isExporting) const CircularProgressIndicator(),
                        if (_isImporting || _isExporting) const SizedBox(width: 16),
                        Expanded(child: Text(_dbStatus!, style: TextStyle(color: _dbStatus!.contains('Errore') ? Colors.red : Colors.green))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String title,
    required double value,
    required double min,
    required double max,
    required String unit,
    required IconData icon,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF64B5F6).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF64B5F6), size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Valore attuale: ${value.toInt()} $unit',
                style: const TextStyle(color: Color(0xFF718096), fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Text('${min.toInt()}', style: const TextStyle(color: Color(0xFF718096), fontSize: 12)),
              Expanded(
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: (max - min).toInt(),
                  activeColor: const Color(0xFF64B5F6),
                  inactiveColor: const Color(0xFF64B5F6).withValues(alpha: 0.15),
                  onChanged: ApiService.isViewer ? null : onChanged,
                ),
              ),
              Text('${max.toInt()}', style: const TextStyle(color: Color(0xFF718096), fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
