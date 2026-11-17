# REFACTOR 후보 표 - android-native-tests (계획 Step 6.1)

2026-11-17, GREEN 을 끝낸 하위 에이전트가 작성. **승인 전이라 코드는 고치지 않았다.** 이 문서가 관문 3 (리팩토링 후보 승인) 의 판단 자료다.

`PlaybackCore` 는 Android · Flutter 런타임에 묶여 있어 JVM 단위 테스트로 실행해 볼 수 없다. 후보 2 (`onMethodCall` 위임) 가 지금 동작과 같은지는 테스트가 아니라 4절의 대조표, `javap` 확인, 빌드, 실기기 확인으로만 판단할 수 있다.

## 1. 시작 확인

| 확인 | 결과 |
| --- | --- |
| 테스트가 고정 커밋과 같음 | `git diff --exit-code 6acf424 -- android/app/src/test` → 차이 없음 (종료 코드 0) |
| GREEN 상태 | `PlaybackCommandRouterTest` 32 / 32, `ChannelAdapterTest` 5 / 5, `DashManifestTest` 4 / 4 통과 |
| 알려진 실패 | `TidalStreamProxyServerTest` 45개 중 3개 (`PX-17`, `PX-19`, `PX-38`). Step 8 의 `fix:` 에서 처리. 이 단계에서 건드리지 않음 |
| 기준 커밋 | `e913989` (GREEN), `b7e28ea` (O-7 · O-8 추가) |

## 2. 후보 표

| # | 후보 | 위치 | 이유 | 바뀌는 것 / 바뀌지 않는 것 | 동작 변화 위험 | 확인 방법 | 권고 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `TidalPlayerManager` 에 `PlayerControls` 구현 선언 | `TidalPlayerManager.kt`: 클래스 선언, 함수 8개 (`playTrack`, `pause`, `resume`, `seekTo`, `stop`, `skipToNext`, `setNextTrack`, `setAudioQuality`) | 후보 2 의 전제. router 의 `player` 가 `PlayerControls?` 를 받는다 (KR-1 3번) | 바뀜: `: PlayerControls` 와 `override` 8개. 안 바뀜: 함수 본문, 매개변수 이름 (`trackId`, `msec`, `name` 이 인터페이스와 이미 같다), 그 밖의 함수 | 없음. 선언만 추가된다 | Kotlin 테스트, 빌드, `git diff` 에 `override` 와 선언 줄만 있는지 | **적용** |
| 2 | `PlaybackCore.onMethodCall` 을 router 위임으로 교체, 협력 인터페이스 운영 구현 3개 연결, 쓰이지 않게 된 코드 삭제 | `PlaybackCore.kt`: `onMethodCall`, `requirePlayerManager`, `runPlayerAction`, 새 private 값 4 ~ 5개 | 메서드 분배 규칙 (CR-01 ~ CR-13) 이 `PlaybackCore` 와 router 두 곳에 있다. 한 곳으로 (TW-7, KR-1 4번, PC-04 ~ PC-06) | 3절 · 4절 참고 | **중간**. 정상 입력에서는 로그 말고 달라지는 것이 없다고 판단하지만, 실행으로 확인할 수단이 없다. 4.8 의 함정 2개는 틀리면 실기기에서 앱이 죽는다 | 4.9 | **적용** (4.5 의 실패 로그 처리 방법을 정한 뒤) |
| 3 | `args.number(key)?.toInt() ?: 0` 을 `int(key, default)` 도우미로 | `PlaybackCommandRouter.kt`: `seekTrack`, `setPhoneVolume` 분기 | 같은 식이 2번 나온다 | 바뀜: router 의 private 도우미 1개 추가. 안 바뀜: 결과 | 낮음 (router 테스트가 잡는다) | Kotlin 테스트 | **그대로 둠**. 2번뿐이고, "어느 인자를 Int 로, 어느 인자를 Long 으로 넘기는지" (CR-10) 가 지금은 분기에서 바로 보인다 |
| 4 | 플레이어가 없을 때 예외를 던졌다가 바로 잡는 구조를, 오류 결과를 직접 돌려주는 구조로 | `PlaybackCommandRouter.kt`: `requirePlayer`, `runPlayerAction` | 예외를 흐름 제어에 쓴다 | 바뀜: `runPlayerAction` 의 모양, `stopTrack` 분기에 try 가 따로 필요해진다. 안 바뀜: 결과 | 낮음 (router 테스트가 잡는다) | Kotlin 테스트 | **그대로 둠**. 지금 구조가 재구성 전의 `PlaybackCore` 와 1:1 이라 후보 2 의 대조 (4.2) 가 쉽다. 바꾸면 try 가 두 곳으로 늘어 오히려 중복이 생긴다 |
| 5 | `"PLAYER_ERROR"`, `"NO_WIFI"` 와 두 메시지를 상수로 | `PlaybackCommandRouter.kt` | 지금은 같은 문자열이 `PlaybackCore` 와 router 에 있다 | - | 낮음 | Kotlin 테스트 | **그대로 둠**. 후보 2 를 적용하면 `PlaybackCore` 쪽이 지워져 router 안에서 각각 1번만 쓰인다. 상수로 뽑을 이유가 사라진다 |
| 6 | `CommandResult.Success(mapOf("status" to ...))` 반복, `playTrack` · `setNextTrack` 의 같은 모양을 묶기 | `PlaybackCommandRouter.kt`: `handle` | 모양이 반복된다 | - | 낮음 | Kotlin 테스트 | **그대로 둠**. 분기 하나가 규칙 문서의 메서드 표 한 줄과 1:1 이다. 묶으면 표와 코드의 대응이 흐려진다 |
| 7 | 오래된 주석 고치기: "호출하는 쪽(MainActivity)이 Flutter에 오류로 돌려준다" | `TidalPlayerManager.kt` 162번째 줄 | 지금도 틀린 말이고 (돌려주는 쪽은 `PlaybackCore`), 후보 2 뒤에는 router 가 된다 | 바뀜: 주석 1줄. 안 바뀜: 코드 | 없음 | `git diff` | **적용** (후보 2 뒤, 주석만 담은 커밋) |

