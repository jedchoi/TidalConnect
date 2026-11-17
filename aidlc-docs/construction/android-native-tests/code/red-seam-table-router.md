# 테스트 경계 표 (RED 1단계) - router 담당

unit `android-native-tests` 의 Code Generation 계획 Step 4.1 산출물이다. `PlaybackCommandRouter` 와 채널 변환 함수의 테스트를 쓰기 전에 승인받을 표다 (패턴 TW-3, 사람 관문 1). 이 문서는 표만 담는다. 테스트 코드는 승인 뒤에 쓴다.

- 범위: CR-01 ~ CR-13, PC-01, PC-02, P-CR-1 ~ P-CR-6
- 근거 문서: `business-rules.md` 1 · 2 · 4 · 7절, `business-logic-model.md` 1 · 3절, `domain-entities.md` 1 · 4절, `nfr-design-patterns.md` 1 · 3절, `logical-components.md` 3절, 뼈대 파일 3개
- 읽지 않은 것: `PlaybackCore.kt` 등 구현 본문, `lib/`, `component-methods.md` (읽기 목록에 없었다. 시그니처는 뼈대 파일에서 가져왔다)
- 표기: `{status: "paused"}` 는 `CommandResult.Success(mapOf("status" to "paused"))` 를 뜻한다. `Success(null)`, `Success(37)` 처럼 맵이 아닌 값은 그대로 적었다
- 2026-11-17 갱신: 처음 표에서 낸 질문 11개가 규칙 문서 보완 (`business-rules.md` CR-01 · CR-02 · CR-07 · CR-10 · PC-01 · PC-03, `nfr-requirements.md` NFR-01-A1 · A2 · NFR-05-A2) 과 이 작업의 조정 세션이 전달한 결정으로 모두 답해져 표에 반영했다. 남은 질문은 없다 (6절). 반영 내용은 7절에 있다

## 1. 경계 (seam) 목록

테스트가 부르는 공개 함수는 아래 넷뿐이다. 내부 함수나 내부 상태는 보지 않는다 (TW-3, TW-9).

| 경계 | 시그니처 (뼈대 파일 그대로) | 파일 |
| --- | --- | --- |
| router 생성자 | `PlaybackCommandRouter(auth: AuthControls, player: () -> PlayerControls?, device: DeviceControls, proxy: ProxyRegistrar)` | `PlaybackCommandRouter.kt` |
| 명령 처리 | `fun handle(method: String, args: Map<String, Any?>): CommandResult` | `PlaybackCommandRouter.kt` |
| 채널 인자 변환 | `fun channelArguments(call: MethodCall): Map<String, Any?>` | `ChannelAdapter.kt` |
| 채널 응답 변환 | `fun sendCommandResult(commandResult: CommandResult, result: MethodChannel.Result)` | `ChannelAdapter.kt` |

테스트가 값으로 쓰는 타입 (`PlaybackContracts.kt`):

- `CommandResult.Success(value: Any?)`, `CommandResult.Error(code: String, message: String?)`, `CommandResult.NotImplemented`
- fake 가 구현하는 인터페이스: `PlayerControls` (8개 함수), `AuthControls` (3개), `DeviceControls` (4개), `ProxyRegistrar` (1개)

"플레이어가 아직 없음" 은 생성자의 `player` 함수가 null 을 돌려주게 해서 만든다. 테스트는 `var currentPlayer: PlayerControls?` 를 두고 `{ currentPlayer }` 를 넘긴다.

## 2. 예시 기반 테스트 표

읽는 법:

- 한 행이 `@Test` 함수 하나다. 이름은 규칙 ID 로 시작하는 한국어 문장이다 (KV-4, 대괄호 없음). "(표)" 라고 적은 행은 한 함수 안에서 여러 입력을 돈다
- 기대값의 "호출" 은 fake 가 남긴 문자열 기록이다 (4절). `player: playTrack(101)` 은 `FakePlayerControls.calls` 가 정확히 `["playTrack(101)"]` 이라는 뜻이다. **적지 않은 fake 의 `calls` 는 빈 목록임을 함께 단언한다** (호출이 그 1건뿐임을 확인)
- 모든 행은 결과 (`CommandResult` 값 비교, KV-1) 와 호출 기록을 둘 다 단언한다 (안티패턴 4)
- 따로 적지 않으면 fake 설정은 이렇다: 플레이어 있음 (예외 없음), `auth.initialize` → true, `phoneVolumePercent` → 37, `requestNotificationPermission` → true, `proxy.registerTrackStream` → `"http://192.0.2.1:8765/audio/0123456789abcdef.flac"`

고정 문구 (규칙 문서에서 그대로 옮김):

- 플레이어 없음 메시지: `"TIDAL Player가 초기화되지 않았습니다"`
- Wi-Fi 없음 메시지: `"Wi-Fi에 연결되어 있지 않아 스피커로 스트리밍할 수 없습니다."`

