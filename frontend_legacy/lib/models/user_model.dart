class UserModel {
  final String? id;
  final String nome;
  final String cognome;
  final String dataNascita;
  final String codiceFiscale;
  final String? note;

  UserModel({
    this.id,
    required this.nome,
    required this.cognome,
    required this.dataNascita,
    required this.codiceFiscale,
    this.note,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'nome': nome,
      'cognome': cognome,
      'data_nascita': dataNascita,
      'codice_fiscale': codiceFiscale,
      'note': note,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      nome: json['nome'],
      cognome: json['cognome'],
      dataNascita: json['data_nascita'],
      codiceFiscale: json['codice_fiscale'],
      note: json['note'],
    );
  }
}
