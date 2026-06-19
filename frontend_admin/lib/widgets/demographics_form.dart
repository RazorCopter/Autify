import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Dati socio-demografici raccolti dal form San Martín.
/// La struttura rispecchia esattamente il campo [EvaluationModel.demographics].
class DemographicsData {
  final String? livelloAssistenza;
  final String? livelloDipendenza;
  final int? percentualeDisabilita;
  final int? annoCertificato;
  final bool disFisica;
  final bool limArtiSuperiori;
  final bool limArtiInferiori;
  final bool disSensoriale;
  final bool uditoSordita;
  final bool visiva;
  final bool paralisiCerebrale;
  final bool epilessia;
  final bool saluteMentale;
  final bool spettroAutistico;
  final bool sindromeDown;
  final bool graviProblemiSalute;
  final bool disturbiCondotta;
  final String altroCondizioni;
  final String inf1Nome;
  final int? inf1Anni;
  final int? inf1Mesi;
  final String? inf1Frequenza;
  final String? inf1Relazione;
  final String inf1RelazioneAltro;
  final bool inf2Abilitato;
  final String inf2Nome;
  final int? inf2Anni;
  final int? inf2Mesi;
  final String? inf2Frequenza;
  final String? inf2Relazione;
  final String inf2RelazioneAltro;

  const DemographicsData({
    this.livelloAssistenza,
    this.livelloDipendenza,
    this.percentualeDisabilita,
    this.annoCertificato,
    this.disFisica = false,
    this.limArtiSuperiori = false,
    this.limArtiInferiori = false,
    this.disSensoriale = false,
    this.uditoSordita = false,
    this.visiva = false,
    this.paralisiCerebrale = false,
    this.epilessia = false,
    this.saluteMentale = false,
    this.spettroAutistico = false,
    this.sindromeDown = false,
    this.graviProblemiSalute = false,
    this.disturbiCondotta = false,
    this.altroCondizioni = '',
    required this.inf1Nome,
    this.inf1Anni,
    this.inf1Mesi,
    this.inf1Frequenza,
    this.inf1Relazione,
    this.inf1RelazioneAltro = '',
    this.inf2Abilitato = false,
    this.inf2Nome = '',
    this.inf2Anni,
    this.inf2Mesi,
    this.inf2Frequenza,
    this.inf2Relazione,
    this.inf2RelazioneAltro = '',
  });

  /// Serializza nel formato atteso da [EvaluationModel.demographics].
  Map<String, dynamic> toJson() => {
        'persona': {
          'livello_assistenza': livelloAssistenza,
          'livello_dipendenza': livelloDipendenza,
          'percentuale_disabilita': percentualeDisabilita,
          'anno_certificato': annoCertificato,
          'condizioni': {
            'disabilita_fisica': disFisica,
            'lim_arti_superiori': limArtiSuperiori,
            'lim_arti_inferiori': limArtiInferiori,
            'disabilita_sensoriale': disSensoriale,
            'udito_sordita': uditoSordita,
            'visiva': visiva,
            'paralisi_cerebrale': paralisiCerebrale,
            'epilessia': epilessia,
            'salute_mentale': saluteMentale,
            'spettro_autistico': spettroAutistico,
            'sindrome_down': sindromeDown,
            'gravi_problemi_salute': graviProblemiSalute,
            'disturbi_condotta': disturbiCondotta,
            'altro_specifica': altroCondizioni,
          }
        },
        'informatore1': {
          'nome_cognome': inf1Nome,
          'contatto_anni': inf1Anni,
          'contatto_mesi': inf1Mesi,
          'frequenza_contatto': inf1Frequenza,
          'relazione': inf1Relazione,
          'relazione_altro': inf1RelazioneAltro,
        },
        'informatore2': inf2Abilitato
            ? {
                'nome_cognome': inf2Nome,
                'contatto_anni': inf2Anni,
                'contatto_mesi': inf2Mesi,
                'frequenza_contatto': inf2Frequenza,
                'relazione': inf2Relazione,
                'relazione_altro': inf2RelazioneAltro,
              }
            : null,
      };
}

