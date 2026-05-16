class AnswerModel {
  final String codiceDomanda;
  int punteggio;
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
      punteggio: json['punteggio_totale'] ?? 0,
      numDomande: json['num_domande'] ?? 0,
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
    required this.domini,
    required this.risposte,
  });

  factory AggregatedEvaluation.fromJson(Map<String, dynamic> json) {
    return AggregatedEvaluation(
      idValutazione: json['id_valutazione'] ?? '',
      idPaziente: json['id_paziente'] ?? '',
      idScala: json['id_scala'] ?? '',
      anno: json['anno'] ?? 0,
      dataCompilazione: json['data_compilazione']?.toString() ?? '',
      nomeOperatore: json['nome_operatore'] ?? '',
      nomeIntervistato: json['nome_intervistato'],
      domini: (json['domini'] as List?)
              ?.map((e) => DomainScore.fromJson(e))
              .toList() ??
          [],
      risposte: (json['risposte'] as List?)
              ?.map((e) => AnswerModel.fromJson(e))
              .toList() ??
          [],
    );
  }
}
