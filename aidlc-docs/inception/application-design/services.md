# 서비스 (Services)

이 앱에는 별도의 서비스 계층이 없다. 조립과 오케스트레이션은 기존 세 곳이 맡고, 이번 작업은 그 조립을 바꾸지 않는다. 이 문서는 (1) 운영 조립이 그대로임을 확인하고, (2) 테스트에서의 조립 방식을 정한다.

## 1. 운영 조립 (변경 없음 확인)

| 조립 지점 | 하는 일 | 이번 변경의 영향 |
| --- | --- | --- |
| `lib/core/providers.dart` | Riverpod Provider 로 서비스 연결. `dlnaManagerProvider` 는 `DlnaManager.instance` | 없음. `DlnaManager.instance` 는 `_internal()` 생성자를 쓰고 동작이 같다 |
| `lib/main.dart` | `WaveAudioHandler(playerManager, dlnaManager: dlnaManager)` 생성 | 없음 |
| `PlayerManager.configure` | `PhoneBackend()`, `DlnaBackend(auth, api, dlna)` 생성, 이벤트 구독 | 없음 |
| `PlaybackCore.attach` (Kotlin) | 채널 연결, 볼륨 관찰 등록 | 없음. 채널 핸들러가 내부에서 `PlaybackCommandRouter` 를 거치게 될 뿐 |
| `PlaybackCore.ensureProxyServer` (Kotlin) | `TidalStreamProxyServer(wifiIp)` 생성 · 시작 | 없음. 새 매개변수는 기본값을 쓴다 |

## 2. 오케스트레이션 역할

| 오케스트레이터 | 역할 | 이번 작업에서 |
| --- | --- | --- |
| `PlayerManager` | 재생 상태의 단일 출처. 출력 기기에 따라 백엔드를 고르고 백엔드 이벤트로만 상태를 바꾼다 | 코드 변경 없음. `WaveAudioHandler` 테스트에서 실제 객체로 쓰인다 |
| `PlaybackCore` | 네이티브 쪽 소유자. 인증 · 플레이어 · 프록시의 수명 관리 | 명령 분배를 `PlaybackCommandRouter` 에 위임. 소유와 수명 관리는 그대로 |
| `PlaybackCommandRouter` (새로 추가) | 채널 명령 → 협력 객체 호출 → 결과. 상태를 갖지 않는다 | 테스트 대상 |

## 3. 테스트 조립

### Dart: 테스트마다 새로 조립 (공유 상태 없음)

| 테스트 | 조립 |
| --- | --- |
| `PhoneBackend` | `FakeNativeChannel.install()` → `PhoneBackend(nativeEvents: controller.stream)`. 명령은 채널 기록으로, 이벤트 변환은 `controller.add(맵)` → `backend.events` 로 검증 |
| `DlnaManager` | `SharedPreferences.setMockInitialValues({...})` → `DlnaManager.forTesting(ssdpService: FakeSsdpDiscoveryService, soapClient: FakeSoapClient)` |
| `DlnaBackend` | `FakeNativeChannel.install()` → 위 방식의 `DlnaManager` (원격 스피커 선택 상태) → `DlnaBackend(auth: FakeAuthRepository, api: FakeApiClient, dlna: manager)`. 폴링은 `fakeAsync` 안에서 시간을 1초씩 진행 |
| `WaveAudioHandler` | `PlayerManager.forTesting()` + `configure(authRepository: FakeAuthRepository, dlnaManager: manager, apiClient: FakeApiClient, phone: FakeBackend, dlna: FakeBackend)` → `WaveAudioHandler(player, dlnaManager: manager)` |

조립 원칙:
- `DlnaManager.instance` (운영 싱글톤) 는 테스트에서 쓰지 않는다. 항상 `forTesting` 으로 새 객체를 만든다
- `TidalSdkNativeBridge` 는 정적 상태 (`_handlerInstalled`, 등록된 refresher) 를 가진다. 테스트는 `FakeNativeChannel` 을 `setUp` 에서 걸고 `tearDown` 에서 풀며, refresher 는 `DlnaBackend` 생성 때마다 덮어써지므로 테스트 간 순서에 의존하지 않는다
- 반복되는 조립 (원격 스피커가 선택된 `DlnaManager` 만들기 등) 은 `test/helpers/` 의 함수로 둔다 (Q6=A)

### Kotlin: JVM 단위 테스트 (`./gradlew :app:testDebugUnitTest`)

| 테스트 | 조립 |
| --- | --- |
| `PlaybackCommandRouter` | `PlaybackCommandRouter(FakeAuthControls, { fakePlayer 또는 null }, FakeDeviceControls, FakeProxyRegistrar)` → `handle(method, args)` 결과와 fake 의 호출 기록 검증. 소켓 · Android 클래스 없음 |
| `TidalStreamProxyServer` | `FakeCdnServer` 시작 → `TidalStreamProxyServer("127.0.0.1", port = 0)` 시작 → `registerTrackStream(directUrl = cdn.baseUrl + 경로, ...)` → 반환 URL 로 실제 HTTP 요청 (GET · HEAD · Range) → 응답과 `cdn.requests` 검증. 테스트마다 두 서버를 닫는다 |

## 4. CI 조립

```text
tool/check.sh (로컬 · CI 공통)
  flutter pub get
  dart format 검사
  flutter analyze --fatal-infos
  flutter test --coverage        <- 변경: 커버리지 수집
  CoverageGate                   <- 추가: 대상 4개 파일 80% 검사
  Kotlin 단위 테스트             (--skip-android 면 생략)

.github/workflows/check.yml
  ... 기존 단계 ...
  tool/check.sh
  debug APK 빌드                 <- 추가
  APK 를 workflow 산출물로 업로드 <- 추가
```

커버리지 검사는 `tool/check.sh` 안에 두어 로컬과 CI 의 점검 내용이 같게 한다 (CLAUDE.md). APK 빌드 · 업로드는 점검이 아니라 산출물 생성이므로 workflow 에만 둔다.
