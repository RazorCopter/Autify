import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

class ApiService {
  // Dato che questo frontend è servito da Nginx sulla stessa origine e proxy verso backend,
  // possiamo usare un URL relativo o parametrizzato. In dev locale su Flutter web, 
  // potremmo aver bisogno dell'url completo se non passiamo da Nginx.
  // Assumiamo che in produzione sia /api/admin.
  static const String baseUrl = 'https://aut.ghome.it/api/admin';

  Future<bool> uploadProtocolCSV(PlatformFile file) async {
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
}