| 규칙 ID | 경계 | 입력 | 기대값 | 테스트 파일 |
| --- | --- | --- | --- | --- |
| CR-01 (표) | `handle` | 아래 "CR-01 메서드 표" 의 17줄 | 줄마다: 결과가 표의 `CommandResult` 와 같고, 호출 기록이 표의 1건뿐 | `PlaybackCommandRouterTest.kt` |
| CR-02 (a) (표) | `handle` | 인자가 있는 메서드 9개를 빈 맵으로 호출. 아래 "CR-02 기본값 표" | 줄마다: 표의 기본값으로 호출 1건, 표의 결과 | `PlaybackCommandRouterTest.kt` |
| CR-02 (b) (표) | `handle` | 일부 키만 있음: ① `updateUserCredentials` `{userId: "user-1"}` ② `initTidalAuth` `{clientId: "test-client-id"}` ③ `registerTrackStream` `{trackId: "101", manifestXml: "<MPD/>"}` | ① `auth: updateUserCredentials(user-1, , 3600)`, `{status: "updated", userId: "user-1"}` ② `auth: initialize(test-client-id, )`, `{status: "initialized", sdk: "com.tidal.sdk", clientId: "test-client-id"}` ③ `proxy: registerTrackStream(101, , <MPD/>, , audio/mp4)`, `{proxyUrl: "http://192.0.2.1:8765/audio/0123456789abcdef.flac"}` | `PlaybackCommandRouterTest.kt` |
| CR-02 (c) (표) | `handle` | 키는 있는데 값이 null: ① `playTrack` `{trackId: null}` ② `seekTrack` `{positionMs: null}` ③ `setAudioQuality` `{quality: null}` ④ `setStreamingLock` `{enabled: null}` ⑤ `updateUserCredentials` `{userId: "user-1", accessToken: null, expiresInSeconds: null}` ⑥ `registerTrackStream` `{trackId: "101", mimeType: null}` | ① `player: playTrack()`, `{status: "playing", trackId: ""}` ② `player: seekTo(0)`, `{status: "seeked", positionMs: 0}` ③ `player: setAudioQuality(LOSSLESS)`, `{status: "quality_set", quality: "LOSSLESS"}` ④ `device: setWifiLock(false)`, `Success(null)` ⑤ `auth: updateUserCredentials(user-1, , 3600)`, `{status: "updated", userId: "user-1"}` ⑥ `proxy: registerTrackStream(101, , , , audio/mp4)`, `{proxyUrl: "http://192.0.2.1:8765/audio/0123456789abcdef.flac"}` | `PlaybackCommandRouterTest.kt` |
| CR-03 (표) | `handle` | 메서드 이름 `"unknownMethod"`, `""`, `"PlayTrack"`, `"playtrack"`, `"playTrackX"`, `"xplayTrack"`. 인자는 `{trackId: "101"}` | 모두 `CommandResult.NotImplemented`. fake 4개의 `calls` 가 모두 빈 목록 | `PlaybackCommandRouterTest.kt` |
| CR-04 (a) | `handle` | `initTidalAuth` `{clientId: "test-client-id", clientSecret: "test-client-secret"}`, `auth.initialize` → true | `{status: "initialized", sdk: "com.tidal.sdk", clientId: "test-client-id"}`. `auth: initialize(test-client-id, test-client-secret)` | `PlaybackCommandRouterTest.kt` |
| CR-04 (b) | `handle` | 같은 입력, `auth.initialize` → false | `{status: "init_failed", sdk: "com.tidal.sdk", clientId: "test-client-id"}` (`Success` 다, `Error` 가 아니다). `auth: initialize(test-client-id, test-client-secret)` | `PlaybackCommandRouterTest.kt` |
| CR-05 (표) | `handle` | 플레이어 없음. `playTrack` `{trackId: "101"}`, `pauseTrack` `{}`, `resumeTrack` `{}`, `seekTrack` `{positionMs: 90000}`, `skipToNext` `{}`, `setNextTrack` `{trackId: "102"}`, `setAudioQuality` `{quality: "HIGH"}` | 7개 모두 `Error("PLAYER_ERROR", "TIDAL Player가 초기화되지 않았습니다")`. auth · device · proxy 의 `calls` 가 빈 목록 | `PlaybackCommandRouterTest.kt` |
| CR-06 | `handle` | 플레이어 없음. `stopTrack` `{}` | `{status: "stopped"}`. auth · device · proxy 의 `calls` 가 빈 목록 | `PlaybackCommandRouterTest.kt` |
| CR-07 (a) (표) | `handle` | 플레이어가 모든 호출에 `IllegalStateException("재생 실패")` 를 던짐. 플레이어 동작 8개 (CR-05 의 7개와 같은 인자 + `stopTrack` `{}`) | 8개 모두 `Error("PLAYER_ERROR", "재생 실패")`. 플레이어 호출이 시도된 1건이 기록됨 (예: `player: playTrack(101)`, `player: stop()`) | `PlaybackCommandRouterTest.kt` |
| CR-07 (b) (표) | `handle` | 플레이어가 모든 호출에 메시지 없는 `IllegalStateException()` 을 던짐. 플레이어 동작 8개 | 8개 모두 `Error("PLAYER_ERROR", "IllegalStateException")` (패키지 없는 단순 이름). 호출 기록은 (a) 와 같음 | `PlaybackCommandRouterTest.kt` |
| CR-07 (c) (표) | `handle` | 플레이어가 모든 호출에 메시지가 빈 문자열인 `IllegalStateException("")` 을 던짐. 플레이어 동작 8개 | 8개 모두 `Error("PLAYER_ERROR", "")` (빈 문자열 그대로, 클래스 이름으로 바꾸지 않음). 호출 기록은 (a) 와 같음 | `PlaybackCommandRouterTest.kt` |
| CR-08 | `handle` | `registerTrackStream` `{trackId: "101", directUrl: "https://cdn.example.test/101.flac", manifestXml: "<MPD/>", allowedHost: "192.0.2.10", mimeType: "audio/flac"}`, `proxy.registerTrackStream` → null | `Error("NO_WIFI", "Wi-Fi에 연결되어 있지 않아 스피커로 스트리밍할 수 없습니다.")`. `proxy: registerTrackStream(101, https://cdn.example.test/101.flac, <MPD/>, 192.0.2.10, audio/flac)` | `PlaybackCommandRouterTest.kt` |
| CR-09 (a) | `handle` | `setStreamingLock` `{enabled: true}` | `Success(null)`. `device: setWifiLock(true)` | `PlaybackCommandRouterTest.kt` |
| CR-09 (b) | `handle` | `setStreamingLock` `{enabled: false}` | `Success(null)`. `device: setWifiLock(false)` | `PlaybackCommandRouterTest.kt` |
| CR-09 (c) | `handle` | `setStreamingLock` `{}` (`enabled` 없음) | `Success(null)`. `device: setWifiLock(false)` | `PlaybackCommandRouterTest.kt` |
| CR-10 (a) (표) | `handle` | 숫자 인자가 Int: ① `seekTrack` `{positionMs: 90000}` ② `setPhoneVolume` `{percent: 42}` ③ `updateUserCredentials` `{userId: "user-1", accessToken: "test-access-token", expiresInSeconds: 7200}` | ① `player: seekTo(90000)`, `{status: "seeked", positionMs: 90000}` ② `device: setPhoneVolumePercent(42)`, `Success(null)` ③ `auth: updateUserCredentials(user-1, test-access-token, 7200)`, `{status: "updated", userId: "user-1"}` | `PlaybackCommandRouterTest.kt` |
| CR-10 (b) (표) | `handle` | 같은 세 호출, 숫자 인자가 Long (`90000L`, `42L`, `7200L`) | 호출 기록과 결과가 모두 (a) 와 같다. ① 의 결과는 `{status: "seeked", positionMs: 90000}` 이고 `positionMs` 는 Int 90000 이다 (Long 90000 이 Int 로 바뀜). `CommandResult` 전체를 값으로 비교한다 | `PlaybackCommandRouterTest.kt` |
| CR-11 (a) (표) | `handle` | 문자열 자리에 숫자: ① `playTrack` `{trackId: 101}` ② `setAudioQuality` `{quality: 1}` ③ `registerTrackStream` `{trackId: "101", mimeType: 5}` | ① `player: playTrack()`, `{status: "playing", trackId: ""}` ② `player: setAudioQuality(LOSSLESS)`, `{status: "quality_set", quality: "LOSSLESS"}` ③ `proxy: registerTrackStream(101, , , , audio/mp4)`, `{proxyUrl: "http://192.0.2.1:8765/audio/0123456789abcdef.flac"}` | `PlaybackCommandRouterTest.kt` |
| CR-11 (b) (표) | `handle` | 정수 자리에 문자열: ① `seekTrack` `{positionMs: "5000"}` ② `setPhoneVolume` `{percent: "42"}` ③ `updateUserCredentials` `{userId: "user-1", accessToken: "test-access-token", expiresInSeconds: "60"}` | ① `player: seekTo(0)`, `{status: "seeked", positionMs: 0}` ② `device: setPhoneVolumePercent(0)`, `Success(null)` ③ `auth: updateUserCredentials(user-1, test-access-token, 3600)`, `{status: "updated", userId: "user-1"}` | `PlaybackCommandRouterTest.kt` |
| CR-11 (c) (표) | `handle` | 불리언 자리에 다른 타입: `setStreamingLock` `{enabled: "true"}`, `{enabled: 1}` | 둘 다 `Success(null)`, `device: setWifiLock(false)` | `PlaybackCommandRouterTest.kt` |
| CR-12 (a) (표) | `handle` | `FakeAuthControls` 가 모든 호출에 `IllegalStateException("auth 실패")` 를 던짐. `initTidalAuth`, `updateUserCredentials`, `clearUserCredentials` (인자는 CR-01 표와 같음) | `handle` 이 `CommandResult` 를 돌려주지 않고 fake 가 던진 **그 예외 객체** 가 그대로 나온다 (`assertSame`). 호출 시도 1건이 기록됨 (예: `auth: clearUserCredentials()`) | `PlaybackCommandRouterTest.kt` |
| CR-12 (b) (표) | `handle` | `FakeDeviceControls` 가 모든 호출에 `IllegalStateException("device 실패")` 를 던짐. `getPhoneVolume`, `setPhoneVolume` `{percent: 42}`, `requestNotificationPermission`, `setStreamingLock` `{enabled: true}` | (a) 와 같은 방식. 예: `device: setPhoneVolumePercent(42)` 가 기록되고 같은 예외 객체가 나옴 | `PlaybackCommandRouterTest.kt` |
| CR-12 (c) | `handle` | `FakeProxyRegistrar` 가 `IllegalStateException("proxy 실패")` 를 던짐. `registerTrackStream` (CR-08 과 같은 인자) | 같은 예외 객체가 나옴. `proxy: registerTrackStream(101, https://cdn.example.test/101.flac, <MPD/>, 192.0.2.10, audio/flac)` | `PlaybackCommandRouterTest.kt` |
| CR-13 (a) | `handle` | 같은 router 에 `playTrack` `{trackId: "101"}` 를 두 번, 이어서 `getPhoneVolume` 을 두 번 | `playTrack` 두 결과 모두 `{status: "playing", trackId: "101"}`, `getPhoneVolume` 두 결과 모두 `Success(37)`. `player: playTrack(101), playTrack(101)`, `device: phoneVolumePercent(), phoneVolumePercent()` | `PlaybackCommandRouterTest.kt` |
| CR-13 (b) | `handle` | 같은 router. 플레이어 없음 상태에서 `playTrack` `{trackId: "101"}` → 플레이어를 넣은 뒤 같은 호출 (근거: `business-logic-model.md` 1.2 "호출할 때마다 조회") | 첫 결과 `Error("PLAYER_ERROR", "TIDAL Player가 초기화되지 않았습니다")`, 둘째 결과 `{status: "playing", trackId: "101"}`. `player: playTrack(101)` 1건 | `PlaybackCommandRouterTest.kt` |
| PC-01 (a) | `channelArguments` | `MethodCall("seekTrack", mapOf("trackId" to "101", "positionMs" to 90000L, "enabled" to true))` | 돌려준 맵이 `mapOf("trackId" to "101", "positionMs" to 90000L, "enabled" to true)` 와 같다 (키 · 값 · 타입 그대로) | `ChannelAdapterTest.kt` |
| PC-01 (b) (표) | `channelArguments` | `arguments` 가 맵이 아님: `null`, `"101"`, `listOf("101")`, `42` | 모두 빈 맵 | `ChannelAdapterTest.kt` |
| PC-02 (a) (표) | `sendCommandResult` | `Success` 의 값 4종: `mapOf("status" to "paused")`, `37`, `true`, `null` | 기록용 `MethodChannel.Result` 가 받은 응답이 정확히 1건이고 `success(<같은 값>)` 이다. `error` · `notImplemented` 는 없음 | `ChannelAdapterTest.kt` |
| PC-02 (b) (표) | `sendCommandResult` | ① `Error("PLAYER_ERROR", "TIDAL Player가 초기화되지 않았습니다")` ② `Error("PLAYER_ERROR", null)` | 받은 응답이 정확히 1건이고 ① `error("PLAYER_ERROR", "TIDAL Player가 초기화되지 않았습니다", null)` ② `error("PLAYER_ERROR", null, null)` | `ChannelAdapterTest.kt` |
| PC-02 (c) | `sendCommandResult` | `CommandResult.NotImplemented` | 받은 응답이 정확히 1건이고 `notImplemented()` | `ChannelAdapterTest.kt` |

