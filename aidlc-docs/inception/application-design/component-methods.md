# 컴포넌트 메서드 (Component Methods)

바뀌는 생성자, 새 인터페이스, fake 의 시그니처만 적는다. 테스트 대상 컴포넌트의 기존 공개 메서드는 `aidlc-docs/inception/reverse-engineering/api-documentation.md` 에 있고 바꾸지 않는다. 상세 규칙 (인자 기본값, 오류 코드, 속성) 은 unit 별 Functional Design 에서 정한다.

## 1. 운영 코드 변경

### `DlnaManager` (Dart, 변경)

```dart
// 운영 싱글톤: 동작 동일. _soapClient 를 필드 초기화에서 생성자 초기화로 옮긴다.
DlnaManager._internal()
    : _ssdpService = SSDPDiscoveryService(),
      _soapClient = UPnPSoapClient();

@visibleForTesting
DlnaManager.forTesting({SSDPDiscoveryService? ssdpService, UPnPSoapClient? soapClient});
```

| 매개변수 | 목적 | 기본값 |
| --- | --- | --- |
| `soapClient` (새로 추가) | 테스트가 가짜 SOAP 클라이언트를 넣는다 | `UPnPSoapClient()` |

### `TidalStreamProxyServer` (Kotlin, 변경)

```kotlin
class TidalStreamProxyServer(
    val boundHost: String,
    port: Int = PROXY_PORT,
    private val httpClient: OkHttpClient = defaultHttpClient(),
) : NanoHTTPD(boundHost, port)
```

| 항목 | 목적 | 입력 → 출력 |
| --- | --- | --- |
| `port` (새로 추가) | 테스트가 임시 포트 (0) 를 쓴다. 운영은 기본값 8765 | `Int` |
| `httpClient` (새로 추가) | 테스트가 타임아웃이 짧은 클라이언트를 넣을 수 있다. 기본값은 지금의 타임아웃 설정 (연결 20초, 읽기 120초, 쓰기 20초) | `OkHttpClient` |
| `registerTrackStream(...)` (동작 보정) | 반환 URL 의 포트를 상수 `PROXY_PORT` 대신 실제로 열린 포트로 만든다. 운영에서는 둘이 같아 결과가 같다 | 기존과 같음 → `String` |

### `PlaybackCommandRouter` (Kotlin, 새로 추가)

```kotlin
class PlaybackCommandRouter(
    private val auth: AuthControls,
    private val player: () -> PlayerControls?,
    private val device: DeviceControls,
    private val proxy: ProxyRegistrar,
) {
    fun handle(method: String, args: Map<String, Any?>): CommandResult
}
```

| 메서드 | 목적 | 입력 | 출력 |
| --- | --- | --- | --- |
| `handle` | 채널 메서드 16개를 협력 객체 호출로 옮기고 결과를 만든다 | `method`: 채널 메서드 이름, `args`: 채널 인자 맵 (없으면 빈 맵) | `CommandResult` |

`player` 가 함수인 이유: 플레이어는 `initTidalAuth` 가 성공한 뒤에야 생기므로 호출 시점에 조회한다. null 이면 플레이어 동작은 오류 결과가 된다 (지금의 "TIDAL Player가 초기화되지 않았습니다").

### 협력 인터페이스 (Kotlin, 새로 추가)

```kotlin
sealed interface CommandResult {
    data class Success(val value: Any?) : CommandResult
    data class Error(val code: String, val message: String?) : CommandResult
    data object NotImplemented : CommandResult
}

interface PlayerControls {
    fun playTrack(trackId: String)
    fun pause()
    fun resume()
    fun seekTo(msec: Int)
    fun stop()
    fun skipToNext()
    fun setNextTrack(trackId: String)
    fun setAudioQuality(name: String)
}

interface AuthControls {
    /** 인증을 초기화하고, 성공하면 플레이어를 만들어 초기화한다. 반환: 인증 초기화 성공 여부. */
    fun initialize(clientId: String, clientSecret: String): Boolean
    fun updateUserCredentials(userId: String, accessToken: String, expiresInSeconds: Long)
    fun clearUserCredentials()
}

interface DeviceControls {
    fun phoneVolumePercent(): Int
    fun setPhoneVolumePercent(percent: Int)
    fun requestNotificationPermission(): Boolean
    fun setWifiLock(enabled: Boolean)
}

fun interface ProxyRegistrar {
    /** 반환: 프록시 URL. Wi-Fi 가 없어 프록시를 띄울 수 없으면 null. */
    fun registerTrackStream(
        trackId: String, directUrl: String, manifestXml: String, allowedHost: String, mimeType: String,
    ): String?
}
```

- `PlayerControls` 의 8개 메서드는 `TidalPlayerManager` 의 지금 공개 메서드와 이름 · 인자가 같다. `TidalPlayerManager` 는 `: PlayerControls` 와 `override` 만 추가한다
- 모든 메서드는 동기 호출이다 (지금의 `onMethodCall` 도 동기)

### `PlaybackCore` (Kotlin, 변경)

```kotlin
// 남는 것: attach, emit, 볼륨 관찰, requestStreamFromDart, requestTokenFromDart, ensureProxyServer, setWifiLock
// 바뀌는 것:
private val router = PlaybackCommandRouter(auth = ..., player = { playerManager }, device = ..., proxy = ...)

private fun onMethodCall(call: MethodCall, result: MethodChannel.Result)
    // call.method, call.arguments → router.handle → CommandResult 를 result.success / error / notImplemented 로 옮김
```

채널 이름, 메서드 이름, 인자 키, 반환 맵의 키와 값은 바꾸지 않는다.

## 2. 테스트 지원 컴포넌트 (Dart)

