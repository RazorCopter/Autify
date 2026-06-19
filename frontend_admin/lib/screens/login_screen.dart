import 'dart:html' as html;
// ignore: uri_does_not_exist
import 'dart:js_util' as js_util;
import 'dart:ui' as ui_core;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isShaking = false;
  
  html.Event? _installPromptEvent;
  bool _showInstallBanner = false;
  bool _isIOS = false;

  @override
  void initState() {
    super.initState();
    _initPWA();

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
    final enteredUsername = _usernameController.text.trim();
    final enteredPassword = _passwordController.text;
    if (enteredUsername.isEmpty || enteredPassword.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final deviceId = html.window.navigator.userAgent;
    final result = await _apiService.login(enteredUsername, enteredPassword, deviceId);

    if (result != null && result['role'] != null) {
      // Il localStorage viene aggiornato direttamente dentro ApiService.login()
      if (mounted) {
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

  void _initPWA() {
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    final isIOSDevice = userAgent.contains('iphone') || userAgent.contains('ipad');
    
    if (isIOSDevice) {
      final isStandalone = html.window.matchMedia('(display-mode: standalone)').matches || js_util.getProperty(html.window.navigator, 'standalone') == true;
      if (!isStandalone) {
        if (mounted) {
          setState(() {
            _isIOS = true;
            _showInstallBanner = true;
          });
        }
      }
      return;
    }

    final deferredPrompt = js_util.getProperty(html.window, 'deferredPWAInstallPrompt');
    if (deferredPrompt != null) {
      if (mounted) {
        setState(() {
          _installPromptEvent = deferredPrompt;
          _showInstallBanner = true;
        });
      }
    } else {
      html.window.on['beforeinstallprompt'].listen((html.Event e) {
        e.preventDefault();
        js_util.setProperty(html.window, 'deferredPWAInstallPrompt', e);
        if (mounted) {
          setState(() {
            _installPromptEvent = e;
            _showInstallBanner = true;
          });
        }
      });
    }
  }

  void _promptInstall() {
    if (_installPromptEvent != null) {
      js_util.callMethod(_installPromptEvent!, 'prompt', []);
      setState(() {
        _showInstallBanner = false;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Sfondo con video nativo HTML + Overlay semitrasparente
          const Positioned.fill(
            child: HtmlElementView(viewType: 'video-background-view'),
          ),
          // Form di Accesso Centrato con effetto Glassmorphism Premium
          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(isMobile ? 24 : 32),
                  child: BackdropFilter(
                    filter: ui_core.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: double.infinity,
                      margin: EdgeInsets.only(left: _isShaking ? 20.0 : 0.0, right: _isShaking ? 0.0 : 20.0),
                      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 36, vertical: isMobile ? 28 : 40),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35), // Vetro scuro omogeneo con lo sfondo
                        borderRadius: BorderRadius.circular(isMobile ? 24 : 32),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 48,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo Autify Premium
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.08),
                                blurRadius: 40,
                                spreadRadius: 5,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/logoAutifyDark.png',
                            height: isMobile ? 80 : 120,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(Icons.psychology, color: Colors.white, size: isMobile ? 48 : 72),
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Campo Username
                        TextFormField(
                          controller: _usernameController,
                          onFieldSubmitted: (_) => FocusScope.of(context).nextFocus(),
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            labelText: 'Nome Utente',
                            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                            floatingLabelStyle: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold),
                            prefixIcon: Icon(Icons.person_outline_rounded, size: 20, color: Colors.white.withValues(alpha: 0.55)),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: Color(0xFF60A5FA), width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.04),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Campo Password integrato nel tema vetro
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          onFieldSubmitted: (_) => _handleLogin(),
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            labelText: 'Chiave di Accesso',
                            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                            floatingLabelStyle: const TextStyle(color: Color(0xFF60A5FA), fontWeight: FontWeight.bold),
                            prefixIcon: Icon(Icons.vpn_key_outlined, size: 20, color: Colors.white.withValues(alpha: 0.55)),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 20,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: Color(0xFF60A5FA), width: 1.5),
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.04),
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFF87171), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Color(0xFFF87171), fontSize: 12.5, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 32),
                        // Pulsante di Accesso Premium con Gradiente e Ombra Luminescente
                        Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF2563EB), // Deep Royal Blue
                                Color(0xFF3B82F6), // Vibrant Light Blue
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
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
            ),
            ),
          ),
          // PWA Install Banner
          if (_showInstallBanner)
            Positioned(
              top: isMobile ? 16 : 24,
              right: isMobile ? 16 : 24,
              left: isMobile ? 16 : null, // Su mobile occupiamo la larghezza
              child: _buildInstallBanner(isMobile),
            ),
        ],
      ),
    );
  }

  Widget _buildInstallBanner(bool isMobile) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 50 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui_core.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: isMobile ? double.infinity : 340,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF60A5FA).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.install_mobile_rounded, color: Color(0xFF60A5FA), size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Autify App',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(Icons.close_rounded, size: 20, color: Colors.white.withValues(alpha: 0.6)),
                      onPressed: () {
                        setState(() {
                          _showInstallBanner = false;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _isIOS ? 'Per installare l\'App su iOS: tocca l\'icona Condividi in basso e seleziona "Aggiungi alla schermata Home".' : 'Installa la nostra App per un\'esperienza migliore.',
                  style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8), height: 1.4),
                ),
                if (!_isIOS) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _promptInstall,
                      child: const Text('Installa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
