import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/tidal_config.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/main/presentation/splash_screen.dart';
import 'features/player/data/player_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  assert(
    TidalConfig.isConfigured,
    'TIDAL 키가 없습니다. flutter run --dart-define-from-file=config/tidal.json 으로 실행하세요.',
  );

  final container = ProviderContainer();
  final authRepository = container.read(authRepositoryProvider);
  // 네이티브 SDK 초기화는 앱 생애 동안 한 번만 한다. 사용자 토큰 복원(autoLogin)은 스플래시에서 이어서 진행한다.
  await authRepository.initNativeSdk();
  PlayerManager.instance.configure(authRepository: authRepository);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const TidalConnectLiteApp(),
    ),
  );
}

class TidalConnectLiteApp extends StatelessWidget {
  const TidalConnectLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WaveConnect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