후보 3 ~ 6 은 GREEN 보고에서 올린 것이다. 넷 다 "그대로 둠" 을 권한다. router 는 129줄이고 규칙 표와 같은 모양이라, 지금 정리해서 얻는 것보다 후보 2 의 대조를 어렵게 만드는 손해가 크다.

## 3. 적용 순서와 커밋 단위

후보 하나가 커밋 하나다. 각 커밋 뒤에 아래 3개를 확인하고, 하나라도 실패하면 그 커밋의 변경을 되돌리고 원인을 보고한다.

- Kotlin 테스트: router 32 · 변환 5 · `DashManifestTest` 4 통과, 실패는 프록시 3개뿐 (결과 XML 로 셈)
- `git diff --exit-code 6acf424 -- android/app/src/test` 가 0
- `flutter build apk --debug --dart-define-from-file=config/tidal.json` 성공

| 순서 | 후보 | 커밋 메시지 (안) | 바꾸는 파일 |
| --- | --- | --- | --- |
| 1 | #1 | `refactor: TidalPlayerManager 가 PlayerControls 를 구현하도록 선언` | `TidalPlayerManager.kt` |
| 2 | #2 | `refactor: PlaybackCore.onMethodCall 을 PlaybackCommandRouter 위임으로 교체` | `PlaybackCore.kt` |
| 3 | #7 | `docs: TidalPlayerManager 의 오래된 주석 수정` | `TidalPlayerManager.kt` |

후보 2 를 더 잘게 나누지 않는 이유: 운영 구현만 먼저 넣으면 `initTidalAuth` 의 본문이 두 곳에 있는 중간 커밋이 생기고, 실패 로그 처리를 뒤로 미루면 로그가 빠진 중간 커밋이 생긴다. 운영 구현 연결, `when` 교체, 쓰이지 않는 함수 삭제, 실패 로그 처리를 한 커밋에 담는다 (KR-1 4번도 한 커밋으로 적었다).

