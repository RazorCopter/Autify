import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
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

  void _handleUnauthorized() {
    try {
      html.window.localStorage.clear();
      html.window.sessionStorage.clear();
      final reloadUrl = (html.window.location.pathname ?? '/') +
          "?v=${DateTime.now().millisecondsSinceEpoch}";
      html.window.location.href = reloadUrl;
    } catch (_) {}
  }

  Future<raw_http.Response> get(Uri url, {Map<String, String>? headers}) async {
    final response = await raw_http.get(url, headers: headers);
    if (response.statusCode == 401) {
      _handleUnauthorized();
    }
    return response;
  }

  Future<raw_http.Response> post(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final response = await raw_http.post(url,
        headers: headers, body: body, encoding: encoding);
    if (response.statusCode == 401 && !url.path.contains('/auth/login')) {
      _handleUnauthorized();
    }
    return response;
  }

  Future<raw_http.Response> put(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final response = await raw_http.put(url,
        headers: headers, body: body, encoding: encoding);
    if (response.statusCode == 401) {
      _handleUnauthorized();
    }
    return response;
  }

  Future<raw_http.Response> patch(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final response = await raw_http.patch(url,
        headers: headers, body: body, encoding: encoding);
    if (response.statusCode == 401) {
      _handleUnauthorized();
    }
    return response;
  }

  Future<raw_http.Response> delete(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    final response = await raw_http.delete(url,
        headers: headers, body: body, encoding: encoding);
    if (response.statusCode == 401) {
      _handleUnauthorized();
    }
    return response;
  }
}

const _Http http = _Http();

class ApiService implements LicenseApi {
  const ApiService();

  static String get kAuthToken {
    try {
      final stored = html.window.localStorage['jwt_token'];
      if (stored != null && stored.isNotEmpty) {
        return stored;
      }
    } catch (_) {}
    return '';
  }

  static bool get isViewer {
    try {
      return html.window.localStorage['auth_role'] == 'viewer';
    } catch (_) {}
    return false;
  }

  static bool get isAdmin {
    try {
      return html.window.localStorage['auth_role'] == 'admin';
    } catch (_) {}
    return false;
  }

  static bool get isAiEnabled {
    try {
      return html.window.localStorage['ai_enabled'] == 'true';
    } catch (_) {}
    return false;
  }

  static String get currentUsername {
    try {
      return html.window.localStorage['auth_username'] ?? '';
    } catch (_) {}
    return '';
  }

  static const String baseUrl = kApiBaseUrl;

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
        // Salva il JWT e i dati di sessione nel localStorage
        try {
          html.window.localStorage['jwt_token'] = data['token'] ?? '';
          html.window.localStorage['auth_role'] = data['role'] ?? '';
          html.window.localStorage['ai_enabled'] =
              (data['ai_enabled'] ?? false).toString();
          html.window.localStorage['auth_username'] = data['username'] ?? '';
        } catch (_) {}
        return data;
      }
      return null;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return null;
    }
  }

  Future<List<AuditLog>> getAuditLogs() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/audit-logs'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => AuditLog.fromJson(e)).toList();
      }
      return [];
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return [];
    }
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

      final response = await request.send();
      if (response.statusCode == 401) {
        http._handleUnauthorized();
      }
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
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
        Uri.parse('$baseUrl/settings/ai'),
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

  Future<Map<String, dynamic>> testAiConnection(Map<String, dynamic> config) async {
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
        'message': err['detail'] ?? 'Errore test connessione (${response.statusCode})',
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
        throw Exception(err['detail'] ?? 'Errore nel recupero modelli (${response.statusCode})');
      }
    } catch (e, s) {
      debugPrint('[ApiService] discoverCompatibleModels error: $e | $s');
      rethrow;
    }
  }

  Future<String> analyzePatientData({
    required PatientModel patient,
    required List<AggregatedEvaluation> evaluations,
    String? notes,
    Map<String, dynamic>? attachment,
    List<Map<String, dynamic>>? historyToInclude,
    String? systemPrompt,
    Map<String, PsychometricAnalysis?>? analyses,
  }) async {
    final List<Map<String, dynamic>> evalsJson = evaluations.map((e) {
      final m = <String, dynamic>{
        'id_valutazione': e.idValutazione,
        'id_paziente': e.idPaziente,
        'id_scala': e.idScala,
        'anno': e.anno,
        'data_compilazione': e.dataCompilazione,
        'nome_operatore': e.nomeOperatore,
        'domini': e.domini.map((d) => {
          'codice': d.codice,
          'etichetta': d.etichetta,
          'punteggio': d.punteggio,
          'num_domande': d.numDomande,
        }).toList(),
      };
      final analysis = analyses?[e.idValutazione] ?? analyses?[e.idScala];
      if (analysis != null) {
        m['analysis'] = {
          'somma_punteggi_standard': analysis.sommaPunteggiStandard,
          'indice_qv': analysis.indiceQv,
          'percentile': analysis.percentile,
          'fascia_qv': analysis.fasciaQv,
          'alert_medico': analysis.alertMedico,
          'alert_comportamentale': analysis.alertComportamentale,
          'sezione_2_top4': analysis.sezione2Top4,
          'domini': analysis.domini.map((da) => {
            'codice': da.codice,
            'etichetta': da.etichetta,
            'punteggio_diretto': da.punteggioDiretto,
            'punteggio_standard': da.punteggioStandard,
            'percentile': da.percentileDominio,
            'fascia': da.fascia,
          }).toList(),
        };
      }
      return m;
    }).toList();

    Map<String, dynamic>? attachmentPayload;
    if (attachment != null && attachment['bytes'] != null) {
      final bytes = attachment['bytes'];
      final ext = (attachment['extension'] as String?) ?? 'pdf';
      attachmentPayload = {
        'filename': 'allegato.$ext',
        'extension': ext,
        'data_base64': base64Encode(bytes is Uint8List ? bytes : Uint8List.fromList(List<int>.from(bytes))),
      };
    }

    final payload = {
      'id_paziente': patient.id,
      'patient': patient.toJson(),
      'evaluations': evalsJson,
      'notes': notes,
      'history_reports': historyToInclude,
      'attachment': attachmentPayload,
      'system_prompt': systemPrompt,
    };

    final response = await http.post(
      Uri.parse('$baseUrl/ai/analyze'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $kAuthToken',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['report'] as String?) ?? '';
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

  Future<List<int>?> exportDatabase() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/export-db'),
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

  Future<bool> importDatabase(PlatformFile file) async {
    try {
      final request = raw_http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/import-db'),
      );
      request.headers['Authorization'] = 'Bearer $kAuthToken';
      if (file.bytes != null) {
        request.files.add(raw_http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ));
      } else {
        throw Exception("Impossibile leggere i bytes del file");
      }
      final response = await request.send();
      if (response.statusCode == 401) {
        http._handleUnauthorized();
      }
      return response.statusCode == 200;
    } catch (e, s) {
      debugPrint('[ApiService] $e | $s');
      return false;
    }
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
        return ScaleModel.fromJson(jsonDecode(response.body));
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
