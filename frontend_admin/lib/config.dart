import 'package:flutter/foundation.dart';

// Credenziali legacy (X-Admin-Password) — usate solo per backward-compat.
// Il login JWT non dipende da queste costanti.
const String kAdminPassword = String.fromEnvironment('ADMIN_PWD', defaultValue: '');
const String kViewerPassword = String.fromEnvironment('VIEWER_PWD', defaultValue: '');

// URL base API — in dev punta al backend locale, in prod all'host di produzione.
const String kApiBaseUrl = kDebugMode
    ? 'http://localhost:8000/api/admin'
    : 'https://tiglio.autify.it/api/admin';

const String kApiClientBaseUrl = kDebugMode
    ? 'http://localhost:8000/api/client'
    : 'https://tiglio.autify.it/api/client';