`PlaybackContracts.kt`, `PlaybackCommandRouter.kt`, `ChannelAdapter.kt`, `TidalStreamProxyServer.kt`, `TidalAuthManager.kt`, `build.gradle.kts`, 테스트 폴더는 어느 커밋에서도 바꾸지 않는다.

## 4. 후보 2 상세: `onMethodCall` 위임

### 4.1 위임 뒤의 모양

`object PlaybackCore` 안에 private 값을 둔다. 새 파일은 만들지 않는다 (운영 구현이 `PlaybackCore` 의 private 함수와 필드를 써야 하기 때문).

| 값 | 모양 | 하는 일 |
| --- | --- | --- |
| `authControls` | `object : AuthControls` | `initialize`: 지금 `initTidalAuth` 분기의 본문을 그대로 옮긴다 (응답을 만드는 부분만 빼고 `isInitialized` 를 돌려준다). `updateUserCredentials`: `auth.updateUserCredentials(...)` 뒤에 지금의 `Log.i`. `clearUserCredentials`: `auth.clearUserCredentials()` |
| `deviceControls` | `object : DeviceControls` | 함수 4개가 기존 private 함수 4개 (`phoneVolumePercent`, `setPhoneVolumePercent`, `requestNotificationPermission`, `setWifiLock`) 를 부르기만 한다 |
| `proxyRegistrar` | `ProxyRegistrar { ... }` (fun interface 라 람다) | `ensureProxyServer()` 가 null 이면 null. 아니면 `server.registerTrackStream(...)` 뒤에 지금의 `Log.i`, 받은 주소를 돌려준다 |
| `router` | `PlaybackCommandRouter(authControls, { playerManager }, deviceControls, proxyRegistrar)` | 플레이어는 호출할 때마다 `playerManager` 필드를 읽는다 (CR-13). 4.5 에서 "나" 를 고르면 `{ playerManager }` 자리에 감싸개가 들어간다 |

`onMethodCall` 은 한 줄이 된다 (KR-3):

```kotlin
private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    sendCommandResult(router.handle(call.method, channelArguments(call)), result)
}
```

본문을 건드리지 않는 것 (KR-2, NFR-06-A3): `attach`, `audioManager`, `phoneVolumePercent`, `setPhoneVolumePercent`, `registerPhoneVolumeObserver`, `emit`, `requestStreamFromDart`, `requestTokenFromDart`, `requestNotificationPermission`, `setWifiLock`, `ensureProxyServer`, 채널 이름 상수 2개, 필드 선언.

### 4.2 분기별 대조표

"지금" 은 `PlaybackCore.onMethodCall` 의 `when` 분기, "위임 뒤" 는 router 분기 (이미 커밋된 코드) + 운영 구현 (4.1) 이다. 인자는 Dart 가 실제로 보내는 타입 (4.3 참고) 을 전제로 한다.

