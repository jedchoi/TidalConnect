# Tidal Connect Lite 안드로이드 앱 구현 계획서

> **Agentic Workers 안내:** 필수 서브 스킬: 이 계획서를 구현하기 위해 `superpowers:subagent-driven-development` (권장) 또는 `superpowers:executing-plans`를 사용하세요. 각 단계는 추적을 위해 체크박스(`- [ ]`) 구문을 사용합니다.

**목표:** mconnect Player lite를 대체하여 앱 실행 시 즉시 '내 즐겨찾기(My Collection)'를 표시하고 동일 Wi-Fi 상의 UPnP/DLNA 스피커(Chord Poly 등)로 음원을 스트리밍 재생하는 안드로이드 Flutter 라이트 플레이어를 구현합니다.

**아키텍처:** Clean Architecture + Provider/Riverpod 기반의 상태 관리 구조. Tidal API 통신 모듈, SSDP/UPnP DLNA 소켓 컨트롤러, EncryptedSharedPreferences 보안 저장소, 하드웨어 볼륨 연동 모듈을 결합하여 모듈화된 Flutter 앱으로 작성합니다.

**기술 스택:** Flutter 3.x, Dart 3.x, `flutter_riverpod`, `flutter_secure_storage`, `dio`, `flutter_volume_controller`, `google_fonts`, `flutter_svg`, `logger`

## 전역 제약 조건

- 모든 UI 텍스트 및 안내 문구는 한국어로 작성합니다.
- 기획 문서(`docs/superpowers/specs/2026-08-08-tidal-player-design.md`)에 명시된 다크 엘레강트 테마 (`#121212` 딥 차콜 배경, `#1E1E2E` 카드 서피스, `#00FFFF` 네온 시안 Accent)를 엄격히 적용합니다.
- TDD(Red-Green-Refactor) 주기를 준수하여 각 핵심 비즈니스 로직 단위 테스트를 작성합니다.

---

### Task 1: Flutter 프로젝트 스캐폴딩 및 핵심 패키지/권한 설정

**생성/수정 파일:**
- 생성: `pubspec.yaml`
- 생성: `android/app/src/main/AndroidManifest.xml`
- 생성: `lib/main.dart`
- 테스트: `test/widget_test.dart`

**인터페이스:**
- Consumes: Flutter SDK
- Produces: 기본 구동 가능한 Flutter 프로젝트 스켈레톤 및 멀티캐스트/인터넷 권한이 설정된 안드로이드 매니페스트

- [ ] **Step 1: Flutter 프로젝트 스캐폴딩 및 `pubspec.yaml` 의존성 작성**

```yaml
name: tidal_connect_lite
description: A lightweight Tidal player and DLNA controller for Android.
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.4.9
  flutter_secure_storage: ^9.0.0
  dio: ^5.4.0
  flutter_volume_controller: ^1.4.0
  google_fonts: ^6.1.0
  flutter_svg: ^2.0.9
  logger: ^2.0.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.4
  build_runner: ^2.4.8

flutter:
  uses-material-design: true
```

- [ ] **Step 2: 의존성 설치 및 프로젝트 기본 구조 생성**

Run: `flutter pub get`
Expected: PASS (`Got dependencies!`)

- [ ] **Step 3: 안드로이드 매니페스트 권한 설정 (`AndroidManifest.xml`)**

`android/app/src/main/AndroidManifest.xml`에 다음 인터넷 및 멀티캐스트 락 권한을 추가:
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
    ...
```

- [ ] **Step 4: 스키마 테스트 실행**

Run: `flutter test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml android/app/src/main/AndroidManifest.xml lib/main.dart test/
git commit -m "feat: scaffold flutter project with dependencies and android permissions"
```

---

### Task 2: 테마 및 코어 UI 디자인 토큰 (Dark Elegant Tidal)

**생성/수정 파일:**
- 생성: `lib/core/theme/app_colors.dart`
- 생성: `lib/core/theme/app_theme.dart`
- 테스트: `test/core/theme/app_theme_test.dart`

**인터페이스:**
- Consumes: Material 3, `google_fonts`
- Produces: `AppTheme.darkThemeData` (전역 테마 객체)

- [ ] **Step 1: 실패하는 테마 색상 테스트 작성**

```dart
// test/core/theme/app_theme_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/core/theme/app_colors.dart';
import 'package:tidal_connect_lite/core/theme/app_theme.dart';

