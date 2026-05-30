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
    String modelName, {
    String? systemPrompt,
    String? notes,
    Map<String, dynamic>? attachment, // { "bytes": Uint8List, "extension": "pdf" }
    List<Map<String, dynamic>>? historyToInclude,
    Map<String, PsychometricAnalysis?>? analyses,
  }) async {
    final url = Uri.parse('$_baseUrl/$modelName:generateContent?key=$apiKey');

    final defaultPrompt = '''
Sei il massimo esperto e consulente di supporto specializzato nei percorsi per l'Autismo e disabilità intellettive/evolutive.
Il tuo compito è analizzare in modo multidimensionale i dati quantitativi e qualitativi estratti dalle scale di valutazione dell'utente.

OBIETTIVO DELL'ANALISI:
1. Valutare l'andamento generale e il profilo dell'utente (punti di forza e aree di supporto nei vari domini).
2. Evidenziare correlazioni significative tra le diverse scale somministrate (es. POS, San Martín, SIS - Supports Intensity Scale).
3. Per la scala SIS, analizzare approfonditamente l'intensità dei bisogni di supporto (Sezione 1 - Domini A-F), le priorità di tutela (Sezione 2) ed i bisogni eccezionali/alert (Sezione 3).
4. Incrociare tutti i dati forniti, incluse le note aggiuntive e gli eventuali allegati documentali.
5. Proporre ipotesi e linee guida per progetti educativi e di supporto customizzati e ritagliati sartorialmente sulle specifiche esigenze dell'utente.
6. Riportare in forma di relazione chiara e coerente quanto emerge dall'incrocio di tutti i dati (scale, note, allegato).

TONO E FORMATTAZIONE:
- Tono: Professionale, rigoroso, empatico, fortemente orientato all'utilità educativa e di supporto.
- Formattazione: Usa il Markdown (titoli, lists, grassetti) per strutturare un referto elegante, chiaro e leggibile.
''';

    final activeSystemPrompt = (systemPrompt != null && systemPrompt.trim().isNotEmpty) ? systemPrompt : defaultPrompt;

    final patientData = _serializePatientData(patient, evaluations, analyses);
    final String currentFormattedDate = "${DateTime.now().toLocal().day.toString().padLeft(2, '0')}/${DateTime.now().toLocal().month.toString().padLeft(2, '0')}/${DateTime.now().toLocal().year}";
    String promptText = "DATA ODIERNA DI COMPILAZIONE DELLA RELAZIONE: $currentFormattedDate. Usa tassativamente questa data ($currentFormattedDate) come data di redazione e generazione del documento, senza inventare o allucinare altre date (future o passate) nei testi generati.\n\nEcco i dati estratti dalle valutazioni dell'utente:\n\n$patientData\n\n";
    
    if (historyToInclude != null && historyToInclude.isNotEmpty) {
      promptText += "STORICO ANALISI E SINTESI PRECEDENTI DELL'UTENTE (utilizzalo per valutare l'evoluzione nel tempo e garantire la continuità dei supporti):\n";
      for (final hist in historyToInclude) {
        final ts = hist['timestamp']?.toString().split('T')[0] ?? '';
        final n = (hist['notes'] != null && hist['notes'].toString().trim().isNotEmpty) ? " (Note: ${hist['notes']})" : "";
        promptText += "\n--- Sintesi del $ts$n ---\n${hist['report']}\n";
      }
      promptText += "\n";
    }

    if (notes != null && notes.trim().isNotEmpty) {
      promptText += "NOTE AGGIUNTIVE FORNITE DALL'OPERATORE:\n$notes\n\n";
    }
    promptText += "Procedi con l'analisi multidimensionale globale incrociando tutti i dati forniti (comprese le valutazioni attuale, lo storico precedente, le note e gli allegati).";

    final parts = <Map<String, dynamic>>[
      {"text": promptText}
    ];

    if (attachment != null) {
      final ext = attachment['extension']?.toString().toLowerCase();
      String mimeType = 'application/octet-stream';
      if (ext == 'pdf') mimeType = 'application/pdf';
      else if (ext == 'txt') mimeType = 'text/plain';
      else if (ext == 'png') mimeType = 'image/png';
      else if (ext == 'jpg' || ext == 'jpeg') mimeType = 'image/jpeg';
      
      parts.add({
        "inlineData": {
          "mimeType": mimeType,
          "data": base64Encode(attachment['bytes'])
        }
      });
    }

    final payload = {
      "system_instruction": {
        "parts": [
          {"text": activeSystemPrompt}
        ]
      },
      "contents": [
        {
          "parts": parts
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

  String _serializePatientData(
    PatientModel patient,
    List<AggregatedEvaluation> evals,
    Map<String, PsychometricAnalysis?>? analyses,
  ) {
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
      final isSis = eval.idScala.toLowerCase().contains('sis');
      buffer.writeln("\nScala: ${eval.idScala} (${isSis ? 'Supports Intensity Scale' : 'Standard QV'})");
      buffer.writeln("Data Compilazione: ${eval.dataCompilazione}");
      
      final analysis = analyses?[eval.idScala];
      
      if (isSis) {
        // SIS Specific Serialization
        if (analysis != null) {
          buffer.writeln("Indici Globali SIS:");
          buffer.writeln("  - Somma dei Punteggi Standard: ${analysis.sommaPunteggiStandard ?? 'N/D'}");
          buffer.writeln("  - Indice SIS Globale: ${analysis.indiceQv ?? 'N/D'}");
          buffer.writeln("  - Percentile Globale SIS: ${analysis.percentile != null ? '${analysis.percentile}°' : 'N/D'}");
          buffer.writeln("  - Classificazione dell'Intensità dei Supporti: ${analysis.fasciaQv ?? 'N/D'}");
          
          if (analysis.domini.isNotEmpty) {
            buffer.writeln("Sottoscale di Supporto (Sezione 1 - Domini A-F):");
            for (final d in analysis.domini) {
              buffer.writeln("  - [${d.codice}] ${d.etichetta}:");
              buffer.writeln("    * Punteggio Grezzo: ${d.punteggioDiretto}");
              buffer.writeln("    * Punteggio Standard: ${d.punteggioStandard ?? 'N/D'}");
              buffer.writeln("    * Percentile di Dominio: ${d.percentileDominio != null ? '${d.percentileDominio}°' : 'N/D'}");
            }
          }
          
          if (analysis.sezione2Top4 != null && analysis.sezione2Top4!.isNotEmpty) {
            buffer.writeln("Sezione 2 - Top 4 Priorità di Tutela e Sostegno:");
            for (final p in analysis.sezione2Top4!) {
              buffer.writeln("  - Item ${p['id']}: Punteggio di Priorità ${p['punteggio_grezzo']}");
            }
          }
          
          buffer.writeln("Sezione 3 - Alert e Bisogni Eccezionali:");
          buffer.writeln("  - Alert Medico (Sezione 3A): ${analysis.alertMedico == true ? 'SÌ (Presenza di bisogni medici eccezionali)' : 'NO'}");
          buffer.writeln("  - Alert Comportamentale (Sezione 3B): ${analysis.alertComportamentale == true ? 'SÌ (Presenza di bisogni comportamentali eccezionali)' : 'NO'}");
        } else {
          buffer.writeln("  * Dati analitici non ancora calcolati per la scala SIS.");
        }
      } else {
        // Standard (POS, San Martín)
        if (eval.domini.isNotEmpty) {
          buffer.writeln("Dettaglio Domini:");
          int totale = 0;
          for (final d in eval.domini) {
            totale += d.punteggio;
            buffer.writeln("  - [${d.codice}] ${d.etichetta}: Punteggio ${d.punteggio}");
          }
          buffer.writeln("Punteggio Totale Stimato: $totale");
        }
        if (analysis != null) {
          buffer.writeln("Indici Analitici:");
          buffer.writeln("  - Somma Punteggi Standard: ${analysis.sommaPunteggiStandard ?? 'N/D'}");
          buffer.writeln("  - Indice QV: ${analysis.indiceQv ?? 'N/D'}");
          buffer.writeln("  - Percentile: ${analysis.percentile != null ? '${analysis.percentile}°' : 'N/D'}");
          buffer.writeln("  - Fascia QV: ${analysis.fasciaQv ?? 'N/D'}");
        }
      }
    }

    return buffer.toString();
  }
}