| 메서드 | 지금의 순서 | 위임 뒤의 순서 | 인자 · 응답 | 같음 |
| --- | --- | --- | --- | --- |
| `initTidalAuth` | 채널 없으면 응답 없이 끝 → 인자 2개 읽기 → `auth.initializeAuth` → 토큰 갱신 함수 연결 → (성공 · 공급자 있음) 플레이어 없으면 생성 + `onEvent` 연결 → `Log.i` → `initializePlayer()` → 응답 | router 가 인자 2개 읽기 → `authControls.initialize`: 채널 없으면 false → `auth.initializeAuth` → 토큰 갱신 함수 연결 → 플레이어 생성 + `onEvent` 연결 → `Log.i` → `initializePlayer()` → router 가 응답 맵 생성 → 응답 | `{status, sdk, clientId}` 같음 | 예. 채널이 없을 때만 다름 (O-6) |
| `updateUserCredentials` | 인자 3개 → `auth.updateUserCredentials` → `Log.i` → 응답 | 인자 3개 → 운영 구현 (`auth.updateUserCredentials` → `Log.i`) → 응답 | `expiresInSeconds` 는 양쪽 다 `Number` → Long. `{status, userId}` | 예 |
| `clearUserCredentials` | `auth.clearUserCredentials` → 응답 | 같음 | `{status: cleared}` | 예 |
| `playTrack` | try 안에서: `trackId` 읽기 → 플레이어 확인 → `playTrack` → 응답 | try 안에서: 같은 순서 | `{status: playing, trackId}` | 예 |
| `pauseTrack` | 플레이어 확인 → `pause` → 응답 | 같음 | `{status: paused}` | 예 |
| `resumeTrack` | 플레이어 확인 → `resume` → 응답 | 같음 | `{status: resumed}` | 예 |
| `seekTrack` | `positionMs` 읽기 → 플레이어 확인 → `seekTo` → 응답 | 같음 | Int 로 읽고 Int 로 응답. Long 이 올 때만 다름 (O-7) | 예 |
| `stopTrack` | `playerManager?.stop()` → 응답 | `player()?.stop()` (`player()` 가 `playerManager` 를 읽음) → 응답 | `{status: stopped}`. 플레이어가 없어도 성공 | 예 |
| `skipToNext` | 플레이어 확인 → `skipToNext` → 응답 | 같음 | `{status: skipped_to_next}` | 예 |
| `setNextTrack` | `trackId` 읽기 → 플레이어 확인 → `setNextTrack` → 응답 | 같음 | `{status: next_track_set, trackId}` | 예 |
| `setAudioQuality` | `quality` 읽기 (기본 `LOSSLESS`) → 플레이어 확인 → `setAudioQuality` → 응답 | 같음 | `{status: quality_set, quality}` | 예 |
| `getPhoneVolume` | `phoneVolumePercent()` → 응답 | `deviceControls` 를 거쳐 같은 함수 → 응답 | 정수 | 예 |
| `setPhoneVolume` | `percent` 읽기 (기본 0) → `setPhoneVolumePercent` → 응답 | 같음 | null. 0 ~ 100 제한은 양쪽 다 `setPhoneVolumePercent` 안. Long 이 올 때만 다름 (O-7) | 예 |
| `requestNotificationPermission` | `requestNotificationPermission()` → 응답 | 같음 | bool | 예 |
| `setStreamingLock` | `setWifiLock(enabled == true)` → 응답 | 같음 | null | 예 |
| `registerTrackStream` | 인자 5개 → `ensureProxyServer()` → null 이면 `NO_WIFI` 오류 → `server.registerTrackStream` → `Log.i` → 응답 | 인자 5개 → 운영 구현 (`ensureProxyServer()` → null 이면 null → `server.registerTrackStream` → `Log.i`) → null 이면 `NO_WIFI` 오류, 아니면 응답 | `{proxyUrl}`, 오류 코드 · 메시지 같음 | 예 |
| 그 밖의 이름 | `notImplemented` | 같음 | - | 예 |

플레이어 동작 8개의 실패 처리: 양쪽 다 `Exception` 만 잡아 `PLAYER_ERROR` 와 `e.message ?: 클래스 단순 이름` 으로 응답한다. 플레이어가 없을 때의 메시지 (`TIDAL Player가 초기화되지 않았습니다`) 도 같다. 달라지는 것은 실패 로그뿐이다 (4.5).

인증 · 기기 · 프록시 쪽에서 난 예외: 양쪽 다 잡지 않아 `onMethodCall` 밖으로 나간다. Flutter 의 채널 처리기가 `RuntimeException` 을 잡아 로그 (`Failed to handle method call`) 를 남기고 코드 `error` 로 응답한다 (Flutter embedding jar 를 `javap` 로 확인). 위임 뒤에도 같다.

### 4.3 동작이 달라지는 곳

Dart 쪽 호출 16곳 (`lib/core/native/tidal_sdk_native_bridge.dart`) 을 확인했다. 인자는 맵 리터럴이거나 없고, `positionMs` · `percent` · `expiresInSeconds` 는 Dart `int`, `enabled` 는 `bool`, 나머지는 `String` 이다.

**실제로 생기는 입력에서 달라지는 것: 실패 로그 하나뿐이다.**

