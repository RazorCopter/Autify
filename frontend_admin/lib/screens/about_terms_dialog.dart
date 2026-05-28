import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AboutTermsDialog extends StatelessWidget {
  const AboutTermsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: AppTheme.backgroundColor,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'About Autify',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildText('Termini e Condizioni di Utilizzo di Autify', isTitle: true, fontSize: 20),
                    _buildText('\nUltimo aggiornamento: 28/5/2026\n', isSubtitle: true),
                    _buildText('Benvenuto in Autify. I presenti Termini e Condizioni disciplinano l\'accesso e l\'utilizzo dell\'applicazione mobile Autify (di seguito, "l\'App"). Creando un account o utilizzando l\'App, l\'utente accetta di essere vincolato dai presenti Termini.\n'),
                    
                    _buildSectionTitle('1. Natura del Servizio e Disclaimer Medico'),
                    _buildText('Autify è un\'applicazione concepita per facilitare l\'organizzazione, l\'archiviazione e la gestione dei documenti legati all\'autismo.\n'),
                    _buildBulletItem('Nessun consulto medico: L\'App è un mero strumento organizzativo e non fornisce alcun tipo di diagnosi, terapia, consiglio o consulenza medica.'),
                    _buildBulletItem('Le informazioni e i documenti archiviati non sostituiscono in alcun modo il parere, la diagnosi o il trattamento da parte di medici, terapisti o professionisti sanitari qualificati.'),
                    _buildBulletItem('L\'utente si assume la piena responsabilità per qualsiasi decisione presa sulla base delle informazioni gestite tramite l\'App.\n'),

                    _buildSectionTitle('2. Versione Pilota e Gratuità Temporanea'),
                    _buildText('Attualmente, Autify è rilasciata in una versione pilota (Beta) ed è fornita a titolo gratuito per le funzionalità di base. Lo scopo di questa fase è valutare le funzionalità, garantire la stabilità del sistema e raccogliere feedback dagli utenti.\n'),

                    _buildSectionTitle('3. Sviluppi Futuri e Modello di Abbonamento'),
                    _buildText('L\'utente prende atto e accetta che, in futuro, per garantire la manutenzione, la sicurezza e lo sviluppo dell\'App, Autify si riserva il diritto di introdurre funzionalità a pagamento o di transitare verso un modello di servizio in abbonamento.\n'),
                    _buildBulletItem('Qualsiasi modifica alle condizioni economiche verrà comunicata all\'utente in modo chiaro e con un preavviso minimo di 30 giorni.'),
                    _buildBulletItem('Nessun addebito automatico o nascosto verrà mai applicato. L\'utente avrà la piena libertà di decidere se aderire ai nuovi piani tariffari o cancellare il proprio account.\n'),

                    _buildSectionTitle('4. Responsabilità dell\'Utente e Sicurezza dell\'Account'),
                    _buildText('Per utilizzare Autify, è necessario registrarsi. L\'utente si impegna a:\n'),
                    _buildBulletItem('Fornire informazioni veritiere durante la registrazione.'),
                    _buildBulletItem('Mantenere la massima riservatezza delle proprie credenziali di accesso.'),
                    _buildBulletItem('Segnalare immediatamente al supporto qualsiasi uso non autorizzato del proprio account o violazione della sicurezza.\n'),

                    _buildSectionTitle('5. Privacy, Dati Sensibili e GDPR'),
                    _buildText('La tutela dei tuoi dati è per noi fondamentale. Il trattamento dei dati personali e dei documenti caricati è disciplinato dalla nostra Privacy Policy.\n'),
                    _buildBulletItem('I documenti caricati rimangono di esclusiva proprietà dell\'utente e/o di chi ne detiene la responsabilità legale.'),
                    _buildBulletItem('L\'utente garantisce di avere il diritto legale di caricare, archiviare e gestire i documenti inseriti nell\'App, sollevando Autify da qualsiasi responsabilità in merito a caricamenti illeciti.\n'),

                    _buildSectionTitle('6. Limitazione di Responsabilità'),
                    _buildText('Poiché l\'App è attualmente in fase pilota, il servizio è fornito "così com\\'è" e "come disponibile".\n'),
                    _buildBulletItem('Autify declina ogni responsabilità per eventuali malfunzionamenti, bug o temporanee interruzioni del servizio.'),
                    _buildBulletItem('Pur adottando misure di sicurezza per proteggere i dati, non possiamo garantire l\'assoluta impossibilità di perdita di informazioni. Si raccomanda vivamente all\'utente di conservare sempre copie di backup personali dei documenti essenziali.\n'),

                    _buildSectionTitle('7. Modifiche ai Termini'),
                    _buildText('Autify si riserva il diritto di aggiornare o modificare i presenti Termini in qualsiasi momento. Le modifiche sostanziali verranno notificate all\'utente tramite avviso all\'interno dell\'App o via email. L\'uso continuato dell\'App dopo tale notifica costituisce accettazione dei Termini modificati.\n'),

                    _buildSectionTitle('8. Contatti e Supporto'),
                    _buildText('Per qualsiasi domanda, segnalazione di bug, richiesta di supporto o per fornire feedback sulla versione pilota, l\'utente può contattarci all\'indirizzo: [Inserisci la tua email di supporto]\n'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }

  Widget _buildText(String text, {bool isTitle = false, bool isSubtitle = false, double? fontSize}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: fontSize ?? (isTitle ? 22 : (isSubtitle ? 14 : 15)),
        fontWeight: isTitle ? FontWeight.w900 : (isSubtitle ? FontWeight.w500 : FontWeight.normal),
        color: isSubtitle ? AppTheme.textSecondary : AppTheme.textPrimary,
        height: 1.5,
      ),
    );
  }

  Widget _buildBulletItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16, color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