/// Form dati socio-demografici per la Scala San Martín.
///
/// Gestisce autonomamente tutti i controller e il proprio stato.
/// Quando l'utente preme "Procedi", chiama [onCompleted] con i dati validati
/// e richiama [onFocusRequested] per restituire il focus al wizard.
class DemographicsForm extends StatefulWidget {
  final void Function(DemographicsData data) onCompleted;
  final VoidCallback? onFocusRequested;

  const DemographicsForm({
    super.key,
    required this.onCompleted,
    this.onFocusRequested,
  });

  @override
  State<DemographicsForm> createState() => _DemographicsFormState();
}

class _DemographicsFormState extends State<DemographicsForm> {
  final _formKey = GlobalKey<FormState>();

  // Persona esaminata
  String? _livelloAssistenza;
  String? _livelloDipendenza;
  final _percController = TextEditingController();
  final _annoController = TextEditingController();

  // Condizioni (checkboxes)
  bool _disFisica = false;
  bool _limArtiSuperiori = false;
  bool _limArtiInferiori = false;
  bool _disSensoriale = false;
  bool _uditoSordita = false;
  bool _visiva = false;
  bool _paralisiCerebrale = false;
  bool _epilessia = false;
  bool _saluteMentale = false;
  bool _spettroAutistico = false;
  bool _sindromeDown = false;
  bool _graviProblemiSalute = false;
  bool _disturbiCondotta = false;
  final _altroCondizioniController = TextEditingController();

  // Informatore 1
  final _inf1NomeController = TextEditingController();
  final _inf1AnniController = TextEditingController();
  final _inf1MesiController = TextEditingController();
  String? _inf1Frequenza;
  String? _inf1Relazione;
  final _inf1RelazioneAltroController = TextEditingController();

  // Informatore 2
  bool _inf2Abilitato = false;
  final _inf2NomeController = TextEditingController();
  final _inf2AnniController = TextEditingController();
  final _inf2MesiController = TextEditingController();
  String? _inf2Frequenza;
  String? _inf2Relazione;
  final _inf2RelazioneAltroController = TextEditingController();

