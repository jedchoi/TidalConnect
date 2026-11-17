# 코드 품질 평가 (Code Quality Assessment)

## 테스트 커버리지
- **전체**: Fair (정성 평가). 커버리지 측정 도구·리포트(`coverage/`, `lcov.info`, CI의 `--coverage`)는 없어 백분율을 낼 수 없다
- **단위 테스트**: Dart 22개 테스트 파일(약 95개 `test`/`testWidgets` 호출)이 `PlayerManager`, `PlayQueue`, `StreamQuality`, `RecentlyPlayedStore`, `TidalAuthRepository`, `SecureStorageService`, `AuthInterceptor`, `TidalApiClient`, `UPnPSoapClient`, `SSDPDiscoveryService`, `FavoritesRepository`, `PlaybackSettings`, `SearchHistoryStore`, `Paginator`, `AppTheme`과 여러 화면 위젯(`TrackTile`, `MiniPlayerWidget`, `MyCollectionScreen`, `SearchScreen`, `ArtistDetailScreen`, 탭 내비게이션)을 다룬다. Kotlin은 `DashManifestTest.kt` 하나뿐이다
- **통합 테스트**: 없음(`integration_test/` 없음). 테스트가 없는 영역: `PhoneBackend`, `DlnaBackend`, `DlnaManager`, `WaveAudioHandler`, `TidalSdkNativeBridge`, Kotlin `PlaybackCore`·`TidalPlayerManager`·`TidalStreamProxyServer`·`DashSegmentInputStream`·`CustomCredentialsProvider`. 실기기 검증은 `docs/dlna-compat.md`의 수동 기록에 의존

## 코드 품질 지표
- **린트**: Configured — `analysis_options.yaml`이 `flutter_lints/flutter.yaml` 포함(추가 규칙 없음), CI에서 `flutter analyze --fatal-infos`
- **코드 스타일**: Consistent — `dart format --line-length 120` 검사가 CI에서 강제. 기능별 `data/domain/presentation` 폴더 구조가 일관됨
- **문서화**: Good — 공개 API에 한국어 doc 주석이 많고, `CLAUDE.md`, `README.md`, `docs/dlna-compat.md`, `docs/superpowers/specs|plans`가 있음. 단 README의 Flutter 버전(3.38 이상)은 CI(3.41.7)와 어긋남

## 기술 부채
- Flutter 업그레이드 위험: `.github/workflows/check.yml` 주석대로 Flutter 3.47+는 `package:flutter/material.dart`를 폐기 예정으로 표시해 `--fatal-infos`가 실패한다. `lib/` 24개 파일이 `material.dart`를 import하므로 버전 상향 시 `material_ui` 이전 작업이 필요
- 큰 파일(줄 수, `wc -l`): `lib/features/player/data/player_manager.dart` 527, `lib/features/player/presentation/now_playing_screen.dart` 505, `lib/features/favorites/presentation/my_collection_screen.dart` 455, `lib/features/auth/data/tidal_auth_repository.dart` 432, `lib/features/search/presentation/search_screen.dart` 431, `lib/features/tidal_api/data/tidal_api_client.dart` 425, `lib/features/dlna/data/upnp_soap_client.dart` 369, `lib/features/player/data/backends/dlna_backend.dart` 359, `android/app/src/main/kotlin/com/example/tidal_connect_lite/PlaybackCore.kt` 351, `android/app/src/main/kotlin/com/example/tidal_connect_lite/TidalStreamProxyServer.kt` 348
- 예외 무시: `catch (_) {}`가 `lib/core/native/tidal_sdk_native_bridge.dart`(223, 230, 237행), `lib/features/dlna/data/upnp_soap_client.dart`(258, 295, 318, 329행), `lib/features/settings/data/playback_settings.dart`(33, 41행), `lib/features/dlna/data/dlna_manager.dart`(229행)에 있어 실패 원인이 로그에 남지 않을 수 있음
- release 빌드가 debug 서명을 사용: `android/app/build.gradle.kts`의 `release { signingConfig = signingConfigs.getByName("debug") }`
- 기본 패키지명 유지: `com.example.tidal_connect_lite`(applicationId, namespace, 채널 이름)
- 전역 cleartext 허용: `android/app/src/main/AndroidManifest.xml`의 `android:usesCleartextTraffic="true"`(LAN 렌더러·프록시 때문이나 범위가 앱 전체)
- 고정 포트: `TidalStreamProxyServer.PROXY_PORT = 8765`. 포트 충돌 시 대체 경로 없음(코드상 확인한 범위)
- 플랫폼 채널 계약이 문자열로만 결합: 메서드·이벤트 이름이 `tidal_sdk_native_bridge.dart`, `phone_backend.dart`, `PlaybackCore.kt`, `TidalPlayerManager.kt`에 중복 정의되고 이를 검증하는 테스트가 없음
- 싱글톤 상태: `PlayerManager.instance`, `DlnaManager.instance`가 Provider 밖의 전역 상태라 테스트 격리가 `configure`/override에 의존
- 클라이언트 secret 내장: `TidalConfig.clientSecret`이 dart-define으로 앱 바이너리에 포함되고 네이티브 `initTidalAuth`로 전달됨
- 상세 로그: Kotlin에 `Log.*` 호출 48개(이모지 포함 로그 다수, `TidalStreamProxyServer.kt` 18개). release에서도 출력될 수 있음
- 문서 불일치: `README.md` 39행 "Flutter 3.38 이상" vs CI 3.41.7, `pubspec.lock` 요구 `>=3.41.0`
- TODO/FIXME/HACK 주석: 없음(`lib/`, `android/app/src` 검색 결과 0건)

## 패턴과 안티 패턴
- **좋은 패턴**:
  - 재생 상태 단일 출처(`PlayerManager`)와 이벤트 기반 갱신
  - `PlaybackBackend` 인터페이스로 출력 기기 추상화, sealed `BackendEvent`
  - 요청 순번(`_requestSeq`)과 `IsCancelled`로 경쟁 상태 방지
  - Riverpod Provider 기반 DI와 `test/helpers/` fake·override
  - 네이티브 재생 객체를 프로세스 범위 `PlaybackCore`가 소유해 Activity 재생성에 견딤
  - 프록시 접근 제어(무작위 토큰, `allowedHost` 비교, LRU 등록부), 만료 URL 자동 갱신
  - 음질 실패 시 한 단계 낮춰 재시도(`audioQualityLadder`)
  - CI에서 format·analyze(--fatal-infos)·Dart·Kotlin 테스트를 한 스크립트(`tool/check.sh`)로 일원화
- **안티 패턴**:
  - 빈 catch로 예외 삼키기 — 위 기술 부채 목록의 파일·행
  - 큰 화면 파일에 UI와 로직이 함께 있음 — `now_playing_screen.dart`, `my_collection_screen.dart`, `search_screen.dart`
  - Provider 안에서 싱글톤 반환(`playerManagerProvider`, `dlnaManagerProvider` → `.instance`) — `lib/core/providers.dart`
  - 문자열 기반 채널 계약 중복 — `tidal_sdk_native_bridge.dart` ↔ `PlaybackCore.kt`
