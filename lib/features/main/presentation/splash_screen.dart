import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/data/tidal_auth_repository.dart';
import '../../dlna/data/dlna_manager.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  String _statusText = '오디오 엔진 초기화 중...';

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeIn),
    );

    _animController.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. 유료 계정 토큰 자동 복원
    setState(() => _statusText = 'TIDAL 계정 인증 확인 중...');
    try {
      await TidalAuthRepository().autoLogin();
    } catch (_) {}

    // 2. DLNA 네트워크 스피커 백그라운드 탐색 시작
    setState(() => _statusText = 'Wi-Fi Hi-Fi 스피커 탐색 중...');
    try {
      DlnaManager.instance.discoverDevices();
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;

    // 3. 메인 화면으로 부드러운 전환
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => const MainScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      body: Stack(
        children: [
          // Ambient Glow Background
          Positioned(
            top: MediaQuery.of(context).size.height * 0.25,
            left: MediaQuery.of(context).size.width * 0.15,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyanAccent.withOpacity(0.12),
                    blurRadius: 120,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                return Opacity(
                  opacity: _opacityAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Seamless App Logo Emblem
                        SizedBox(
                          width: 140,
                          height: 140,
                          child: Image.asset(
                            'assets/images/app_logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 28),
                        // App Title
                        const Text(
                          'WAVECONNECT',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6.0,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Subtitle
                        Text(
                          'HI-RES LOSSLESS & TIDAL CONNECT',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2.5,
                            color: AppColors.cyanAccent.withOpacity(0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Bottom Loading Status
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Column(
              children: [
                SizedBox(
                  width: 32,
                  height: 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.cyanAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _statusText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