행 수: CR 26행 (CR-01 1, CR-02 3, CR-03 1, CR-04 2, CR-05 1, CR-06 1, CR-07 3, CR-08 1, CR-09 3, CR-10 2, CR-11 3, CR-12 3, CR-13 2) + PC 5행 (PC-01 2, PC-02 3) = 31행.

테스트하지 않는 입력 (규칙 문서가 입력 범위 밖으로 정함): 정수 인자의 소수와 Int 범위를 넘는 값 (CR-10), 키가 문자열이 아닌 인자 맵 (PC-01). PC-01 의 "메서드 이름을 router 에 넘긴다" 와 PC-03 은 단위 테스트 대상이 아니다 (빌드 · 코드 검토 · `git diff` 로 확인).

### CR-01 메서드 표

테스트 하나가 이 표를 돈다. 줄마다 새 fake 와 새 router 를 만든다. 메서드는 16개이고 줄은 17개다: `requestNotificationPermission` 의 성공 값이 "그 반환값 (bool)" 이라 true · false 두 줄로 나눴다 (두 줄 유지로 확정).

| # | 메서드 | 인자 | fake 설정 | 기대 호출 (그 밖의 fake 는 빈 목록) | 기대 `CommandResult` |
| --- | --- | --- | --- | --- | --- |
| 1 | `initTidalAuth` | `{clientId: "test-client-id", clientSecret: "test-client-secret"}` | `initialize` → true | `auth: initialize(test-client-id, test-client-secret)` | `{status: "initialized", sdk: "com.tidal.sdk", clientId: "test-client-id"}` |
| 2 | `updateUserCredentials` | `{userId: "user-1", accessToken: "test-access-token", expiresInSeconds: 7200}` | - | `auth: updateUserCredentials(user-1, test-access-token, 7200)` | `{status: "updated", userId: "user-1"}` |
| 3 | `clearUserCredentials` | `{}` | - | `auth: clearUserCredentials()` | `{status: "cleared"}` |
| 4 | `playTrack` | `{trackId: "101"}` | - | `player: playTrack(101)` | `{status: "playing", trackId: "101"}` |
| 5 | `pauseTrack` | `{}` | - | `player: pause()` | `{status: "paused"}` |
| 6 | `resumeTrack` | `{}` | - | `player: resume()` | `{status: "resumed"}` |
| 7 | `seekTrack` | `{positionMs: 90000}` | - | `player: seekTo(90000)` | `{status: "seeked", positionMs: 90000}` |
| 8 | `stopTrack` | `{}` | 플레이어 있음 | `player: stop()` | `{status: "stopped"}` |
| 9 | `skipToNext` | `{}` | - | `player: skipToNext()` | `{status: "skipped_to_next"}` |
| 10 | `setNextTrack` | `{trackId: "102"}` | - | `player: setNextTrack(102)` | `{status: "next_track_set", trackId: "102"}` |
| 11 | `setAudioQuality` | `{quality: "HI_RES_LOSSLESS"}` | - | `player: setAudioQuality(HI_RES_LOSSLESS)` | `{status: "quality_set", quality: "HI_RES_LOSSLESS"}` |
| 12 | `getPhoneVolume` | `{}` | `phoneVolumePercent` → 37 | `device: phoneVolumePercent()` | `Success(37)` |
| 13 | `setPhoneVolume` | `{percent: 42}` | - | `device: setPhoneVolumePercent(42)` | `Success(null)` |
| 14 | `requestNotificationPermission` | `{}` | 반환 true | `device: requestNotificationPermission()` | `Success(true)` |
| 15 | `requestNotificationPermission` | `{}` | 반환 false | `device: requestNotificationPermission()` | `Success(false)` |
| 16 | `setStreamingLock` | `{enabled: true}` | - | `device: setWifiLock(true)` | `Success(null)` |
| 17 | `registerTrackStream` | `{trackId: "101", directUrl: "https://cdn.example.test/101.flac", manifestXml: "<MPD/>", allowedHost: "192.0.2.10", mimeType: "audio/flac"}` | 반환 `"http://192.0.2.1:8765/audio/0123456789abcdef.flac"` | `proxy: registerTrackStream(101, https://cdn.example.test/101.flac, <MPD/>, 192.0.2.10, audio/flac)` | `{proxyUrl: "http://192.0.2.1:8765/audio/0123456789abcdef.flac"}` |

