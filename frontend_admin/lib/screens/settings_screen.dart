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

  // --- Stato Gestione Utenze ---
  List<Map<String, dynamic>> _users = [];
  bool _isUsersLoading = false;

  bool _isLoading = false;
  bool _isExporting = false;
  bool _isImporting = false;
  String? _uploadStatus;
  String? _dbStatus;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (ApiService.isAdmin) _loadUsers();
  }

  String _selectedModel = 'gemini-1.5-pro';

  Future<void> _loadSettings() async {
    final settings = await _apiService.getGeminiSettings();
    final String? key = settings['key'] as String?;
    if (key != null && key.isNotEmpty) {
      _apiKeyController.text = key;
    }
    final String loadedPrompt = (settings['prompt'] as String?) ?? '';
    _promptController.text = loadedPrompt.isNotEmpty ? loadedPrompt : _defaultSystemPrompt;
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

  Future<void> _loadUsers() async {
    setState(() => _isUsersLoading = true);
    final users = await _apiService.getUsers();
    setState(() {
      _users = users;
      _isUsersLoading = false;
    });
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

  // --- GESTIONE UTENTI ---

  void _showUserDialog({Map<String, dynamic>? user}) {
    final isEditing = user != null;
    final isDefault = isEditing && (user['is_default'] == true);
    final usernameCtrl = TextEditingController(text: isEditing ? user['username'] : '');
    final pwdCtrl = TextEditingController();
    final confirmPwdCtrl = TextEditingController();
    String selectedRole = isEditing ? (user['role'] ?? 'viewer') : 'viewer';
    bool aiEnabled = isEditing ? (user['ai_enabled'] ?? false) : false;
    bool obscurePwd = true;
    bool obscureConfirm = true;
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            isEditing ? 'Modifica Operatore' : 'Nuovo Operatore',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (dialogError != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(dialogError!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                        ],
                      ),
                    ),
                  // Campo username
                  TextField(
                    controller: usernameCtrl,
                    enabled: !isDefault,
                    decoration: InputDecoration(
                      labelText: 'Nome Utente${isDefault ? ' (bloccato)' : ' *'}',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      helperText: isDefault ? 'L\'username admin non è modificabile' : 'Min 3 caratteri, nessuno spazio',
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Campo password
                  StatefulBuilder(
                    builder: (_, setObs) => TextField(
                      controller: pwdCtrl,
                      obscureText: obscurePwd,
                      decoration: InputDecoration(
                        labelText: isEditing ? 'Nuova Password (opzionale)' : 'Password *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        helperText: 'Min 4 caratteri',
                        suffixIcon: IconButton(
                          icon: Icon(obscurePwd ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setDialogState(() => obscurePwd = !obscurePwd),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Conferma password
                  TextField(
                    controller: confirmPwdCtrl,
                    obscureText: obscureConfirm,
                    decoration: InputDecoration(
                      labelText: isEditing ? 'Conferma Nuova Password' : 'Conferma Password *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setDialogState(() => obscureConfirm = !obscureConfirm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Ruolo
                  const Text('Profilo (Ruolo)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.admin_panel_settings_rounded, size: 18, color: Colors.indigo),
                              SizedBox(width: 6),
                              Text('Admin'),
                            ],
                          ),
                          value: 'admin',
                          groupValue: selectedRole,
                          onChanged: isDefault ? null : (v) => setDialogState(() => selectedRole = v!),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.visibility_outlined, size: 18, color: Colors.teal),
                              SizedBox(width: 6),
                              Text('Viewer'),
                            ],
                          ),
                          value: 'viewer',
                          groupValue: selectedRole,
                          onChanged: isDefault ? null : (v) => setDialogState(() => selectedRole = v!),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Switch AI
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Row(
                      children: [
                        Icon(Icons.psychology_rounded, size: 18, color: Colors.purple),
                        SizedBox(width: 8),
                        Text('Abilitazione AI', style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    subtitle: const Text('Consenti interrogazioni Gemini AI'),
                    value: aiEnabled,
                    activeColor: Colors.purple,
                    onChanged: (v) => setDialogState(() => aiEnabled = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Validazione
                final uname = usernameCtrl.text.trim();
                if (!isDefault && uname.length < 3) {
                  setDialogState(() => dialogError = 'Username troppo corto (min 3 caratteri)');
                  return;
                }
                if (!isDefault && uname.contains(' ')) {
                  setDialogState(() => dialogError = 'Lo username non può contenere spazi');
                  return;
                }
                if (!isEditing && pwdCtrl.text.length < 4) {
                  setDialogState(() => dialogError = 'Password troppo corta (min 4 caratteri)');
                  return;
                }
                if (pwdCtrl.text.isNotEmpty && pwdCtrl.text != confirmPwdCtrl.text) {
                  setDialogState(() => dialogError = 'Le password non coincidono');
                  return;
                }

                Navigator.pop(ctx);

                bool success;
                if (isEditing) {
                  final data = <String, dynamic>{
                    'role': selectedRole,
                    'ai_enabled': aiEnabled,
                  };
                  if (pwdCtrl.text.isNotEmpty) {
                    data['password'] = pwdCtrl.text;
                    data['confirm_password'] = confirmPwdCtrl.text;
                  }
                  success = await _apiService.updateUser(uname, data);
                } else {
                  success = await _apiService.createUser({
                    'username': uname,
                    'password': pwdCtrl.text,
                    'confirm_password': confirmPwdCtrl.text,
                    'role': selectedRole,
                    'ai_enabled': aiEnabled,
                  });
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(success
                        ? (isEditing ? 'Operatore aggiornato!' : 'Operatore creato!')
                        : 'Errore durante l\'operazione.'),
                    backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
                  ));
                  if (success) _loadUsers();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
              child: Text(isEditing ? 'Salva Modifiche' : 'Crea Operatore'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUserConfirm(String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferma Eliminazione', style: TextStyle(fontWeight: FontWeight.bold)),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black87, fontSize: 14),
            children: [
              const TextSpan(text: 'Stai per eliminare l\'operatore '),
              TextSpan(text: username, style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: '. Questa azione è irreversibile.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _apiService.deleteUser(username);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success ? 'Operatore eliminato.' : 'Errore durante l\'eliminazione.'),
          backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
        ));
        if (success) _loadUsers();
      }
    }
  }

  // --- Sezione Utenti UI ---
  Widget _buildUserManagementSection() {
    return _buildPremiumExpansionTile(
      context: context,
      title: 'Gestione Utenze e Sicurezza',
      subtitle: 'Crea, modifica ed elimina gli operatori del sistema',
      icon: Icons.manage_accounts_rounded,
      iconColor: Colors.blue.shade700,
      initiallyExpanded: false,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Operatori del Sistema', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _showViewerLogsDialog,
                  icon: const Icon(Icons.list_alt_rounded, size: 16),
                  label: const Text('Log Accessi'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8EEF8),
                    foregroundColor: Colors.black87,
                    elevation: 0,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showUserDialog(),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Nuovo Operatore'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isUsersLoading)
          const Center(child: CircularProgressIndicator())
        else if (_users.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8EEF8)),
            ),
            child: const Center(child: Text('Nessun operatore trovato.', style: TextStyle(color: Color(0xFF64748B)))),
          )
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE8EEF8)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(2.5),
                  1: FlexColumnWidth(1.8),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1.5),
                  4: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFE8EEF8)),
                    children: [
                      _tableHeader('Username'),
                      _tableHeader('Ruolo'),
                      _tableHeader('AI'),
                      _tableHeader('Creato il'),
                      _tableHeader('Azioni'),
                    ],
                  ),
                  ..._users.map((u) {
                    final username = u['username'] as String? ?? '';
                    final role = u['role'] as String? ?? 'viewer';
                    final aiEn = u['ai_enabled'] as bool? ?? false;
                    final isDefault = u['is_default'] as bool? ?? false;
                    final createdAt = u['created_at'] as String?;
                    final dt = createdAt != null ? DateTime.tryParse(createdAt) : null;
                    final dateStr = dt != null ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}' : '-';

                    return TableRow(
                      decoration: BoxDecoration(
                        color: _users.indexOf(u) % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
                      ),
                      children: [
                        _tableCell(Row(
                          children: [
                            Text(username, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (isDefault) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Utente di sistema (non eliminabile)',
                                child: Icon(Icons.lock_rounded, size: 14, color: Colors.grey.shade500),
                              ),
                            ],
                          ],
                        )),
                        _tableCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: role == 'admin' ? Colors.indigo.shade50 : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: role == 'admin' ? Colors.indigo.shade200 : Colors.teal.shade200,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                role == 'admin' ? Icons.admin_panel_settings_rounded : Icons.visibility_outlined,
                                size: 13,
                                color: role == 'admin' ? Colors.indigo.shade700 : Colors.teal.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                role == 'admin' ? 'Admin' : 'Viewer',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: role == 'admin' ? Colors.indigo.shade700 : Colors.teal.shade700,
                                ),
                              ),
                            ],
                          ),
                        )),
                        _tableCell(Icon(
                          aiEn ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: aiEn ? Colors.green.shade600 : Colors.grey.shade400,
                          size: 20,
                        )),
                        _tableCell(Text(dateStr, style: const TextStyle(fontSize: 13))),
                        _tableCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Modifica',
                              icon: Icon(Icons.edit_rounded, size: 18, color: Colors.blue.shade700),
                              onPressed: () => _showUserDialog(user: u),
                            ),
                            IconButton(
                              tooltip: isDefault ? 'Non eliminabile' : 'Elimina',
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: isDefault ? Colors.grey.shade300 : Colors.red.shade400,
                              ),
                              onPressed: isDefault ? null : () => _deleteUserConfirm(username),
                            ),
                          ],
                        )),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          '🔒 L\'utente "admin" non può essere eliminato né rinominato — è l\'account di sistema.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
    );
  }

  Widget _tableCell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: child,
    );
  }


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
            initiallyExpanded: false,
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
              
              // Switch permessi IA ai viewer (ora per-utente)
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.purple.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: Colors.purple.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'L\'abilitazione AI è ora gestita per singolo operatore nella sezione "Gestione Utenze".',
                        style: TextStyle(fontSize: 13, color: Colors.purple.shade700),
                      ),
                    ),
                  ],
                ),
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
                    title: 'Validità Scala SIS',
                    value: settings.validityMonthsSIS.toDouble(),
                    min: 1,
                    max: 24,
                    unit: 'mesi',
                    icon: Icons.calendar_today_rounded,
                    onChanged: (val) {
                      notifier.updateSettings(validityMonthsSIS: val.toInt());
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
      margin: const EdgeInsets.only(bottom: 20),
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
