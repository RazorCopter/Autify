import 'package:flutter/material.dart';

void main() {
  runApp(const ClientApp());
}

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AutAnalysis Client',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const SelectionScreen(),
    );
  }
}

class SelectionScreen extends StatelessWidget {
  const SelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AutAnalysis - Nuova Valutazione'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Seleziona Paziente e Scala da compilare', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                // Naviga al WizardScreen (da migrare dal frontend_legacy)
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Inizia Compilazione'),
            ),
          ],
        ),
      ),
    );
  }
}
