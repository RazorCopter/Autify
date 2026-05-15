class Answer {
  final String idDomanda;
  final dynamic valoreRisposta; // Usiamo dynamic per supportare int (rating), bool, o List
  final String? noteOpzionali;

  Answer({
    required this.idDomanda,
    required this.valoreRisposta,
    this.noteOpzionali,
  });

  Map<String, dynamic> toJson() {
    return {
      'id_domanda': idDomanda,
      'valore_risposta': valoreRisposta,
      if (noteOpzionali != null && noteOpzionali!.isNotEmpty)
        'note_opzionali': noteOpzionali,
    };
  }

  factory Answer.fromJson(Map<String, dynamic> json) {
    return Answer(
      idDomanda: json['id_domanda'],
      valoreRisposta: json['valore_risposta'],
      noteOpzionali: json['note_opzionali'],
    );
  }
}

class EvaluationModel {
  final String? idValutazione;
  final String idPaziente;
  final int anno;
  final String idScala;
  final String? dataCompilazione;
  final String nomeOperatore;
  final List<Answer> risposte;

  EvaluationModel({
    this.idValutazione,
    required this.idPaziente,
    required this.anno,
    required this.idScala,
    this.dataCompilazione,
    required this.nomeOperatore,
    required this.risposte,
  });

  Map<String, dynamic> toJson() {
    return {
      if (idValutazione != null) 'id_valutazione': idValutazione,
      'id_paziente': idPaziente,
      'anno': anno,
      'id_scala': idScala,
      if (dataCompilazione != null) 'data_compilazione': dataCompilazione,
      'nome_operatore': nomeOperatore,
      'risposte': risposte.map((r) => r.toJson()).toList(),
    };
  }

  factory EvaluationModel.fromJson(Map<String, dynamic> json) {
    return EvaluationModel(
      idValutazione: json['id_valutazione'],
      idPaziente: json['id_paziente'],
      anno: json['anno'],
      idScala: json['id_scala'],
      dataCompilazione: json['data_compilazione'],
      nomeOperatore: json['nome_operatore'],
      risposte: (json['risposte'] as List)
          .map((r) => Answer.fromJson(r))
          .toList(),
    );
  }
}