### CR-02 기본값 표 (빈 맵으로 호출)

인자가 있는 메서드는 9개다. 기본값은 `business-rules.md` 메서드 표의 괄호 값이다.

| # | 메서드 | 기대 호출 | 기대 `CommandResult` |
| --- | --- | --- | --- |
| 1 | `initTidalAuth` | `auth: initialize(, )` | `{status: "initialized", sdk: "com.tidal.sdk", clientId: ""}` |
| 2 | `updateUserCredentials` | `auth: updateUserCredentials(, , 3600)` | `{status: "updated", userId: ""}` |
| 3 | `playTrack` | `player: playTrack()` | `{status: "playing", trackId: ""}` |
| 4 | `seekTrack` | `player: seekTo(0)` | `{status: "seeked", positionMs: 0}` |
| 5 | `setNextTrack` | `player: setNextTrack()` | `{status: "next_track_set", trackId: ""}` |
| 6 | `setAudioQuality` | `player: setAudioQuality(LOSSLESS)` | `{status: "quality_set", quality: "LOSSLESS"}` |
| 7 | `setPhoneVolume` | `device: setPhoneVolumePercent(0)` | `Success(null)` |
| 8 | `setStreamingLock` | `device: setWifiLock(false)` | `Success(null)` |
| 9 | `registerTrackStream` | `proxy: registerTrackStream(, , , , audio/mp4)` | `{proxyUrl: "http://192.0.2.1:8765/audio/0123456789abcdef.flac"}` |

