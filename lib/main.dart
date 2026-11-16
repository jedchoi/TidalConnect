import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/tidal_config.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/main/presentation/splash_screen.dart';
import 'features/player/data/wave_audio_handler.dart';

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
  final dlnaManager = container.read(dlnaManagerProvider);
  final playerManager = container.read(playerManagerProvider)
    ..configure(
      authRepository: authRepository,
      dlnaManager: dlnaManager,
      apiClient: container.read(apiClientProvider),
    );

  // 저장된 음질을 적용하고, 설정에서 바꾸면 다음 곡부터 반영한다.
  final settings = container.read(playbackSettingsProvider);
  await settings.load();
  void applyQuality() => playerManager.setAudioQuality(settings.audioQuality.value.apiValue);
  applyQuality();
  settings.audioQuality.addListener(applyQuality);

  // 재생을 시작한 곡을 최근 재생 목록에 남긴다.
  final recent = container.read(recentlyPlayedProvider);
  await recent.load();
  playerManager.currentTrackNotifier.addListener(() {
    final track = playerManager.currentTrack;
    if (track != null) recent.add(track);
  });

  // 잠금화면·알림·블루투스 버튼 제어와 백그라운드 재생 유지(포그라운드 서비스)
  await AudioService.init(
    builder: () => WaveAudioHandler(playerManager, dlnaManager: dlnaManager),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.tidal_connect_lite.playback',
      androidNotificationChannelName: 'WaveConnect 재생',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

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
