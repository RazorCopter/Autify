import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
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
      final response = await http.get(Uri.parse('$baseUrl/scales'));
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
        headers: {'Content-Type': 'application/json'},
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
      final response = await http.delete(Uri.parse('$baseUrl/scales/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Errore eliminazione scala: $e');
      return false;
    }
  }

  Future<String?> getGeminiKey() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/settings'));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['gemini_api_key'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> saveGeminiKey(String key) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': 'global_settings',
          'gemini_api_key': key,
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
      final response = await http.get(Uri.parse('$baseUrl/patients'));
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
        headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
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
      final response = await http.delete(Uri.parse('$baseUrl/patients/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Errore eliminazione paziente: $e');
      return false;
    }
  }

  // --- VALUTAZIONI AGGREGATE ---

  Future<AggregatedEvaluation?> getAggregatedEvaluation(
      String patientId, String scaleId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/evaluations/$patientId/$scaleId'),
      );
      if (response.statusCode == 200) {
        return AggregatedEvaluation.fromJson(jsonDecode(response.body));
      }
      return null;
    } catch (e) {
      print('Errore caricamento valutazione aggregata: $e');
      return null;
    }
  }

  Future<AggregatedEvaluation?> updateEvaluationAnswers(
      String evaluationId, List<AnswerModel> risposte) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/evaluations/$evaluationId'),
        headers: {'Content-Type': 'application/json'},
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

  Future<List<int>?> downloadEvaluationPdf(
      String evaluationId, String chartType) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/evaluations/$evaluationId/pdf?chart_type=$chartType'),
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
}
