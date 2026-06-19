import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_version.dart';
import 'utils/responsive_helper.dart';
import 'services/settings_notifier.dart';
import 'screens/settings_screen.dart';
import 'screens/about_terms_dialog.dart';
import 'screens/protocols_screen.dart';
import 'screens/anagrafica_screen.dart';
import 'screens/selection_screen.dart';
import 'screens/audit_log_screen.dart';
import 'screens/dashboard_screen.dart';
import 'widgets/connection_status_indicator.dart';
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
      themeMode: ThemeMode.light,
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
  String? _patientSemanticFilter;

  void _performLogout() {
    try {
      html.window.localStorage.clear();
      html.window.sessionStorage.clear();
    } catch (_) {}

    try {
      js.context.callMethod('eval', [
        '''
        if ('caches' in window) {
          caches.keys().then(function(names) {
            for (let name of names) {
              caches.delete(name);
            }
          });
        }
        if ('serviceWorker' in navigator) {
          navigator.serviceWorker.getRegistrations().then(function(registrations) {
            for (let registration of registrations) {
              registration.unregister();
            }
          });
        }
        sessionStorage.clear();
        localStorage.clear();
        setTimeout(function() {
          window.location.href = window.location.pathname + "?v=" + new Date().getTime();
        }, 150);
        '''
      ]);
    } catch (_) {
      try {
        html.window.location.href = '/?v=\${DateTime.now().millisecondsSinceEpoch}';
      } catch (_) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  static const _navItems = [
    (icon: Icons.dashboard_outlined, active: Icons.dashboard, label: 'Dashboard'),
    (icon: Icons.edit_note_outlined, active: Icons.edit_note, label: 'Compila'),
    (icon: Icons.people_outline, active: Icons.people, label: 'Utenza'),
    (icon: Icons.library_books_outlined, active: Icons.library_books, label: 'Protocolli'),
    (icon: Icons.history_outlined, active: Icons.history, label: 'Registro'),
    (icon: Icons.settings_outlined, active: Icons.settings, label: 'Impostazioni'),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      // AppBar solo su mobile
      appBar: isMobile
          ? AppBar(
              backgroundColor: AppTheme.surfaceColor,
              elevation: 0,
              centerTitle: true,
              title: Text(
                _navItems[_selectedIndex].label,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              leading: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu_rounded, color: AppTheme.textPrimary),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(
                  color: const Color(0xFFE8EEF8),
                  height: 1,
                ),
              ),
            )
          : null,
      // Drawer con info utente e azioni secondarie (solo mobile)
      drawer: isMobile ? _buildMobileDrawer() : null,
      // BottomNavigationBar su mobile
      bottomNavigationBar: isMobile ? _buildBottomNav() : null,
      body: isMobile ? _buildMobileBody() : _buildDesktopBody(),
    );
  }

  // ─── DESKTOP LAYOUT (sidebar + contenuto) ──────────────────────────────────
  Widget _buildDesktopBody() {
    return Row(
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
                    opacity: 0.015, // Trasparenza soft ottimizzata all'1.5% per garantire contrasto ottimale
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
    );
  }

  // ─── MOBILE LAYOUT (solo contenuto, nav in bottom) ─────────────────────────
  Widget _buildMobileBody() {
    return Stack(
      children: [
        Positioned.fill(
          child: _buildBody(),
        ),
        // Watermark (ridotto su mobile)
        Positioned.fill(
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.015, // Trasparenza soft ottimizzata all'1.5% per garantire contrasto ottimale
              child: Image.asset(
                'assets/images/bradipo_hd_BG.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── BOTTOM NAVIGATION BAR (mobile) ────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE8EEF8), width: 1)),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.surfaceColor,
        selectedItemColor: AppTheme.puzzleColorAt(_selectedIndex),
        unselectedItemColor: AppTheme.textSecondary,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        iconSize: 24,
        elevation: 0,
        items: _navItems
            .map((item) => BottomNavigationBarItem(
                  icon: Icon(item.icon),
                  activeIcon: Icon(item.active),
                  label: item.label,
                ))
            .toList(),
      ),
    );
  }

  // ─── MOBILE DRAWER ─────────────────────────────────────────────────────────
  Widget _buildMobileDrawer() {
    return Drawer(
      backgroundColor: AppTheme.surfaceColor,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Logo
            _buildLogo(),
            const SizedBox(height: 16),
            const Divider(indent: 24, endIndent: 24, color: Color(0xFFE8EEF8)),
            const SizedBox(height: 8),
            // Voci navigazione
            Expanded(
              child: ListView.builder(
                itemCount: _navItems.length,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemBuilder: (context, index) {
                  final item = _navItems[index];
                  final isSelected = _selectedIndex == index;
                  final color = isSelected ? AppTheme.puzzleColorAt(index) : AppTheme.textSecondary;
                  return ListTile(
                    leading: Icon(
                      isSelected ? item.active : item.icon,
                      color: color,
                      size: 24,
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: color,
                        fontSize: 15,
                      ),
                    ),
                    selected: isSelected,
                    selectedTileColor: color.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    onTap: () {
                      setState(() => _selectedIndex = index);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            // Footer drawer
            const Divider(indent: 24, endIndent: 24, color: Color(0xFFE8EEF8)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  _buildRoleBadge(),
                  const SizedBox(height: 8),
                  const ConnectionStatusIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    'v$kFrontendVersion',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        builder: (context) => const AboutTermsDialog(),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        'About & Termini',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Logout button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _performLogout,
                      icon: const Icon(Icons.logout_rounded, size: 18, color: AppTheme.errorColor),
                      label: const Text('Esci', style: TextStyle(color: AppTheme.errorColor, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.errorColor.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ─── DESKTOP SIDEBAR (invariata) ───────────────────────────────────────────
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
            onPressed: _performLogout,
          ),
          const SizedBox(height: 8),
          // Footer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                _buildRoleBadge(),
                const SizedBox(height: 8),
                const ConnectionStatusIndicator(compact: true),
                const SizedBox(height: 8),
                Text(
                  'v$kFrontendVersion',
                  style: TextStyle(fontSize: 10, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => const AboutTermsDialog(),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      'About',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Image.asset(
        'assets/images/logo_autify_int.png',
        height: 72,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.psychology, color: AppTheme.primaryColor, size: 32),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final item = _navItems[index];
    final isSelected = _selectedIndex == index;
    final color = isSelected ? AppTheme.puzzleColorAt(index) : AppTheme.textSecondary;

    return Tooltip(
      message: item.label,
      waitDuration: const Duration(milliseconds: 600),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: InkWell(
          onTap: () => setState(() => _selectedIndex = index),
          borderRadius: BorderRadius.circular(16),
          hoverColor: color.withValues(alpha: 0.08),
          splashColor: color.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Capsula attiva Material 3 per l'icona
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    isSelected ? item.active : item.icon,
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
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
            onNavigate: (index, {searchFilter, semanticFilter}) {
              setState(() {
                _patientSearchQuery = searchFilter;
                _patientSemanticFilter = semanticFilter;
                _selectedIndex = index;
              });
            },
          ),
        1 => const SelectionScreen(key: ValueKey(1)),
        2 => AnagraficaScreen(
            key: ValueKey('anagrafica_${_patientSearchQuery ?? ""}_${_patientSemanticFilter ?? ""}_$_selectedIndex'),
            initialSearchQuery: _patientSearchQuery,
            initialSemanticFilter: _patientSemanticFilter,
          ),
        3 => const ProtocolsScreen(key: ValueKey(3)),
        4 => const AuditLogScreen(key: ValueKey(4)),
        5 => const SettingsScreen(key: ValueKey(5)),
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
