import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/evaluation_model.dart';
import '../models/patient_model.dart';

class GeminiService {
  static const String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta/models';

  /// Invia i dati a Gemini e ritorna il report Markdown
  Future<String> analyzePatientData(
    PatientModel patient,
    List<AggregatedEvaluation> evaluations,
    String apiKey,
    String modelName,
  ) async {
    final url = Uri.parse('$_baseUrl/$modelName:generateContent?key=$apiKey');

    final systemPrompt = '''
Sei il massimo esperto e consulente di supporto specializzato nei percorsi per l'Autismo.
Il tuo compito è analizzare in modo multidimensionale i dati quantitativi e qualitativi estratti dalle scale di valutazione dell'utente.

OBIETTIVO DELL'ANALISI:
1. Valutare l'andamento generale e il profilo dell'utente (punti di forza e aree di supporto nei vari domini).
2. Evidenziare correlazioni significative tra le diverse scale somministrate (es. POS, San Martín).
3. Proporre ipotesi e linee guida per progetti educativi e di supporto customizzati e ritagliati sartorialmente sulle specifiche esigenze dell'utente.

TONO E FORMATTAZIONE:
- Tono: Professionale, rigoroso, empatico, fortemente orientato all'utilità educativa e di supporto.
- Formattazione: Usa il Markdown (titoli, liste, grassetti) per strutturare un referto elegante, chiaro e leggibile.
''';

    final patientData = _serializePatientData(patient, evaluations);

    final payload = {
      "system_instruction": {
        "parts": [
          {"text": systemPrompt}
        ]
      },
      "contents": [
        {
          "parts": [
            {"text": "Ecco i dati estratti dalle valutazioni dell'utente:\n\n$patientData\n\nProcedi con l'analisi multidimensionale globale."}
          ]
        }
      ]
    };

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates'][0]['content']['parts'][0]['text'];
        return text;
      } else {
        throw Exception('Errore API Gemini (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('Impossibile comunicare con Gemini: $e');
    }
  }

  String _serializePatientData(PatientModel patient, List<AggregatedEvaluation> evals) {
    final buffer = StringBuffer();
    buffer.writeln("Dati Anagrafici:");
    buffer.writeln("- ID Utente: ${patient.id}");
    buffer.writeln("- Sesso: ${patient.sesso}");
    if (patient.dataNascita != null) {
      buffer.writeln("- Data di Nascita: ${patient.dataNascita!.split('T')[0]}");
    }
    if (patient.note != null && patient.note!.isNotEmpty) {
      buffer.writeln("- Note Generali: ${patient.note}");
    }

    buffer.writeln("\nCronologia Valutazioni:");
    for (final eval in evals) {
      buffer.writeln("\nScala: ${eval.idScala}");
      buffer.writeln("Data Compilazione: ${eval.dataCompilazione}");
      
      if (eval.domini.isNotEmpty) {
        buffer.writeln("Dettaglio Domini:");
        int totale = 0;
        for (final d in eval.domini) {
          totale += d.punteggio;
          buffer.writeln("  - [${d.codice}] ${d.etichetta}: Punteggio ${d.punteggio}");
        }
        buffer.writeln("Punteggio Totale Stimato: $totale");
      }
    }

    return buffer.toString();
  }
}
