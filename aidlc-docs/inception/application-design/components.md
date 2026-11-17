# 컴포넌트 (Components)

이 설계에는 새 기능 컴포넌트가 없다. 컴포넌트는 세 종류다: (1) 테스트 대상인 기존 운영 컴포넌트, (2) 테스트를 가능하게 하려고 운영 코드에 추가하는 대체 지점, (3) 테스트 지원 컴포넌트 (fake · 도우미 · CI 검사).

결정 근거: `aidlc-docs/inception/plans/application-design-plan.md` Q1 ~ Q6 (모두 A).

## 1. 테스트 대상 운영 컴포넌트

| 컴포넌트 | 위치 | 목적 | 운영 코드 변경 | 요구사항 |
| --- | --- | --- | --- | --- |
| `PhoneBackend` | `lib/features/player/data/backends/phone_backend.dart` | 폰 출력. 네이티브 TIDAL Player SDK 를 채널로 제어하고 네이티브 이벤트를 `BackendEvent` 로 변환 | 없음 | FR-01 |
| `DlnaBackend` | `lib/features/player/data/backends/dlna_backend.dart` | DLNA 출력. 스트림을 프록시에 등록하고 SOAP 명령을 보내며 1초 주기로 스피커 상태를 확인 | 없음 | FR-02 |
| `DlnaManager` | `lib/features/dlna/data/dlna_manager.dart` | 기기 탐색 · 선택 · 선택 저장, 선택된 스피커로의 SOAP 명령 전달 | 작음: 테스트용 생성자에 SOAP 클라이언트 주입 | FR-03, FR-07 |
| `WaveAudioHandler` | `lib/features/player/data/wave_audio_handler.dart` | 시스템 미디어 세션 (잠금화면 · 알림 · 블루투스) 과 `PlayerManager` 연결 | 없음 | FR-04 |
| `TidalStreamProxyServer` | `android/app/src/main/kotlin/com/example/tidal_connect_lite/TidalStreamProxyServer.kt` | 렌더러에 TIDAL 오디오를 짧은 URL 로 제공하는 로컬 HTTP 서버 | 작음: 생성자에 포트 · HTTP 클라이언트 주입 | FR-05, FR-07 |
| `PlaybackCore` | `android/app/src/main/kotlin/com/example/tidal_connect_lite/PlaybackCore.kt` | 프로세스 범위 소유자. 채널 연결, 인증 · 플레이어 · 프록시 소유 | 중간: 명령 분배를 `PlaybackCommandRouter` 로 옮기고 자신은 연결 · 소유만 맡음 | FR-06, FR-07 |

## 2. 운영 코드에 추가하는 컴포넌트 (대체 지점)

### `PlaybackCommandRouter` (새 Kotlin 클래스)
- **위치**: `android/app/src/main/kotlin/com/example/tidal_connect_lite/PlaybackCommandRouter.kt`
- **목적**: `PlaybackCore.onMethodCall` 에 있던 명령 분배를 Android 클래스 없이 실행할 수 있게 분리한다
- **책임**: 메서드 이름으로 동작 선택, 인자 해석과 기본값 적용, 반환 맵 구성, 예외를 오류 결과로 변환, 알 수 없는 메서드 판정
- **책임 아님**: 채널 연결, 이벤트 전송, 플레이어 · 프록시 생성과 소유, Android 시스템 서비스 접근 (모두 `PlaybackCore` 에 남는다)
- **인터페이스**: `handle(method, args): CommandResult`. Flutter · Android 타입을 받지 않는다

### 협력 인터페이스 (새 Kotlin 인터페이스, 같은 파일 또는 `PlaybackContracts.kt`)

| 인터페이스 | 목적 | 운영 구현 |
| --- | --- | --- |
| `PlayerControls` | 재생 제어 8개 동작 | `TidalPlayerManager` 가 구현 (메서드 이름 · 시그니처는 지금과 같음) |
| `AuthControls` | 인증 초기화 (플레이어 생성 포함), 사용자 자격 증명 갱신 · 삭제 | `PlaybackCore` 안의 구현이 `TidalAuthManager` 와 플레이어 생성을 묶음 |
| `DeviceControls` | 폰 볼륨 읽기 · 쓰기, 알림 권한 요청, WifiLock | `PlaybackCore` 안의 구현 (`AudioManager`, `WifiManager` 사용) |
| `ProxyRegistrar` | 곡을 프록시에 등록하고 URL 반환, Wi-Fi 없으면 null | `PlaybackCore` 안의 구현 (`ensureProxyServer` 사용) |
| `CommandResult` | 명령 결과 3종: 성공 값, 오류 (code · message), 미구현 | `PlaybackCore` 가 `MethodChannel.Result` 로 옮김 |

### 기존 컴포넌트의 주입 지점

| 대상 | 추가하는 것 | 기본값 (운영 동작) |
| --- | --- | --- |
| `DlnaManager.forTesting` | `soapClient` 매개변수 | `UPnPSoapClient()` (운영 싱글톤 `DlnaManager.instance` 는 그대로) |
| `TidalStreamProxyServer` 생성자 | `port`, `httpClient` 매개변수 | `PROXY_PORT` (8765), 기존 타임아웃 설정의 `OkHttpClient` |
| `android/app/build.gradle.kts` | JVM 단위 테스트에서 `android.util.Log` 호출이 예외를 내지 않게 하는 테스트 설정 (방식은 NFR Requirements 에서 확정) | 운영 빌드에 영향 없음 |

## 3. 테스트 지원 컴포넌트

### Dart (`test/helpers/`)

