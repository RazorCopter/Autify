import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isShaking = false;

  @override
  void initState() {
    super.initState();
    // Registra la Platform View per il video di sfondo nativo HTML
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      'video-background-view',
      (int viewId) {
        final html.DivElement container = html.DivElement()
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.position = 'relative'
          ..style.overflow = 'hidden';

        // Tag Video configurato con tutti i requisiti tecnici per autoplay e compatibilità cross-browser/mobile
        final html.VideoElement video = html.VideoElement()
          ..autoplay = true
          ..loop = true
          ..muted = true
          ..setAttribute('playsinline', 'true')
          ..setAttribute('webkit-playsinline', 'true') // Per massima compatibilità iOS
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.objectFit = 'cover'
          ..style.position = 'absolute'
          ..style.top = '0'
          ..style.left = '0'
          ..style.zIndex = '-2';

        // Utilizziamo il tag <source> per caricare il video da assets/videos
        final html.SourceElement sourceMp4 = html.SourceElement()
          ..src = 'assets/videos/background.mp4'
          ..type = 'video/mp4';
        video.append(sourceMp4);

        /* 
          NOTA PRO MEMORIA: In futuro, per ottimizzare ulteriormente il caricamento,
          inserire qui una versione .webm come prima scelta:
          
          final html.SourceElement sourceWebm = html.SourceElement()
            ..src = 'assets/videos/background.webm'
            ..type = 'video/webm';
          video.insertBefore(sourceWebm, sourceMp4);
        */

        // Overlay semitrasparente scuro al 45% per contrasto e leggibilità
        final html.DivElement overlay = html.DivElement()
          ..style.position = 'absolute'
          ..style.top = '0'
          ..style.left = '0'
          ..style.width = '100%'
          ..style.height = '100%'
          ..style.backgroundColor = 'rgba(0, 0, 0, 0.45)'
          ..style.zIndex = '-1';

        container.append(video);
        container.append(overlay);
        return container;
      },
    );
  }

  Future<void> _handleLogin() async {
    final enteredPassword = _passwordController.text;
    if (enteredPassword.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final deviceId = html.window.navigator.userAgent;
    final result = await _apiService.login(enteredPassword, deviceId);

    if (result != null && result['role'] != null) {
      final role = result['role'];
      
      // Salva lo stato in localStorage
      try {
        html.window.localStorage['admin_authenticated'] = 'true';
        html.window.localStorage['auth_role'] = role;
        html.window.localStorage['auth_password'] = enteredPassword;
      } catch (_) {}

      if (mounted) {
        // Naviga alla Dashboard pulendo lo stack
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AdminDashboard()),
          (route) => false,
        );
      }
    } else {
      if (mounted) {
        setState(() {
          _errorMessage = 'Credenziali non valide o accesso disabilitato.';
          _isShaking = true;
          _isLoading = false;
        });
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _isShaking = false;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Sfondo con video nativo HTML + Overlay semitrasparente
          const Positioned.fill(
            child: HtmlElementView(viewType: 'video-background-view'),
          ),
          // Form di Accesso Centrato
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                width: 400,
                margin: EdgeInsets.only(left: _isShaking ? 20.0 : 0.0, right: _isShaking ? 0.0 : 20.0),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFFE8EEF8), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo Bradipo Utenza
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: Image.asset(
                          'assets/images/logo_bradipo.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const CircleAvatar(
                            backgroundColor: AppTheme.primaryColor,
                            child: Icon(Icons.psychology, color: Colors.white, size: 40),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Titolo
                    const Text(
                      'AutAnalysis',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Centro di Controllo Documentale',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Campo Password
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      onFieldSubmitted: (_) => _handleLogin(),
                      decoration: InputDecoration(
                        labelText: 'Chiave di Accesso',
                        prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFFE8EEF8)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                        ),
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: AppTheme.errorColor, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: AppTheme.errorColor, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 28),
                    // Pulsante di Accesso
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Accedi',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded, size: 18),
                              ],
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
