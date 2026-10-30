import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/web_compat.dart';
import 'package:http/http.dart' as raw_http;
import 'package:file_picker/file_picker.dart';
import '../config.dart' show kApiBaseUrl, kApiClientBaseUrl;
import '../models/scale_model.dart';
import '../models/patient_model.dart';
import '../models/evaluation_model.dart';
import '../models/audit_log.dart';
import 'license_api.dart';

export 'license_api.dart';

class _Http {
  const _Http();

  // Client HTTP con timeout esteso per operazioni AI lunghe
  static final _client = raw_http.Client();

  bool _passwordChangeRequired(raw_http.Response response) {
    if (response.statusCode != 403) return false;
    try {
      final detail = jsonDecode(response.body)['detail'];
      return detail is Map && detail['code'] == 'password_change_required';
    } catch (_) {
      return false;
    }
  }

  void _handleAudit(raw_http.Response response) {
    if (response.headers['x-audit-status'] == 'degraded') {
      WebCompat.dispatchCustomEvent('autify-audit-warning', detail: response.headers['x-correlation-id'] ?? '');
    }
  }

  void _handleUnauthorized() {
    try {
      WebCompat.localStorageRemove('jwt_token');
      WebCompat.localStorageRemove('auth_role');
      WebCompat.localStorageRemove('auth_username');
      WebCompat.localStorageRemove('ai_enabled');
      WebCompat.localStorageRemove('must_change_password');
      WebCompat.sessionStorageClear();
      final reloadUrl = WebCompat.getCurrentPath() +
          "?v=${DateTime.now().millisecondsSinceEpoch}";
      WebCompat.reloadWindow(reloadUrl);
    } catch (_) {}
  }

  Future<raw_http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final request = raw_http.Request('GET', url);
    if (headers != null) request.headers.addAll(headers);

    final response = await _client
        .send(request)
        .timeout(
          const Duration(
              seconds: 350), // Margine oltre il timeout backend (300s)
        )
        .then((streamedResponse) =>
            raw_http.Response.fromStream(streamedResponse));

    if (response.statusCode == 401 || _passwordChangeRequired(response)) {
      _handleUnauthorized();
    }
    _handleAudit(response);
    return response;
  }

  Future<raw_http.Response> post(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final request = raw_http.Request('POST', url);
    if (headers != null) request.headers.addAll(headers);
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else {
        request.bodyBytes = body as List<int>;
      }
    }

    final timeout = url.path.contains('/ai/analyze')
        ? const Duration(seconds: 350) // Timeout esteso per analisi AI
        : const Duration(seconds: 60); // Timeout normale per altre operazioni

    final response = await _client.send(request).timeout(timeout).then(
        (streamedResponse) => raw_http.Response.fromStream(streamedResponse));

    if ((response.statusCode == 401 && !url.path.contains('/auth/login')) ||
        _passwordChangeRequired(response)) {
      _handleUnauthorized();
    }
    _handleAudit(response);
    return response;
  }

  Future<raw_http.Response> put(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final request = raw_http.Request('PUT', url);
    if (headers != null) request.headers.addAll(headers);
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else {
        request.bodyBytes = body as List<int>;
      }
    }

    final response = await _client
        .send(request)
        .timeout(
          const Duration(seconds: 60),
        )
        .then((streamedResponse) =>
            raw_http.Response.fromStream(streamedResponse));

    if (response.statusCode == 401 || _passwordChangeRequired(response)) {
      _handleUnauthorized();
    }
    _handleAudit(response);
    return response;
  }

  Future<raw_http.Response> patch(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final request = raw_http.Request('PATCH', url);
    if (headers != null) request.headers.addAll(headers);
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else {
        request.bodyBytes = body as List<int>;
      }
    }

    final response = await _client
        .send(request)
        .timeout(
          const Duration(seconds: 60),
        )
        .then((streamedResponse) =>
            raw_http.Response.fromStream(streamedResponse));

    if (response.statusCode == 401 || _passwordChangeRequired(response)) {
      _handleUnauthorized();
    }
    _handleAudit(response);
    return response;
  }

  Future<raw_http.Response> delete(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final request = raw_http.Request('DELETE', url);
    if (headers != null) request.headers.addAll(headers);
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else {
        request.bodyBytes = body as List<int>;
      }
    }

    final response = await _client
        .send(request)
        .timeout(
          const Duration(seconds: 60),
        )
        .then((streamedResponse) =>
            raw_http.Response.fromStream(streamedResponse));

    if (response.statusCode == 401 || _passwordChangeRequired(response)) {
      _handleUnauthorized();
    }
    _handleAudit(response);
    return response;
  }
}

