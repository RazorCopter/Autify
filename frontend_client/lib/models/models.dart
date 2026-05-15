class PatientModel {
  final String id;
  final String nome;
  final String cognome;

  PatientModel({required this.id, required this.nome, required this.cognome});

  factory PatientModel.fromJson(Map<String, dynamic> json) {
    return PatientModel(
      id: json['id'],
      nome: json['nome'],
      cognome: json['cognome'],
    );
  }
}

class ScaleModel {
  final String id;
  final String nome;

  ScaleModel({required this.id, required this.nome});

  factory ScaleModel.fromJson(Map<String, dynamic> json) {
    return ScaleModel(
      id: json['id'],
      nome: json['nome'],
    );
  }
}