  @override
  void dispose() {
    _percController.dispose();
    _annoController.dispose();
    _altroCondizioniController.dispose();
    _inf1NomeController.dispose();
    _inf1AnniController.dispose();
    _inf1MesiController.dispose();
    _inf1RelazioneAltroController.dispose();
    _inf2NomeController.dispose();
    _inf2AnniController.dispose();
    _inf2MesiController.dispose();
    _inf2RelazioneAltroController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Correggi gli errori nel modulo prima di procedere')),
      );
      return;
    }

    final data = DemographicsData(
      livelloAssistenza: _livelloAssistenza,
      livelloDipendenza: _livelloDipendenza,
      percentualeDisabilita: int.tryParse(_percController.text),
      annoCertificato: int.tryParse(_annoController.text),
      disFisica: _disFisica,
      limArtiSuperiori: _limArtiSuperiori,
      limArtiInferiori: _limArtiInferiori,
      disSensoriale: _disSensoriale,
      uditoSordita: _uditoSordita,
      visiva: _visiva,
      paralisiCerebrale: _paralisiCerebrale,
      epilessia: _epilessia,
      saluteMentale: _saluteMentale,
      spettroAutistico: _spettroAutistico,
      sindromeDown: _sindromeDown,
      graviProblemiSalute: _graviProblemiSalute,
      disturbiCondotta: _disturbiCondotta,
      altroCondizioni: _altroCondizioniController.text,
      inf1Nome: _inf1NomeController.text,
      inf1Anni: int.tryParse(_inf1AnniController.text),
      inf1Mesi: int.tryParse(_inf1MesiController.text),
      inf1Frequenza: _inf1Frequenza,
      inf1Relazione: _inf1Relazione,
      inf1RelazioneAltro: _inf1RelazioneAltroController.text,
      inf2Abilitato: _inf2Abilitato,
      inf2Nome: _inf2NomeController.text,
      inf2Anni: int.tryParse(_inf2AnniController.text),
      inf2Mesi: int.tryParse(_inf2MesiController.text),
      inf2Frequenza: _inf2Frequenza,
      inf2Relazione: _inf2Relazione,
      inf2RelazioneAltro: _inf2RelazioneAltroController.text,
    );

    widget.onCompleted(data);
    widget.onFocusRequested?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 650),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.analytics_outlined, size: 48, color: AppTheme.primaryColor),
                const SizedBox(height: 16),
                const Text(
                  'Dati Socio-Demografici',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Informazioni richieste dal protocollo Scala San Martín',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 24),

                // --- SEZIONE 1: PERSONA ESAMINATA ---
                _buildSectionHeader('DATI DELLA PERSONA ESAMINATA'),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: _livelloAssistenza,
                  decoration: AppTheme.inputDecoration('Livello di necessità di assistenza', Icons.assistant_direction_outlined),
                  items: const [
                    DropdownMenuItem(value: 'Esteso', child: Text('Esteso')),
                    DropdownMenuItem(value: 'Generalizzato', child: Text('Generalizzato')),
                  ],
                  onChanged: (val) => setState(() => _livelloAssistenza = val),
                  validator: (val) => val == null ? 'Campo richiesto' : null,
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: _livelloDipendenza,
                  decoration: AppTheme.inputDecoration('Livello di dipendenza riconosciuto', Icons.accessible_forward_outlined),
                  items: const [
                    DropdownMenuItem(value: 'Grado I', child: Text('Grado I - Dipendenza moderata')),
                    DropdownMenuItem(value: 'Grado II', child: Text('Grado II - Dipendenza grave')),
                    DropdownMenuItem(value: 'Grado III', child: Text('Grado III - Dipendenza elevata')),
                  ],
                  onChanged: (val) => setState(() => _livelloDipendenza = val),
                  validator: (val) => val == null ? 'Campo richiesto' : null,
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _percController,
                        keyboardType: TextInputType.number,
                        decoration: AppTheme.inputDecoration('Disabilità (%)', Icons.percent),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Richiesto';
                          final n = int.tryParse(val);
                          if (n == null || n < 0 || n > 100) return '0-100';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _annoController,
                        keyboardType: TextInputType.number,
                        decoration: AppTheme.inputDecoration('Anno certificato', Icons.calendar_today_outlined),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Richiesto';
                          final n = int.tryParse(val);
                          if (n == null || n < 1900 || n > DateTime.now().year) return 'Anno non valido';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                const Text(
                  'Altre condizioni della persona esaminata:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),

                _buildCheckbox('Disabilità fisica', _disFisica, (val) {
                  setState(() {
                    _disFisica = val ?? false;
                    if (!_disFisica) {
                      _limArtiSuperiori = false;
                      _limArtiInferiori = false;
                    }
                  });
                }),
                if (_disFisica) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 24.0, bottom: 8),
                    child: Column(
                      children: [
                        _buildCheckbox('Limitazioni funzionali degli arti superiori', _limArtiSuperiori,
                            (val) => setState(() => _limArtiSuperiori = val ?? false)),
                        _buildCheckbox('Limitazioni funzionali degli arti inferiori', _limArtiInferiori,
                            (val) => setState(() => _limArtiInferiori = val ?? false)),
                      ],
                    ),
                  ),
                ],

                _buildCheckbox('Disabilità sensoriale', _disSensoriale, (val) {
                  setState(() {
                    _disSensoriale = val ?? false;
                    if (!_disSensoriale) {
                      _uditoSordita = false;
                      _visiva = false;
                    }
                  });
                }),
                if (_disSensoriale) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 24.0, bottom: 8),
                    child: Column(
                      children: [
                        _buildCheckbox('Uditiva/sordità', _uditoSordita,
                            (val) => setState(() => _uditoSordita = val ?? false)),
                        _buildCheckbox('Visiva', _visiva,
                            (val) => setState(() => _visiva = val ?? false)),
                      ],
                    ),
                  ),
                ],

                _buildCheckbox('Paralisi cerebrale', _paralisiCerebrale,
                    (val) => setState(() => _paralisiCerebrale = val ?? false)),
                _buildCheckbox('Epilessia', _epilessia,
                    (val) => setState(() => _epilessia = val ?? false)),
                _buildCheckbox('Problemi di salute mentale/disturbi emotivi', _saluteMentale,
                    (val) => setState(() => _saluteMentale = val ?? false)),
                _buildCheckbox('Disturbo dello spettro autistico', _spettroAutistico,
                    (val) => setState(() => _spettroAutistico = val ?? false)),
                _buildCheckbox('Sindrome di Down', _sindromeDown,
                    (val) => setState(() => _sindromeDown = val ?? false)),
                _buildCheckbox('Gravi problemi di salute', _graviProblemiSalute,
                    (val) => setState(() => _graviProblemiSalute = val ?? false)),
                _buildCheckbox('Disturbi della condotta', _disturbiCondotta,
                    (val) => setState(() => _disturbiCondotta = val ?? false)),

                TextFormField(
                  controller: _altroCondizioniController,
                  decoration: AppTheme.inputDecoration('Altre condizioni specifiche / Note', Icons.more_horiz),
                ),
                const SizedBox(height: 28),

                // --- SEZIONE 2: INFORMATORE 1 ---
                _buildSectionHeader('DATI DELL\'INFORMATORE 1'),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _inf1NomeController,
                  decoration: AppTheme.inputDecoration('Nome e Cognome Informatore 1', Icons.person_outline),
                  validator: (val) => val == null || val.isEmpty ? 'Campo richiesto' : null,
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _inf1AnniController,
                        keyboardType: TextInputType.number,
                        decoration: AppTheme.inputDecoration('Periodo contatto (anni)', Icons.date_range),
                        validator: (val) => val == null || val.isEmpty ? 'Richiesto' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: _inf1MesiController,
                        keyboardType: TextInputType.number,
                        decoration: AppTheme.inputDecoration('Mesi', Icons.timelapse),
                        validator: (val) => val == null || val.isEmpty ? 'Richiesto' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: _inf1Frequenza,
                  decoration: AppTheme.inputDecoration('Frequenza di contatto', Icons.loop),
                  items: const [
                    DropdownMenuItem(value: 'Varie volte alla settimana', child: Text('Varie volte alla settimana')),
                    DropdownMenuItem(value: 'Una volta alla settimana', child: Text('Una volta alla settimana')),
                    DropdownMenuItem(value: 'Una volta ogni due settimane', child: Text('Una volta ogni due settimane')),
                    DropdownMenuItem(value: 'Una volta al mese', child: Text('Una volta al mese')),
                  ],
                  onChanged: (val) => setState(() => _inf1Frequenza = val),
                  validator: (val) => val == null ? 'Campo richiesto' : null,
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  initialValue: _inf1Relazione,
                  decoration: AppTheme.inputDecoration('Relazione con la persona esaminata', Icons.people_outline),
                  items: const [
                    DropdownMenuItem(value: 'Professionale', child: Text('Professionale')),
                    DropdownMenuItem(value: 'Madre /Padre', child: Text('Madre / Padre')),
                    DropdownMenuItem(value: 'Fratello/Sorella', child: Text('Fratello / Sorella')),
                    DropdownMenuItem(value: 'Tutore/tutrice legale', child: Text('Tutore / tutrice legale')),
                    DropdownMenuItem(value: 'Altro', child: Text('Altro (specificare)')),
                  ],
                  onChanged: (val) => setState(() => _inf1Relazione = val),
                  validator: (val) => val == null ? 'Campo richiesto' : null,
                ),
                if (_inf1Relazione == 'Altro') ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _inf1RelazioneAltroController,
                    decoration: AppTheme.inputDecoration('Specificare relazione', Icons.edit_note),
                    validator: (val) => val == null || val.isEmpty ? 'Specificare la relazione' : null,
                  ),
                ],
                const SizedBox(height: 28),

                // --- SEZIONE 3: INFORMATORE 2 (OPZIONALE) ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildSectionHeader('DATI DELL\'INFORMATORE 2 (OPZIONALE)'),
                    Switch(
                      value: _inf2Abilitato,
                      activeThumbColor: AppTheme.primaryColor,
                      onChanged: (val) => setState(() => _inf2Abilitato = val),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_inf2Abilitato) ...[
                  TextFormField(
                    controller: _inf2NomeController,
                    decoration: AppTheme.inputDecoration('Nome e Cognome Informatore 2', Icons.person_outline),
                    validator: (val) => _inf2Abilitato && (val == null || val.isEmpty) ? 'Campo richiesto' : null,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _inf2AnniController,
                          keyboardType: TextInputType.number,
                          decoration: AppTheme.inputDecoration('Periodo contatto (anni)', Icons.date_range),
                          validator: (val) => _inf2Abilitato && (val == null || val.isEmpty) ? 'Richiesto' : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _inf2MesiController,
                          keyboardType: TextInputType.number,
                          decoration: AppTheme.inputDecoration('Mesi', Icons.timelapse),
                          validator: (val) => _inf2Abilitato && (val == null || val.isEmpty) ? 'Richiesto' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    initialValue: _inf2Frequenza,
                    decoration: AppTheme.inputDecoration('Frequenza di contatto', Icons.loop),
                    items: const [
                      DropdownMenuItem(value: 'Varie volte alla settimana', child: Text('Varie volte alla settimana')),
                      DropdownMenuItem(value: 'Una volta alla settimana', child: Text('Una volta alla settimana')),
                      DropdownMenuItem(value: 'Una volta ogni due settimane', child: Text('Una volta ogni due settimane')),
                      DropdownMenuItem(value: 'Una volta al mese', child: Text('Una volta al mese')),
                    ],
                    onChanged: (val) => setState(() => _inf2Frequenza = val),
                    validator: (val) => _inf2Abilitato && val == null ? 'Campo richiesto' : null,
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<String>(
                    initialValue: _inf2Relazione,
                    decoration: AppTheme.inputDecoration('Relazione con la persona esaminata', Icons.people_outline),
                    items: const [
                      DropdownMenuItem(value: 'Professionale', child: Text('Professionale')),
                      DropdownMenuItem(value: 'Madre /Padre', child: Text('Madre / Padre')),
                      DropdownMenuItem(value: 'Fratello/Sorella', child: Text('Fratello / Sorella')),
                      DropdownMenuItem(value: 'Tutore/tutrice legale', child: Text('Tutore / tutrice legale')),
                      DropdownMenuItem(value: 'Altro', child: Text('Altro (specificare)')),
                    ],
                    onChanged: (val) => setState(() => _inf2Relazione = val),
                    validator: (val) => _inf2Abilitato && val == null ? 'Campo richiesto' : null,
                  ),
                  if (_inf2Relazione == 'Altro') ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _inf2RelazioneAltroController,
                      decoration: AppTheme.inputDecoration('Specificare relazione', Icons.edit_note),
                      validator: (val) => _inf2Abilitato && (val == null || val.isEmpty) ? 'Specificare la relazione' : null,
                    ),
                  ],
                ],
                const SizedBox(height: 32),

                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 22),
                    label: const Text(
                      'Procedi alle Domande',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: AppTheme.primaryColor,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildCheckbox(String title, bool value, ValueChanged<bool?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
