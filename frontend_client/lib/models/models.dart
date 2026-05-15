class PatientModel {
  final String id;
  final String nome;
  final String cognome;

  PatientModel({required this.id, required this.nome, required this.cognome});

  factory PatientModel.fromJson(Map<String, dynamic> json) {
    return PatientModel(
      id: json['id'] ?? '',
      nome: json['nome'] ?? '',
      cognome: json['cognome'] ?? '',
    );
  }
}

class QuestionModel {
  final String idDomanda;
  final String testoDomanda;
  final String tipoRisposta;

  QuestionModel({required this.idDomanda, required this.testoDomanda, required this.tipoRisposta});

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      idDomanda: json['id_domanda'] ?? '',
      testoDomanda: json['testo_domanda'] ?? '',
      tipoRisposta: json['tipo_risposta'] ?? '',
    );
  }
}

class SectionModel {
  final String titoloSezione;
  final List<QuestionModel> domande;

  SectionModel({required this.titoloSezione, required this.domande});

  factory SectionModel.fromJson(Map<String, dynamic> json) {
    return SectionModel(
      titoloSezione: json['titolo_sezione'] ?? '',
      domande: (json['domande'] as List?)?.map((e) => QuestionModel.fromJson(e)).toList() ?? [],
    );
  }
}

class ScaleModel {
  final String id;
  final String nome;
  final String descrizione;
  final List<SectionModel> sezioni;

  ScaleModel({required this.id, required this.nome, this.descrizione = '', this.sezioni = const []});

  factory ScaleModel.fromJson(Map<String, dynamic> json) {
    return ScaleModel(
      id: json['id'] ?? '',
      nome: json['nome'] ?? '',
      descrizione: json['descrizione'] ?? '',
      sezioni: (json['sezioni'] as List?)?.map((e) => SectionModel.fromJson(e)).toList() ?? [],
    );
  }
}

class AnswerModel {
  final String idDomanda;
  final int valoreRisposta;
  final String? noteOpzionali;

  AnswerModel({required this.idDomanda, required this.valoreRisposta, this.noteOpzionali});

  Map<String, dynamic> toJson() {
    return {
      'id_domanda': idDomanda,
      'valore_risposta': valoreRisposta,
      'note_opzionali': noteOpzionali,
    };
  }
}

class EvaluationModel {
  final String idPaziente;
  final String idScala;
  final int anno;
  final String nomeOperatore;
  final List<AnswerModel> risposte;

  EvaluationModel({
    required this.idPaziente,
    required this.idScala,
    required this.anno,
    required this.nomeOperatore,
    required this.risposte,
  });

  Map<String, dynamic> toJson() {
    return {
      'id_paziente': idPaziente,
      'id_scala': idScala,
      'anno': anno,
      'nome_operatore': nomeOperatore,
      'risposte': risposte.map((e) => e.toJson()).toList(),
    };
  }
}
