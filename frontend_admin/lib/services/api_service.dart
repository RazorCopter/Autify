import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import '../config.dart';
import '../models/scale_model.dart';
import '../models/patient_model.dart';
import '../models/evaluation_model.dart';

class ApiService {
  // Dato che questo frontend è servito da Nginx sulla stessa origine e proxy verso backend,
  // possiamo usare un URL relativo o parametrizzato. In dev locale su Flutter web, 
  // potremmo aver bisogno dell'url completo se non passiamo da Nginx.
  // Assumiamo che in produzione sia /api/admin.
  static const String baseUrl = 'https://aut.ghome.it/api/admin';

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
        headers: {'X-Admin-Password': kAdminPassword},
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
          'X-Admin-Password': kAdminPassword,
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
        headers: {'X-Admin-Password': kAdminPassword},
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Errore eliminazione scala: $e');
      return false;
    }
  }

  Future<Map<String, String?>> getGeminiSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/settings'),
        headers: {'X-Admin-Password': kAdminPassword},
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return {
          'key': body['gemini_api_key'],
          'model': body['gemini_model'] ?? 'gemini-1.5-pro',
        };
      }
      return {'key': null, 'model': 'gemini-1.5-pro'};
    } catch (e) {
      return {'key': null, 'model': 'gemini-1.5-pro'};
    }
  }

  Future<bool> saveGeminiSettings(String key, String model) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/settings'),
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Password': kAdminPassword,
        },
        body: jsonEncode({
          'id': 'global_settings',
          'gemini_api_key': key,
          'gemini_model': model,
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
        headers: {'X-Admin-Password': kAdminPassword},
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
          'X-Admin-Password': kAdminPassword,
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
          'X-Admin-Password': kAdminPassword,
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
        headers: {'X-Admin-Password': kAdminPassword},
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
        headers: {'X-Admin-Password': kAdminPassword},
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
      String evaluationId, List<AnswerModel> risposte) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/evaluations/$evaluationId'),
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Password': kAdminPassword,
        },
        body: jsonEncode({
          'risposte': risposte.map((r) => r.toJson()).toList(),
        }),
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
        headers: {'X-Admin-Password': kAdminPassword},
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
        headers: {'X-Admin-Password': kAdminPassword},
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
        headers: {'X-Admin-Password': kAdminPassword},
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
        headers: {'X-Admin-Password': kAdminPassword},
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
}
