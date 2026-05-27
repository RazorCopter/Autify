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

class OptionModel {
  final String testoRisposta;
  final int punteggio;
  final String? descrizione;

  OptionModel({required this.testoRisposta, required this.punteggio, this.descrizione});

  factory OptionModel.fromJson(Map<String, dynamic> json) {
    return OptionModel(
      testoRisposta: json['testo_risposta'] ?? '',
      punteggio: json['punteggio'] ?? 0,
      descrizione: json['descrizione'],
    );
  }
}

class QuestionModel {
  final String idDomanda;
  final String? codice;
  final String testoDomanda;
  final String? note;
  final List<OptionModel> opzioni;

  QuestionModel({required this.idDomanda, this.codice, required this.testoDomanda, this.note, required this.opzioni});

  factory QuestionModel.fromJson(Map<String, dynamic> json) {
    return QuestionModel(
      idDomanda: json['id_domanda'] ?? '',
      codice: json['codice'],
      testoDomanda: json['testo_domanda'] ?? '',
      note: json['note'],
      opzioni: (json['opzioni'] as List?)?.map((e) => OptionModel.fromJson(e)).toList() ?? [],
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
  final String codiceDomanda;
  final dynamic punteggio;
  final String? nota;

  AnswerModel({required this.codiceDomanda, required this.punteggio, this.nota});

  Map<String, dynamic> toJson() {
    return {
      'codice_domanda': codiceDomanda,
      'punteggio': punteggio,
      if (nota != null && nota!.isNotEmpty) 'nota': nota,
    };
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