| # | 상황 | 지금 | 위임 뒤 |
| --- | --- | --- | --- |
| D-1 | 플레이어 동작이 실패 (플레이어 없음, SDK 예외, 빈 `trackId`, 모르는 음질 이름) | `Log.e("TIDAL_NATIVE_SDK", "플레이어 동작 실패: ...", e)` 로 스택 트레이스를 남기고 오류 응답 | 오류 응답은 같다. 로그는 4.5 에서 고른 방법에 따른다 (O-8) |

**생기지 않는 입력에서만 달라지는 것**

| # | 상황 | 지금 | 위임 뒤 | 생기지 않는 이유 |
| --- | --- | --- | --- | --- |
| D-2 (O-1) | 인자의 타입이 계약과 다름 (예: `trackId` 가 숫자) | 형 변환 예외. 플레이어 동작 8개에서는 `PLAYER_ERROR` 응답, 그 밖에서는 예외가 밖으로 나가 코드 `error` 응답 | 기본값으로 처리 (CR-11) | Dart 가 정해진 타입으로만 보낸다 |
| D-3 (O-6) | `initTidalAuth` 가 왔는데 `channel` 필드가 null | 아무 일도 하지 않고 응답도 하지 않음 | 아무 일도 하지 않고 `{status: init_failed, ...}` 로 응답 | 호출이 채널을 통해 왔다면 `attach` 가 이미 `channel` 을 넣었다 |
| D-4 (O-7) | `positionMs` · `percent` 가 Long | 형 변환 예외 (`seekTrack` 은 `PLAYER_ERROR`, `setPhoneVolume` 은 코드 `error`) | Int 로 바꿔 처리 (CR-10) | 표준 코덱은 32비트에 들어가는 정수를 Integer 로 보낸다 |
| D-5 (새로 발견) | 채널 인자가 null 도 맵도 아님 (문자열, 목록 등) | 인자를 읽는 메서드는 `call.argument` 가 형 변환 예외를 던진다 (결과는 D-2 와 같음). 인자가 없는 메서드는 정상 | 빈 맵으로 보고 기본값으로 처리 (PC-01) | Dart 가 맵 또는 인자 없음으로만 보낸다 |
| D-6 (새로 발견) | 채널 인자가 `JSONObject` | `call.argument` 가 값을 읽는다 | 빈 맵으로 보고 기본값으로 처리 | JSON 코덱을 쓸 때만 생긴다. 이 채널은 표준 코덱이다 |
| D-7 (새로 발견) | 숫자 인자가 소수 | `positionMs` · `percent` 는 형 변환 예외, `expiresInSeconds` 는 버림 | 셋 다 버림 | Dart 타입이 `int` 다 |
| D-8 (새로 발견) | 플레이어 동작이 성공했는데 `result.success` 가 예외를 던짐 | try 안이라 잡혀서 `result.error` 를 한 번 더 부른다 | 예외가 밖으로 나간다 | 응답을 처음 보낼 때 `result.success` 는 실패하지 않는다 |

D-5 ~ D-8 은 규칙 문서 7절에 아직 없다. 처리는 5절의 요청 사항에 적었다.

### 4.4 로그 4개

| 로그 | 지금 위치 | 위임 뒤 위치 | 순서 · 문구 |
| --- | --- | --- | --- |
| `Log.i("TIDAL_NATIVE_SDK", "updateUserCredentials 호출됨 (UserId: $userId)")` | `updateUserCredentials` 분기, `auth.updateUserCredentials` 뒤 | `authControls.updateUserCredentials`, 같은 호출 뒤 | 같음 |
| `Log.i("PROXY", "registerTrackStream: TrackID=$trackId")` | `registerTrackStream` 분기, 등록 뒤 | `proxyRegistrar`, 등록 뒤 | 같음 |
| `Log.i("TIDAL_NATIVE_SDK", "initializePlayer() called")` | `initTidalAuth` 분기, `initializePlayer()` 앞 | `authControls.initialize`, 본문과 함께 그대로 옮김 | 같음 |
| `Log.e("TIDAL_NATIVE_SDK", "플레이어 동작 실패: ${e.message}", e)` | `runPlayerAction` 의 catch | 4.5 | 4.5 |

