class LicenseStatus {
  final String status;
  final bool valid;
  final String plan;
  final bool trial;
  final bool offline;
  final int? daysRemaining;
  final DateTime? expiresAt;
  final String? message;

  const LicenseStatus({
    required this.status,
    required this.valid,
    required this.plan,
    required this.trial,
    required this.offline,
    this.daysRemaining,
    this.expiresAt,
    this.message,
  });

  factory LicenseStatus.fromJson(Map<String, dynamic> json) => LicenseStatus(
        status: json['status']?.toString() ?? 'invalid',
        valid: json['valid'] == true,
        plan: json['plan']?.toString() ?? 'trial',
        trial: json['trial'] == true,
        offline: json['offline'] == true,
        daysRemaining: json['days_remaining'] as int?,
        expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
        message: json['message']?.toString(),
      );
}

class LicenseApiException implements Exception {
  final String message;
  final bool networkError;
  const LicenseApiException(this.message, {this.networkError = false});

  @override
  String toString() => message;
}

abstract interface class LicenseApi {
  Future<LicenseStatus> getLicenseStatus({bool forceRemote = false});

  Future<LicenseStatus> activateLicense(String code);
}