빈 문자열 인자는 기록에서 빈 자리로 보인다 (`playTrack()`, `initialize(, )`). fake 의 기록 형식 때문이다 (4절).

## 3. 속성 테스트 표

- 설정: `PbtSupport.kt` 의 `pbt(100)` 과 `property { }` 를 쓴다 (KP-1, KP-2). seed 는 `PBT_SEED` 또는 20261117. 축소 설정은 건드리지 않는다 (KP-5)
- 생성기는 모두 `RouterGenerators.kt` 에 Kotest `Arb` 로 둔다 (NFR-04-A7)
- 한 속성이 `@Test` 함수 하나다. 이름은 `P-CR-1 ...` 처럼 속성 ID 로 시작한다
- 예시마다 새 fake 와 새 router 를 만든다
- 속성 안의 기대값은 생성된 입력 그 자체 (전달 여부 확인) 또는 규칙 문서의 고정 문구다. router 의 분기 · 해석을 테스트에서 다시 계산하지 않는다

| 속성 ID | 생성기 (domain-entities.md 4절의 범위) | 검증하는 것 | 실행 횟수 | 테스트 파일 |
| --- | --- | --- | --- | --- |
| P-CR-1 | 모르는 메서드 이름: 빈 문자열, 임의의 영문자 문자열, 알려진 16개 이름의 대소문자를 바꾼 것, 앞 또는 뒤에 글자를 붙인 것. 16개 이름과 같은 값은 걸러낸다. 인자는 빈 맵 (확정) | 결과가 `CommandResult.NotImplemented`. fake 4개 (플레이어 있음) 의 `calls` 가 모두 빈 목록 | 100 | `PlaybackCommandRouterTest.kt` |
| P-CR-2 | 플레이어 동작 이름 8개 중 하나 + 그 메서드의 인자 (곡 ID: 숫자 문자열 1 ~ 12자리와 빈 문자열, 재생 위치: 0 ~ 36,000,000 을 Int · Long 두 타입으로, 음질 이름: `LOW` · `HIGH` · `LOSSLESS` · `HI_RES_LOSSLESS` + 임의의 대문자 문자열. 각 인자는 있거나 없음). 플레이어 없음 | `stopTrack` 이면 `{status: "stopped"}`, 나머지 7개면 `Error("PLAYER_ERROR", "TIDAL Player가 초기화되지 않았습니다")`. auth · device · proxy 의 `calls` 가 빈 목록 | 100 | `PlaybackCommandRouterTest.kt` |
| P-CR-3 | 플레이어 동작 이름 8개 중 하나 + 예외 (클래스: `IllegalStateException` · `IllegalArgumentException` · `RuntimeException`, 메시지: 있음 (한글을 포함한 임의의 문자열, 빈 문자열 포함) 또는 없음 (null)). 인자는 빈 맵 (확정). 플레이어가 모든 호출에 그 예외를 던짐 | 결과가 `Error("PLAYER_ERROR", m)`. 메시지가 있으면 `m` 은 생성된 메시지 그대로 (빈 문자열이면 `""`). 메시지가 null 이면 `m` 은 단순 클래스 이름이다: 생성기가 예외와 함께 실어 주는 리터럴 `"IllegalStateException"` · `"IllegalArgumentException"` · `"RuntimeException"` 과 비교한다 (테스트에서 `simpleName` 으로 계산하지 않음). 플레이어 `calls` 가 1건 | 100 | `PlaybackCommandRouterTest.kt` |
| P-CR-4 | 메서드별 `checkAll` 6개. `playTrack` · `setNextTrack`: 곡 ID. `seekTrack`: 재생 위치 0 ~ 36,000,000 (Int · Long). `setAudioQuality`: 음질 이름. `updateUserCredentials`: `userId` · `accessToken` 은 임의의 영숫자 문자열, `expiresInSeconds` 는 1 ~ 86,400 (Int · Long). `setPhoneVolume`: 볼륨 −1000 ~ 1000 | 협력 객체가 받은 값이 입력과 같다 (예: `player: playTrack(<곡 ID>)`, `auth: updateUserCredentials(<userId>, <accessToken>, <초>)`, `device: setPhoneVolumePercent(<볼륨>)`: 범위 밖 값도 그대로). 성공 값에 실린 값이 입력과 같다 (`{status: "playing", trackId: <곡 ID>}`, `{status: "next_track_set", trackId}`, `{status: "seeked", positionMs}`, `{status: "quality_set", quality}`, `{status: "updated", userId}`, 볼륨은 `Success(null)`). `positionMs` 는 Int 값 v 를 만든 뒤 입력으로 v (Int) 또는 같은 값의 Long 을 넣고, 성공 값은 두 경우 모두 Int v 로 전체 비교한다 (CR-10) | `checkAll` 마다 100 | `PlaybackCommandRouterTest.kt` |
| P-CR-5 | 등록 인자: `trackId` (곡 ID), `directUrl` (URL 모양, `.test` 도메인), `manifestXml` (XML 조각), `allowedHost` (`127.0.0.1` 또는 문서용 예약 대역의 IPv4), `mimeType` (MIME) 각각 있음 (빈 문자열 포함) 또는 없음. 등록 함수가 돌려줄 URL: URL 모양의 임의 문자열 (확정) | `proxy.calls` 가 1건이고, 있는 인자는 입력 그대로, 없는 인자는 기본값 (`""` 넷, `mimeType` 은 `"audio/mp4"`). 결과가 `{proxyUrl: <fake 가 돌려준 URL>}` | 100 | `PlaybackCommandRouterTest.kt` |
| P-CR-6 | 임의의 채널 호출: 16개 메서드 중 하나 + 그 메서드의 인자 (위 생성기들, 각각 있거나 없음). fake 는 기본 설정으로 고정 (플레이어 있음, 예외 없음) | 같은 router 에 같은 호출을 두 번 했을 때 두 결과가 같다. 두 번째 호출 뒤의 호출 기록이 첫 번째 호출 뒤 기록을 두 번 이은 것과 같다 | 100 | `PlaybackCommandRouterTest.kt` |

