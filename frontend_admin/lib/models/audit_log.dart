class AuditLog {
  final String id;
  final String azione;
  final String operatore;
  final String? targetId;
  final String dettagli;
  final DateTime timestamp;

  AuditLog({
    required this.id,
    required this.azione,
    required this.operatore,
    this.targetId,
    required this.dettagli,
    required this.timestamp,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json['id'] ?? '',
      azione: json['azione'] ?? '',
      operatore: json['operatore'] ?? '',
      targetId: json['target_id'],
      dettagli: json['dettagli'] ?? '',
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']).toLocal() : DateTime.now(),
    );
  }
}
