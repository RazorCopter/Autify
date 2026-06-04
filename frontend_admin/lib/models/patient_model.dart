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
  String? ultimoOgvaCompilato;
  String? ultimoSabsCompilato;
  String? ultimoOsoCompilato;
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
    this.ultimoOgvaCompilato,
    this.ultimoSabsCompilato,
    this.ultimoOsoCompilato,
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
      ultimoOgvaCompilato: json['ultimo_ogva_compilato'],
      ultimoSabsCompilato: json['ultimo_sabs_compilato'],
      ultimoOsoCompilato: json['ultimo_oso_compilato'],
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
      'ultimo_ogva_compilato': ultimoOgvaCompilato,
      'ultimo_sabs_compilato': ultimoSabsCompilato,
      'ultimo_oso_compilato': ultimoOsoCompilato,
      'ultima_analisi_ia': ultimaAnalisiIa,
    };
  }
}

class PaginatedPatientsResult {
  final List<PatientModel> items;
  final int total;
  final int page;
  final int pageSize;

  const PaginatedPatientsResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory PaginatedPatientsResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return PaginatedPatientsResult(
      items: rawItems.map((e) => PatientModel.fromJson(e as Map<String, dynamic>)).toList(),
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? 50,
    );
  }

  static PaginatedPatientsResult empty() => const PaginatedPatientsResult(
        items: [],
        total: 0,
        page: 1,
        pageSize: 50,
      );

  int get totalPages => pageSize > 0 ? (total / pageSize).ceil() : 1;
  bool get hasNextPage => page < totalPages;
  bool get hasPrevPage => page > 1;
}