속성 행: 6행.

## 4. fake 설계 요약

`RouterFakes.kt` 에 둔다 (KV-2). 공통 사항:

- `val calls: MutableList<String>`: 받은 호출을 순서대로 `함수이름(인자1, 인자2)` 형식으로 남긴다. 인자는 `toString()` 그대로, 구분은 쉼표와 공백 한 칸. 문자열에 따옴표를 붙이지 않는다 (`nfr-design-patterns.md` KV-2 의 예 `"playTrack(101)"` 과 같게)
- `var failure: RuntimeException?` (기본 null): 값이 있으면 모든 함수가 **호출을 기록한 뒤** 그 예외를 던진다
- 판단 로직을 넣지 않는다. 값 범위 제한 · 상태 변화가 없다
- 표에서 `player:` · `auth:` 같은 머리말은 어느 fake 의 `calls` 인지를 가리키는 표기다. 기록 문자열에는 들어가지 않는다

| fake | 기록하는 문자열 | 지정할 수 있는 것 |
| --- | --- | --- |
| `FakePlayerControls` (`PlayerControls`) | `playTrack(101)`, `pause()`, `resume()`, `seekTo(90000)`, `stop()`, `skipToNext()`, `setNextTrack(102)`, `setAudioQuality(HIGH)` | `failure` |
| `FakeAuthControls` (`AuthControls`) | `initialize(test-client-id, test-client-secret)`, `updateUserCredentials(user-1, test-access-token, 7200)`, `clearUserCredentials()` | `initializeResult: Boolean` (기본 true), `failure` |
| `FakeDeviceControls` (`DeviceControls`) | `phoneVolumePercent()`, `setPhoneVolumePercent(42)`, `requestNotificationPermission()`, `setWifiLock(true)` | `volumePercent: Int` (기본 37), `notificationPermission: Boolean` (기본 true), `failure` |
| `FakeProxyRegistrar` (`ProxyRegistrar`) | `registerTrackStream(101, https://cdn.example.test/101.flac, <MPD/>, 192.0.2.10, audio/flac)` | `result: String?` (기본 `"http://192.0.2.1:8765/audio/0123456789abcdef.flac"`, null 이면 Wi-Fi 없음), `failure` |