### 4.5 실패 로그 (O-8): 선택지와 권고

router 는 예외를 잡아 `CommandResult.Error(code, message)` 로 바꾼다. 예외 객체가 router 밖으로 나오지 않으므로, 지금처럼 `onMethodCall` 에서 스택 트레이스를 남길 수 없다. 아래 선택지는 모두 `PlaybackContracts.kt`, router, 테스트를 고치지 않는다.

| 선택지 | 방법 | 스택 트레이스 | 로그가 남는 경우 | 추가 코드와 위험 |
| --- | --- | --- | --- | --- |
| 가 | `onMethodCall` 에서 결과가 `PLAYER_ERROR` 오류면 `Log.e("TIDAL_NATIVE_SDK", "플레이어 동작 실패: <메시지>")` | **남지 않음** | 실패 전부 | 약 4줄. 잘못 연결할 곳이 없다. 예외 메시지가 null 일 때 문구가 `...: null` 에서 `...: IllegalStateException` 으로 바뀐다 |
| 나 | `PlaybackCore.kt` 에 `PlayerControls` 감싸개 (private 클래스) 를 둔다. 함수 8개가 안쪽 플레이어를 부르고, `Exception` 이 나면 지금과 같은 `Log.e(..., e)` 를 남긴 뒤 다시 던진다. router 에는 `{ playerManager?.let { 감싸개(it) } }` 를 넘긴다 | **남음** (플레이어가 던진 예외) | 플레이어가 던진 실패. **"플레이어 없음" 은 로그가 사라진다** (router 안에서 만들어져 감싸개를 지나지 않는다) | 약 20줄. 위임 8줄은 테스트로 검증되지 않아 `git diff` 로 짝을 확인해야 한다 (`pause` 가 `resume` 을 부르는 식의 실수). 호출마다 감싸개 객체가 하나 생긴다 |
| 다 | 나 + `onMethodCall` 에서 결과가 `PLAYER_ERROR` 이고 `playerManager == null` 일 때만 메시지 로그 | 플레이어가 던진 예외는 **남음**, "플레이어 없음" 은 남지 않음 | 실패 전부, 한 번씩 | 나 + 약 4줄. `onMethodCall` 이 "변환 두 번과 router 호출만" (KR-3) 에서 벗어난다 |
| 라 | 로그를 없앤다 | **남지 않음** | 없음 | 없음 |

`TidalPlayerManager` 의 함수 본문에 로그를 넣는 방법은 "본문은 그대로" (`logical-components.md` 2절) 에 어긋나 넣지 않았다.

**권고: 나.** 근거:

- 스택 트레이스는 SDK 안에서 난 실패의 위치를 알려 주는 유일한 정보다. 오류 코드와 메시지는 Dart 로 전달되고 Dart 쪽이 `AppLogger` 로 남기지만 (`playTrack`, `pauseTrack`, `resumeTrack`, `seekTrack` 에서 확인, 나머지는 확인하지 않음) 트레이스는 전달되지 않는다
- "플레이어 없음" 의 트레이스는 항상 같은 호출 경로 (`requirePlayerManager` ← `onMethodCall`) 라 정보가 없고, 메시지는 Dart 로 그대로 간다. 이 로그 한 줄이 logcat 에서 사라지는 것이 "나" 의 유일한 손실이다
- 로그 줄을 하나도 잃지 않으려면 "다" 를, 트레이스가 필요 없다고 보면 위험이 가장 작은 "가" 를 고르면 된다

### 4.6 스레드와 시점

