import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/data/tidal_auth_repository.dart';
import '../features/auth/domain/models/auth_token.dart';
import '../features/dlna/data/dlna_manager.dart';
import '../features/favorites/data/favorites_repository.dart';
import '../features/player/data/player_manager.dart';
import '../features/player/data/recently_played_store.dart';
import '../features/settings/data/playback_settings.dart';
import '../features/tidal_api/data/tidal_api_client.dart';

/// 앱 전체에서 하나만 쓰는 인증 저장소.
final authRepositoryProvider = Provider<TidalAuthRepository>((ref) => TidalAuthRepository());

/// 로그인 상태. 사용자 토큰이 바뀔 때마다 구독 중인 위젯을 다시 그린다.
final authStateProvider = ChangeNotifierProvider<ValueNotifier<AuthToken?>>(
  (ref) => ref.watch(authRepositoryProvider).userToken,
);

/// 로그인한 사용자 ID. 로그아웃 상태면 null.
/// 토큰 갱신처럼 ID가 그대로인 변경에는 반응하지 않는다.
final loggedInUserIdProvider = Provider<String?>((ref) => ref.watch(authStateProvider).value?.userId);

/// TIDAL REST API 클라이언트.
final apiClientProvider = Provider<TidalApiClient>(
  (ref) => TidalApiClient(authRepository: ref.watch(authRepositoryProvider)),
);

/// DLNA 스피커 탐색과 제어. 테스트에서는 override로 바꿔 끼운다.
final dlnaManagerProvider = Provider<DlnaManager>((ref) => DlnaManager.instance);

/// 재생 상태의 단일 출처. main()에서 configure된 인스턴스를 쓴다.
final playerManagerProvider = Provider<PlayerManager>((ref) => PlayerManager.instance);

/// 재생 설정(음질 등). main()에서 load한 뒤 쓴다.
final playbackSettingsProvider = Provider<PlaybackSettings>((ref) => PlaybackSettings());

/// 즐겨찾기 ID와 하트 버튼 처리. 로그인 사용자가 바뀌면 ID를 다시 받는다.
final favoritesProvider = ChangeNotifierProvider<FavoritesRepository>((ref) {
  final repo = FavoritesRepository(api: ref.watch(apiClientProvider));
  ref.listen<String?>(loggedInUserIdProvider, (_, userId) => repo.setUser(userId), fireImmediately: true);
  return repo;
});

/// 최근 재생 목록. main()에서 load하고 재생할 때마다 추가한다.
final recentlyPlayedProvider = Provider<RecentlyPlayedStore>((ref) => RecentlyPlayedStore());
