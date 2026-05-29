import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/audit_log.dart';
import '../theme/app_theme.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final ApiService _api = ApiService();
  List<AuditLog> _logs = [];
  bool _isLoading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    try {
      setState(() {
        _isLoading = true;
        _error = '';
      });
      final logs = await _api.getAuditLogs();
      setState(() {
        _logs = logs;
      });
    } catch (e) {
      setState(() {
        _error = 'Errore nel caricamento del registro: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  IconData _getIconForAction(String action) {
    if (action.contains('CREAZIONE_UTENTE')) return Icons.person_add;
    if (action.contains('MODIFICA_UTENTE')) return Icons.manage_accounts;
    if (action.contains('CANCELLAZIONE_UTENTE')) return Icons.person_remove;
    if (action.contains('COMPILAZIONE_SCALA')) return Icons.assignment_turned_in;
    return Icons.history;
  }

  Color _getColorForAction(String action) {
    if (action.contains('CREAZIONE')) return Colors.green;
    if (action.contains('MODIFICA')) return Colors.blue;
    if (action.contains('CANCELLAZIONE')) return Colors.red;
    if (action.contains('COMPILAZIONE')) return Colors.purple;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.puzzleColorAt(4).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.history, color: AppTheme.puzzleColorAt(4), size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Registro Attività',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Tracciabilità educativa di tutte le operazioni',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _loadLogs,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Aggiorna',
                ),
              ],
            ),
          ),

          // Contenuto
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error.isNotEmpty
                    ? Center(child: Text(_error, style: const TextStyle(color: Colors.red)))
                    : _logs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history_toggle_off, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                                const SizedBox(height: 16),
                                Text(
                                  'Nessuna attività registrata',
                                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                            itemCount: _logs.length,
                            itemBuilder: (context, index) {
                              final log = _logs[index];
                              final color = _getColorForAction(log.azione);
                              
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  leading: CircleAvatar(
                                    backgroundColor: color.withValues(alpha: 0.1),
                                    child: Icon(_getIconForAction(log.azione), color: color),
                                  ),
                                  title: Text(
                                    log.dettagli,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Row(
                                      children: [
                                        Icon(Icons.person, size: 14, color: AppTheme.textSecondary),
                                        const SizedBox(width: 4),
                                        Text(log.operatore, style: TextStyle(color: AppTheme.textSecondary)),
                                        const SizedBox(width: 16),
                                        Icon(Icons.access_time, size: 14, color: AppTheme.textSecondary),
                                        const SizedBox(width: 4),
                                        Text(
                                          "${log.timestamp.day.toString().padLeft(2, '0')}/${log.timestamp.month.toString().padLeft(2, '0')}/${log.timestamp.year} ${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}",
                                          style: const TextStyle(color: AppTheme.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
