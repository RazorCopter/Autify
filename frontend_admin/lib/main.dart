import 'dart:async';
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
import 'screens/license_screen.dart';
import 'services/api_service.dart';
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

class _NotificationBellPainter extends CustomPainter {
  const _NotificationBellPainter({
    required this.color,
    required this.filled,
  });

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * 0.09;
    final centerX = size.width / 2;
    final bellPath = Path()
      ..moveTo(size.width * 0.24, size.height * 0.70)
      ..quadraticBezierTo(
        size.width * 0.31,
        size.height * 0.61,
        size.width * 0.31,
        size.height * 0.43,
      )
      ..cubicTo(
        size.width * 0.31,
        size.height * 0.22,
        size.width * 0.40,
        size.height * 0.14,
        centerX,
        size.height * 0.14,
      )
      ..cubicTo(
        size.width * 0.60,
        size.height * 0.14,
        size.width * 0.69,
        size.height * 0.22,
        size.width * 0.69,
        size.height * 0.43,
      )
      ..quadraticBezierTo(
        size.width * 0.69,
        size.height * 0.61,
        size.width * 0.76,
        size.height * 0.70,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.76,
        size.width * 0.70,
        size.height * 0.76,
      )
      ..lineTo(size.width * 0.30, size.height * 0.76)
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.76,
        size.width * 0.24,
        size.height * 0.70,
      )
      ..close();

    final bellPaint = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(bellPath, bellPaint);

    final clapperPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(centerX, size.height * 0.84),
      size.shortestSide * 0.075,
      clapperPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _NotificationBellPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.filled != filled;
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
  bool _checkingLicense = true;
  bool _licenseValid = false;
  bool _licenseCheckUnavailable = false;
  int _unreadNotifications = 0;
  List<Map<String, dynamic>> _notifications = [];
  Timer? _notificationTimer;

  @override
  void initState() {
    super.initState();
    _checkLicense();
    _pollNotifications();
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _pollNotifications(),
    );
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollNotifications() async {
    try {
      final api = ApiService();
      final values = await Future.wait([
        api.getNotifications(),
        api.getUnreadNotificationCount(),
      ]);
      if (!mounted) return;
      setState(() {
        _notifications = values[0] as List<Map<String, dynamic>>;
        _unreadNotifications = values[1] as int;
      });
    } catch (_) {
      // Polling silenzioso: la shell resta utilizzabile se la rete non è disponibile.
    }
  }

  Future<void> _showNotifications() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('Notifiche')),
            if (_unreadNotifications > 0)
              TextButton(
                onPressed: () async {
                  await ApiService().markAllNotificationsRead();
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _pollNotifications();
                },
                child: const Text('Segna tutte lette'),
              ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: _notifications.isEmpty
              ? const Text('Nessuna notifica')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _notifications.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final item = _notifications[index];
                    final failed = item['type'] == 'ai_analysis_failed';
                    return ListTile(
                      leading: Icon(
                        failed ? Icons.error_outline : Icons.auto_awesome,
                        color: failed ? Colors.redAccent : Colors.teal,
                      ),
                      title: Text(item['message']?.toString() ?? ''),
                      subtitle: Text(item['created_at']?.toString() ?? ''),
                      tileColor: item['read'] == true
                          ? null
                          : AppTheme.primaryColor.withValues(alpha: 0.05),
                      onTap: () async {
                        await ApiService()
                            .markNotificationRead(item['id'].toString());
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                        setState(() {
                          _selectedIndex = 2;
                          _patientSearchQuery =
                              item['patient_name']?.toString();
                        });
                        await _pollNotifications();
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  Widget _notificationBell({bool inHeader = false}) {
    final semanticLabel = _unreadNotifications > 0
        ? 'Notifiche, $_unreadNotifications non lette'
        : 'Notifiche';

    const unreadBellColor = Color(0xFFD97706);
    const idleBellColor = Color(0xFF5F6368);
    final bellColor = _unreadNotifications > 0
        ? unreadBellColor
        : (inHeader ? idleBellColor : AppTheme.textSecondary);
    final borderRadius = BorderRadius.circular(inHeader ? 14 : 12);

    final bellContent = SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              CustomPaint(
                key: const ValueKey('notification-bell-symbol'),
                size: const Size(24, 24),
                painter: _NotificationBellPainter(
                  color: bellColor,
                  filled: _unreadNotifications > 0,
                ),
              ),
              if (_unreadNotifications > 0)
                Positioned(
                  top: -5,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1.5),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _unreadNotifications > 99
                          ? '99+'
                          : '$_unreadNotifications',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final bellButton = Semantics(
      button: true,
      label: semanticLabel,
      child: Tooltip(
        message: semanticLabel,
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
          ),
          child: InkWell(
            onTap: _showNotifications,
            borderRadius: borderRadius,
            hoverColor: bellColor.withValues(alpha: 0.08),
            splashColor: bellColor.withValues(alpha: 0.16),
            highlightColor: bellColor.withValues(alpha: 0.10),
            child: bellContent,
          ),
        ),
      ),
    );

    if (inHeader) {
      return Container(
        height: 40,
        width: 40,
        clipBehavior: Clip.none,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8EEF8), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: bellButton,
      );
    }

    return bellButton;
  }

  Future<void> _checkLicense() async {
    try {
      final license = await ApiService().getLicenseStatus();
      if (mounted) {
        setState(() {
          _licenseValid = license.valid;
          _licenseCheckUnavailable = false;
          _checkingLicense = false;
        });
      }
    } on LicenseApiException catch (error) {
      if (mounted) {
        setState(() {
          _licenseValid = false;
          _licenseCheckUnavailable = error.networkError;
          _checkingLicense = false;
        });
      }
    }
  }

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
        html.window.location.href =
            '/?v=\${DateTime.now().millisecondsSinceEpoch}';
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
    (
      icon: Icons.dashboard_outlined,
      active: Icons.dashboard,
      label: 'Dashboard'
    ),
    (icon: Icons.edit_note_outlined, active: Icons.edit_note, label: 'Compila'),
    (icon: Icons.people_outline, active: Icons.people, label: 'Utenza'),
    (
      icon: Icons.library_books_outlined,
      active: Icons.library_books,
      label: 'Protocolli'
    ),
    (icon: Icons.history_outlined, active: Icons.history, label: 'Registro'),
    (
      icon: Icons.settings_outlined,
      active: Icons.settings,
      label: 'Impostazioni'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_checkingLicense) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_licenseValid) {
      return LicenseScreen(
        blocking: true,
        isViewer: ApiService.isViewer,
        initialConnectionError: _licenseCheckUnavailable,
        onActivated: _checkLicense,
      );
    }
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
                  icon: const Icon(Icons.menu_rounded,
                      color: AppTheme.textPrimary),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              actions: [_notificationBell()],
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
                    opacity:
                        0.015, // Trasparenza soft ottimizzata all'1.5% per garantire contrasto ottimale
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
              opacity:
                  0.015, // Trasparenza soft ottimizzata all'1.5% per garantire contrasto ottimale
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
                  final color = isSelected
                      ? AppTheme.puzzleColorAt(index)
                      : AppTheme.textSecondary;
                  return ListTile(
                    leading: Icon(
                      isSelected ? item.active : item.icon,
                      color: color,
                      size: 24,
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: color,
                        fontSize: 15,
                      ),
                    ),
                    selected: isSelected,
                    selectedTileColor: color.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
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
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary.withValues(alpha: 0.5)),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
                      icon: const Icon(Icons.logout_rounded,
                          size: 18, color: AppTheme.errorColor),
                      label: const Text('Esci',
                          style: TextStyle(
                              color: AppTheme.errorColor,
                              fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: AppTheme.errorColor.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
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
            icon: const Icon(Icons.logout_rounded,
                size: 20, color: AppTheme.errorColor),
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
                  style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textSecondary.withValues(alpha: 0.5)),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            isAdmin
                ? Icons.admin_panel_settings_rounded
                : Icons.visibility_rounded,
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
        errorBuilder: (_, __, ___) => const Icon(Icons.psychology,
            color: AppTheme.primaryColor, size: 32),
      ),
    );
  }

  Widget _buildNavItem(int index) {
    final item = _navItems[index];
    final isSelected = _selectedIndex == index;
    final color =
        isSelected ? AppTheme.puzzleColorAt(index) : AppTheme.textSecondary;

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withValues(alpha: 0.15)
                        : Colors.transparent,
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
                    color: isSelected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
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
            headerAction: _notificationBell(inHeader: true),
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
            key: ValueKey(
                'anagrafica_${_patientSearchQuery ?? ""}_${_patientSemanticFilter ?? ""}_$_selectedIndex'),
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
              color:
                  AppTheme.puzzleColorAt(_selectedIndex).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isHome
                  ? Icons.analytics_outlined
                  : Icons.manage_accounts_outlined,
              size: 64,
              color:
                  AppTheme.puzzleColorAt(_selectedIndex).withValues(alpha: 0.5),
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
            children: List.generate(
                4,
                (i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.extension,
                        size: 22,
                        color:
                            AppTheme.puzzleColorAt(i).withValues(alpha: 0.35),
                      ),
                    )),
          ),
        ],
      ),
    );
  }
}