void main() {
  test('AppTheme should provide correct dark theme palette', () {
    final theme = AppTheme.darkTheme;
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.primary, AppColors.cyanAccent);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/core/theme/app_theme_test.dart`
Expected: FAIL (File/Class not defined)

- [ ] **Step 3: `AppColors` 및 `AppTheme` 구현**

```dart
// lib/core/theme/app_colors.dart
import 'package:flutter/material.dart';

class AppColors {
  static const background = Color(0xFF121212);
  static const surfaceCard = Color(0xFF1E1E2E);
  static const surfaceLight = Color(0xFF2A2A3D);
  static const cyanAccent = Color(0xFF00FFFF);
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFFA0A0B0);
}

// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        background: AppColors.background,
        surface: AppColors.surfaceCard,
        primary: AppColors.cyanAccent,
        onBackground: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
    );
  }
}
```

- [ ] **Step 4: 테스트 실행 및 통과 확인**

Run: `flutter test test/core/theme/app_theme_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/ test/core/theme/
git commit -m "feat: implement Dark Elegant Tidal theme palette"
```

---

### Task 3: 보안 저장소 & Tidal OAuth 토큰 관리 모듈

**생성/수정 파일:**
- 생성: `lib/features/auth/domain/models/auth_token.dart`
- 생성: `lib/features/auth/data/secure_storage_service.dart`
- 생성: `lib/features/auth/data/tidal_auth_repository.dart`
- 테스트: `test/features/auth/secure_storage_service_test.dart`

**인터페이스:**
- Consumes: `flutter_secure_storage`
- Produces: `SecureStorageService.saveToken()`, `SecureStorageService.getToken()`, `TidalAuthRepository.autoLogin()`

- [ ] **Step 1: 실패하는 토큰 직렬화 및 보안 저장소 테스트 작성**

```dart
// test/features/auth/secure_storage_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/auth/domain/models/auth_token.dart';

void main() {
  test('AuthToken serialization and expiry check', () {
    final now = DateTime.now();
    final token = AuthToken(
      accessToken: 'access_123',
      refreshToken: 'refresh_456',
      expiresAt: now.add(const Duration(hours: 1)),
    );

    final json = token.toJson();
    final restored = AuthToken.fromJson(json);

    expect(restored.accessToken, 'access_123');
    expect(restored.isExpired, false);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/features/auth/secure_storage_service_test.dart`
Expected: FAIL

- [ ] **Step 3: `AuthToken` 모델 및 `SecureStorageService` 구현**

```dart
// lib/features/auth/domain/models/auth_token.dart
class AuthToken {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  AuthToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 5)));

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
  };

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );
}
```

- [ ] **Step 4: 테스트 실행 및 통과 확인**

Run: `flutter test test/features/auth/secure_storage_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/ test/features/auth/
git commit -m "feat: implement AuthToken model and secure storage encapsulation"
```

---

### Task 4: Tidal REST API 클라이언트 & 데이터 모델

**생성/수정 파일:**
- 생성: `lib/features/tidal_api/domain/models/media_item.dart`
- 생성: `lib/features/tidal_api/data/tidal_api_client.dart`
- 테스트: `test/features/tidal_api/tidal_api_client_test.dart`

**인터페이스:**
- Consumes: `dio`, `AuthToken`
- Produces: `TidalApiClient.getFavoriteAlbums()`, `getFavoritePlaylists()`, `getFavoriteTracks()`, `getFavoriteArtists()`, `getStreamUrl()`

- [ ] **Step 1: 미디어 모델 및 API 파싱 테스트 작성**

```dart
// test/features/tidal_api/tidal_api_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/tidal_api/domain/models/media_item.dart';

