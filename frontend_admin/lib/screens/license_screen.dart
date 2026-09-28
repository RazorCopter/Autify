import 'package:flutter/material.dart';
import '../services/license_api.dart';
import '../services/license_api_factory_stub.dart'
    if (dart.library.html) '../services/license_api_factory_web.dart';
import '../theme/app_theme.dart';

class LicenseScreen extends StatefulWidget {
  final bool blocking;
  final bool initialConnectionError;
  final VoidCallback? onActivated;
  final LicenseApi api;
  final bool isViewer;
  LicenseScreen({
    super.key,
    this.blocking = false,
    this.initialConnectionError = false,
    this.onActivated,
    this.isViewer = false,
    LicenseApi? api,
  }) : api = api ?? createLicenseApi();
  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _code = TextEditingController();
  LicenseStatus? _status;
  LicenseServerInfo? _serverInfo;
  bool _loading = true;
  bool _activating = false;
  bool _connectionError = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _connectionError = widget.initialConnectionError;
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _connectionError = false;
    });
    try {
      final results = await Future.wait([
        widget.api.getLicenseStatus(forceRemote: force),
        widget.api.getLicenseServerInfo(),
      ]);
      if (mounted) {
        setState(() {
          _status = results[0] as LicenseStatus;
          _serverInfo = results[1] as LicenseServerInfo;
        });
      }
    } on LicenseApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _connectionError = e.networkError;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _activate() async {
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _activating = true;
      _error = null;
      _connectionError = false;
    });
    try {
      final value = await widget.api.activateLicense(_code.text.trim());
      if (!mounted) return;
      setState(() => _status = value);
      _code.clear();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Licenza attivata correttamente')));
      widget.onActivated?.call();
    } on LicenseApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _connectionError = e.networkError;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  String _date(DateTime? value) {
    if (value == null) return 'Nessuna scadenza';
    final d = value.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final value = _status;
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: widget.blocking
          ? AppBar(
              title: const Text('Licenza Autify'),
              automaticallyImplyLeading: false)
          : null,
      body: Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: Color(0xFFE4EAF4))),
                      child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                      Icon(
                                          _connectionError
                                              ? Icons.cloud_off_rounded
                                              : value?.valid == true
                                                  ? Icons.verified_rounded
                                                  : Icons.key_off_rounded,
                                          size: 58,
                                          color: value?.valid == true
                                              ? Colors.green
                                              : Colors.orange.shade800),
                                      const SizedBox(height: 14),
                                      Text(
                                          _connectionError
                                              ? 'Verifica temporaneamente non disponibile'
                                              : value?.valid == true
                                                  ? (value!.trial
                                                      ? 'Periodo di prova attivo'
                                                      : 'Licenza attiva')
                                                  : 'Licenza richiesta',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 18),
                                      _serverInfoCard(),
                                      if (value != null) ...[
                                        const SizedBox(height: 18),
                                        _InfoRow(
                                            label: 'Piano',
                                            value: value.trial
                                                ? 'Trial 15 giorni'
                                                : value.plan),
                                        _InfoRow(
                                            label: 'Scadenza',
                                            value: _date(value.expiresAt)),
                                        if (value.daysRemaining != null)
                                          _InfoRow(
                                              label: 'Giorni rimanenti',
                                              value: '${value.daysRemaining}'),
                                        if (value.offline)
                                          const Padding(
                                              padding: EdgeInsets.only(top: 10),
                                              child: Text(
                                                  'Validazione offline tramite cache',
                                                  textAlign: TextAlign.center))
                                      ],
                                      if (_error != null ||
                                          value?.message != null) ...[
                                        const SizedBox(height: 16),
                                        Text(_error ?? value!.message!,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: Colors.redAccent,
                                                fontWeight: FontWeight.w600))
                                      ],
                                      if (widget.isViewer) ...[
                                        const SizedBox(height: 24),
                                        const Text(
                                          'Il profilo Viewer ├¿ in sola lettura. Contatta un amministratore per attivare o sostituire la licenza.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ] else ...[
                                        const SizedBox(height: 26),
                                        TextField(
                                            controller: _code,
                                            textCapitalization:
                                                TextCapitalization.characters,
                                            decoration: const InputDecoration(
                                                labelText: 'Codice licenza',
                                                hintText:
                                                    'AUTIFY-12M-XXXXXXXXXXXXXXXX-XXXXXX',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(
                                                    Icons.vpn_key_outlined)),
                                            onSubmitted: (_) => _activate()),
                                        const SizedBox(height: 14),
                                        FilledButton.icon(
                                            onPressed:
                                                _activating ? null : _activate,
                                            icon: _activating
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2))
                                                : const Icon(
                                                    Icons.check_circle_outline),
                                            label: Text(_activating
                                                ? 'Attivazione...'
                                                : 'Attiva licenza')),
                                      ],
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                          onPressed: _loading
                                              ? null
                                              : () => _load(force: true),
                                          icon: const Icon(Icons.refresh),
                                          label: const Text(
                                              'Verifica nuovamente')),
                                    ])))))),
    );
  }

  Widget _serverInfoCard() {
    final info = _serverInfo;
    final reachable = info?.reachable == true;
    final configured = info?.configured == true;
    return Container(
      key: const Key('license-server-info'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4EAF4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            reachable ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            color: reachable ? Colors.green : Colors.orange.shade800,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Server licenza',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  configured ? info!.url : 'Non configurato',
                  key: const Key('license-server-url'),
                ),
                const SizedBox(height: 4),
                Text(
                  reachable ? 'Raggiungibile' : 'Non raggiungibile',
                  style: TextStyle(
                    color: reachable
                        ? Colors.green.shade700
                        : Colors.orange.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700))
      ]));
}
