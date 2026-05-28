import 'dart:convert';
import 'dart:html' as html;
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../config.dart' as cfg;
import '../models/scale_model.dart';
import '../models/patient_model.dart';
import '../models/evaluation_model.dart';

class ApiService {
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

  // Dato che questo frontend è servito da Nginx sulla stessa origine e proxy verso backend,
  // possiamo usare un URL relativo o parametrizzato. In dev locale su Flutter web, 
  // potremmo aver bisogno dell'url completo se non passiamo da Nginx.
  // Assumiamo che in produzione sia /api/admin.
  static const String baseUrl = 'https://aut.ghome.it/api/admin';
  
  // --- AUTHENTICATION ---
  
  Future<Map<String, dynamic>?> login(String username, String password, String deviceId) async {
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
          html.window.localStorage['ai_enabled'] = (data['ai_enabled'] ?? false).toString();
          html.window.localStorage['auth_username'] = data['username'] ?? '';
        } catch (_) {}
        return data;
      }
      return null;
    } catch (e) {
      print('Errore login: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getAuthConfig() async {
    // Mantenuto per backward-compat — non più utilizzato dalla UI
    return null;
  }

  Future<bool> updateAuthConfig(Map<String, dynamic> newConfig) async {
    // Mantenuto per backward-compat — non più utilizzato dalla UI
    return false;
  }

  Future<List<dynamic>> getViewerLogs() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/logs'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      print('Errore caricamento viewer logs: $e');
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
    } catch (e) {
      print('Errore caricamento utenti: $e');
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
    } catch (e) {
      print('Errore creazione utente: $e');
      return false;
    }
  }

  Future<bool> updateUser(String username, Map<String, dynamic> updateData) async {
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
    } catch (e) {
      print('Errore aggiornamento utente: $e');
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
    } catch (e) {
      print('Errore eliminazione utente: $e');
      return false;
    }
  }

  Future<bool> uploadProtocolJSON(PlatformFile file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/import-scale'),
      );
      request.headers['X-Admin-Password'] = kAdminPassword;
      
      // In Flutter Web, il file ha i bytes esposti direttamente se letto con withData: true
      if (file.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ));
      } else {
        throw Exception("Impossibile leggere i bytes del file");
      }

      final response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      print('Errore upload: $e');
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
    } catch (e) {
      print('Errore caricamento scale: $e');
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
    } catch (e) {
      print('Errore aggiornamento scala: $e');
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
    } catch (e) {
      print('Errore eliminazione scala: $e');
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
    } catch (e) {
      print('Errore eliminazione valutazione: $e');
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
    } catch (e) {
      return {
        'key': null,
        'model': 'gemini-1.5-pro',
        'prompt': null,
        'viewer_ai_enabled': false,
      };
    }
  }

  Future<bool> saveGeminiSettings(String key, String model, {String? prompt, bool? viewerAiEnabled}) async {
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
    } catch (e) {
      return false;
    }
  }

  // --- ANAGRAFICA (PATIENTS) ---

  Future<List<PatientModel>> getPatients() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/patients'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((json) => PatientModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      print('Errore caricamento pazienti: $e');
      return [];
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
    } catch (e) {
      print('Errore creazione paziente: $e');
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
    } catch (e) {
      print('Errore aggiornamento paziente: $e');
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
    } catch (e) {
      print('Errore eliminazione paziente: $e');
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
    } catch (e) {
      print('Errore caricamento storico valutazioni: $e');
      return [];
    }
  }

  Future<AggregatedEvaluation?> updateEvaluationAnswers(
      String evaluationId, List<AnswerModel> risposte,
      {String? nomeOperatore, String? nomeIntervistato, Map<String, dynamic>? demographics}) async {
    try {
      final Map<String, dynamic> body = {
        'risposte': risposte.map((r) => r.toJson()).toList(),
      };
      if (nomeOperatore != null) body['nome_operatore'] = nomeOperatore;
      if (nomeIntervistato != null) body['nome_intervistato'] = nomeIntervistato;
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
    } catch (e) {
      print('Errore aggiornamento valutazione: $e');
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
    } catch (e) {
      print('Errore download PDF: $e');
      return null;
    }
  }

  // --- ANALISI PSICOMETRICA ---

  Future<PsychometricAnalysis?> getEvaluationAnalysis(String evaluationId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/evaluations/$evaluationId/analysis'),
        headers: {'Authorization': 'Bearer $kAuthToken'},
      );
      print('DEBUG AUTANALYSIS API - analysis status: ${response.statusCode}');
      if (response.statusCode == 200) {
        print('DEBUG AUTANALYSIS API - analysis body: ${response.body}');
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return PsychometricAnalysis.fromJson(decoded);
      }
      print('DEBUG AUTANALYSIS API - analysis request failed: ${response.body}');
      return null;
    } catch (e, stackTrace) {
      print('Errore caricamento analisi: $e');
      print('Stack caricamento analisi: $stackTrace');
      return null;
    }
  }

  // --- DATABASE EXPORT / IMPORT ---

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
    } catch (e) {
      print('Errore export database: $e');
      return null;
    }
  }

  Future<bool> importDatabase(PlatformFile file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/import-db'),
      );
      request.headers['X-Admin-Password'] = kAdminPassword;
      if (file.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          file.bytes!,
          filename: file.name,
        ));
      } else {
        throw Exception("Impossibile leggere i bytes del file");
      }
      final response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      print('Errore import database: $e');
      return false;
    }
  }

  // --- AI HISTORICAL ANALYSES ---

  Future<List<Map<String, dynamic>>> getPatientAiAnalyses(String patientId) async {
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
    } catch (e) {
      print('Errore caricamento storico analisi IA: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> savePatientAiAnalysis(
      String patientId, String report, {String? notes, List<String>? evaluationsUsed}) async {
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
    } catch (e) {
      print('Errore salvataggio analisi IA: $e');
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
    } catch (e) {
      print('Errore eliminazione analisi IA: $e');
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
    } catch (e) {
      print('Errore aggiornamento label analisi IA: $e');
      return false;
    }
  }

  // --- CLIENT-SIDE ENDPOINTS INTEGRATED ---
  static const String clientBaseUrl = 'https://aut.ghome.it/api/client';

  Future<ScaleModel?> getScaleById(String scaleId) async {
    try {
      final response = await http.get(Uri.parse('$clientBaseUrl/scales/$scaleId'));
      if (response.statusCode == 200) {
        return ScaleModel.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      print('Errore caricamento dettagli scala: $e');
      return null;
    }
  }

  Future<bool> saveEvaluation(EvaluationModel evaluation) async {
    try {
      final response = await http.post(
        Uri.parse('$clientBaseUrl/evaluations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(evaluation.toJson()),
      );
      return response.statusCode == 201;
    } catch (e) {
      print('Errore salvataggio valutazione: $e');
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
    } catch (e) {
      print('Errore caricamento statistiche dashboard: $e');
      return null;
    }
  }

  Future<List<int>?> downloadAiAnalysisPdf(PatientModel patient, String report) async {
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
    } catch (e) {
      print('Errore download PDF AI: $e');
      return null;
    }
  }
}
