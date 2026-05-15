import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import 'hub_evaluations_screen.dart';
import 'users_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _apiService = ApiService();
  String? selectedPatientId;
  int selectedYear = DateTime.now().year;
  List<UserModel> users = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final fetchedUsers = await _apiService.getUsers();
      setState(() {
        users = fetchedUsers;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AutAnalysis', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UsersScreen())).then((_) => _loadUsers()),
          ),
        ],
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Seleziona il Paziente',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: users.isEmpty 
                    ? const Center(child: Text("Nessun utente trovato. Vai in 'Gestione Utenti'"))
                    : ListView.builder(
                        itemCount: users.length,
                        itemBuilder: (context, index) {
                          final user = users[index];
                          final isSelected = selectedPatientId == user.id;
                          return Card(
                            elevation: isSelected ? 4 : 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2),
                            ),
                            child: ListTile(
                              onTap: () => setState(() => selectedPatientId = user.id),
                              title: Text('${user.nome} ${user.cognome}'),
                              leading: const CircleAvatar(child: Icon(Icons.person)),
                            ),
                          );
                        },
                      ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: selectedPatientId == null ? null : () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => HubEvaluationsScreen(patientId: selectedPatientId!, year: selectedYear)));
                  },
                  child: const Text('Accedi all\'Hub'),
                )
              ],
            ),
          ),
        ),
    );
  }
}