### `FakeNativeChannel` (새로 추가, `test/helpers/fake_native_channel.dart`)

```dart
class FakeNativeChannel {
  static const channelName = 'com.example.tidal_connect_lite/tidal_sdk';

  final List<MethodCall> calls = [];
  final Map<String, Object? Function(MethodCall call)> responses = {};
  final Set<String> failing = {};

  void install();
  void uninstall();
  List<MethodCall> callsOf(String method);
  Future<Object?> invokeFromNative(String method, [Object? arguments]);
}
```

| 메서드 | 목적 | 입력 → 출력 |
| --- | --- | --- |
| `install` / `uninstall` | 테스트 바인딩에 가짜 채널 핸들러를 걸고 푼다 (`setUp` / `tearDown`) | - |
| `responses` | 메서드별 반환값 지정. 지정이 없으면 null 반환 | `MethodCall` → 반환값 |
| `failing` | 여기 든 메서드는 `PlatformException` 을 던진다 | 메서드 이름 집합 |
| `callsOf` | 특정 메서드의 호출 기록 | 메서드 이름 → `List<MethodCall>` |
| `invokeFromNative` | Kotlin → Dart 호출 (`refreshTrackStream`, `refreshUserToken`) 을 흉내 낸다 | 메서드 이름, 인자 → Dart 핸들러의 반환값 |

### `FakeSoapClient` (새로 추가, `test/helpers/fake_soap_client.dart`)

```dart
class FakeSoapClient extends UPnPSoapClient {
  final List<String> calls = [];               // '<액션>:<controlUrl>' 순서 기록
  final Map<String, bool> commandResults = {}; // 액션별 성공 여부, 지정 없으면 true
  String? transportState;                      // getTransportInfo 결과, null = 응답 없음
  Map<String, String>? positionInfo;           // getPositionInfo 결과 (RelTime, TrackDuration, TrackURI)
  int? volume;                                 // getVolume 결과
  DidlMetadata? lastMetadata;
  String? lastStreamUrl;
  String? lastRelTime;
  int? lastVolume;

  // UPnPSoapClient 의 공개 메서드 10개를 모두 override:
  // setAVTransportURI, setNextAVTransportURI, play, pause, stop, seek,
  // getTransportInfo, getPositionInfo, getVolume, setVolume
}
```

### 기존 fake 확장

| fake | 추가하는 것 | 목적 |
| --- | --- | --- |
| `FakeSsdpDiscoveryService` | `List<DlnaDevice> devices` 필드. `discoverDevices` 가 이 목록을 돌려주고 기기마다 `onDeviceFound` 를 호출. 기본값은 지금처럼 폰 스피커만 | `DlnaManager` 탐색 · 선택 복원 테스트 |
| `FakeAuthRepository` | `AuthToken? validUserToken` 필드, `getValidUserToken()` override | `DlnaBackend` 의 로그인 여부 분기 |
| `FakeApiClient` | `Map<String, TidalPlaybackInfo?> playbackInfos` 필드, `getPlaybackInfo(trackId, {quality})` override (호출 기록 포함) | `DlnaBackend` 의 스트림 정보 분기 (직접 URL · DASH · 없음) |
| `FakeBackend` | `test/helpers/fake_backend.dart` 로 이동. `pause` · `resume` · `seek` · `stop` 호출 기록 추가. 기존 필드 (`played`, `onPlay`, `nextRequests`, `quality`, `controller`) 는 유지 | `WaveAudioHandler` 명령 전달 검증, `player_manager_test.dart` 와 공용 |

기존 fake 의 기본 동작은 바꾸지 않는다 (기존 95개 테스트가 그대로 통과해야 한다).

## 3. 테스트 지원 컴포넌트 (Kotlin)

### `FakeCdnServer` (새로 추가)

```kotlin
class FakeCdnServer : Closeable {
    val baseUrl: String                                    // http://127.0.0.1:<임시 포트>
    val requests: List<RecordedRequest>                    // method, path, headers
    fun respond(path: String, status: Int, headers: Map<String, String> = emptyMap(), body: ByteArray = ByteArray(0))
    fun respondSequence(path: String, vararg responses: CannedResponse)  // 첫 요청 403, 다음 요청 200 같은 순서 응답
    override fun close()
}
```

구현 수단 (프로젝트에 이미 있는 NanoHTTPD 를 쓸지, 다른 테스트 라이브러리를 쓸지) 은 NFR Requirements 에서 정한다.

### router 용 fake 4개 (새로 추가)

```kotlin
class FakePlayerControls : PlayerControls   // calls: List<String>, failWith: Exception?
class FakeAuthControls : AuthControls       // initializeResult: Boolean, calls 기록
class FakeDeviceControls : DeviceControls   // volume: Int, permissionResult: Boolean, calls 기록
class FakeProxyRegistrar : ProxyRegistrar   // url: String? (null = Wi-Fi 없음), calls 기록
```

## 4. CI 컴포넌트

### `CoverageGate` (새로 추가, `tool/`)

| 항목 | 내용 |
| --- | --- |
| 입력 | lcov 파일 경로 (`coverage/lcov.info`), 대상 파일 목록 (4개), 기준 백분율 (80) |
| 출력 | 파일별 커버리지 표 (표준 출력), 종료 코드 0 (모두 기준 이상) 또는 1 (미달 · 대상 파일이 lcov 에 없음) |
| 호출 | `tool/check.sh` 의 Dart 테스트 단계 바로 뒤 |

대상 파일이 lcov 에 아예 없는 경우 (어떤 테스트도 import 하지 않음) 를 미달로 처리해야 한다. 지금 `wave_audio_handler.dart` 가 그 상태다.
