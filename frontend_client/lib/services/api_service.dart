import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

class ApiService {
  static const String baseUrl = 'https://aut.ghome.it/api/client';

  Future<List<PatientModel>> getPatients() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/patients'));
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((e) => PatientModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Errore caricamento pazienti: $e');
      return [];
    }
  }

  Future<List<ScaleModel>> getScales() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/scales'));
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((e) => ScaleModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('Errore caricamento scale: $e');
      return [];
    }
  }

  Future<ScaleModel?> getScaleById(String scaleId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/scales/$scaleId'));
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
        Uri.parse('$baseUrl/evaluations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(evaluation.toJson()),
      );
      return response.statusCode == 201;
    } catch (e) {
      print('Errore salvataggio valutazione: $e');
      return false;
    }
  }
}
