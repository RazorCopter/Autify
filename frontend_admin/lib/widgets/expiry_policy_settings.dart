import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ExpiryPolicySettings extends StatefulWidget {
  const ExpiryPolicySettings({super.key});
  @override
  State<ExpiryPolicySettings> createState() => _ExpiryPolicySettingsState();
}

class _ExpiryPolicySettingsState extends State<ExpiryPolicySettings> {
  static const names = {'pos': 'POS', 'san_martin': 'San Martín', 'sis': 'SIS',
    'ogva': 'OGVA', 'sabs': 'SABS', 'oso': 'OSO'};
  final fields = <String, TextEditingController>{};
  final warning = TextEditingController();
  final requiredScales = <String>{};
  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    for (final key in names.keys) { fields[key] = TextEditingController(); }
    _load();
  }

  Future<void> _load() async {
    setState(() { loading = true; error = null; });
    try {
      final policy = await ApiService.getExpiryPolicy();
      if (!mounted) return;
      for (final key in names.keys) { fields[key]!.text = '${policy['scale_validity_months'][key]}'; }
      warning.text = '${policy['expiry_warning_days']}';
      requiredScales..clear()..addAll(List<String>.from(policy['required_scale_types']));
    } catch (e) {
      if (!mounted) return;
      error = '$e';
    }
    if (mounted) setState(() { loading = false; });
  }

  Future<void> _save() async {
    final months = {for (final key in names.keys) key: int.tryParse(fields[key]!.text)};
    final days = int.tryParse(warning.text);
    if (months.values.any((v) => v == null || v < 1 || v > 120) ||
        days == null || days < 0 || days > 365 || requiredScales.isEmpty) {
      setState(() { error = 'Inserire mesi da 1 a 120, preavviso da 0 a 365 giorni e almeno una scala richiesta.'; });
      return;
    }
    setState(() { saving = true; error = null; });
    try {
      await ApiService.saveExpiryPolicy({'scale_validity_months': months,
        'required_scale_types': requiredScales.toList(), 'expiry_warning_days': days});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Policy salvata sul server. Aggiornare dashboard ed elenco per rileggere gli stati.')));
    } catch (e) {
      if (!mounted) return;
      setState(() { error = '$e'; });
    } finally {
      if (mounted) setState(() { saving = false; });
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) { field.dispose(); }
    warning.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(child: ExpansionTile(
    leading: const Icon(Icons.calendar_month),
    title: const Text('Scadenze e scale richieste'),
    subtitle: const Text('Policy comune sul server · mesi di calendario · Europe/Rome'),
    childrenPadding: const EdgeInsets.all(16),
    children: [
      if (loading) const LinearProgressIndicator()
      else ...[
        const Text('Le scale selezionate determinano copertura e filtri. La valutazione resta valida per tutto il giorno di scadenza. Le modifiche valgono per tutti gli operatori.'),
        for (final entry in names.entries) Row(children: [
          Checkbox(value: requiredScales.contains(entry.key), onChanged: !ApiService.isAdmin || saving ? null : (value) {
            setState(() { if (value == true) { requiredScales.add(entry.key); } else { requiredScales.remove(entry.key); } });
          }),
          Expanded(child: Text('${entry.value} richiesta')),
          SizedBox(width: 110, child: TextField(controller: fields[entry.key], enabled: ApiService.isAdmin && !saving,
            keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Mesi'))),
        ]),
        TextField(controller: warning, enabled: ApiService.isAdmin && !saving,
          keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Preavviso in giorni')),
        const SizedBox(height: 12),
        if (ApiService.isAdmin) FilledButton(onPressed: saving ? null : _save, child: Text(saving ? 'Salvataggio...' : 'Salva policy')),
        TextButton(onPressed: saving ? null : _load, child: const Text('Rileggi dal server')),
      ],
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ],
  ));
}