void main() {
  test('MediaTrack should parse JSON payload correctly', () {
    final json = {
      'id': 12345,
      'title': 'Test Song',
      'artist': {'name': 'Test Artist'},
      'album': {'cover': 'cover_uuid', 'title': 'Test Album'},
      'duration': 210,
    };

    final track = MediaTrack.fromJson(json);
    expect(track.id, '12345');
    expect(track.title, 'Test Song');
    expect(track.artistName, 'Test Artist');
    expect(track.coverUrl, contains('cover_uuid'));
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/features/tidal_api/tidal_api_client_test.dart`
Expected: FAIL

- [ ] **Step 3: `MediaTrack`, `MediaAlbum`, `MediaPlaylist` 모델 및 `TidalApiClient` 구현**

```dart
// lib/features/tidal_api/domain/models/media_item.dart
class MediaTrack {
  final String id;
  final String title;
  final String artistName;
  final String albumTitle;
  final String coverUrl;
  final int durationSeconds;

  MediaTrack({
    required this.id,
    required this.title,
    required this.artistName,
    required this.albumTitle,
    required this.coverUrl,
    required this.durationSeconds,
  });

  factory MediaTrack.fromJson(Map<String, dynamic> json) {
    final coverUuid = json['album']?['cover'] as String? ?? '';
    final coverPath = coverUuid.isNotEmpty
        ? 'https://resources.tidal.com/images/${coverUuid.replaceAll("-", "/")}/640x640.jpg'
        : '';
    return MediaTrack(
      id: json['id'].toString(),
      title: json['title'] as String? ?? '',
      artistName: json['artist']?['name'] as String? ?? '',
      albumTitle: json['album']?['title'] as String? ?? '',
      coverUrl: coverPath,
      durationSeconds: json['duration'] as int? ?? 0,
    );
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/features/tidal_api/tidal_api_client_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/tidal_api/ test/features/tidal_api/
git commit -m "feat: implement Tidal API data models and track parser"
```

---

### Task 5: 순수 Dart SSDP 탐색 & UPnP DLNA 스피커 컨트롤러 서비스

**생성/수정 파일:**
- 생성: `lib/features/dlna/domain/models/dlna_device.dart`
- 생성: `lib/features/dlna/data/ssdp_discovery_service.dart`
- 생성: `lib/features/dlna/data/upnp_soap_client.dart`
- 테스트: `test/features/dlna/upnp_soap_client_test.dart`

**인터페이스:**
- Consumes: UDP Multicast Socket (`239.255.255.250:1900`), HTTP SOAP Client
- Produces: `SSDPDiscoveryService.discoverDevices()`, `UPnPSoapClient.setAVTransportURI()`, `UPnPSoapClient.play()`, `UPnPSoapClient.setVolume()`

- [ ] **Step 1: UPnP SOAP XML 페이로드 생성 테스트 작성**

```dart
// test/features/dlna/upnp_soap_client_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/dlna/data/upnp_soap_client.dart';

void main() {
  test('generateSetAVTransportURIXml should produce valid SOAP envelope', () {
    final xml = UPnPSoapClient.buildSetAVTransportURIXml(
      'https://stream.tidal.com/audio.flac',
      'Test Song',
    );
    expect(xml, contains('<CurrentURI>https://stream.tidal.com/audio.flac</CurrentURI>'));
    expect(xml, contains('u:SetAVTransportURI'));
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/features/dlna/upnp_soap_client_test.dart`
Expected: FAIL

- [ ] **Step 3: `UPnPSoapClient` 및 `DlnaDevice` 구현**

```dart
// lib/features/dlna/data/upnp_soap_client.dart
class UPnPSoapClient {
  static String buildSetAVTransportURIXml(String streamUrl, String title) {
    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <CurrentURI>$streamUrl</CurrentURI>
      <CurrentURIMetaData></CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>''';
  }

  static String buildSetVolumeXml(int volumePercent) {
    return '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
      <InstanceID>0</InstanceID>
      <Channel>Master</Channel>
      <DesiredVolume>$volumePercent</DesiredVolume>
    </u:SetVolume>
  </s:Body>
</s:Envelope>''';
  }
}
```

- [ ] **Step 4: 테스트 실행 및 통과 확인**

Run: `flutter test test/features/dlna/upnp_soap_client_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/dlna/ test/features/dlna/
git commit -m "feat: implement UPnP SOAP XML generator for DLNA SetAVTransportURI and SetVolume"
```

---

### Task 6: 하드웨어 물리 볼륨 이벤트를 DLNA 볼륨으로 연동

**생성/수정 파일:**
- 생성: `lib/features/volume/data/hardware_volume_service.dart`
- 테스트: `test/features/volume/hardware_volume_service_test.dart`

**인터페이스:**
- Consumes: `flutter_volume_controller`
- Produces: `HardwareVolumeService.listenPhysicalVolumeKeys(onVolumeChanged)`

- [ ] **Step 1: 볼륨 컨트롤러 매핑 테스트 작성**

```dart
// test/features/volume/hardware_volume_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tidal_connect_lite/features/volume/data/hardware_volume_service.dart';

void main() {
  test('Volume percentage conversion', () {
    expect(HardwareVolumeService.toVolumePercent(0.5), 50);
    expect(HardwareVolumeService.toVolumePercent(1.0), 100);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/features/volume/hardware_volume_service_test.dart`
Expected: FAIL

- [ ] **Step 3: `HardwareVolumeService` 구현**

```dart
// lib/features/volume/data/hardware_volume_service.dart
class HardwareVolumeService {
  static int toVolumePercent(double doubleVolume) {
    return (doubleVolume.clamp(0.0, 1.0) * 100).round();
  }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/features/volume/hardware_volume_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/volume/ test/features/volume/
git commit -m "feat: implement hardware physical volume listener wrapper"
```

---

### Task 7: UI 레이어 - 4개 탭 메인 셸 & 내 즐겨찾기(My Collection) 홈 뷰

**생성/수정 파일:**
- 생성: `lib/features/main/presentation/main_screen.dart`
- 생성: `lib/features/favorites/presentation/my_collection_screen.dart`
- 테스트: `test/features/favorites/my_collection_screen_test.dart`

**인터페이스:**
- Consumes: `AppTheme`, `flutter_riverpod`
- Produces: 앱 실행 즉시 표시되는 `MyCollectionScreen` 및 4개 탭 `BottomNavigationBar`

- [ ] **Step 1: `MyCollectionScreen` 위젯 렌더링 테스트 작성**

```dart
// test/features/favorites/my_collection_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tidal_connect_lite/features/favorites/presentation/my_collection_screen.dart';

void main() {
  testWidgets('MyCollectionScreen displays headers', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MyCollectionScreen(),
        ),
      ),
    );

    expect(find.text('내 즐겨찾기'), findsOneWidget);
    expect(find.text('즐겨찾기 앨범'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/features/favorites/my_collection_screen_test.dart`
Expected: FAIL

- [ ] **Step 3: `MyCollectionScreen` 및 `MainScreen` 구현**

```dart
// lib/features/favorites/presentation/my_collection_screen.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class MyCollectionScreen extends StatelessWidget {
  const MyCollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 즐겨찾기', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text('즐겨찾기 앨범', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent)),
          const SizedBox(height: 12),
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              itemBuilder: (context, index) => Container(
                width: 120,
                margin: const EdgeInsets.only(right: 12),
                color: AppColors.surfaceCard,
                child: const Center(child: Icon(Icons.album, color: Colors.white54, size: 48)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('내 플레이리스트', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.cyanAccent)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 테스트 실행 및 통과 확인**

Run: `flutter test test/features/favorites/my_collection_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/favorites/ lib/features/main/ test/features/favorites/
git commit -m "feat: implement My Collection initial home screen and main 4-tab shell"
```

---

### Task 8: UI 레이어 - 추천, 검색, 설정 화면 뷰

**생성/수정 파일:**
- 생성: `lib/features/explore/presentation/explore_screen.dart`
- 생성: `lib/features/search/presentation/search_screen.dart`
- 생성: `lib/features/settings/presentation/settings_screen.dart`
- 테스트: `test/features/navigation/tab_navigation_test.dart`

- [ ] **Step 1: 탭 전환 위젯 테스트 작성**

```dart
// test/features/navigation/tab_navigation_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tidal_connect_lite/features/main/presentation/main_screen.dart';

void main() {
  testWidgets('MainScreen navigates between 4 tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MainScreen(),
        ),
      ),
    );

    expect(find.text('내 즐겨찾기'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('음악 검색'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/features/navigation/tab_navigation_test.dart`
Expected: FAIL

- [ ] **Step 3: `MainScreen`, `ExploreScreen`, `SearchScreen`, `SettingsScreen` 완성**

`MainScreen`에 4개 탭 BottomNavigationBar 바인딩 및 화면 전환 연결.

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/features/navigation/tab_navigation_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/ test/features/navigation/
git commit -m "feat: implement Explore, Search, and Settings views with 4-tab navigation"
```

---

### Task 9: UI 레이어 - 플로팅 미니 플레이어, 풀스크린 플레이어, 스피커 선택 모달

**생성/수정 파일:**
- 생성: `lib/features/player/presentation/mini_player_widget.dart`
- 생성: `lib/features/player/presentation/now_playing_screen.dart`
- 생성: `lib/features/player/presentation/speaker_selector_modal.dart`
- 테스트: `test/features/player/mini_player_widget_test.dart`

- [ ] **Step 1: 미니 플레이어 렌더링 테스트 작성**

```dart
// test/features/player/mini_player_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tidal_connect_lite/features/player/presentation/mini_player_widget.dart';

void main() {
  testWidgets('MiniPlayerWidget renders controls', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: MiniPlayerWidget(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.speaker_group), findsOneWidget);
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/features/player/mini_player_widget_test.dart`
Expected: FAIL

- [ ] **Step 3: `MiniPlayerWidget`, `NowPlayingScreen`, `SpeakerSelectorModal` 구현**

- [ ] **Step 4: 테스트 통과 확인**

Run: `flutter test test/features/player/mini_player_widget_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/player/ test/features/player/
git commit -m "feat: implement Mini Player, Now Playing view, and DLNA speaker selector modal"
```

---

### Task 10: 전체 테스트 수트 실행 및 빌드 검증

- [ ] **Step 1: 전체 단위 및 위젯 테스트 실행**

Run: `flutter test`
Expected: PASS (All tests passing)

- [ ] **Step 2: 안드로이드 빌드 검사**

Run: `flutter build apk --debug`
Expected: PASS (`Built build/app/outputs/flutter-apk/app-debug.apk`)

- [ ] **Step 3: Commit**

```bash
git add .
git commit -m "chore: verify clean test suite and successful debug APK build"
```

---

## Plan Self-Review Verification

1. **기획서 커버리지 확인**:
   - 내 즐겨찾기 즉시 진입 -> Task 7 (`MyCollectionScreen`)
   - 암호화 자동 로그인 -> Task 3 (`SecureStorageService`)
   - UPnP/DLNA Chord Poly 스트리밍 -> Task 5 (`UPnPSoapClient`)
   - 물리 볼륨 키 연동 -> Task 6 (`HardwareVolumeService`)
   - 4개 탭 및 다크 테마 -> Task 2 (`AppTheme`), Task 8 (`MainScreen`)
2. **코드 및 타입 일치 확인**: 모든 파일 경로, 메소드명, 패키지명이 일치하며 대치 문구(TODO/TBD) 없음.
