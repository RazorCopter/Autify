class Question {
  final String idDomanda;
  final String testoDomanda;
  final String tipoRisposta;

  Question({
    required this.idDomanda,
    required this.testoDomanda,
    required this.tipoRisposta,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      idDomanda: json['id_domanda'],
      testoDomanda: json['testo_domanda'],
      tipoRisposta: json['tipo_risposta'],
    );
  }
}

class Section {
  final String titoloSezione;
  final List<Question> domande;

  Section({
    required this.titoloSezione,
    required this.domande,
  });

  factory Section.fromJson(Map<String, dynamic> json) {
    return Section(
      titoloSezione: json['titolo_sezione'],
      domande: (json['domande'] as List)
          .map((q) => Question.fromJson(q))
          .toList(),
    );
  }
}

class ScaleModel {
  final String id;
  final String nome;
  final String descrizione;
  final List<Section> sezioni;

  ScaleModel({
    required this.id,
    required this.nome,
    required this.descrizione,
    required this.sezioni,
  });

  factory ScaleModel.fromJson(Map<String, dynamic> json) {
    return ScaleModel(
      id: json['id'],
      nome: json['nome'],
      descrizione: json['descrizione'],
      sezioni: (json['sezioni'] as List)
          .map((s) => Section.fromJson(s))
          .toList(),
    );
  }
}
