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
}
