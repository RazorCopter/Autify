import '../models/evaluation_model.dart';
import '../models/patient_model.dart';
import 'api_service.dart';

/// Servizio delegato per l'analisi educativa multidimensionale IA.
/// Centralizzato e inoltrato al backend gateway sicuro per evitare l'esposizione di API key.
class GeminiService {
  final ApiService _apiService = const ApiService();

  Future<Map<String, dynamic>> analyzePatientData(
    PatientModel patient,
    List<AggregatedEvaluation> evaluations,
    String? apiKey,
    String? modelName, {
    String? systemPrompt,
    String? notes,
    Map<String, dynamic>? attachment,
    List<Map<String, dynamic>>? historyToInclude,
    Map<String, PsychometricAnalysis?>? analyses,
  }) async {
    return _apiService.analyzePatientData(
      patient: patient,
      evaluations: evaluations,
      systemPrompt: systemPrompt,
      notes: notes,
      attachment: attachment,
      historyToInclude: historyToInclude,
      analyses: analyses,
    );
  }
}