그 밖의 테스트 도우미:

- "플레이어 없음" 은 fake 가 아니라 router 생성자에 넘기는 함수 (`{ currentPlayer }`) 가 null 을 돌려주는 것으로 만든다. 이 함수가 몇 번 불렸는지는 단언하지 않는다 (내부 동작)
- `ChannelAdapterTest.kt` 안에 `MethodChannel.Result` 를 직접 구현한 기록용 클래스를 둔다 (`logical-components.md`). 받은 응답을 순서대로 `listOf("success", 값)`, `listOf("error", code, message, details)`, `listOf("notImplemented")` 로 남긴다
- 테스트 데이터의 주소는 `192.0.2.0/24` 와 `.test` 도메인만 쓴다. 자격 증명은 `test-` 로 시작하는 가짜 값이다

## 5. 뼈대에서 이미 통과할 것으로 예상되는 테스트

뼈대의 동작: `handle` 은 항상 `CommandResult.NotImplemented` 를 돌려주고 협력 객체를 부르지 않는다. `channelArguments` 는 항상 빈 맵을 돌려준다. `sendCommandResult` 는 아무것도 보내지 않는다.

### 통과 예상 ("보호" 로 표시할 것)

| 행 | 통과하는 이유 |
| --- | --- |
| CR-03 | 뼈대가 모든 이름에 `NotImplemented` 를 돌려주고 fake 를 부르지 않는다 (TW-1 에 적힌 경우) |
| P-CR-1 | CR-03 과 같다 |
| P-CR-6 | 두 결과가 모두 `NotImplemented` 라 같고, 호출 기록은 둘 다 비어 있다. 구현 뒤에 router 가 상태를 갖게 되는 실수를 막는 용도다. 뼈대에서는 내용 없이 통과한다. "결과가 `NotImplemented` 가 아님" 단언은 CR-01 의 규칙이라 넣지 않는다 (확정) |
| PC-01 (b) | 뼈대가 항상 빈 맵을 돌려준다 |

### 실패해야 하는 것 (RED)

| 행 | 예상 실패 |
| --- | --- |
| CR-01, CR-02 (a) (b) (c), CR-04 (a) (b), CR-06, CR-09 (a) (b) (c), CR-10 (a) (b), CR-11 (a) (b) (c), CR-13 (a) | `Success(...)` 를 기대했는데 `NotImplemented` |
| CR-05, CR-07 (a) (b) (c), CR-08, CR-13 (b) | `Error(...)` 를 기대했는데 `NotImplemented` |
| CR-12 (a) (b) (c) | 예외가 나와야 하는데 `NotImplemented` 가 돌아옴 (단언 실패) |
| PC-01 (a) | 인자 맵을 기대했는데 빈 맵 |
| PC-02 (a) (b) (c) | 응답 1건을 기대했는데 기록이 비어 있음 |
| P-CR-2, P-CR-3, P-CR-4, P-CR-5 | 첫 예시에서 `NotImplemented` 로 실패 (축소된 입력이 출력됨) |

