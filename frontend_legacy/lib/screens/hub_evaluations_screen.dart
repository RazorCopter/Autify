import 'package:flutter/material.dart';
import '../models/evaluation_model.dart';
import '../services/api_service.dart';
import 'wizard_screen.dart';

class HubEvaluationsScreen extends StatefulWidget {
  final String patientId;
  final int year;

  const HubEvaluationsScreen({
    super.key,
    required this.patientId,
    required this.year,
  });

  @override
  State<HubEvaluationsScreen> createState() => _HubEvaluationsScreenState();
}

class _HubEvaluationsScreenState extends State<HubEvaluationsScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<EvaluationModel>> _evaluationsFuture;

  @override
  void initState() {
    super.initState();
    _loadEvaluations();
  }

  void _loadEvaluations() {
    _evaluationsFuture = _apiService.getEvaluations(widget.patientId, widget.year);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Hub: ${widget.patientId} (${widget.year})'),
      ),
      body: FutureBuilder<List<EvaluationModel>>(
        future: _evaluationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  Text('Errore: ${snapshot.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _loadEvaluations()),
                    child: const Text('Riprova'),
                  )
                ],
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder_open, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Nessuna valutazione per quest\'anno.',
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            );
          }

          final evals = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: evals.length,
            itemBuilder: (context, index) {
              final eval = evals[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.assessment)),
                  title: Text('Scala: ${eval.idScala}'),
                  subtitle: Text('Compilato da: ${eval.nomeOperatore}\nData: ${eval.dataCompilazione ?? "-"}'),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WizardScreen(
                patientId: widget.patientId,
                year: widget.year,
              ),
            ),
          );
          // Ricarica la lista se è stata aggiunta una nuova valutazione
          if (result == true) {
            setState(() {
              _loadEvaluations();
            });
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuova Valutazione'),
      ),
    );
  }
}
