class Option {
  final String testoRisposta;
  final int punteggio;
  final String? descrizione;

  Option({required this.testoRisposta, required this.punteggio, this.descrizione});

  factory Option.fromJson(Map<String, dynamic> json) {
    return Option(
      testoRisposta: json['testo_risposta'] ?? '',
      punteggio: json['punteggio'] ?? 0,
      descrizione: json['descrizione'],
    );
  }

  Map<String, dynamic> toJson() => {
    'testo_risposta': testoRisposta,
    'punteggio': punteggio,
    if (descrizione != null) 'descrizione': descrizione,
  };
}

class Question {
  final String idDomanda;
  final String? codice;
  final String testoDomanda;
  final String? note;
  final String tipo;
  final List<Map<String, dynamic>>? sottodomande;
  final List<Option> opzioni;

  Question({
    required this.idDomanda,
    this.codice,
    required this.testoDomanda,
    this.note,
    this.tipo = 'likert',
    this.sottodomande,
    required this.opzioni,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      idDomanda: json['id_domanda'],
      codice: json['codice'],
      testoDomanda: json['testo_domanda'],
      note: json['note'],
      tipo: json['tipo'] ?? 'likert',
      sottodomande: json['sottodomande'] != null ? List<Map<String, dynamic>>.from(json['sottodomande']) : null,
      opzioni: (json['opzioni'] as List?)?.map((e) => Option.fromJson(e)).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id_domanda': idDomanda,
    'codice': codice,
    'testo_domanda': testoDomanda,
    if (note != null) 'note': note,
    'tipo': tipo,
    if (sottodomande != null) 'sottodomande': sottodomande,
    'opzioni': opzioni.map((e) => e.toJson()).toList(),
  };
}

class Section {
  final String? codiceSezione;
  final String titoloSezione;
  final String? descrizioneSezione;
  final List<Question> domande;

  Section({
    this.codiceSezione,
    required this.titoloSezione,
    this.descrizioneSezione,
    required this.domande,
  });

  factory Section.fromJson(Map<String, dynamic> json) {
    return Section(
      codiceSezione: json['codice_sezione'],
      titoloSezione: json['titolo_sezione'] ?? '',
      descrizioneSezione: json['descrizione_sezione'],
      domande: (json['domande'] as List)
          .map((q) => Question.fromJson(q))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (codiceSezione != null) 'codice_sezione': codiceSezione,
    'titolo_sezione': titoloSezione,
    if (descrizioneSezione != null) 'descrizione_sezione': descrizioneSezione,
    'domande': domande.map((q) => q.toJson()).toList(),
  };
}

class ScaleModel {
  final String id;
  String nome;
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

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': nome,
    'descrizione': descrizione,
    'sezioni': sezioni.map((s) => s.toJson()).toList(),
  };
}
