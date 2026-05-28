import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_version.dart';
import 'services/settings_notifier.dart';
import 'screens/settings_screen.dart';
import 'screens/protocols_screen.dart';
import 'screens/anagrafica_screen.dart';
import 'screens/selection_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => SettingsNotifier(),
      child: const AdminApp(),
    ),
  );
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Verifica se l'utente è già autenticato (JWT token presente)
    bool isAuthenticated = false;
    try {
      final token = html.window.localStorage['jwt_token'];
      isAuthenticated = token != null && token.isNotEmpty;
    } catch (_) {}

    return MaterialApp(
      title: 'Autify Admin v$kFrontendVersion',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: isAuthenticated ? const AdminDashboard() : const LoginScreen(),
    );
  }
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  String? _patientSearchQuery;

  static const _navItems = [
    (icon: Icons.dashboard_outlined, active: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.edit_note_outlined, active: Icons.edit_note, label: 'Compila'),
    (icon: Icons.people_outline, active: Icons.people, label: 'Utenza'),
    (icon: Icons.library_books_outlined, active: Icons.library_books, label: 'Protocolli'),
    (icon: Icons.settings_outlined, active: Icons.settings, label: 'Impostazioni'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Row(
        children: [
          // Sidebar
          _buildSidebar(),
          // Contenuto principale
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _buildBody(),
                ),
                // Sfondo Watermark Bradipo HD Premium post-login (in overlay sopra il body per aggirare gli sfondi coprenti delle schede)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.08, // Trasparenza soft ottimizzata all'8% per un watermark elegante e discreto
                      child: Image.asset(
                        'assets/images/bradipo_hd_BG.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 88,
      color: AppTheme.surfaceColor,
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Logo
          _buildLogo(),
          const SizedBox(height: 32),
          const Divider(indent: 16, endIndent: 16, color: Color(0xFFE8EEF8)),
          const SizedBox(height: 16),
          // Voci menu
          Expanded(
            child: ListView.builder(
              itemCount: _navItems.length,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, index) => _buildNavItem(index),
            ),
          ),
          // Pulsante Logout
          IconButton(
            icon: const Icon(Icons.logout_rounded, size: 20, color: AppTheme.errorColor),
            tooltip: 'Esci',
            onPressed: () {
              try {
                html.window.localStorage.remove('admin_authenticated');
                html.window.localStorage.remove('auth_role');
                html.window.localStorage.remove('auth_password');
              } catch (_) {}
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
          const SizedBox(height: 8),
          // Footer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                _buildRoleBadge(),
                const SizedBox(height: 6),
                Text(
                  'v$kFrontendVersion',
                  style: TextStyle(fontSize: 10, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildRoleBadge() {
    String role = 'viewer';
    try {
      role = html.window.localStorage['auth_role'] ?? 'viewer';
    } catch (_) {}

    final isAdmin = role == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAdmin 
            ? AppTheme.accentColor.withValues(alpha: 0.15) 
            : AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAdmin ? Icons.admin_panel_settings_rounded : Icons.visibility_rounded,
            size: 10,
            color: isAdmin ? const Color(0xFF388E3C) : AppTheme.primaryColor,
          ),
          const SizedBox(width: 4),
          Text(
            isAdmin ? 'Admin' : 'Sola Lettura',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              color: isAdmin ? const Color(0xFF388E3C) : AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.purpleColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/images/autify_logo.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.psychology, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Autify',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppTheme.primaryColor,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildNavItem(int index) {
    final item = _navItems[index];
    final isSelected = _selectedIndex == index;
    final color = isSelected ? AppTheme.puzzleColorAt(index) : AppTheme.textSecondary;

    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(
              isSelected ? item.active : item.icon,
              color: color,
              size: isSelected ? 26 : 22,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: switch (_selectedIndex) {
        0 => DashboardScreen(
            key: const ValueKey(0),
            onNavigate: (index, {searchFilter}) {
              setState(() {
                _patientSearchQuery = searchFilter;
                _selectedIndex = index;
              });
            },
          ),
        1 => const SelectionScreen(key: ValueKey(1)),
        2 => AnagraficaScreen(
            key: ValueKey('anagrafica_${_patientSearchQuery ?? ""}_$_selectedIndex'),
            initialSearchQuery: _patientSearchQuery,
          ),
        3 => const ProtocolsScreen(key: ValueKey(3)),
        4 => const SettingsScreen(key: ValueKey(4)),
        _ => _buildPlaceholder(),
      },
    );
  }

  Widget _buildPlaceholder() {
    final isHome = _selectedIndex == 0;
    return Center(
      key: ValueKey(_selectedIndex),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppTheme.puzzleColorAt(_selectedIndex).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isHome ? Icons.analytics_outlined : Icons.manage_accounts_outlined,
              size: 64,
              color: AppTheme.puzzleColorAt(_selectedIndex).withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isHome ? 'Dashboard Analitica' : 'Gestione Utenza',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Modulo in fase di sviluppo',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 16),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.extension,
                size: 22,
                color: AppTheme.puzzleColorAt(i).withValues(alpha: 0.35),
              ),
            )),
          ),
        ],
      ),
    );
  }
}