| 항목 | 지금 | 위임 뒤 |
| --- | --- | --- |
| `onMethodCall` 이 도는 스레드 | 메인 스레드 (`MethodChannel` 을 작업 큐 없이 만들었다) | 같음. `attach` 를 바꾸지 않는다 |
| 응답 시점 | `onMethodCall` 이 돌아가기 전에 동기로 응답 | 같음. router 와 변환 함수는 스레드를 바꾸지 않고 기다리지도 않는다 |
| `initTidalAuth`: 플레이어 생성 · `onEvent` 연결 · `initializePlayer()` | 메인 스레드에서, 응답 전에 | 같음. 본문을 그대로 옮기고 router 가 그 뒤에 응답을 만든다 |
| `registerTrackStream`: `ensureProxyServer()` (프록시 시작 포함) | 메인 스레드에서, 응답 전에 | 같음 |
| Dart 로 되묻는 요청 (`refreshUserToken`, `refreshTrackStream`) | 다른 스레드에서 시작해 메인으로 넘김 | 바꾸지 않음 (PC-07) |
| 호출마다 생기는 객체 | 응답 맵 | 응답 맵 + `CommandResult` 1개 (+ "나" · "다" 면 감싸개 1개). 인자 맵은 복사하지 않고 그대로 넘긴다 |

### 4.7 지우는 코드

| 대상 | 처리 | 이유 |
| --- | --- | --- |
| `onMethodCall` 의 `when` 16분기 | 삭제 (router 호출 한 줄로 교체) | router 와 같은 규칙의 중복 |
| `requirePlayerManager()` | 삭제 | 부르는 곳이 없어진다. router 의 `requirePlayer()` 가 같은 일을 한다 |
| `runPlayerAction()` | 삭제 | 부르는 곳이 없어진다. router 의 `runPlayerAction()` 이 같은 일을 한다 |
| import | 그대로 | `MethodCall`, `MethodChannel`, `Log` 는 계속 쓰인다 |

`TidalPlayerManager.requirePlayer()` 는 지우지 않는다. 이름과 메시지가 같지만 조건이 다르다 (관리 객체는 있는데 SDK 플레이어가 없음).

### 4.8 구현할 때의 함정 (테스트가 잡지 못함)

| # | 함정 | 틀리면 | 막는 방법 |
| --- | --- | --- | --- |
| T-1 | `DeviceControls` 의 함수 이름 4개가 `PlaybackCore` 의 private 함수 이름과 같다. 익명 객체 안에서 `phoneVolumePercent()` 라고만 쓰면 자기 자신을 부른다 | 무한 재귀 → `StackOverflowError`. Flutter 처리기는 `RuntimeException` 만 잡으므로 앱이 죽는다 | `PlaybackCore.phoneVolumePercent()` 처럼 바깥 객체를 명시한다. 컴파일된 클래스를 `javap` 로 열어 4개 함수가 자기 자신이 아닌 `PlaybackCore` 의 함수를 부르는지 확인한다 |
| T-2 | `object` 의 속성은 적힌 순서대로 초기화된다. `router` 가 운영 구현 3개보다 위에 있으면 null 을 받는다 | `PlaybackCore` 를 처음 쓰는 순간 (앱 시작) 초기화 예외로 앱이 죽는다 | 운영 구현 3개를 먼저, `router` 를 그 아래에 적는다. `javap` 로 정적 초기화 블록의 순서를 확인한다 |
| T-3 | `authControls.initialize` 로 본문을 옮길 때 줄이 빠지거나 순서가 바뀜 | 토큰 갱신이 연결되지 않거나 이벤트가 오지 않는다 | `git diff` 에서 지워진 분기와 새 함수를 줄 단위로 맞춰 본다. 달라도 되는 것은 첫 줄 (`?: return` → `?: return false`) 과 끝 (응답 대신 `return isInitialized`) 뿐이다 |

### 4.9 확인 방법

| 확인 | 수단 | 잡는 것 |
| --- | --- | --- |
| router · 변환의 동작 | Kotlin 테스트 (고정본) | router 분기와 변환 함수. `PlaybackCore` 는 잡지 못한다 |
| 컴파일 · 연결 | Kotlin 테스트의 컴파일 단계, `flutter build apk --debug` | 타입 · 이름 오류 |
| T-1, T-2 | `javap -c -p` 로 `PlaybackCore` 와 익명 클래스 확인 | 재귀 호출, 초기화 순서 |
| 남는 함수의 본문 | `git diff` 의 변경 구간이 `onMethodCall`, 지운 함수 2개, 새 값들뿐인지 | KR-2 위반 |
| T-3, "나" 의 위임 8줄 | `git diff` 를 4.2 의 표와 줄 단위로 대조 | 옮기다 생긴 누락 |
| 실기기 동작 | **이 에이전트는 할 수 없다** | 위의 수단이 놓친 모든 것 |

