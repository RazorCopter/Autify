import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final ApiService _apiService = ApiService();
  late Future<List<UserModel>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _refreshUsers();
  }

  void _refreshUsers() {
    setState(() {
      _usersFuture = _apiService.getUsers();
    });
  }

  void _showUserForm([UserModel? user]) {
    final nomeController = TextEditingController(text: user?.nome);
    final cognomeController = TextEditingController(text: user?.cognome);
    final dataNascitaController = TextEditingController(text: user?.dataNascita);
    final cfController = TextEditingController(text: user?.codiceFiscale);
    final noteController = TextEditingController(text: user?.note);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user == null ? 'Nuovo Utente' : 'Modifica Utente'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nomeController, decoration: const InputDecoration(labelText: 'Nome')),
              TextField(controller: cognomeController, decoration: const InputDecoration(labelText: 'Cognome')),
              TextField(controller: dataNascitaController, decoration: const InputDecoration(labelText: 'Data Nascita')),
              TextField(controller: cfController, decoration: const InputDecoration(labelText: 'Codice Fiscale')),
              TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
          ElevatedButton(
            onPressed: () async {
              final newUser = UserModel(
                id: user?.id,
                nome: nomeController.text,
                cognome: cognomeController.text,
                dataNascita: dataNascitaController.text,
                codiceFiscale: cfController.text,
                note: noteController.text,
              );

              bool success;
              if (user == null) {
                success = await _apiService.createUser(newUser);
              } else {
                success = await _apiService.updateUser(newUser);
              }

              if (success) {
                Navigator.pop(context);
                _refreshUsers();
              }
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestione Utenti')),
      body: FutureBuilder<List<UserModel>>(
        future: _usersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Errore: ${snapshot.error}'));
          final users = snapshot.data ?? [];
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                title: Text('${user.nome} ${user.cognome}'),
                subtitle: Text(user.codiceFiscale),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit), onPressed: () => _showUserForm(user)),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Conferma'),
                            content: const Text('Eliminare questo utente?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
                              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sì')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _apiService.deleteUser(user.id!);
                          _refreshUsers();
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUserForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
