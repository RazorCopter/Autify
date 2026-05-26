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
  final TextEditingController _promptController = TextEditingController();
  bool _viewerAiEnabled = false;
  
  final TextEditingController _adminPwdController = TextEditingController();
  final TextEditingController _viewerPwdController = TextEditingController();
  bool _viewerEnabled = true;
  bool _isAuthConfigLoading = false;
  bool _obscureAdminPwd = true;
  bool _obscureViewerPwd = true;

  bool _isLoading = false;
  bool _isExporting = false;
  bool _isImporting = false;
  String? _uploadStatus;
  String? _dbStatus;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAuthConfig();
  }

  String _selectedModel = 'gemini-1.5-pro';

  Future<void> _loadSettings() async {
    final settings = await _apiService.getGeminiSettings();
    final String? key = settings['key'] as String?;
    if (key != null && key.isNotEmpty) {
      _apiKeyController.text = key;
    }
    _promptController.text = (settings['prompt'] as String?) ?? '';
    _viewerAiEnabled = (settings['viewer_ai_enabled'] as bool?) ?? false;
    final String rawModel = (settings['model'] as String?) ?? 'gemini-1.5-pro';
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

  Future<void> _loadAuthConfig() async {
    if (ApiService.isViewer) return;
    setState(() => _isAuthConfigLoading = true);
    final config = await _apiService.getAuthConfig();
    setState(() {
      _isAuthConfigLoading = false;
      if (config != null) {
        _adminPwdController.text = config['admin_pwd'] ?? '';
        _viewerPwdController.text = config['viewer_pwd'] ?? '';
        _viewerEnabled = config['viewer_enabled'] ?? true;
      }
    });
  }

  Future<void> _saveAuthConfig() async {
    if (ApiService.isViewer) return;
    setState(() => _isAuthConfigLoading = true);
    final success = await _apiService.updateAuthConfig({
      'admin_pwd': _adminPwdController.text,
      'viewer_pwd': _viewerPwdController.text,
      'viewer_enabled': _viewerEnabled,
    });
    setState(() => _isAuthConfigLoading = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Configurazione Sicurezza salvata!' : 'Errore nel salvataggio')),
      );
      // Aggiorna password salvata se l'admin ha cambiato la propria
      if (success) {
         try {
           html.window.localStorage['auth_password'] = _adminPwdController.text;
         } catch (_) {}
      }
    }
  }

  Future<void> _showViewerLogsDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    final logs = await _apiService.getViewerLogs();
    if (mounted) Navigator.pop(context);

    if (mounted) {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Registro Accessi Viewer', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 800,
              height: 500,
              child: logs.isEmpty
                  ? const Center(child: Text('Nessun accesso registrato.'))
                  : SingleChildScrollView(
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFE8EEF8)),
                        columns: const [
                          DataColumn(label: Text('Data e Ora', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Indirizzo IP', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Dispositivo/PC', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: logs.map<DataRow>((log) {
                          DateTime dt = DateTime.tryParse(log['timestamp'] ?? '') ?? DateTime.now();
                          String formattedDate = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                          return DataRow(cells: [
                            DataCell(Text(formattedDate)),
                            DataCell(Text(log['ip_address'] ?? 'N/A')),
                            DataCell(Text(log['device_name'] ?? 'N/A')),
                          ]);
                        }).toList(),
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Chiudi'),
              ),
            ],
          );
        },
      );
    }
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
    final success = await _apiService.saveGeminiSettings(
      _apiKeyController.text,
      _selectedModel,
      prompt: _promptController.text.trim().isEmpty ? null : _promptController.text.trim(),
      viewerAiEnabled: _viewerAiEnabled,
    );
    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Configurazione AI salvata!' : 'Errore nel salvataggio')),
      );
    }
  }

  static const String _defaultSystemPrompt = '''
Sei il massimo esperto e consulente di supporto specializzato nei percorsi per l'Autismo.
Il tuo compito è analizzare in modo multidimensionale i dati quantitativi e qualitativi estratti dalle scale di valutazione dell'utente.

OBIETTIVO DELL'ANALISI:
1. Valutare l'andamento generale e il profilo dell'utente (punti di forza e aree di supporto nei vari domini).
2. Evidenziare correlazioni significative tra le diverse scale somministrate (es. POS, San Martín).
3. Incrociare tutti i dati forniti, incluse le note aggiuntive e gli eventuali allegati documentali.
4. Proporre ipotesi e linee guida per progetti educativi e di supporto customizzati e ritagliati sartorialmente sulle specifiche esigenze dell'utente.
5. Riportare in forma di relazione chiara e coerente quanto emerge dall'incrocio di tutti i dati (scale, note, allegato).

TONO E FORMATTAZIONE:
- Tono: Professionale, rigoroso, empatico, fortemente orientato all'utilità educativa e di supporto.
- Formattazione: Usa il Markdown (titoli, liste, grassetti) per strutturare un referto elegante, chiaro e leggibile.
''';

  void _resetDefaultPrompt() {
    setState(() {
      _promptController.text = _defaultSystemPrompt;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prompt ripristinato al default! (Salva per rendere effettiva la modifica)')),
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

          // 1. Gestione Accessi e Sicurezza
          if (!ApiService.isViewer)
            _buildPremiumExpansionTile(
              context: context,
              title: 'Gestione Accessi e Sicurezza',
              subtitle: 'Gestisci le credenziali di accesso per l\'Admin e per i Viewer',
              icon: Icons.security_rounded,
              iconColor: Colors.blue.shade700,
              initiallyExpanded: true,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Credenziali di Accesso',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      onPressed: _showViewerLogsDialog,
                      icon: const Icon(Icons.list_alt_rounded),
                      label: const Text('Registro Accessi Viewer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE8EEF8),
                        foregroundColor: Colors.black87,
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Configura password robuste per proteggere l\'integrità dei dati.'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _adminPwdController,
                        obscureText: _obscureAdminPwd,
                        decoration: InputDecoration(
                          labelText: 'Password Admin',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.admin_panel_settings),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureAdminPwd ? Icons.visibility : Icons.visibility_off),
                            onPressed: () {
                              setState(() {
                                _obscureAdminPwd = !_obscureAdminPwd;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _viewerPwdController,
                        obscureText: _obscureViewerPwd,
                        decoration: InputDecoration(
                          labelText: 'Password Viewer',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.visibility_outlined),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureViewerPwd ? Icons.visibility : Icons.visibility_off),
                            onPressed: () {
                              setState(() {
                                _obscureViewerPwd = !_obscureViewerPwd;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Switch(
                      value: _viewerEnabled,
                      onChanged: (val) {
                        setState(() {
                          _viewerEnabled = val;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _viewerEnabled ? 'Accesso Viewer Abilitato' : 'Accesso Viewer Disabilitato',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _viewerEnabled ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(0, 56)),
                      onPressed: _isAuthConfigLoading ? null : _saveAuthConfig,
                      icon: _isAuthConfigLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save),
                      label: const Text('Salva Configurazione'),
                    ),
                  ],
                ),
              ],
            ),

          // 2. Protocolli di Supporto
          _buildPremiumExpansionTile(
            context: context,
            title: 'Protocolli di Supporto',
            subtitle: 'Importa le scale di valutazione da file JSON',
            icon: Icons.description_rounded,
            iconColor: Colors.teal.shade600,
            children: [
              const Text('Importa nuovi protocolli clinici o scale di valutazione personalizzate nel sistema.'),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isLoading || ApiService.isViewer ? null : _pickAndUploadJSON,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Carica Protocollo JSON'),
                ),
              ),
              if (_uploadStatus != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_isLoading) const CircularProgressIndicator(),
                    if (_isLoading) const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _uploadStatus!,
                        style: TextStyle(
                          color: _uploadStatus!.contains('Errore') ? Colors.red : Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),

          // 3. Configurazione AI (Gemini)
          _buildPremiumExpansionTile(
            context: context,
            title: 'Configurazione AI (Gemini)',
            subtitle: 'API Key, modelli e prompt personalizzato del consulente IA',
            icon: Icons.psychology_rounded,
            iconColor: Colors.purple.shade700,
            initiallyExpanded: true,
            children: [
              const Text('Configura i parametri di connessione e il comportamento dell\'Intelligenza Artificiale per l\'analisi clinica.'),
              const SizedBox(height: 20),
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
                        DropdownMenuItem(value: 'gemini-1.5-pro', child: Text('Gemini 1.5 Pro')),
                        DropdownMenuItem(value: 'gemini-1.5-flash', child: Text('Gemini 1.5 Flash')),
                        DropdownMenuItem(value: 'gemini-1.5-pro-latest', child: Text('Gemini 1.5 Pro Latest')),
                        DropdownMenuItem(value: 'gemini-2.5-pro', child: Text('Gemini 2.5 Pro (Consigliato)')),
                        DropdownMenuItem(value: 'gemini-2.5-flash', child: Text('Gemini 2.5 Flash')),
                        DropdownMenuItem(value: 'gemini-3.5-flash', child: Text('Gemini 3.5 Flash')),
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
                ],
              ),
              const SizedBox(height: 20),
              
              // Switch permessi IA ai viewer
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Consenti l\'uso dell\'IA ai Viewer', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Abilita le utenze Viewer a lanciare analisi IA consumando l\'API Key dell\'Admin.'),
                value: _viewerAiEnabled,
                activeColor: Colors.purple.shade700,
                onChanged: ApiService.isViewer ? null : (val) {
                  setState(() {
                    _viewerAiEnabled = val;
                  });
                },
              ),
              const SizedBox(height: 20),

              // System Prompt di Gemini
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'System Prompt di Analisi (Consulente IA)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      TextButton.icon(
                        onPressed: ApiService.isViewer ? null : _resetDefaultPrompt,
                        icon: const Icon(Icons.settings_backup_restore, size: 18),
                        label: const Text('Ripristina Default'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.purple.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _promptController,
                    maxLines: 12,
                    minLines: 5,
                    enabled: !ApiService.isViewer,
                    decoration: InputDecoration(
                      hintText: 'Inserisci il prompt di sistema per personalizzare l\'analisi...',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      border: const OutlineInputBorder(),
                      fillColor: const Color(0xFFF8FAFC),
                      filled: true,
                    ),
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(140, 56),
                    ),
                    onPressed: _isLoading || ApiService.isViewer ? null : _saveAIConfig,
                    icon: const Icon(Icons.save),
                    label: const Text('Salva Configurazione AI', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),

          // 4. Parametri di Validità Scale
          Consumer<SettingsNotifier>(
            builder: (context, notifier, child) {
              final settings = notifier.settings;
              return _buildPremiumExpansionTile(
                context: context,
                title: 'Parametri di Validità Scale',
                subtitle: 'Configura la validità temporale delle valutazioni e la soglia di preavviso',
                icon: Icons.calendar_month_rounded,
                iconColor: Colors.orange.shade700,
                children: [
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
              );
            },
          ),

          // 5. Database
          _buildPremiumExpansionTile(
            context: context,
            title: 'Database',
            subtitle: 'Backup, esportazione e ripristino dell\'archivio clinico',
            icon: Icons.storage_rounded,
            iconColor: Colors.indigo.shade700,
            children: [
              const Text('Esporta l\'intero database in formato JSON per conservare un backup offline o ripristinare i dati precedenti.'),
              const SizedBox(height: 20),
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
                    Expanded(
                      child: Text(
                        _dbStatus!,
                        style: TextStyle(
                          color: _dbStatus!.contains('Errore') ? Colors.red : Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumExpansionTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.bottom(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFFE8EEF8), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
            ),
            trailing: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF64748B),
              size: 24,
            ),
            childrenPadding: const EdgeInsets.only(left: 24, right: 24, bottom: 24, top: 8),
            children: children,
          ),
        ),
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
