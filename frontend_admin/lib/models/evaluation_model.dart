int? _parseNullableInt(dynamic value) {
  if (value == null) return null;
  try {
    return num.parse(value.toString()).toInt();
  } catch (_) {
    return null;
  }
}
class AnswerModel {
  final String codiceDomanda;
  dynamic punteggio;
  String? nota;

  AnswerModel({
    required this.codiceDomanda,
    required this.punteggio,
    this.nota,
  });

  factory AnswerModel.fromJson(Map<String, dynamic> json) {
    return AnswerModel(
      codiceDomanda: json['codice_domanda'] ?? '',
      punteggio: json['punteggio'] ?? 0,
      nota: json['nota'],
    );
  }

  Map<String, dynamic> toJson() => {
    'codice_domanda': codiceDomanda,
    'punteggio': punteggio,
    if (nota != null && nota!.isNotEmpty) 'nota': nota,
  };
}

class DomainScore {
  final String codice;
  final String etichetta;
  final int punteggio;
  final int numDomande;

  DomainScore({
    required this.codice,
    required this.etichetta,
    required this.punteggio,
    required this.numDomande,
  });

  factory DomainScore.fromJson(Map<String, dynamic> json) {
    return DomainScore(
      codice: json['codice'] ?? '',
      etichetta: json['etichetta'] ?? '',
      punteggio: _parseNullableInt(json['punteggio_totale']) ?? 0,
      numDomande: _parseNullableInt(json['num_domande']) ?? 0,
    );
  }
}

class DomainAnalysis {
  final String codice;
  final String etichetta;
  final int punteggioDiretto;
  final int? punteggioStandard;
  final int? percentileDominio;
  final String? fascia;
  final int numDomande;

  DomainAnalysis({
    required this.codice,
    required this.etichetta,
    required this.punteggioDiretto,
    this.punteggioStandard,
    this.percentileDominio,
    this.fascia,
    required this.numDomande,
  });

  factory DomainAnalysis.fromJson(Map<String, dynamic> json) {
    return DomainAnalysis(
      codice: json['codice'] ?? '',
      etichetta: json['etichetta'] ?? '',
      punteggioDiretto: _parseNullableInt(json['punteggio_diretto']) ??
          _parseNullableInt(json['punteggio_grezzo']) ??
          0,
      punteggioStandard: _parseNullableInt(json['punteggio_standard']),
      percentileDominio: _parseNullableInt(json['percentile_dominio']) ??
          _parseNullableInt(json['percentile']),
      fascia: json['fascia'] as String?,
      numDomande: _parseNullableInt(json['num_domande']) ?? 0,
    );
  }
}

class PsychometricAnalysis {
  final String idValutazione;
  final String idPaziente;
  final String idScala;
  final String scalaNome;
  final List<DomainAnalysis> domini;
  final int? sommaPunteggiStandard;
  final int? indiceQv;
  final int? percentile;
  final String? fasciaQv;
  final bool? alertMedico;
  final bool? alertComportamentale;
  final List<Map<String, dynamic>>? sezione2Top4;

  PsychometricAnalysis({
    required this.idValutazione,
    required this.idPaziente,
    required this.idScala,
    required this.scalaNome,
    required this.domini,
    this.sommaPunteggiStandard,
    this.indiceQv,
    this.percentile,
    this.fasciaQv,
    this.alertMedico,
    this.alertComportamentale,
    this.sezione2Top4,
  });

  factory PsychometricAnalysis.fromJson(Map<String, dynamic> json) {
    return PsychometricAnalysis(
      idValutazione: json['id_valutazione'] ?? '',
      idPaziente: json['id_paziente'] ?? '',
      idScala: json['id_scala'] ?? '',
      scalaNome: json['scala_nome'] ?? '',
      sommaPunteggiStandard: _parseNullableInt(json['somma_punteggi_standard']),
      indiceQv: _parseNullableInt(json['indice_qv']) ?? _parseNullableInt(json['indice_sis']),
      percentile: _parseNullableInt(json['percentile']),
      fasciaQv: (json['fascia_qv'] ?? json['classificazione_intensita']) as String?,
      alertMedico: json['alert_medico'] as bool?,
      alertComportamentale: json['alert_comportamentale'] as bool?,
      sezione2Top4: (json['sezione_2_top4'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      domini: (json['domini'] as List?)
              ?.map((e) => DomainAnalysis.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class AggregatedEvaluation {
  final String idValutazione;
  final String idPaziente;
  final String idScala;
  final int anno;
  final String dataCompilazione;
  final String nomeOperatore;
  final String? nomeIntervistato;
  final Map<String, dynamic>? demographics;
  final List<DomainScore> domini;
  final List<AnswerModel> risposte;

  AggregatedEvaluation({
    required this.idValutazione,
    required this.idPaziente,
    required this.idScala,
    required this.anno,
    required this.dataCompilazione,
    required this.nomeOperatore,
    this.nomeIntervistato,
    this.demographics,
    required this.domini,
    required this.risposte,
  });

  factory AggregatedEvaluation.fromJson(Map<String, dynamic> json) {
    return AggregatedEvaluation(
      idValutazione: json['id_valutazione'] ?? '',
      idPaziente: json['id_paziente'] ?? '',
      idScala: json['id_scala'] ?? '',
      anno: _parseNullableInt(json['anno']) ?? 0,
      dataCompilazione: json['data_compilazione']?.toString() ?? '',
      nomeOperatore: json['nome_operatore'] ?? '',
      nomeIntervistato: json['nome_intervistato'] as String?,
      demographics: json['demographics'] != null
          ? Map<String, dynamic>.from(json['demographics'] as Map)
          : null,
      domini: (json['domini'] as List?)
              ?.map((e) => DomainScore.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      risposte: (json['risposte'] as List?)
              ?.map((e) => AnswerModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class EvaluationModel {
  final String idPaziente;
  final String idScala;
  final int anno;
  final String nomeOperatore;
  final String? nomeIntervistato;
  final String? dataCompilazione;
  final Map<String, dynamic>? demographics;
  final List<AnswerModel> risposte;

  EvaluationModel({
    required this.idPaziente,
    required this.idScala,
    required this.anno,
    required this.nomeOperatore,
    this.nomeIntervistato,
    this.dataCompilazione,
    this.demographics,
    required this.risposte,
  });

  Map<String, dynamic> toJson() {
    return {
      'id_paziente': idPaziente,
      'id_scala': idScala,
      'anno': anno,
      'nome_operatore': nomeOperatore,
      if (nomeIntervistato != null) 'nome_intervistato': nomeIntervistato,
      if (dataCompilazione != null) 'data_compilazione': dataCompilazione,
      if (demographics != null) 'demographics': demographics,
      'risposte': risposte.map((e) => e.toJson()).toList(),
    };
  }
}