결과 단언을 호출 기록 단언보다 먼저 두어, 실패 사유가 기대값 불일치로 나오게 한다.

정리: 예시 31행 가운데 2행 (CR-03, PC-01 (b)) 이 보호, 29행이 RED. 속성 6행 가운데 2행 (P-CR-1, P-CR-6) 이 보호, 4행이 RED. 실행 전의 예상이다. 실제 결과는 Step 4.4 의 RED 판정 표에서 확인한다.

## 6. 문서만으로 정할 수 없는 것

없음. 처음 표에서 낸 질문 11개는 2026-11-17 의 규칙 문서 보완과 조정 세션이 전달한 결정으로 모두 답해졌다 (7절).

참고 (표에 영향 없음): `business-rules.md` 2절 머리말에는 "Flutter 타입을 테스트 클래스패스에서 쓸 수 있으면 PC-01 ~ PC-03 은 테스트하고" 라는 문장이 남아 있다. 같은 절의 PC-03 행과 `nfr-requirements.md` NFR-01-A2 는 "PC-03 은 별도 테스트 없음" 으로 정정되었으므로 이 표는 정정된 쪽을 따랐다. 머리말 문구만 예전 그대로다.

## 7. 문서 보완으로 해결된 것

번호는 처음 표의 질문 번호다. "근거" 는 다시 읽어 확인한 문구의 위치다.

| # | 질문 | 답 | 근거 | 표에 반영한 것 |
| --- | --- | --- | --- | --- |
| 1 | 메시지 없는 예외의 "클래스 이름" 표기 | 패키지 없는 단순 이름 (예: `IllegalStateException`) | `business-rules.md` CR-07 | CR-07 (b) 의 기대값을 `Error("PLAYER_ERROR", "IllegalStateException")` 로 채움. P-CR-3 은 생성기가 실어 주는 단순 이름 리터럴과 비교 |
| 2 | 메시지가 빈 문자열인 예외 | 빈 문자열 그대로 | `business-rules.md` CR-07 | CR-07 (c) 행 추가. P-CR-3 생성기의 메시지에 빈 문자열 포함 |
| 3 | Long 으로 온 `positionMs` 의 성공 값 타입 | Int 로 바꾼 값 (Long 90000 → Int 90000) | `business-rules.md` CR-10 | CR-10 (b) 와 P-CR-4 를 Int 값 전체 비교로 바꿈 |
| 4 | 키는 있고 값이 null | 없는 인자와 같게 기본값 | `business-rules.md` CR-02 | CR-02 (c) 행 추가 |
| 5 | PC-01 의 메서드 이름 전달, 문자열이 아닌 키 | 단위 테스트는 `channelArguments` 만. 문자열이 아닌 키는 입력 범위 밖 | `business-rules.md` PC-01 | 행 변경 없음 |
| 6 | PC-03 의 테스트 여부 | 별도 테스트 없음 (CR-01 의 테스트와 `git diff` 로 확인) | `business-rules.md` PC-03, `nfr-requirements.md` NFR-01-A2 | 행 변경 없음 |
| 7 | 테스트 이름의 대괄호 | 대괄호 없이 규칙 ID 를 맨 앞에 | `nfr-requirements.md` NFR-01-A1, NFR-05-A2 (KV-4 와 일치) | 변경 없음 (처음부터 KV-4 를 따름) |
| 8 | P-CR-1 · P-CR-3 의 인자 맵, P-CR-5 의 반환 URL 범위 | 임시 처리대로: 빈 인자 맵, URL 모양 문자열 | 조정 세션이 전달한 결정 (문서 변경 없음) | 속성 표의 "질문" 표시를 "확정" 으로 바꿈 |
| 9 | "다른 협력 객체 호출 없음" 단언 | 단언한다 | `business-rules.md` CR-01 | 변경 없음 (나머지 fake 의 `calls` 가 빈 목록임을 계속 단언) |
| 10 | 소수 · Int 범위를 넘는 숫자 | 입력 범위 밖. 테스트하지 않음 | `business-rules.md` CR-10 | 2절 끝에 "테스트하지 않는 입력" 으로 적음 |
| 11 | `component-methods.md` 와의 대조 | 뼈대 파일이 시그니처의 기준 | 조정 세션이 전달한 결정 (문서 변경 없음) | 변경 없음 |

함께 정해진 것:

- CR-01 메서드 표: `requestNotificationPermission` 은 true · false 두 줄을 유지한다 (17줄)
- P-CR-6: 지금 내용 그대로 둔다. "결과가 `NotImplemented` 가 아님" 단언은 넣지 않는다. 뼈대에서 통과하므로 "보호" 로 표시한다