| 컴포넌트 | 상태 | 목적 | 책임 |
| --- | --- | --- | --- |
| `FakeNativeChannel` | 새로 만듦 | MethodChannel `com.example.tidal_connect_lite/tidal_sdk` 를 테스트에서 가로챔 | 호출 기록, 메서드별 응답 · 실패 지정, 네이티브 → Dart 호출 (`refreshTrackStream`, `refreshUserToken`) 흉내 |
| `FakeSoapClient` | 새로 만듦 | `UPnPSoapClient` 대체 (상속) | SOAP 액션 호출 기록, 액션별 성공 · 실패, 전송 상태 · 위치 · 볼륨 응답 지정 |
| `FakeSsdpDiscoveryService` | 있음 (`app_overrides.dart`), 확장 | 소켓 없는 기기 탐색 | 돌려줄 기기 목록 지정, `onDeviceFound` 호출 |
| `FakeAuthRepository` | 있음 (`fakes.dart`), 확장 | 인증 저장소 대체 | 사용자 토큰 (`getValidUserToken`) 결과 지정 |
| `FakeApiClient` | 있음 (`app_overrides.dart`), 확장 | TIDAL API 대체 | `getPlaybackInfo` 결과 지정 (직접 URL · DASH · null) |
| `FakeBackend` | 있음 (`player_manager_test.dart` 안), `test/helpers/` 로 옮기고 확장 | `PlaybackBackend` 대체 | 재생 · 일시정지 · 탐색 · 정지 호출 기록, 이벤트 주입 |

### Kotlin (`android/app/src/test/kotlin/com/example/tidal_connect_lite/`)

| 컴포넌트 | 목적 | 책임 |
| --- | --- | --- |
| `FakeCdnServer` | 업스트림 TIDAL CDN 대체 (루프백 로컬 서버) | 경로별 응답 (상태 코드 · 헤더 · 본문) 지정, 받은 요청 (메서드 · Range 헤더) 기록 |
| `FakePlayerControls`, `FakeAuthControls`, `FakeDeviceControls`, `FakeProxyRegistrar` | router 협력 인터페이스의 가짜 구현 | 호출 기록, 반환값 · 예외 지정 |

### CI

| 컴포넌트 | 위치 | 목적 | 책임 |
| --- | --- | --- | --- |
| `CoverageGate` | `tool/` (파일 이름 · 언어는 CI unit 의 NFR Requirements 에서 확정) | NFR-01 검사 | lcov 결과에서 대상 4개 파일의 라인 커버리지를 계산하고 80% 미만이면 실패 종료 |
| `tool/check.sh` | 있음, 수정 | 로컬 · CI 공통 점검 | `flutter test` 를 커버리지 수집으로 바꾸고 `CoverageGate` 호출 |
| `.github/workflows/check.yml` | 있음, 수정 | CI | debug APK 빌드, workflow 산출물 업로드 (FR-09) |

## 4. 테스트 묶음 (새 테스트 파일)

| 테스트 파일 | 대상 | 쓰는 지원 컴포넌트 |
| --- | --- | --- |
| `test/features/player/phone_backend_test.dart` | `PhoneBackend` | `FakeNativeChannel`, 이벤트 `StreamController` |
| `test/features/player/dlna_backend_test.dart` | `DlnaBackend` | `FakeNativeChannel`, `DlnaManager.forTesting` + `FakeSoapClient`, `FakeAuthRepository`, `FakeApiClient`, `fake_async` |
| `test/features/dlna/dlna_manager_test.dart` | `DlnaManager` | `FakeSoapClient`, `FakeSsdpDiscoveryService`, `SharedPreferences.setMockInitialValues` |
| `test/features/player/wave_audio_handler_test.dart` | `WaveAudioHandler` | `PlayerManager.forTesting` + `FakeBackend`, `DlnaManager.forTesting` |
| `android/app/src/test/kotlin/com/example/tidal_connect_lite/TidalStreamProxyServerTest.kt` | `TidalStreamProxyServer` | `FakeCdnServer` |
| `android/app/src/test/kotlin/com/example/tidal_connect_lite/PlaybackCommandRouterTest.kt` | `PlaybackCommandRouter` | Kotlin fake 4개 |

## 5. 요구사항 배정

| 요구사항 | 컴포넌트 |
| --- | --- |
| FR-01 | `PhoneBackend`, `FakeNativeChannel` |
| FR-02 | `DlnaBackend`, `FakeNativeChannel`, `FakeSoapClient`, `FakeAuthRepository`, `FakeApiClient` |
| FR-03 | `DlnaManager`, `FakeSoapClient`, `FakeSsdpDiscoveryService` |
| FR-04 | `WaveAudioHandler`, `FakeBackend` |
| FR-05 | `TidalStreamProxyServer`, `FakeCdnServer` |
| FR-06 | `PlaybackCommandRouter`, 협력 인터페이스, Kotlin fake 4개 (`PlaybackCore` 의 Android 연결부는 테스트 범위 밖, Q4=A) |
| FR-07 | 2절의 대체 지점 전부 |
| FR-08 | 컴포넌트 없음 (절차). 후보는 `application-design.md` 의 관찰 사항 |
| FR-09 | `CoverageGate`, `tool/check.sh`, `.github/workflows/check.yml` |

## 6. 워크로드 중요도 (RESILIENCY-01)

기존 컴포넌트의 분류는 `requirements.md` 의 워크로드 분류 표를 따른다. 새 컴포넌트:

| 컴포넌트 | 중요도 | 근거 |
| --- | --- | --- |
| `PlaybackCommandRouter` | High | 폰 재생 · DLNA 등록의 모든 채널 명령이 거친다. 잘못되면 재생 전체가 안 된다 |
| 테스트 지원 컴포넌트, `CoverageGate` | Low | 운영 경로가 아니다. 잘못되면 CI 가 틀린 결과를 낸다 |
