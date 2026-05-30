class PatientModel {
  String id;
  String nome;
  String cognome;
  int? altezza;
  double? peso;
  String? dataNascita;
  String? sesso;
  String? note;
  bool attivo;
  String? ultimoPosCompilato;
  String? ultimoSanMartinCompilato;
  String? ultimoSisCompilato;
  String? ultimaAnalisiIa;

  PatientModel({
    required this.id,
    required this.nome,
    required this.cognome,
    this.altezza,
    this.peso,
    this.dataNascita,
    this.sesso,
    this.note,
    this.attivo = true,
    this.ultimoPosCompilato,
    this.ultimoSanMartinCompilato,
    this.ultimoSisCompilato,
    this.ultimaAnalisiIa,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) {
    return PatientModel(
      id: json['id'],
      nome: json['nome'],
      cognome: json['cognome'],
      altezza: json['altezza'],
      peso: json['peso'] != null ? (json['peso'] as num).toDouble() : null,
      dataNascita: json['data_nascita'],
      sesso: json['sesso'],
      note: json['note'],
      attivo: json['attivo'] ?? true,
      ultimoPosCompilato: json['ultimo_pos_compilato'],
      ultimoSanMartinCompilato: json['ultimo_san_martin_compilato'],
      ultimoSisCompilato: json['ultimo_sis_compilato'],
      ultimaAnalisiIa: json['ultima_analisi_ia'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'nome': nome,
      'cognome': cognome,
      'altezza': altezza,
      'peso': peso,
      'data_nascita': dataNascita,
      'sesso': sesso,
      'note': note,
      'attivo': attivo,
      'ultimo_pos_compilato': ultimoPosCompilato,
      'ultimo_san_martin_compilato': ultimoSanMartinCompilato,
      'ultimo_sis_compilato': ultimoSisCompilato,
      'ultima_analisi_ia': ultimaAnalisiIa,
    };
  }
}
