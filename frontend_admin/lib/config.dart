import 'package:flutter/foundation.dart';

// Credenziali legacy (X-Admin-Password) — usate solo per backward-compat.
// Il login JWT non dipende da queste costanti.
const String kAdminPassword = String.fromEnvironment('ADMIN_PWD', defaultValue: '');
const String kViewerPassword = String.fromEnvironment('VIEWER_PWD', defaultValue: '');

// URL base API — in dev punta al backend locale, in prod all'host di produzione o da --dart-define.
const String _kEnvApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
const String _kEnvApiClientBaseUrl = String.fromEnvironment('API_CLIENT_BASE_URL', defaultValue: '');

const String kApiBaseUrl = _kEnvApiBaseUrl != ''
    ? _kEnvApiBaseUrl
    : (kDebugMode
        ? 'http://localhost:8000/api/admin'
        : '/api/admin');

const String kApiClientBaseUrl = _kEnvApiClientBaseUrl != ''
    ? _kEnvApiClientBaseUrl
    : (kDebugMode
        ? 'http://localhost:8000/api/client'
        : '/api/client');
