import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/scale_model.dart';
import '../models/user_model.dart';

class ApiService {
  // Puntamento all'ambiente di produzione
  static const String baseUrl = 'https://aut.ghome.it';

  // --- SCALE ---
  Future<List<ScaleModel>> getScales() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/scales'));
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((json) => ScaleModel.fromJson(json)).toList();
      } else {
        throw Exception('Errore nel caricamento delle scale');
      }
    } catch (e) {
      throw Exception('Errore di connessione: $e');
    }
  }

  // --- VALUTAZIONI ---
  Future<List<EvaluationModel>> getEvaluations(String idPatient, int year) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/patients/$idPatient/evaluations/$year'));
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((json) => EvaluationModel.fromJson(json)).toList();
      } else {
        throw Exception('Errore nel caricamento dello storico');
      }
    } catch (e) {
      throw Exception('Errore di connessione: $e');
    }
  }

  Future<bool> createEvaluation(EvaluationModel evaluation) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/evaluations'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(evaluation.toJson()),
      );
      return response.statusCode == 201;
    } catch (e) {
      throw Exception('Errore durante il salvataggio: $e');
    }
  }

  // --- UTENTI ---
  Future<List<UserModel>> getUsers() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/users'));
      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        return body.map((json) => UserModel.fromJson(json)).toList();
      } else {
        throw Exception('Errore nel caricamento utenti');
      }
    } catch (e) {
      throw Exception('Errore di connessione: $e');
    }
  }

  Future<bool> createUser(UserModel user) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(user.toJson()),
      );
      return response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateUser(UserModel user) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/users/${user.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(user.toJson()),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteUser(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/users/$id'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
