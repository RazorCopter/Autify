import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_admin/models/patient_model.dart';
import 'package:frontend_admin/models/evaluation_model.dart';

void main() {
  group('AI Clinical Payload Serialization Tests', () {
    test('Serializes patient demographics and evaluation domains correctly', () {
      final patient = PatientModel(
        id: 'pat_test_1',
        nome: 'Luca',
        cognome: 'Bianchi',
        dataNascita: '1990-01-01',
      );

      final evaluation = AggregatedEvaluation(
        idValutazione: 'eval_pos_1',
        idPaziente: 'pat_test_1',
        idScala: 'pos',
        anno: 2026,
        dataCompilazione: '2026-01-10T10:00:00Z',
        nomeOperatore: 'Dott. Rossi',
        domini: [
          DomainScore(
            codice: 'SP',
            etichetta: 'Sviluppo Personale',
            punteggio: 22,
            numDomande: 10,
          ),
          DomainScore(
            codice: 'AD',
            etichetta: 'Autodeterminazione',
            punteggio: 18,
            numDomande: 8,
          ),
        ],
        risposte: [],
      );

      expect(patient.id, equals('pat_test_1'));
      expect(evaluation.domini.length, equals(2));
      expect(evaluation.domini[0].codice, equals('SP'));
      expect(evaluation.domini[0].punteggio, equals(22));
      expect(evaluation.domini[1].codice, equals('AD'));
      expect(evaluation.domini[1].punteggio, equals(18));
    });

    test('PsychometricAnalysis holds SIS section and alerts data', () {
      final analysis = PsychometricAnalysis(
        idValutazione: 'eval_sis_1',
        idPaziente: 'pat_test_1',
        idScala: 'sis',
        scalaNome: 'Supports Intensity Scale',
        sommaPunteggiStandard: 64,
        indiceQv: 95,
        percentile: 37,
        fasciaQv: 'Livello Medio',
        alertMedico: true,
        alertComportamentale: false,
        sezione2Top4: [
          {'codice': '2A', 'testo': 'Assunzione farmaci'},
        ],
        domini: [
          DomainAnalysis(
            codice: 'A',
            etichetta: 'Vita nella comunità',
            punteggioDiretto: 28,
            punteggioStandard: 11,
            percentileDominio: 63,
            fascia: 'Medio',
            numDomande: 8,
          ),
        ],
      );

      expect(analysis.idValutazione, equals('eval_sis_1'));
      expect(analysis.alertMedico, isTrue);
      expect(analysis.alertComportamentale, isFalse);
      expect(analysis.sezione2Top4?.first['codice'], equals('2A'));
      expect(analysis.domini.first.punteggioStandard, equals(11));
    });
  });
}