const _Http http = _Http();

class ApiService implements LicenseApi {
  const ApiService();

  static String get kAuthToken {
    try {
      final stored = WebCompat.sessionStorageGet('jwt_token');
      if (stored != null && stored.isNotEmpty) {
        return stored;
      }
    } catch (_) {}
    return '';
  }

  static bool get isViewer {
    try {
      return WebCompat.localStorageGet('auth_role') == 'viewer';
    } catch (_) {}
    return false;
  }

  static bool get isAdmin {
    try {
      return WebCompat.localStorageGet('auth_role') == 'admin';
    } catch (_) {}
    return false;
  }

  static bool get isAiEnabled {
    try {
      return WebCompat.localStorageGet('ai_enabled') == 'true';
    } catch (_) {}
    return false;
  }

  static String get currentUsername {
    try {
      return WebCompat.localStorageGet('auth_username') ?? '';
    } catch (_) {}
    return '';
  }

  static const String baseUrl = kApiBaseUrl;

  static Future<Map<String, dynamic>> getExpiryPolicy() async {
    final response = await http.get(Uri.parse('$baseUrl/expiry-policy'),
        headers: {'Authorization': 'Bearer $kAuthToken'});
    if (response.statusCode != 200) throw Exception('Impossibile leggere la policy server');
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static Future<void> saveExpiryPolicy(Map<String, dynamic> policy) async {
    final response = await http.post(Uri.parse('$baseUrl/expiry-policy'),
        headers: {'Authorization': 'Bearer $kAuthToken', 'Content-Type': 'application/json'},
        body: jsonEncode(policy));
    if (response.statusCode != 200) throw Exception('Impossibile salvare la policy server');
  }


  Future<LicenseStatus> getLicenseStatus({bool forceRemote = false}) async {
    final uri = Uri.parse('$baseUrl/license/status').replace(
      queryParameters: forceRemote ? const {'force_remote': 'true'} : null,
    );
    late raw_http.Response response;
    try {
      response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
    } catch (_) {
      throw const LicenseApiException(
        'Impossibile contattare il backend. Verifica la connessione e riprova.',
        networkError: true,
      );
    }
    if (response.statusCode != 200) {
      throw LicenseApiException(
          _licenseError(response, 'Impossibile verificare la licenza'));
    }
    return LicenseStatus.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<LicenseServerInfo> getLicenseServerInfo() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/license/server-info'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body is Map<String, dynamic>) {
        return LicenseServerInfo.fromJson(body);
      }
      throw LicenseApiException(
        body is Map
            ? body['detail']?.toString() ?? 'Errore server licenze'
            : 'Errore server licenze',
      );
    } on LicenseApiException {
      rethrow;
    } catch (_) {
      throw const LicenseApiException(
        'Impossibile leggere la configurazione del server licenze',
        networkError: true,
      );
    }
  }

  @override
  Future<LicenseStatus> activateLicense(String code) async {
    late raw_http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/license/activate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode({'code': code.trim()}),
      );
    } catch (_) {
      throw const LicenseApiException(
        'Server non raggiungibile. L’attivazione non è stata completata.',
        networkError: true,
      );
    }
    if (response.statusCode != 200) {
      throw LicenseApiException(
          _licenseError(response, 'Attivazione non riuscita'));
    }
    return LicenseStatus.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<LicenseStatus> deactivateLicense() async {
    late raw_http.Response response;
    try {
      response = await http.post(
        Uri.parse('$baseUrl/license/deactivate'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
      );
    } catch (_) {
      throw const LicenseApiException(
        'Server non raggiungibile. La disattivazione non è stata completata.',
        networkError: true,
      );
    }
    if (response.statusCode != 200) {
      throw LicenseApiException(
          _licenseError(response, 'Disattivazione non riuscita'));
    }
    return LicenseStatus.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  String _licenseError(raw_http.Response response, String fallback) {
    try {
      return (jsonDecode(response.body) as Map<String, dynamic>)['detail']
              ?.toString() ??
          fallback;
    } catch (_) {
      return fallback;
    }
  }

  // --- AUTHENTICATION ---

  Future<Map<String, dynamic>?> login(
      String username, String password, String deviceId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'device_id': deviceId,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // JWT limitato alla scheda; metadati UI nel localStorage (ruoli verificati dal server).
        try {
          WebCompat.sessionStorageSet('jwt_token', data['token'] ?? '');
          WebCompat.localStorageSet('auth_role', data['role'] ?? '');
          WebCompat.localStorageSet('ai_enabled',
              (data['ai_enabled'] ?? false).toString());
          WebCompat.localStorageSet('auth_username', data['username'] ?? '');
          WebCompat.localStorageSet('must_change_password',
              (data['must_change_password'] == true).toString());
        } catch (_) {}
        return data;
      }
      return null;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return null;
    }
  }

  Future<void> changeOwnPassword(String currentPassword, String newPassword,
      String confirmation) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/change-password'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $kAuthToken',
      },
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
        'confirm_password': confirmation,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(_apiError(response));
    }
    // No stale token is reused after the server revokes every session.
    http._handleUnauthorized();
  }

  Future<List<AuditLog>> getAuditLogs() async {
    final response = await http.get(Uri.parse('$baseUrl/audit-logs'), headers: {'Authorization': 'Bearer $kAuthToken'});
    if (response.statusCode != 200) throw Exception('Registro non disponibile (${response.statusCode})');
    final data = jsonDecode(response.body) as List;
    return data.map((e) => AuditLog.fromJson(e)).toList();
  }

  // --- CRUD UTENZE ---

  Future<List<Map<String, dynamic>>> getUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return [];
    }
  }

  Future<bool> createUser(Map<String, dynamic> userData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode(userData),
      );
      return response.statusCode == 201;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  Future<bool> updateUser(
      String username, Map<String, dynamic> updateData) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/$username'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode(updateData),
      );
      if (response.statusCode == 200 && username == currentUsername &&
          (updateData.containsKey('password') || updateData.containsKey('role') ||
           updateData.containsKey('ai_enabled'))) {
        http._handleUnauthorized();
      }
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  Future<bool> deleteUser(String username) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/users/$username'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  Future<bool> uploadProtocolJSON(PlatformFile file) async {
    try {
      final request = raw_http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/import-scale'),
      );
      request.headers['Authorization'] = 'Bearer $kAuthToken';

      // In Flutter Web, il file ha i bytes esposti direttamente se letto con withData: true
      if (file.bytes != null) {
        request.files.add(raw_http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ));
      } else {
        throw Exception("Impossibile leggere i bytes del file");
      }

      final response = await raw_http.Response.fromStream(await request.send());
      if (response.statusCode == 401 || http._passwordChangeRequired(response)) {
        http._handleUnauthorized();
      }
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  Future<List<ScaleModel>> getHistoricalScales(String patientId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/patients/$patientId/evaluation-scales'),
      headers: {'Authorization': 'Bearer $kAuthToken'},
    );
    if (response.statusCode != 200) throw Exception(_apiError(response));
    return (jsonDecode(response.body) as List)
        .map((item) => ScaleModel.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<ScaleModel>> getScales() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/scales'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((json) => ScaleModel.fromJson(json)).toList();
      }
      return [];
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return [];
    }
  }

  Future<bool> updateScale(ScaleModel scale) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/scales/${scale.id}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode(scale.toJson()),
      );
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  Future<bool> deleteScale(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/scales/$id'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  Future<bool> deleteEvaluation(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/evaluations/$id'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  Future<Map<String, dynamic>> getGeminiSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/settings'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return {
          'key': body['gemini_api_key'],
          'model': body['gemini_model'] ?? 'gemini-1.5-pro',
          'prompt': body['gemini_prompt'],
          'viewer_ai_enabled': body['viewer_ai_enabled'] ?? false,
        };
      }
      return {
        'key': null,
        'model': 'gemini-1.5-pro',
        'prompt': null,
        'viewer_ai_enabled': false,
      };
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return {
        'key': null,
        'model': 'gemini-1.5-pro',
        'prompt': null,
        'viewer_ai_enabled': false,
      };
    }
  }

  Future<bool> saveGeminiSettings(String key, String model,
      {String? prompt, bool? viewerAiEnabled}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode({
          'id': 'global_settings',
          'gemini_api_key': key,
          'gemini_model': model,
          'gemini_prompt': prompt,
          'viewer_ai_enabled': viewerAiEnabled ?? false,
        }),
      );
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  // --- NUOVI ENDPOINT CONFIGURAZIONE IA SICURA ---

  Future<Map<String, dynamic>?> getAiSettings() async {
    try {
      final response = await http.get(
        Uri.parse(isAdmin ? '$baseUrl/settings/ai' : '$baseUrl/ai/capabilities'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e, s) {
      debugPrint('[ApiService] getAiSettings error: $e | $s');
      return null;
    }
  }

  Future<bool> patchAiSettings(Map<String, dynamic> patch) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/settings/ai'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode(patch),
      );
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] patchAiSettings error: $e | $s');
      return false;
    }
  }

  Future<Map<String, dynamic>> testAiConnection(
      Map<String, dynamic> config) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/ai/test-connection'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode(config),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      final err = jsonDecode(response.body);
      return {
        'success': false,
        'message':
            err['detail'] ?? 'Errore test connessione (${response.statusCode})',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Impossibile contattare il server: $e',
      };
    }
  }

  Future<List<String>> discoverCompatibleModels({
    String? providerBaseUrl,
    String? baseUrl,
    String? apiKey,
    Map<String, String>? customHeaders,
  }) async {
    try {
      final targetUrl = (providerBaseUrl ?? baseUrl)?.trim();
      final payload = <String, dynamic>{};
      if (targetUrl != null && targetUrl.isNotEmpty) {
        payload['base_url'] = targetUrl;
      }
      if (apiKey != null && apiKey.isNotEmpty) {
        payload['api_key'] = apiKey;
      }
      if (customHeaders != null && customHeaders.isNotEmpty) {
        payload['custom_headers'] = customHeaders;
      }

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/ai/openai-compatible/models'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = data['models'] as List<dynamic>? ?? [];
        return list.map((e) => e.toString()).toList();
      } else {
        final err = jsonDecode(response.body);
        throw Exception(err['detail'] ??
            'Errore nel recupero modelli (${response.statusCode})');
      }
    } catch (e, s) {
      debugPrint('[ApiService] discoverCompatibleModels error: $e | $s');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> analyzePatientData({
    required PatientModel patient,
    required List<AggregatedEvaluation> evaluations,
    String? notes,
    Map<String, dynamic>? attachment,
    List<Map<String, dynamic>>? historyToInclude,
    String? systemPrompt,
    bool externalContentConfirmed = false,
  }) async {
    Map<String, dynamic>? attachmentPayload;
    if (attachment != null && attachment['bytes'] != null) {
      final bytes = attachment['bytes'];
      final ext = (attachment['extension'] as String?) ?? 'pdf';
      attachmentPayload = {
        'filename': 'allegato.$ext',
        'extension': ext,
        'data_base64': base64Encode(bytes is Uint8List
            ? bytes
            : Uint8List.fromList(List<int>.from(bytes))),
      };
    }

    final payload = {
      'id_paziente': patient.id,
      'evaluation_ids': evaluations.map((e) => e.idValutazione).toList(),
      'notes': notes,
      'history_report_ids': (historyToInclude ?? []).map((r) => r['id']).toList(),
      'external_content_confirmed': externalContentConfirmed,
      'attachment': attachmentPayload,
      if (isAdmin && systemPrompt != null) 'system_prompt': systemPrompt,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/ai/analyze'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $kAuthToken',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200 || response.statusCode == 202) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    String errorMsg = 'Errore analisi IA (${response.statusCode})';
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data.containsKey('detail')) {
        errorMsg = data['detail'].toString();
      }
    } catch (_) {}
    throw Exception(errorMsg);
  }

  Future<void> approveAiAnalysis(String id, String reportHash) async {
    final response = await http.post(
      Uri.parse('$baseUrl/patients/ai-analyses/$id/approve'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $kAuthToken'},
      body: jsonEncode({'report_hash': reportHash}),
    );
    if (response.statusCode != 200) throw Exception(_apiError(response));
  }

  Future<List<int>?> downloadSavedAiAnalysisPdf(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/patients/ai-analyses/$id/pdf'),
      headers: {'Authorization': 'Bearer $kAuthToken'},
    );
    if (response.statusCode != 200) throw Exception(_apiError(response));
    return response.bodyBytes;
  }

  Future<List<Map<String, dynamic>>> getAiJobs({int limit = 30}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/ai/jobs?limit=$limit'),
      headers: {'Authorization': 'Bearer $kAuthToken'},
    );
    if (response.statusCode != 200)
      throw Exception('Errore caricamento job IA');
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getNotifications({int limit = 50}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications?limit=$limit'),
      headers: {'Authorization': 'Bearer $kAuthToken'},
    );
    if (response.statusCode != 200)
      throw Exception('Errore caricamento notifiche');
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  Future<int> getUnreadNotificationCount() async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications/unread-count'),
      headers: {'Authorization': 'Bearer $kAuthToken'},
    );
    if (response.statusCode != 200) return 0;
    return (jsonDecode(response.body)['unread_count'] as num?)?.toInt() ?? 0;
  }

  Future<void> markNotificationRead(String id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/notifications/$id/read'),
      headers: {'Authorization': 'Bearer $kAuthToken'},
    );
    if (response.statusCode != 200)
      throw Exception('Errore aggiornamento notifica');
  }

  Future<void> markAllNotificationsRead() async {
    final response = await http.post(
      Uri.parse('$baseUrl/notifications/read-all'),
      headers: {'Authorization': 'Bearer $kAuthToken'},
    );
    if (response.statusCode != 200)
      throw Exception('Errore aggiornamento notifiche');
  }

  // --- ANAGRAFICA (PATIENTS) ---

  Future<PaginatedPatientsResult> getPatients({
    int page = 1,
    int pageSize = 50,
    String? search,
    String status = 'active',
    String? filter,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': '$page',
        'page_size': '$pageSize',
        'status': status,
      };
      if (search != null && search.trim().isNotEmpty) {
        queryParams['search'] = search.trim();
      }
      if (filter != null && filter.isNotEmpty) {
        queryParams['filter'] = filter;
      }
      final uri =
          Uri.parse('$baseUrl/patients').replace(queryParameters: queryParams);
      final response =
          await http.get(uri, headers: {'Authorization': 'Bearer $kAuthToken'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return PaginatedPatientsResult.fromJson(data);
      }
      return PaginatedPatientsResult.empty();
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return PaginatedPatientsResult.empty();
    }
  }

  Future<bool> createPatient(PatientModel patient) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/patients'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode(patient.toJson()),
      );
      return response.statusCode == 201;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  Future<bool> updatePatient(PatientModel patient) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/patients/${patient.id}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode(patient.toJson()),
      );
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  Future<bool> deletePatient(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/patients/$id'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  // --- VALUTAZIONI AGGREGATE ---

  Future<List<AggregatedEvaluation>> getAggregatedEvaluationHistory(
      String patientId, String scaleId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/evaluations/$patientId/$scaleId'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((json) => AggregatedEvaluation.fromJson(json)).toList();
      }
      return [];
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return [];
    }
  }

  Future<AggregatedEvaluation?> updateEvaluationAnswers(
      String evaluationId, List<AnswerModel> risposte,
      {String? nomeOperatore,
      String? nomeIntervistato,
      Map<String, dynamic>? demographics}) async {
    try {
      final Map<String, dynamic> body = {
        'risposte': risposte.map((r) => r.toJson()).toList(),
      };
      if (nomeOperatore != null) body['nome_operatore'] = nomeOperatore;
      if (nomeIntervistato != null)
        body['nome_intervistato'] = nomeIntervistato;
      if (demographics != null) body['demographics'] = demographics;

      final response = await http.put(
        Uri.parse('$baseUrl/evaluations/$evaluationId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return AggregatedEvaluation.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return null;
    }
  }

  Future<List<int>?> downloadEvaluationPdf(String evaluationId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/evaluations/$evaluationId/pdf'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return null;
    }
  }

  // --- ANALISI PSICOMETRICA ---

  Future<PsychometricAnalysis?> getEvaluationAnalysis(
      String evaluationId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/evaluations/$evaluationId/analysis'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return PsychometricAnalysis.fromJson(decoded);
      }
      return null;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return null;
    }
  }

  // --- DATABASE EXPORT / IMPORT ---

  Future<List<int>?> exportPatientsCsv() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/export-patients-csv'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return null;
    }
  }

  String _apiError(raw_http.Response response) {
    try {
      final detail = jsonDecode(response.body)['detail'];
      if (detail is String) return detail;
    } catch (_) {}
    return 'Operazione non riuscita (HTTP ${response.statusCode}).';
  }

  Future<List<int>?> exportDatabase() async {
    final response = await http.get(
      Uri.parse('$baseUrl/export-db'),
      headers: {'Authorization': 'Bearer $kAuthToken'},
    );
    if (response.statusCode != 200) throw Exception(_apiError(response));
    return response.bodyBytes;
  }

  Future<bool> importDatabase(PlatformFile file) async {
    if (file.size > 64 * 1024 * 1024) {
      throw Exception('Il backup supera il limite di 64 MiB.');
    }
    if (file.bytes == null) throw Exception('Impossibile leggere il file.');
    final request =
        raw_http.MultipartRequest('POST', Uri.parse('$baseUrl/import-db'));
    request.headers['Authorization'] = 'Bearer $kAuthToken';
    request.files.add(raw_http.MultipartFile.fromBytes('file', file.bytes!,
        filename: file.name));
    late final raw_http.Response response;
    try {
      response = await request.send()
          .then(raw_http.Response.fromStream)
          .timeout(const Duration(seconds: 180));
    } catch (_) {
      throw Exception('Connessione interrotta o tempo scaduto: esito del '
          'ripristino da verificare nel registro audit. Non ripetere '
          'automaticamente; mantenere la manutenzione attiva.');
    }
    if (response.statusCode == 401 || http._passwordChangeRequired(response)) {
      http._handleUnauthorized();
    }
    if (response.statusCode != 200) throw Exception(_apiError(response));
    // Restore invalidates all sessions; return to login using the existing handler.
    http._handleUnauthorized();
    return true;
  }

  // --- AI HISTORICAL ANALYSES ---

  Future<List<Map<String, dynamic>>> getPatientAiAnalyses(
      String patientId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/patients/$patientId/ai-analyses'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((item) => item as Map<String, dynamic>).toList();
      }
      return [];
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return [];
    }
  }

  Future<Map<String, dynamic>?> savePatientAiAnalysis(
      String patientId, String report,
      {String? notes, List<String>? evaluationsUsed}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/patients/$patientId/ai-analyses'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode({
          'report': report,
          'notes': notes,
          'evaluations_used': evaluationsUsed ?? [],
        }),
      );
      if (response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return null;
    }
  }

  Future<bool> deleteAiAnalysis(String analysisId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/patients/ai-analyses/$analysisId'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  Future<bool> updateAiAnalysisLabel(String analysisId, String newLabel) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/patients/ai-analyses/$analysisId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode({
          'notes': newLabel,
        }),
      );
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  // --- CLIENT-SIDE ENDPOINTS INTEGRATED ---
  static const String clientBaseUrl = kApiClientBaseUrl;

  Future<ScaleModel?> getScaleById(String scaleId) async {
    try {
      final response = await http.get(
        Uri.parse('$clientBaseUrl/scales/$scaleId'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        return ScaleModel.fromJson(jsonDecode(utf8.decode(response.bodyBytes)));
      }
      return null;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return null;
    }
  }

  Future<bool> saveEvaluation(EvaluationModel evaluation) async {
    try {
      final response = await http.post(
        Uri.parse('$clientBaseUrl/evaluations'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode(evaluation.toJson()),
      );
      return response.statusCode == 201;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getDashboardStats() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/dashboard-stats'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return null;
    }
  }

  Future<List<int>?> downloadAiAnalysisPdf(
      PatientModel patient, String report) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/evaluations/ai-analysis-pdf'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kAuthToken',
        },
        body: jsonEncode({
          'patient': patient.toJson(),
          'report': report,
        }),
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return null;
    }
  }
}