실기기 확인을 권한다. 메서드 16개는 평소 사용으로 모두 지나간다: 로그인 → 폰 재생 → 일시정지 · 재개 → 탐색 → 다음 곡 → 음질 변경 → 볼륨 → 정지 → DLNA 재생 (프록시 등록, Wi-Fi 잠금) → Wi-Fi 를 끈 채 DLNA 재생 (`NO_WIFI`). 실기기에서 보기 전까지 이 부분은 "확인하지 못함" 으로 요약에 남는다 (NFR-06-A6).

## 5. 후보에서 뺀 것 (정리가 아니라 동작 변경)

| 항목 | 뺀 이유 |
| --- | --- |
| 프록시 테스트 3개 (`PX-17`, `PX-19`, `PX-38`) 를 통과시키기 | 버그 수정이다. Step 8 의 `fix:` 커밋 |
| router 가 소수나 Int 범위 밖의 Long 을 기본값으로 처리하게 하기 | 규칙에 없는 새 동작. 필요하면 규칙과 테스트부터 (RED) |
| `channel` 이 null 일 때도 인증 초기화를 진행하게 하기 | 지금은 아무 일도 하지 않는다. 응답만 생기는 쪽 (D-3) 이 가장 작은 변화다 |
| `TidalPlayerManager` 의 함수 안에 실패 로그 넣기 | 함수 본문을 바꾼다 |
| 인증 · 기기 · 프록시 쪽 예외를 오류 결과로 바꾸기 | CR-12 와 반대다 |
| "플레이어가 초기화되지 않았습니다" 문구를 router 와 `TidalPlayerManager` 가 함께 쓰는 상수로 | `TidalPlayerManager` 의 본문을 바꾸고, 두 곳은 조건이 다르다 |

### 주 세션에 요청하는 문서 보완

- D-5 ~ D-8 을 `business-rules.md` 7절 관찰 사항에 추가할지 정해 주기 바란다. 넷 다 O-1 과 같은 성격 (생기지 않는 입력) 이다
- O-6 의 "항상 응답한다" 에 응답 내용 (`init_failed`) 을 적어 두면 D-3 과 맞는다

## 6. 사람이 정할 것

| # | 결정 | 선택지 | 권고 |
| --- | --- | --- | --- |
| 1 | 후보별 적용 여부 | 2절의 권고대로 (#1, #2, #7 적용 / #3 ~ #6 그대로 둠) 또는 조정 | 권고대로 |
| 2 | 실패 로그 (O-8) | 가 / 나 / 다 / 라 (4.5) | 나 |
| 3 | `channel` 이 null 일 때의 `initialize` | false 를 돌려줘 `init_failed` 로 응답 (D-3) / 다른 처리 | false |
| 4 | 실기기 확인을 언제 할지 | 후보 2 커밋 직후 / unit 끝 (Step 9 뒤) / 하지 않고 요약에 기록 | 후보 2 커밋 직후 |

## 7. 표를 쓰면서 생긴 의문

- 후보 2 는 스킬의 "한 번에 하나만 변경" 보다 크다 (운영 구현 3개 + 교체 + 삭제 + 로그). 3절에 적은 이유로 한 커밋을 권했지만, 나눠야 한다고 보면 "운영 구현 추가 (아직 쓰지 않음)" 와 "교체 · 삭제" 의 2개로 나눌 수 있다. 그 경우 첫 커밋에 `initTidalAuth` 본문의 중복이 잠시 생긴다
- "나" 의 감싸개는 테스트가 없는 새 코드다. 고정된 테스트를 고칠 수 없어 이 단계에서는 `git diff` 검토로만 확인한다. 테스트를 붙이려면 RED 로 돌아가야 한다
- 주석 수정 (#7) 을 `docs:` 커밋으로 적었다. 소스 파일의 주석이라 `refactor:` 가 맞다고 보면 바꾸면 된다
