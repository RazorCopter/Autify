// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../services/settings_notifier.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import 'license_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _apiService = ApiService();

  // --- Stato Gestione Utenze ---
  List<Map<String, dynamic>> _users = [];
  bool _isUsersLoading = false;

  bool _isLoading = false;
  bool _isExporting = false;
  bool _isImporting = false;
  String? _uploadStatus;
  String? _dbStatus;

  // --- Stato Configurazione IA Cline-Style ---
  String _activeProvider = 'gemini'; // 'gemini' | 'openai' | 'openai_compatible'

  // Gemini
  bool _geminiKeyConfigured = false;
  String? _geminiKeyHint;
  final TextEditingController _geminiKeyController = TextEditingController();
  String _geminiSelectedModel = 'gemini-2.5-pro';
  final TextEditingController _geminiCustomModelController = TextEditingController();
  bool _geminiIsCustom = false;

  // OpenAI
  bool _openaiKeyConfigured = false;
  String? _openaiKeyHint;
  final TextEditingController _openaiKeyController = TextEditingController();
  String _openaiSelectedModel = 'gpt-4o';
  final TextEditingController _openaiCustomModelController = TextEditingController();
  bool _openaiIsCustom = false;
  String _openaiProtocol = 'chat_completions';

  // OpenAI-Compatible (OmniRoute / vLLM / Ollama)
  final TextEditingController _compatBaseUrlController = TextEditingController();
  bool _compatKeyConfigured = false;
  String? _compatKeyHint;
  final TextEditingController _compatKeyController = TextEditingController();
  final TextEditingController _compatModelController = TextEditingController();
  String _compatProtocol = 'chat_completions';
  final List<MapEntry<TextEditingController, TextEditingController>> _compatHeaderControllers = [];
  List<String> _discoveredCompatModels = [];
  bool _isDiscoveringModels = false;
  bool _compatManualModel = false;

  // Parametri Generazione
  double? _temperature;
  double? _topP;
  int _maxOutputTokens = 4096;
  String? _reasoningEffort;

  // Parametri Rete
  int _timeoutSeconds = 60;
  int _maxRetries = 2;

  // System Prompt
  final TextEditingController _promptController = TextEditingController();

  // Test Connessione & Salvataggio
  bool _isTestingConnection = false;
  Map<String, dynamic>? _testConnectionResult;
  bool _isSavingAI = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (ApiService.isAdmin) _loadUsers();
  }

  Future<void> _loadSettings() async {
    final aiSettings = await _apiService.getAiSettings();
    if (aiSettings != null) {
      _activeProvider = (aiSettings['active_provider'] as String?) ?? 'gemini';

      final gen = aiSettings['generation'] as Map<String, dynamic>?;
      if (gen != null) {
        _temperature = (gen['temperature'] as num?)?.toDouble();
        _topP = (gen['top_p'] as num?)?.toDouble();
        _maxOutputTokens = (gen['max_output_tokens'] as int?) ?? 4096;
        _reasoningEffort = gen['reasoning_effort'] as String?;
      }

      final net = aiSettings['network'] as Map<String, dynamic>?;
      if (net != null) {
        _timeoutSeconds = (net['timeout_seconds'] as int?) ?? 60;
        _maxRetries = (net['max_retries'] as int?) ?? 2;
      }

      final prompt = aiSettings['system_prompt'] as String?;
      _promptController.text = (prompt != null && prompt.isNotEmpty) ? prompt : _defaultSystemPrompt;

      // Gemini
      final gem = aiSettings['gemini'] as Map<String, dynamic>?;
      if (gem != null) {
        final keyStatus = gem['api_key'] as Map<String, dynamic>?;
        _geminiKeyConfigured = keyStatus?['configured'] == true;
        _geminiKeyHint = keyStatus?['hint'] as String?;
        final m = gem['model'] as String? ?? 'gemini-2.5-pro';
        if (['gemini-2.5-pro', 'gemini-2.5-flash', 'gemini-1.5-pro', 'gemini-1.5-flash'].contains(m)) {
          _geminiSelectedModel = m;
          _geminiIsCustom = false;
        } else {
          _geminiSelectedModel = 'custom';
          _geminiCustomModelController.text = m;
          _geminiIsCustom = true;
        }
      }

      // OpenAI
      final oai = aiSettings['openai'] as Map<String, dynamic>?;
      if (oai != null) {
        final keyStatus = oai['api_key'] as Map<String, dynamic>?;
        _openaiKeyConfigured = keyStatus?['configured'] == true;
        _openaiKeyHint = keyStatus?['hint'] as String?;
        _openaiProtocol = (oai['protocol'] as String?) ?? 'chat_completions';
        final m = oai['model'] as String? ?? 'gpt-4o';
        if (['gpt-4o', 'gpt-4o-mini', 'o3-mini', 'gpt-5'].contains(m)) {
          _openaiSelectedModel = m;
          _openaiIsCustom = false;
        } else {
          _openaiSelectedModel = 'custom';
          _openaiCustomModelController.text = m;
          _openaiIsCustom = true;
        }
      }

      // OpenAI-Compatible
      final oac = aiSettings['openai_compatible'] as Map<String, dynamic>?;
      if (oac != null) {
        final keyStatus = oac['api_key'] as Map<String, dynamic>?;
        _compatKeyConfigured = keyStatus?['configured'] == true;
        _compatKeyHint = keyStatus?['hint'] as String?;
        _compatBaseUrlController.text = (oac['base_url'] as String?) ?? '';
        _compatModelController.text = (oac['model'] as String?) ?? '';
        _compatProtocol = (oac['protocol'] as String?) ?? 'chat_completions';
        final headers = oac['custom_headers'] as Map<String, dynamic>? ?? {};
        _compatHeaderControllers.clear();
        headers.forEach((k, v) {
          _compatHeaderControllers.add(MapEntry(
            TextEditingController(text: k),
            TextEditingController(text: v.toString()),
          ));
        });
      }
      setState(() {});
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _isUsersLoading = true);
    final users = await _apiService.getUsers();
    setState(() {
      _users = users;
      _isUsersLoading = false;
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
          _uploadStatus =
              'Errore durante il caricamento o formato non ancora supportato.';
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
      final dataUrl = 'data:application/octet-stream;base64,$b64';
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-')
          .substring(0, 19);
      html.AnchorElement(href: dataUrl)
        ..setAttribute('download', 'autify_backup_$timestamp.enc')
        ..click();
      setState(() => _dbStatus = 'Backup esportato con successo!');
    } else {
      setState(() => _dbStatus = 'Errore durante l\'esportazione.');
    }
  }

  Future<void> _importDatabase() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'enc'],
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
          _dbStatus =
              'Errore durante l\'importazione. Verifica il formato del file.';
        }
      });
    }
  }

  Future<void> _clearAIKey(String provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conferma Rimozione Chiave'),
        content: Text('Vuoi rimuovere la chiave API salvata per il provider $provider?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final patch = <String, dynamic>{
        provider: {'clear_api_key': true}
      };
      final success = await _apiService.patchAiSettings(patch);
      if (success) {
        await _loadSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chiave API rimossa con successo!'), backgroundColor: Colors.teal),
          );
        }
      }
    }
  }

  Future<void> _testAIConnection() async {
    setState(() {
      _isTestingConnection = true;
      _testConnectionResult = null;
    });

    final payload = <String, dynamic>{
      'provider': _activeProvider,
    };

    if (_activeProvider == 'gemini') {
      payload['model'] = _geminiIsCustom ? _geminiCustomModelController.text.trim() : _geminiSelectedModel;
      if (_geminiKeyController.text.trim().isNotEmpty) {
        payload['api_key'] = _geminiKeyController.text.trim();
      }
    } else if (_activeProvider == 'openai') {
      payload['model'] = _openaiIsCustom ? _openaiCustomModelController.text.trim() : _openaiSelectedModel;
      payload['protocol'] = _openaiProtocol;
      if (_openaiKeyController.text.trim().isNotEmpty) {
        payload['api_key'] = _openaiKeyController.text.trim();
      }
    } else if (_activeProvider == 'openai_compatible') {
      payload['base_url'] = _compatBaseUrlController.text.trim();
      payload['model'] = _compatModelController.text.trim();
      payload['protocol'] = _compatProtocol;
      if (_compatKeyController.text.trim().isNotEmpty) {
        payload['api_key'] = _compatKeyController.text.trim();
      }
      final headers = <String, String>{};
      for (final entry in _compatHeaderControllers) {
        final k = entry.key.text.trim();
        final v = entry.value.text.trim();
        if (k.isNotEmpty) headers[k] = v;
      }
      payload['custom_headers'] = headers;
    }

    final res = await _apiService.testAiConnection(payload);
    setState(() {
      _isTestingConnection = false;
      _testConnectionResult = res;
    });
  }

  Future<void> _discoverModels() async {
    setState(() {
      _isDiscoveringModels = true;
    });
    try {
      final headers = <String, String>{};
      for (final entry in _compatHeaderControllers) {
        final k = entry.key.text.trim();
        final v = entry.value.text.trim();
        if (k.isNotEmpty && v.isNotEmpty) {
          headers[k] = v;
        }
      }
      final models = await _apiService.discoverCompatibleModels(
        providerBaseUrl: _compatBaseUrlController.text.trim().isNotEmpty ? _compatBaseUrlController.text.trim() : null,
        apiKey: _compatKeyController.text.trim().isNotEmpty ? _compatKeyController.text.trim() : null,
        customHeaders: headers.isNotEmpty ? headers : null,
      );
      setState(() {
        _discoveredCompatModels = models;
        if (models.isNotEmpty) {
          _compatManualModel = false;
          if (!_discoveredCompatModels.contains(_compatModelController.text.trim())) {
            _compatModelController.text = models.first;
          }
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trovati ${models.length} modelli disponibili dal gateway.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore scoperta modelli: ${e.toString().replaceAll("Exception: ", "")}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDiscoveringModels = false;
        });
      }
    }
  }

  Future<void> _saveAIConfig() async {
    setState(() => _isSavingAI = true);

    final patch = <String, dynamic>{
      'active_provider': _activeProvider,
      'system_prompt': _promptController.text.trim().isEmpty ? null : _promptController.text.trim(),
      'generation': {
        'temperature': _temperature,
        'top_p': _topP,
        'max_output_tokens': _maxOutputTokens,
        'reasoning_effort': _reasoningEffort,
      },
      'network': {
        'timeout_seconds': _timeoutSeconds,
        'max_retries': _maxRetries,
      },
    };

    if (_activeProvider == 'gemini') {
      final gemPatch = <String, dynamic>{
        'model': _geminiIsCustom ? _geminiCustomModelController.text.trim() : _geminiSelectedModel,
      };
      if (_geminiKeyController.text.trim().isNotEmpty) {
        gemPatch['api_key'] = _geminiKeyController.text.trim();
      }
      patch['gemini'] = gemPatch;
    } else if (_activeProvider == 'openai') {
      final oaiPatch = <String, dynamic>{
        'model': _openaiIsCustom ? _openaiCustomModelController.text.trim() : _openaiSelectedModel,
        'protocol': _openaiProtocol,
      };
      if (_openaiKeyController.text.trim().isNotEmpty) {
        oaiPatch['api_key'] = _openaiKeyController.text.trim();
      }
      patch['openai'] = oaiPatch;
    } else if (_activeProvider == 'openai_compatible') {
      final headers = <String, String>{};
      for (final entry in _compatHeaderControllers) {
        final k = entry.key.text.trim();
        final v = entry.value.text.trim();
        if (k.isNotEmpty) headers[k] = v;
      }
      final oacPatch = <String, dynamic>{
        'base_url': _compatBaseUrlController.text.trim(),
        'model': _compatModelController.text.trim(),
        'protocol': _compatProtocol,
        'custom_headers': headers,
      };
      if (_compatKeyController.text.trim().isNotEmpty) {
        oacPatch['api_key'] = _compatKeyController.text.trim();
      }
      patch['openai_compatible'] = oacPatch;
    }

    final success = await _apiService.patchAiSettings(patch);
    setState(() => _isSavingAI = false);

    if (success) {
      _geminiKeyController.clear();
      _openaiKeyController.clear();
      _compatKeyController.clear();
      await _loadSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configurazione IA salvata con successo!'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Errore durante il salvataggio della configurazione IA.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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
        const SnackBar(
            content: Text(
                'Prompt ripristinato al default! (Salva per rendere effettiva la modifica)')),
      );
    }
  }

  // --- GESTIONE UTENTI ---

  void _showUserDialog({Map<String, dynamic>? user}) {
    final isEditing = user != null;
    final isDefault = isEditing && (user['is_default'] == true);
    final usernameCtrl =
        TextEditingController(text: isEditing ? user['username'] : '');
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
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(dialogError!,
                                  style: const TextStyle(
                                      color: Colors.red, fontSize: 13))),
                        ],
                      ),
                    ),
                  // Campo username
                  TextField(
                    controller: usernameCtrl,
                    enabled: !isDefault,
                    decoration: InputDecoration(
                      labelText:
                          'Nome Utente${isDefault ? ' (bloccato)' : ' *'}',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      helperText: isDefault
                          ? 'L\'username admin non è modificabile'
                          : 'Min 3 caratteri, nessuno spazio',
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Campo password
                  StatefulBuilder(
                    builder: (_, setObs) => TextField(
                      controller: pwdCtrl,
                      obscureText: obscurePwd,
                      decoration: InputDecoration(
                        labelText: isEditing
                            ? 'Nuova Password (opzionale)'
                            : 'Password *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        helperText: 'Min 4 caratteri',
                        suffixIcon: IconButton(
                          icon: Icon(obscurePwd
                              ? Icons.visibility
                              : Icons.visibility_off),
                          onPressed: () =>
                              setDialogState(() => obscurePwd = !obscurePwd),
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
                      labelText: isEditing
                          ? 'Conferma Nuova Password'
                          : 'Conferma Password *',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setDialogState(
                            () => obscureConfirm = !obscureConfirm),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Ruolo
                  const Text('Profilo (Ruolo)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.admin_panel_settings_rounded,
                                  size: 18, color: Colors.indigo),
                              SizedBox(width: 6),
                              Text('Admin'),
                            ],
                          ),
                          value: 'admin',
                          groupValue: selectedRole,
                          onChanged: isDefault
                              ? null
                              : (v) => setDialogState(() => selectedRole = v!),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Row(
                            children: [
                              Icon(Icons.visibility_outlined,
                                  size: 18, color: Colors.teal),
                              SizedBox(width: 6),
                              Text('Viewer'),
                            ],
                          ),
                          value: 'viewer',
                          groupValue: selectedRole,
                          onChanged: isDefault
                              ? null
                              : (v) => setDialogState(() => selectedRole = v!),
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
                        Icon(Icons.psychology_rounded,
                            size: 18, color: Colors.purple),
                        SizedBox(width: 8),
                        Text('Abilitazione AI',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    subtitle: const Text('Consenti interrogazioni Gemini AI'),
                    value: aiEnabled,
                    activeThumbColor: Colors.purple,
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
                  setDialogState(() =>
                      dialogError = 'Username troppo corto (min 3 caratteri)');
                  return;
                }
                if (!isDefault && uname.contains(' ')) {
                  setDialogState(() =>
                      dialogError = 'Lo username non può contenere spazi');
                  return;
                }
                if (!isEditing && pwdCtrl.text.length < 4) {
                  setDialogState(() =>
                      dialogError = 'Password troppo corta (min 4 caratteri)');
                  return;
                }
                if (pwdCtrl.text.isNotEmpty &&
                    pwdCtrl.text != confirmPwdCtrl.text) {
                  setDialogState(
                      () => dialogError = 'Le password non coincidono');
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
                        ? (isEditing
                            ? 'Operatore aggiornato!'
                            : 'Operatore creato!')
                        : 'Errore durante l\'operazione.'),
                    backgroundColor:
                        success ? Colors.green.shade700 : Colors.red.shade700,
                  ));
                  if (success) _loadUsers();
                }
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white),
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
        title: const Text('Conferma Eliminazione',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(color: Colors.black87, fontSize: 14),
            children: [
              const TextSpan(text: 'Stai per eliminare l\'operatore '),
              TextSpan(
                  text: username,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: '. Questa azione è irreversibile.'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _apiService.deleteUser(username);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? 'Operatore eliminato.'
              : 'Errore durante l\'eliminazione.'),
          backgroundColor:
              success ? Colors.green.shade700 : Colors.red.shade700,
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
            const Text('Operatori del Sistema',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Row(
              children: [
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
            child: const Center(
                child: Text('Nessun operatore trovato.',
                    style: TextStyle(color: Color(0xFF64748B)))),
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
                    final dt =
                        createdAt != null ? DateTime.tryParse(createdAt) : null;
                    final dateStr = dt != null
                        ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
                        : '-';

                    return TableRow(
                      decoration: BoxDecoration(
                        color: _users.indexOf(u) % 2 == 0
                            ? Colors.white
                            : const Color(0xFFF8FAFC),
                      ),
                      children: [
                        _tableCell(Row(
                          children: [
                            Text(username,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            if (isDefault) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: 'Utente di sistema (non eliminabile)',
                                child: Icon(Icons.lock_rounded,
                                    size: 14, color: Colors.grey.shade500),
                              ),
                            ],
                          ],
                        )),
                        _tableCell(Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: role == 'admin'
                                ? Colors.indigo.shade50
                                : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: role == 'admin'
                                  ? Colors.indigo.shade200
                                  : Colors.teal.shade200,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                role == 'admin'
                                    ? Icons.admin_panel_settings_rounded
                                    : Icons.visibility_outlined,
                                size: 13,
                                color: role == 'admin'
                                    ? Colors.indigo.shade700
                                    : Colors.teal.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                role == 'admin' ? 'Admin' : 'Viewer',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: role == 'admin'
                                      ? Colors.indigo.shade700
                                      : Colors.teal.shade700,
                                ),
                              ),
                            ],
                          ),
                        )),
                        _tableCell(Icon(
                          aiEn
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: aiEn
                              ? Colors.green.shade600
                              : Colors.grey.shade400,
                          size: 20,
                        )),
                        _tableCell(Text(dateStr,
                            style: const TextStyle(fontSize: 13))),
                        _tableCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Modifica',
                              icon: Icon(Icons.edit_rounded,
                                  size: 18, color: Colors.blue.shade700),
                              onPressed: () => _showUserDialog(user: u),
                            ),
                            IconButton(
                              tooltip:
                                  isDefault ? 'Non eliminabile' : 'Elimina',
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: isDefault
                                    ? Colors.grey.shade300
                                    : Colors.red.shade400,
                              ),
                              onPressed: isDefault
                                  ? null
                                  : () => _deleteUserConfirm(username),
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
          style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Color(0xFF334155))),
    );
  }

  Widget _tableCell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Impostazioni di Sistema',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),

          if (ApiService.isAdmin) _buildUserManagementSection(),
          if (ApiService.isAdmin) const SizedBox(height: 32),

          _buildPremiumExpansionTile(
            context: context,
            title: 'Licenza Autify',
            subtitle: 'Stato, validazione e attivazione del prodotto',
            icon: Icons.vpn_key_outlined,
            iconColor: Colors.green.shade700,
            children: [
              const Text(
                  'Controlla la scadenza del trial o gestisci la licenza commerciale associata a questa installazione.'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('Gestisci licenza'),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            LicenseScreen(isViewer: ApiService.isViewer))),
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
              const Text(
                  'Importa nuovi protocolli clinici o scale di valutazione personalizzate nel sistema.'),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isLoading || ApiService.isViewer
                      ? null
                      : _pickAndUploadJSON,
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
                          color: _uploadStatus!.contains('Errore')
                              ? Colors.red
                              : Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),

          // 3. Configurazione AI Multi-Provider
          _buildAIConfigurationSection(context),



          Consumer<SettingsNotifier>(
            builder: (context, notifier, child) {
              return _buildPremiumExpansionTile(
                context: context,
                title: 'Esperienza Autify',
                subtitle: 'Scegli l’interfaccia della dashboard',
                icon: Icons.auto_awesome_rounded,
                iconColor: const Color(0xFF635BFF),
                initiallyExpanded: true,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        const Flexible(
                          child: Text(
                            'Nuova interfaccia Autify 4.0',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF635BFF)
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'NOVITÀ',
                            style: TextStyle(
                              color: Color(0xFF5145CD),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Attiva la nuova esperienza grafica con dashboard moderna, grafici interattivi ed effetti visivi avanzati.',
                      ),
                    ),
                    value: notifier.dashboardV4Enabled,
                    activeThumbColor: const Color(0xFF635BFF),
                    onChanged: notifier.initialized
                        ? (enabled) async {
                            try {
                              await notifier.setDashboardV4Enabled(enabled);
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Impossibile salvare la preferenza. La selezione precedente è stata ripristinata.',
                                  ),
                                ),
                              );
                            }
                          }
                        : null,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),


          // 4. Parametri di Validità Scale
          Consumer<SettingsNotifier>(
            builder: (context, notifier, child) {
              final settings = notifier.settings;
              return _buildPremiumExpansionTile(
                context: context,
                title: 'Parametri di Validità Scale',
                subtitle:
                    'Configura la validità temporale delle valutazioni e la soglia di preavviso',
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
                      notifier.updateSettings(
                          validityMonthsSanMartin: val.toInt());
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
            subtitle:
                'Backup, esportazione e ripristino dell\'archivio clinico',
            icon: Icons.storage_rounded,
            iconColor: Colors.indigo.shade700,
            children: [
              const Text(
                  'Esporta l\'intero database in un file di backup criptato (.enc). Per motivi di sicurezza, il file è cifrato con la chiave di questa installazione e potrà essere ripristinato solo su questa specifica istanza di Autify (o su una configurata con la medesima chiave segreta).'),
              const SizedBox(height: 20),
              Row(
                children: [
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isExporting || _isImporting || ApiService.isViewer
                              ? null
                              : _exportDatabase,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded),
                      label: Text(_isExporting
                          ? 'Esportazione...'
                          : 'Esporta Database'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isExporting || _isImporting || ApiService.isViewer
                              ? null
                              : _importDatabase,
                      icon: _isImporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file),
                      label: Text(_isImporting
                          ? 'Importazione...'
                          : 'Importa Database'),
                    ),
                  ),
                ],
              ),
              if (_dbStatus != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_isImporting || _isExporting)
                      const CircularProgressIndicator(),
                    if (_isImporting || _isExporting) const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _dbStatus!,
                        style: TextStyle(
                          color: _dbStatus!.contains('Errore')
                              ? Colors.red
                              : Colors.green,
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
            childrenPadding: EdgeInsets.only(
                left: ResponsiveHelper.isMobile(context) ? 12 : 24,
                right: ResponsiveHelper.isMobile(context) ? 12 : 24,
                bottom: 24,
                top: 8),
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
    final isMobile = ResponsiveHelper.isMobile(context);

    Widget sliderContent = Row(
      children: [
        Text('${min.toInt()}',
            style: const TextStyle(color: Color(0xFF718096), fontSize: 12)),
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
        Text('${max.toInt()}',
            style: const TextStyle(color: Color(0xFF718096), fontSize: 12)),
      ],
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF64B5F6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF64B5F6), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Valore attuale: ${value.toInt()} $unit',
                      style: const TextStyle(
                          color: Color(0xFF718096), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          sliderContent,
        ],
      );
    }

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
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
          child: sliderContent,
        ),
      ],
    );
  }

  Widget _buildAIStatusBadge(bool configured, String? hint, String provider) {
    if (configured) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 16),
            const SizedBox(width: 6),
            Text(
              hint != null ? 'Chiave attiva ($hint)' : 'Chiave attiva nel server',
              style: TextStyle(color: Colors.green.shade800, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: ApiService.isViewer ? null : () => _clearAIKey(provider),
              child: Tooltip(
                message: 'Rimuovi chiave salvata',
                child: Icon(Icons.close_rounded, color: Colors.green.shade800, size: 16),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800, size: 16),
          const SizedBox(width: 6),
          Text(
            'Nessuna chiave configurata',
            style: TextStyle(color: Colors.amber.shade900, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 16),
                SizedBox(width: 6),
                Text('Google Gemini'),
              ],
            ),
            selected: _activeProvider == 'gemini',
            selectedColor: Colors.purple.shade700,
            labelStyle: TextStyle(
              color: _activeProvider == 'gemini' ? Colors.white : const Color(0xFF334155),
              fontWeight: FontWeight.bold,
            ),
            onSelected: ApiService.isViewer ? null : (sel) {
              if (sel) setState(() => _activeProvider = 'gemini');
            },
          ),
          ChoiceChip(
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, size: 16),
                SizedBox(width: 6),
                Text('OpenAI (Ufficiale)'),
              ],
            ),
            selected: _activeProvider == 'openai',
            selectedColor: Colors.purple.shade700,
            labelStyle: TextStyle(
              color: _activeProvider == 'openai' ? Colors.white : const Color(0xFF334155),
              fontWeight: FontWeight.bold,
            ),
            onSelected: ApiService.isViewer ? null : (sel) {
              if (sel) setState(() => _activeProvider = 'openai');
            },
          ),
          ChoiceChip(
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.alt_route_rounded, size: 16),
                SizedBox(width: 6),
                Text('OpenAI-Compatible (OmniRoute / vLLM)'),
              ],
            ),
            selected: _activeProvider == 'openai_compatible',
            selectedColor: Colors.purple.shade700,
            labelStyle: TextStyle(
              color: _activeProvider == 'openai_compatible' ? Colors.white : const Color(0xFF334155),
              fontWeight: FontWeight.bold,
            ),
            onSelected: ApiService.isViewer ? null : (sel) {
              if (sel) setState(() => _activeProvider = 'openai_compatible');
            },
          ),
        ],
      ),
    );
  }
  Widget _buildGeminiCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.purple.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Configurazione Google Gemini',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                _buildAIStatusBadge(_geminiKeyConfigured, _geminiKeyHint, 'gemini'),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _geminiKeyController,
              obscureText: true,
              enabled: !ApiService.isViewer,
              decoration: const InputDecoration(
                labelText: 'Nuova Gemini API Key',
                hintText: 'Lascia vuoto per mantenere la chiave attuale',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _geminiIsCustom ? 'custom' : _geminiSelectedModel,
              decoration: const InputDecoration(
                labelText: 'Modello Gemini',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.psychology),
              ),
              items: const [
                DropdownMenuItem(value: 'gemini-2.5-pro', child: Text('Gemini 2.5 Pro (Consigliato)')),
                DropdownMenuItem(value: 'gemini-2.5-flash', child: Text('Gemini 2.5 Flash (Ultra rapido)')),
                DropdownMenuItem(value: 'gemini-1.5-pro', child: Text('Gemini 1.5 Pro')),
                DropdownMenuItem(value: 'gemini-1.5-flash', child: Text('Gemini 1.5 Flash')),
                DropdownMenuItem(value: 'custom', child: Text('Modello Personalizzato...')),
              ],
              onChanged: ApiService.isViewer ? null : (val) {
                if (val != null) {
                  setState(() {
                    if (val == 'custom') {
                      _geminiIsCustom = true;
                    } else {
                      _geminiIsCustom = false;
                      _geminiSelectedModel = val;
                    }
                  });
                }
              },
            ),
            if (_geminiIsCustom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _geminiCustomModelController,
                enabled: !ApiService.isViewer,
                decoration: const InputDecoration(
                  labelText: 'Model ID Personalizzato (es. gemini-2.5-flash-latest)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit_note),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOpenAICard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.purple.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Configurazione OpenAI (Nativo)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                _buildAIStatusBadge(_openaiKeyConfigured, _openaiKeyHint, 'openai'),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _openaiKeyController,
              obscureText: true,
              enabled: !ApiService.isViewer,
              decoration: const InputDecoration(
                labelText: 'Nuova OpenAI API Key',
                hintText: 'Lascia vuoto per mantenere la chiave attuale',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _openaiIsCustom ? 'custom' : _openaiSelectedModel,
                    decoration: const InputDecoration(
                      labelText: 'Modello OpenAI',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.psychology),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'gpt-4o', child: Text('GPT-4o (Consigliato)')),
                      DropdownMenuItem(value: 'gpt-4o-mini', child: Text('GPT-4o Mini (Economico)')),
                      DropdownMenuItem(value: 'o3-mini', child: Text('o3-mini (Ragionamento)')),
                      DropdownMenuItem(value: 'gpt-5', child: Text('GPT-5')),
                      DropdownMenuItem(value: 'custom', child: Text('Modello Personalizzato...')),
                    ],
                    onChanged: ApiService.isViewer ? null : (val) {
                      if (val != null) {
                        setState(() {
                          if (val == 'custom') {
                            _openaiIsCustom = true;
                          } else {
                            _openaiIsCustom = false;
                            _openaiSelectedModel = val;
                          }
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: _openaiProtocol,
                    decoration: const InputDecoration(
                      labelText: 'Protocollo API',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'chat_completions', child: Text('Chat Completions')),
                      DropdownMenuItem(value: 'responses', child: Text('Responses API')),
                    ],
                    onChanged: ApiService.isViewer ? null : (val) {
                      if (val != null) setState(() => _openaiProtocol = val);
                    },
                  ),
                ),
              ],
            ),
            if (_openaiIsCustom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _openaiCustomModelController,
                enabled: !ApiService.isViewer,
                decoration: const InputDecoration(
                  labelText: 'Model ID Personalizzato (es. gpt-4-turbo)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.edit_note),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCompatCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.purple.shade100),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Gateway OpenAI-Compatible (OmniRoute / vLLM)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                _buildAIStatusBadge(_compatKeyConfigured, _compatKeyHint, 'openai_compatible'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _compatBaseUrlController,
                    enabled: !ApiService.isViewer,
                    decoration: const InputDecoration(
                      labelText: 'Base URL',
                      hintText: 'https://api.openai.com/v1 o endpoint gateway',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: _compatProtocol,
                    decoration: const InputDecoration(
                      labelText: 'Protocollo',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'chat_completions', child: Text('Chat Completions')),
                      DropdownMenuItem(value: 'responses', child: Text('Responses API')),
                    ],
                    onChanged: ApiService.isViewer ? null : (val) {
                      if (val != null) setState(() => _compatProtocol = val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_discoveredCompatModels.isNotEmpty && !_compatManualModel) ...[
                        DropdownButtonFormField<String>(
                          value: _discoveredCompatModels.contains(_compatModelController.text.trim())
                              ? _compatModelController.text.trim()
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Seleziona Modello',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.psychology),
                          ),
                          items: [
                            ..._discoveredCompatModels.map((m) => DropdownMenuItem(value: m, child: Text(m))),
                            const DropdownMenuItem(value: '__custom__', child: Text('Altro / Inserisci manualmente...')),
                          ],
                          onChanged: ApiService.isViewer ? null : (val) {
                            if (val == '__custom__') {
                              setState(() => _compatManualModel = true);
                            } else if (val != null) {
                              setState(() => _compatModelController.text = val);
                            }
                          },
                        ),
                      ] else ...[
                        TextField(
                          controller: _compatModelController,
                          enabled: !ApiService.isViewer,
                          decoration: InputDecoration(
                            labelText: 'Model ID',
                            hintText: 'es. gpt-4o, llama3, qwen-2.5',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.psychology),
                            suffixIcon: _discoveredCompatModels.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.list),
                                    tooltip: 'Torna alla lista modelli rilevati',
                                    onPressed: () => setState(() => _compatManualModel = false),
                                  )
                                : null,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _isDiscoveringModels || ApiService.isViewer ? null : _discoverModels,
                          icon: _isDiscoveringModels
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.explore, size: 16),
                          label: Text(_isDiscoveringModels ? 'Ricerca modelli in corso...' : 'Cerca Modelli (GET /models)'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _compatKeyController,
                    obscureText: true,
                    enabled: !ApiService.isViewer,
                    decoration: const InputDecoration(
                      labelText: 'API Key (Opzionale)',
                      hintText: 'Lascia vuoto per preservare',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.key),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Custom HTTP Headers', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const Spacer(),
                TextButton.icon(
                  onPressed: ApiService.isViewer ? null : () {
                    setState(() {
                      _compatHeaderControllers.add(MapEntry(TextEditingController(), TextEditingController()));
                    });
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Aggiungi Header'),
                ),
              ],
            ),
            if (_compatHeaderControllers.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._compatHeaderControllers.asMap().entries.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: item.value.key,
                        enabled: !ApiService.isViewer,
                        decoration: const InputDecoration(labelText: 'Header', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: item.value.value,
                        enabled: !ApiService.isViewer,
                        decoration: const InputDecoration(labelText: 'Valore', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: ApiService.isViewer ? null : () => setState(() => _compatHeaderControllers.removeAt(item.key)),
                    ),
                  ],
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGenerationParamsCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.tune, color: Color(0xFF64748B)),
          title: const Text('Parametri di Generazione (Stile Cline)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          subtitle: const Text('Temperature, Top-P, Max Output Tokens, Reasoning Effort',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Temperature: ${_temperature != null ? _temperature!.toStringAsFixed(2) : "Predefinito"}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Slider(
                        value: _temperature ?? 0.7,
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        label: (_temperature ?? 0.7).toStringAsFixed(2),
                        onChanged: ApiService.isViewer ? null : (v) => setState(() => _temperature = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Top P: ${_topP != null ? _topP!.toStringAsFixed(2) : "Predefinito"}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Slider(
                        value: _topP ?? 0.95,
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        label: (_topP ?? 0.95).toStringAsFixed(2),
                        onChanged: ApiService.isViewer ? null : (v) => setState(() => _topP = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<int>(
                    value: _maxOutputTokens,
                    decoration: const InputDecoration(labelText: 'Max Output Tokens', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 2048, child: Text('2,048 token')),
                      DropdownMenuItem(value: 4096, child: Text('4,096 token (Consigliato)')),
                      DropdownMenuItem(value: 8192, child: Text('8,192 token')),
                      DropdownMenuItem(value: 16384, child: Text('16,384 token')),
                    ],
                    onChanged: ApiService.isViewer ? null : (v) {
                      if (v != null) setState(() => _maxOutputTokens = v);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String?>(
                    value: _reasoningEffort,
                    decoration: const InputDecoration(labelText: 'Reasoning Effort', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Nessuno / Predefinito')),
                      DropdownMenuItem(value: 'low', child: Text('Low (Veloce)')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'high', child: Text('High (Massima accuratezza)')),
                    ],
                    onChanged: ApiService.isViewer ? null : (v) => setState(() => _reasoningEffort = v),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkParamsCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.network_ping, color: Color(0xFF64748B)),
          title: const Text('Rete & Resilienza Gateway',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          subtitle: const Text('Timeout HTTP e tentativi di retry automatici',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _timeoutSeconds,
                    decoration: const InputDecoration(labelText: 'Timeout Richiesta', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('30 secondi')),
                      DropdownMenuItem(value: 60, child: Text('60 secondi (Predefinito)')),
                      DropdownMenuItem(value: 120, child: Text('120 secondi')),
                      DropdownMenuItem(value: 180, child: Text('180 secondi')),
                    ],
                    onChanged: ApiService.isViewer ? null : (v) {
                      if (v != null) setState(() => _timeoutSeconds = v);
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _maxRetries,
                    decoration: const InputDecoration(labelText: 'Retry su errori transitori', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Nessun retry')),
                      DropdownMenuItem(value: 1, child: Text('1 tentativo')),
                      DropdownMenuItem(value: 2, child: Text('2 tentativi (Consigliato)')),
                      DropdownMenuItem(value: 3, child: Text('3 tentativi')),
                    ],
                    onChanged: ApiService.isViewer ? null : (v) {
                      if (v != null) setState(() => _maxRetries = v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemPromptCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.description_outlined, color: Color(0xFF64748B)),
          title: const Text('Istruzioni di Sistema (System Prompt)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          subtitle: Text('${_promptController.text.length} caratteri configurati',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Definisce il ruolo e le linee guida del consulente clinico:'),
                TextButton.icon(
                  onPressed: ApiService.isViewer ? null : _resetDefaultPrompt,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Ripristina Predefinito'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _promptController,
              maxLines: 12,
              minLines: 5,
              enabled: !ApiService.isViewer,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                fillColor: Color(0xFFF8FAFC),
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
      ),
    );
  }

  Widget _buildTestAndSaveFooter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_testConnectionResult != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _testConnectionResult!['success'] == true ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _testConnectionResult!['success'] == true ? Colors.green.shade200 : Colors.red.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _testConnectionResult!['success'] == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: _testConnectionResult!['success'] == true ? Colors.green.shade700 : Colors.red.shade700,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _testConnectionResult!['message']?.toString() ?? '',
                    style: TextStyle(
                      color: _testConnectionResult!['success'] == true ? Colors.green.shade900 : Colors.red.shade900,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(160, 52),
                side: BorderSide(color: Colors.purple.shade400),
                foregroundColor: Colors.purple.shade800,
              ),
              onPressed: (_isTestingConnection || _isSavingAI || ApiService.isViewer) ? null : _testAIConnection,
              icon: _isTestingConnection
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.speed_rounded),
              label: Text(_isTestingConnection ? 'Verifica...' : 'Test Connessione'),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size(180, 52),
              ),
              onPressed: (_isSavingAI || _isTestingConnection || ApiService.isViewer) ? null : _saveAIConfig,
              icon: _isSavingAI
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(_isSavingAI ? 'Salvataggio...' : 'Salva Configurazione IA',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAIConfigurationSection(BuildContext context) {
    return _buildPremiumExpansionTile(
      context: context,
      title: 'Configurazione IA Multi-Provider',
      subtitle: 'Google Gemini, OpenAI, Gateway compatibili (OmniRoute / vLLM) e parametri avanzati',
      icon: Icons.psychology_rounded,
      iconColor: Colors.purple.shade700,
      initiallyExpanded: false,
      children: [
        const Text(
          'Configura il motore IA per le analisi cliniche multidimensionali. '
          'Tutte le chiamate e le chiavi API sono gestite in modo sicuro direttamente dal server backend.',
          style: TextStyle(color: Color(0xFF475569), fontSize: 13),
        ),
        const SizedBox(height: 16),
        _buildProviderSelector(),
        const SizedBox(height: 16),
        if (_activeProvider == 'gemini') _buildGeminiCard(),
        if (_activeProvider == 'openai') _buildOpenAICard(),
        if (_activeProvider == 'openai_compatible') _buildCompatCard(),
        const SizedBox(height: 16),
        _buildGenerationParamsCard(),
        const SizedBox(height: 12),
        _buildNetworkParamsCard(),
        const SizedBox(height: 12),
        _buildSystemPromptCard(),
        const SizedBox(height: 20),
        _buildTestAndSaveFooter(),
      ],
    );
  }
}
