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
Sei il massimo esperto clinico e ricercatore specializzato nei Disturbi dello Spettro Autistico (ASD) a livello mondiale.
Il tuo compito è analizzare in modo multidimensionale i dati quantitativi e qualitativi estratti dalle scale di valutazione del paziente.

OBIETTIVO DELL'ANALISI:
1. Valutare l'andamento clinico e il profilo dell'utente (punti di forza e aree di severità nei vari domini).
2. Evidenziare correlazioni significative tra le diverse scale somministrate (es. POS, San Martín).
3. Proporre ipotesi e linee guida per progetti terapeutici/educativi customizzati e ritagliati sartorialmente sulle specifiche esigenze dell'utente.

TONO E FORMATTAZIONE:
- Tono: Professionale, rigoroso, empatico, fortemente orientato all'utilità clinica ed educativa.
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
            {"text": "Ecco i dati clinici estratti dalle valutazioni del paziente:\n\n$patientData\n\nProcedi con l'analisi clinica globale."}
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
    buffer.writeln("- ID Paziente: ${patient.id}");
    buffer.writeln("- Sesso: ${patient.sesso}");
    if (patient.dataNascita != null) {
      buffer.writeln("- Data di Nascita: ${patient.dataNascita!.toIso8601String().split('T')[0]}");
    }
    if (patient.note != null && patient.note!.isNotEmpty) {
      buffer.writeln("- Note Cliniche: ${patient.note}");
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
