# 비즈니스 규칙 (Business Rules) - android-native-tests

`PlaybackCommandRouter` (새로 분리하는 명령 분배) 와 `TidalStreamProxyServer` 가 어떻게 동작해야 하는지를 규칙으로 적었다. 기준은 **지금 코드의 동작** 이다 (`PlaybackCore.onMethodCall`, `TidalStreamProxyServer`). 규칙 하나가 Code Generation 에서 테스트 케이스 하나 이상이 된다.

판단 기준 (계획 Q1=A): 문서 · 주석의 의도와 다르거나 예외 · 잘못된 상태를 남기는 경우만 버그로 고치고, 그 밖에는 지금 동작을 고정한다.

규칙 ID: `CR` = `PlaybackCommandRouter`, `PC` = `PlaybackCore` 와 router 의 경계, `PX` = `TidalStreamProxyServer`.

---

## 1. `PlaybackCommandRouter` (FR-06)

2026-11-17 보완: RED 단계에서 테스트 작성 에이전트가 문서만으로 정할 수 없다고 보고한 곳 (CR-01, CR-02, CR-07, CR-10, PC-01, PC-03) 의 문구를 지금 코드의 동작 기준으로 구체화했다.

`handle(method, args)` 는 채널 메서드 이름과 인자 맵을 받아 `CommandResult` (성공 값 / 오류 / 미구현) 를 돌려준다.

### 채널 메서드 표

| 메서드 | 인자 (없을 때 기본값) | 협력 객체 호출 | 성공 값 |
| --- | --- | --- | --- |
| `initTidalAuth` | `clientId` (`""`), `clientSecret` (`""`) | `auth.initialize(clientId, clientSecret)` | `{status: "initialized" 또는 "init_failed", sdk: "com.tidal.sdk", clientId}` |
| `updateUserCredentials` | `userId` (`""`), `accessToken` (`""`), `expiresInSeconds` (3600) | `auth.updateUserCredentials(userId, accessToken, expiresInSeconds)` | `{status: "updated", userId}` |
| `clearUserCredentials` | - | `auth.clearUserCredentials()` | `{status: "cleared"}` |
| `playTrack` | `trackId` (`""`) | `player.playTrack(trackId)` | `{status: "playing", trackId}` |
| `pauseTrack` | - | `player.pause()` | `{status: "paused"}` |
| `resumeTrack` | - | `player.resume()` | `{status: "resumed"}` |
| `seekTrack` | `positionMs` (0) | `player.seekTo(positionMs)` | `{status: "seeked", positionMs}` |
| `stopTrack` | - | `player.stop()` (플레이어가 있을 때만) | `{status: "stopped"}` |
| `skipToNext` | - | `player.skipToNext()` | `{status: "skipped_to_next"}` |
| `setNextTrack` | `trackId` (`""`) | `player.setNextTrack(trackId)` | `{status: "next_track_set", trackId}` |
| `setAudioQuality` | `quality` (`"LOSSLESS"`) | `player.setAudioQuality(quality)` | `{status: "quality_set", quality}` |
| `getPhoneVolume` | - | `device.phoneVolumePercent()` | 정수 (백분율) |
| `setPhoneVolume` | `percent` (0) | `device.setPhoneVolumePercent(percent)` | null |
| `requestNotificationPermission` | - | `device.requestNotificationPermission()` | 그 반환값 (bool) |
| `setStreamingLock` | `enabled` (false) | `device.setWifiLock(enabled)` | null |
| `registerTrackStream` | `trackId` (`""`), `directUrl` (`""`), `manifestXml` (`""`), `allowedHost` (`""`), `mimeType` (`"audio/mp4"`) | `proxy.registerTrackStream(...)` | `{proxyUrl}` |

### 규칙

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| CR-01 | 표의 16개 메서드 | 표의 협력 객체 호출이 표의 인자로 1회 일어나고, 표의 성공 값을 돌려준다. 그 호출 말고는 어떤 협력 객체도 부르지 않는다 |
| CR-02 | 인자가 없거나, 인자 맵이 비어 있거나, 키는 있는데 값이 null | 표의 기본값을 쓴다 |
| CR-03 | 표에 없는 메서드 이름 | 미구현 (`NotImplemented`). 협력 객체를 부르지 않는다 |
| CR-04 | `initTidalAuth`, `auth.initialize` 가 true / false | `status` 가 `"initialized"` / `"init_failed"`. 두 경우 모두 성공 값으로 돌려준다 (오류가 아님) |
| CR-05 | 플레이어 동작 7개 (`playTrack`, `pauseTrack`, `resumeTrack`, `seekTrack`, `skipToNext`, `setNextTrack`, `setAudioQuality`), 플레이어가 아직 없음 | 오류 `PLAYER_ERROR`, 메시지 `"TIDAL Player가 초기화되지 않았습니다"` |
| CR-06 | `stopTrack`, 플레이어가 아직 없음 | 오류가 아니다. `{status: "stopped"}` |
| CR-07 | 플레이어 동작 8개 (`stopTrack` 포함) 에서 플레이어가 예외를 던짐 | 오류 `PLAYER_ERROR`, 메시지는 예외의 메시지. 메시지가 null 이면 예외 클래스의 단순 이름 (패키지 없이, 예: `IllegalStateException`). 메시지가 빈 문자열이면 빈 문자열 그대로 |
| CR-08 | `registerTrackStream`, 프록시 등록이 null (Wi-Fi 없음) | 오류 `NO_WIFI`, 메시지 `"Wi-Fi에 연결되어 있지 않아 스피커로 스트리밍할 수 없습니다."` |
| CR-09 | `setStreamingLock` | `enabled` 가 정확히 true 일 때만 `setWifiLock(true)`, 그 밖 (false, 없음) 은 `setWifiLock(false)` |
| CR-10 | 숫자 인자 (`positionMs`, `percent`, `expiresInSeconds`) | 정수 타입의 크기 (Int · Long) 와 상관없이 읽는다. `expiresInSeconds` 는 Long 으로, 나머지는 Int 로 넘긴다. 성공 값에 실리는 `positionMs` 도 Int 로 바꾼 값이다 (Long 90000 이 오면 Int 90000). 소수나 Int 범위를 넘는 값은 테스트 입력 범위 밖이다. 이 규칙은 router 의 동작이며, 재구성 전의 `onMethodCall` 은 `positionMs` · `percent` 를 Int 로만 읽는다 (O-7) |
| CR-11 | 인자의 타입이 계약과 다름 (예: `trackId` 가 숫자) | 그 인자가 없는 것으로 보고 기본값을 쓴다 (테스트 입력 범위 밖, 아래 관찰 사항 O-1) |
| CR-12 | 인증 · 기기 · 프록시 협력 객체가 예외를 던짐 | router 가 잡지 않고 그대로 전파한다. 예외를 오류 결과로 바꾸는 것은 플레이어 동작뿐이다 (지금 코드와 같음) |
| CR-13 | 같은 호출을 두 번 | router 는 상태를 갖지 않는다. 협력 객체가 같은 답을 주면 결과도 같다 |

`setPhoneVolume` 의 0 ~ 100 범위 제한은 router 가 아니라 `DeviceControls` 의 운영 구현 (`PlaybackCore`) 이 한다. router 는 받은 값을 그대로 넘긴다.

---

## 2. `PlaybackCore` 와 router 의 경계 (FR-06, FR-07)

이 절의 규칙은 Android · Flutter 타입에 닿아 있어 JVM 단위 테스트의 대상이 아닐 수 있다. 확인 수단 (NFR Requirements 에서 확정): PC-01 · PC-02 는 변환 함수의 단위 테스트로, PC-03 은 CR-01 의 테스트와 `git diff` 로, PC-04 ~ PC-07 은 빌드와 코드 검토로 확인한다.

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| PC-01 | 채널 호출이 옴 | `call.method` 와 `call.arguments` (맵이 아니면 빈 맵) 를 router 에 넘긴다. 단위 테스트는 인자 변환 함수 (`channelArguments`) 만 검증한다. 메서드 이름을 넘기는 부분은 `PlaybackCore.onMethodCall` 에 있어 빌드와 코드 검토로 확인한다. 키가 문자열이 아닌 맵은 테스트 입력 범위 밖이다 |
| PC-02 | router 결과가 성공 / 오류 / 미구현 | `result.success(값)` / `result.error(code, message, null)` / `result.notImplemented()` |
| PC-03 | 채널 이름, 메서드 이름, 인자 키, 반환 맵 | 재구성 전과 같다 (`api-documentation.md` C절). 별도 테스트는 없다: 메서드 이름 · 인자 키 · 반환 맵은 CR-01 의 테스트가 검증하고, 채널 이름은 `git diff` 로 변경이 없음을 확인한다 |
| PC-04 | `AuthControls.initialize` 의 운영 구현 | 지금의 `initTidalAuth` 순서 그대로: 인증 공급자 초기화 → 토큰 갱신 함수 연결 → (성공했고 공급자가 있으면) 플레이어를 한 번만 만들고 이벤트 콜백 연결 → 플레이어 초기화 |
| PC-05 | `ProxyRegistrar` 의 운영 구현 | 지금의 `ensureProxyServer` 로 서버를 얻어 등록. Wi-Fi 주소가 없으면 null |
| PC-06 | `DeviceControls` 의 운영 구현 | 지금의 `phoneVolumePercent`, `setPhoneVolumePercent` (0 ~ 100 제한), `requestNotificationPermission`, `setWifiLock` |
| PC-07 | `attach`, 이벤트 전송, 볼륨 관찰, Dart 로 되묻는 요청 (`refreshUserToken`, `refreshTrackStream`) | 바꾸지 않는다 |

---

## 3. `TidalStreamProxyServer` (FR-05)

테스트는 서버를 `127.0.0.1` 의 임시 포트에 띄우고 실제 HTTP 요청을 보낸다. 요청을 보내는 쪽의 주소는 `127.0.0.1` 이다.

2026-11-17 보완: RED 단계에서 테스트 작성 에이전트가 문서만으로 정할 수 없다고 보고한 곳 (PX-02, 04, 11, 16, 17, 19, 24, 27, 28, 29, 30, 34, 36, 38) 의 문구를 지금 코드의 동작 기준으로 구체화했다. GET · HEAD 밖의 메서드, 쿼리 문자열이 붙은 경로, 서버를 시작하기 전의 등록은 테스트 입력 범위 밖이다. 응답 헤더가 클라이언트에 실제로 어떻게 보이는지 (NanoHTTPD 가 스스로 붙이거나 바꾸는 헤더) 는 여기서 정하지 않았다. 테스트 결과로 확인한다.

### 곡 등록

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| PX-01 | `registerTrackStream(...)` | `http://<바인딩 주소>:<열린 포트>/audio/<토큰>.<확장자>` 를 돌려준다. 토큰은 16자의 16진수 소문자 |
| PX-02 | 확장자 | MIME 에 `flac` 이 있으면 `flac`. `mp4` · `m4a` · `aac` 가 있으면 `m4a`. `mpeg` 이 있으면 `mp3`. 그 밖에는 `m4a`. 판정은 이 순서대로 한다 판정은 대소문자를 구분한다 (소문자만 인식). 대문자 MIME 과 공백만 있는 MIME 은 테스트 입력 범위 밖이다 |
| PX-03 | MIME 이 빈 문자열 | `audio/mp4` 로 본다 |
| PX-04 | 매니페스트만 있고 직접 주소가 없음 (DASH) | 넘어온 MIME 과 상관없이 `audio/mp4` 로 등록한다 (DASH 는 fMP4, 코드 주석) 주소의 확장자도 이렇게 정한 MIME (`audio/mp4`) 으로 고르므로 `m4a` 다 |
| PX-05 | 같은 곡을 다시 등록 | 새 토큰을 만든다. 두 주소 모두 쓸 수 있다 |
| PX-06 | 네 번째 곡을 등록 | 가장 오래된 등록이 지워진다. 최근 3개만 남는다 |

### 요청 처리

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| PX-07 | `GET /ping` | 200, `text/plain`, 본문 `pong` |
| PX-08 | `/audio/` 로 시작하지 않고 `/ping` 도 아닌 경로 | 404, 본문 `Not Found` |
| PX-09 | `/audio/<등록되지 않은 토큰>` | 404 |
| PX-10 | 등록은 되어 있으나 직접 주소와 매니페스트가 모두 빈 값 | 404 (요구사항의 "400" 을 정정, 계획 Q2=A) |
| PX-11 | `allowedHost` 가 비어 있지 않고 요청한 쪽의 주소와 다름 | 403, 본문 `Forbidden`. CDN 에 요청하지 않는다 비교는 문자열 그대로 한다. `127.0.0.1` 에서 온 요청에 `allowedHost` 가 `localhost` 이면 403 이다 |
| PX-12 | `allowedHost` 가 빈 값이거나 요청한 쪽의 주소와 같음 | 통과 |
| PX-13 | 등록되지 않은 토큰 + 허용되지 않은 주소 | 404 (등록 여부를 먼저 본다) |
| PX-14 | 경로의 확장자 | 토큰은 `/audio/` 뒤에서 첫 `.` 앞까지다. 확장자가 다르거나 없어도 같은 곡을 찾는다 |
| PX-15 | HEAD 요청 | PX-09 ~ PX-13 의 판정을 GET 과 똑같이 거친다 |

### HEAD

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| PX-16 | 단일 파일 곡 | CDN 에 HEAD 를 보내 받은 `Content-Length` 를 그대로 알린다. `Content-Type` 은 등록한 MIME. `Accept-Ranges: bytes`. 본문 없음 HEAD 응답의 상태는 이 절의 모든 경우에 200 이다. CDN 이 `Content-Length: 0` 을 주면 0 을 그대로 알린다 |
| PX-17 | 단일 파일 곡, CDN HEAD 가 실패하거나 길이가 없음 | 200, `Content-Length` 없이 응답 (0 으로 알리면 렌더러가 빈 파일로 여긴다, 코드 주석) 여기서 "CDN HEAD 가 실패" 는 연결하지 못한 경우다. CDN 이 오류 상태로 답하면서 길이를 준 경우는 PX-20 과 같이 그 길이를 알린다. 길이 없이 응답할 때도 `Content-Type` 과 `Accept-Ranges: bytes` 는 보낸다 |
| PX-18 | DASH 곡 | 초기화 세그먼트와 모든 세그먼트의 HEAD 길이를 더해 `Content-Length` 로 알린다. `Content-Type` 은 `audio/mp4`. `Accept-Ranges` 없음 |
| PX-19 | DASH 곡, 세그먼트 하나라도 길이를 모름 | `Content-Length` 없이 응답 "길이를 모름" 은 세그먼트 HEAD 가 성공 상태가 아니거나, `Content-Length` 가 없거나, 연결하지 못한 경우다. 매니페스트를 해석하지 못하는 DASH 곡에 HEAD 가 오면 이 규칙과 같이 200, 길이 없음으로 응답한다 (GET 은 PX-37 대로 500) |
| PX-20 | 단일 파일 곡, 서명 주소가 만료 (CDN HEAD 가 401 · 403) | 주소를 갱신하지 않는다. CDN 응답의 `Content-Length` 가 있으면 그 값을 알린다 (계획 Q3=A 로 고정, 관찰 사항 O-3) |

### GET: 단일 파일 중계

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| PX-21 | CDN 이 200 | 200, 본문은 CDN 본문 그대로. `Content-Type` 은 등록한 MIME (CDN 이 `octet-stream` 으로 보내도, 코드 주석). `Content-Length` 는 CDN 값. `Accept-Ranges: bytes` |
| PX-22 | CDN 이 `Content-Length` 를 주지 않음 | 길이 없이 (chunked) 본문 전체를 전달 |
| PX-23 | 요청에 `Range` 헤더 | 같은 값을 CDN 요청에 넣는다 |
| PX-24 | Range 요청에 CDN 이 206 + `Content-Range` | 206, `Content-Range` 를 그대로 전달, 본문은 그 구간 `Content-Length` 는 PX-21 과 같이 CDN 값이다. Range 없이 요청했는데 CDN 이 206 을 준 경우도 206 과 `Content-Range` 를 전달한다 |
| PX-25 | Range 요청에 CDN 이 200 (Range 무시) | 206, `Content-Range` 없음, 본문은 CDN 이 준 전체 (계획 Q3=A 로 고정, 관찰 사항 O-2) |
| PX-26 | CDN 이 401 또는 403 (주소 만료), 재발급 함수가 새 직접 주소를 줌 | 재발급 함수를 곡 ID 로 1회 호출하고 새 주소로 다시 요청해 중계한다. 처음 요청의 `Range` 는 유지된다 |
| PX-27 | PX-26 뒤 같은 토큰으로 다시 요청 | 갱신된 주소를 바로 쓴다 (재발급 함수를 다시 부르지 않음) 갱신된 MIME (PX-31) 도 다음 요청에 유지된다 |
| PX-28 | 재발급 함수가 없음 / null 반환 / 예외 / 직접 주소와 매니페스트가 모두 빈 값 | 403, 본문 `Stream expired` 재발급 응답 맵에서 키가 빠졌거나 값이 문자열이 아니면 그 값은 빈 값으로 본다 |
| PX-29 | 재발급으로 받은 주소도 401 · 403 | 다시 재발급하지 않는다 (1회만). 500, 본문 `CDN error: <코드>` `<코드>` 는 재발급 뒤 두 번째 응답의 상태 코드다 |
| PX-30 | 재발급 결과가 매니페스트뿐 (DASH) | DASH 중계로 응답 이때 `Content-Type` 은 처음 등록한 MIME 이나 재발급 MIME 과 상관없이 PX-34 대로 `audio/mp4` 다 |
| PX-31 | 재발급 결과의 MIME | 값이 있으면 그 MIME 으로, 비어 있으면 처음 등록한 MIME 을 유지 |
| PX-32 | CDN 이 그 밖의 실패 (예: 404, 500) | 500, 본문 `CDN error: <코드>` |
| PX-33 | CDN 에 연결하지 못함 | 500, 본문이 `Proxy error:` 로 시작 |

### GET: DASH 중계

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| PX-34 | 유효한 매니페스트 | 200, 본문은 초기화 세그먼트 + 세그먼트들을 순서대로 이어 붙인 것. `Content-Type` 은 `audio/mp4`. `Accept-Ranges` 없음 매니페스트에 초기화 세그먼트 (`initialization` 속성) 가 없어도 유효하며, 그때 본문은 세그먼트들만 이은 것이다 |
| PX-35 | 모든 세그먼트의 길이를 앎 | `Content-Length` 는 합계 |
| PX-36 | 세그먼트 하나라도 길이를 모름 | 길이 없이 (chunked) 본문 전체를 전달 "길이를 모름" 의 범위는 PX-19 와 같다 |
| PX-37 | 매니페스트를 해석하지 못함 | 500, 본문 `Invalid DASH manifest` |
| PX-38 | 같은 매니페스트에 HEAD 뒤 GET (또는 GET 두 번) | 세그먼트 길이 조회 (HEAD) 는 매니페스트당 한 번만 한다 기억하는 범위는 서버 인스턴스 하나다. 길이를 모르는 결과는 기억하지 않아 다음 요청에서 다시 조회한다. 세그먼트 HEAD 는 동시에 보내므로 순서는 정해져 있지 않다 |

세그먼트를 받다가 실패했을 때의 동작 (거기서 스트림을 끝냄) 은 `DashSegmentInputStream` 의 책임이고 이 unit 의 대상 파일이 아니라 규칙에 넣지 않았다.

---

## 4. 오류 표

### router

| 코드 | 발생 | 규칙 |
| --- | --- | --- |
| `PLAYER_ERROR` | 플레이어가 없거나 플레이어 동작이 예외를 던짐 | CR-05, CR-07 |
| `NO_WIFI` | 프록시를 띄울 Wi-Fi 주소가 없음 | CR-08 |
| (미구현) | 모르는 메서드 | CR-03 |

### 프록시

| 상태 | 본문 | 발생 | 규칙 |
| --- | --- | --- | --- |
| 404 | `Not Found` | 모르는 경로, 등록되지 않은 토큰, 내용이 빈 등록 | PX-08, PX-09, PX-10 |
| 403 | `Forbidden` | 허용되지 않은 주소 | PX-11 |
| 403 | `Stream expired` | 주소 만료 뒤 재발급 실패 | PX-28 |
| 500 | `CDN error: <코드>` | CDN 실패 | PX-29, PX-32 |
| 500 | `Proxy error: ...` | CDN 연결 실패 | PX-33 |
| 500 | `Invalid DASH manifest` | 매니페스트 해석 실패 | PX-37 |

---

## 5. 요구사항 대응

| 요구사항 항목 (`requirements.md`) | 규칙 |
| --- | --- |
| FR-06: `onMethodCall` 이 메서드를 올바른 동작으로 보내고 정해진 반환 맵을 돌려줌 | CR-01, CR-02, CR-04, CR-09, CR-10, PC-01 ~ PC-03 |
| FR-06: 플레이어가 초기화되지 않았을 때 오류 | CR-05, CR-06, CR-07 |
| FR-06: 알 수 없는 메서드는 `notImplemented` | CR-03, PC-02 |
| FR-06: Wi-Fi 가 없을 때 `NO_WIFI` | CR-08 |
| FR-05: `/ping` 200, 그 밖 404 | PX-07, PX-08 |
| FR-05: 미등록 토큰 404, 다른 요청 IP 403, 갱신 실패 403 `Stream expired` | PX-09, PX-11, PX-13, PX-28 |
| FR-05: "CDN URL 없음 400" (정정: 404) | PX-10 |
| FR-05: HEAD 는 본문 없이 길이 · 타입 | PX-15 ~ PX-20 |
| FR-05: Range 헤더를 업스트림에 전달 | PX-23, PX-24 |
| FR-05: 16자 토큰과 MIME 에 맞는 확장자 | PX-01 ~ PX-04 |
| FR-07: 대체 지점 (router, 인터페이스, 프록시 생성자) | PC-04 ~ PC-07, `component-methods.md` |

요구사항에 없지만 동작 고정을 위해 규칙에 넣은 것: 최근 3곡 유지 (PX-06), 주소 갱신 뒤의 동작 (PX-26 ~ PX-31), CDN 실패 응답 (PX-32, PX-33), DASH 중계 (PX-34 ~ PX-38).

---

## 6. unit 1 과의 계약 대조

unit 1 의 Dart 테스트가 검증한 채널 문자열과 이 unit 의 규칙이 같은지 대조했다.

| 메서드 | Dart 가 보내는 인자 키 (unit 1 테스트) | router 가 읽는 키 (CR-01) | 일치 |
| --- | --- | --- | --- |
| `playTrack` | `trackId` (`phone_backend_test.dart` [PB-01]) | `trackId` | 예 |
| `seekTrack` | `positionMs` ([PB-06]) | `positionMs` | 예 |
| `setAudioQuality` | `quality` ([PB-08]) | `quality` | 예 |
| `setNextTrack` | `trackId`, 등록 삭제는 빈 문자열 ([PB-09]) | `trackId` | 예 |
| `pauseTrack`, `resumeTrack`, `stopTrack` | 인자 없음 ([PB-04], [PB-05], [PB-07]) | 인자 없음 | 예 |
| `registerTrackStream` | `trackId`, `directUrl`, `manifestXml`, `allowedHost`, `mimeType` (`dlna_backend_test.dart` [DB-05]) | 같은 5개 | 예 |
| `registerTrackStream` 의 응답 | `proxyUrl` 을 읽음 ([DB-06]) | `{proxyUrl}` | 예 |
| `setStreamingLock` | `enabled` ([DB-07]) | `enabled` | 예 |
| `setPhoneVolume` | `percent` (`wave_audio_handler_test.dart` [WA-09]) | `percent` | 예 |
| `refreshTrackStream` (Kotlin → Dart) 의 응답 | `directUrl`, `manifestXml`, `mimeType` ([DB-48]) | 프록시의 재발급 함수가 읽는 키 (PX-26, PX-31) | 예 |

---

## 7. 관찰 사항 (지금 동작으로 고정, 수정하지 않음)

| # | 관찰 | 처리 |
| --- | --- | --- |
| O-1 | 지금의 `onMethodCall` 은 인자 타입이 계약과 다르면 형 변환 예외가 난다. router 는 기본값으로 처리한다 (CR-11) | 입력 범위 밖. Dart 쪽은 정해진 타입으로만 보낸다. 범위 밖 입력에 대한 동작만 달라진다 |
| O-2 | Range 요청에 CDN 이 200 을 주면 프록시는 `Content-Range` 없이 206 으로 응답한다 | PX-25 로 고정 (계획 Q3=A) |
| O-3 | 주소가 만료된 상태의 HEAD 는 주소를 갱신하지 않는다. 또한 CDN HEAD 의 상태 코드를 확인하지 않고 응답의 `Content-Length` 를 쓰므로, CDN 이 오류 응답에 길이를 실어 보내면 그 길이를 곡의 길이로 알린다 | PX-20 으로 고정 (계획 Q3=A). 계획의 질문에는 "길이 없는 응답을 준다" 고만 적었는데, 코드를 다시 읽으니 오류 응답의 길이가 전달될 수 있다. 완료 메시지에서 따로 알린다 |
| O-4 | `proxyDirectCdn` 의 400 분기 (`CDN URL required`) 는 도달할 수 없다 | 코드에 그대로 둔다 (계획 Q2=A) |
| O-5 | DASH 전체 길이 캐시는 매니페스트 원문을 키로 쓰고 지우지 않는다 | 규칙 없음. 곡마다 매니페스트가 달라 재생한 곡 수만큼 늘지만 항목이 작다 |
| O-6 | `initTidalAuth` 는 지금 채널 객체가 없으면 응답 없이 끝난다. 재구성 뒤에는 `AuthControls.initialize` 가 결과를 돌려주므로 항상 응답한다 | 채널을 통해 호출이 왔다면 채널 객체는 항상 있다. 생기지 않는 상태에서만 동작이 달라진다 |
| O-7 | 재구성 전의 `onMethodCall` 은 `positionMs` · `percent` 를 `call.argument<Int>` 로 읽는다. Long 이 오면 형 변환 예외가 나서 `seekTrack` 은 `PLAYER_ERROR`, `setPhoneVolume` 은 예외가 밖으로 나간다. router 는 Long 도 읽어 Int 로 넘긴다 (CR-10). 2026-11-17 보완 때 CR-10 을 "지금 코드 기준" 이라고 적었으나 이 부분은 지금 코드와 다르다 (GREEN 에이전트가 발견) | 입력 범위 밖. Flutter 의 표준 코덱은 32비트에 들어가는 정수를 Integer 로 보내므로, 재생 위치 (약 24.8일 미만) 와 볼륨 (0 ~ 100) 은 항상 Int 로 온다. `onMethodCall` 을 router 로 넘기면 생기지 않는 입력에 대한 동작만 달라진다 (O-1 과 같은 성격) |
| O-8 | 재구성 전의 `runPlayerAction` 은 플레이어 동작이 실패하면 `Log.e` 로 예외의 스택 트레이스를 남긴다. router 는 Android 타입을 쓰지 않아 로그를 남기지 않는다 | 사람 판정 (2026-11-17, 후보 표의 선택지 "나"): `PlaybackCore.kt` 의 `LoggingPlayerControls` 감싸개가 플레이어가 던진 예외를 같은 태그 · 문구의 `Log.e` 로 남기고 다시 던진다. 플레이어가 없을 때의 로그 한 줄은 남지 않는다 (오류 응답은 같다) |
| O-9 | 채널 인자가 null 도 맵도 아니면 재구성 전에는 `call.argument` 가 형 변환 예외를 던진다. 위임 뒤에는 빈 맵으로 본다 (PC-01) | 입력 범위 밖. Dart 쪽은 인자 없이 부르거나 맵으로만 보낸다 (REFACTOR 후보 표의 D-5) |
| O-10 | 채널 인자가 `JSONObject` 이면 재구성 전에는 값을 읽고, 위임 뒤에는 빈 맵으로 본다 | 이 채널은 표준 코덱을 써서 `JSONObject` 가 오지 않는다 (D-6) |
| O-11 | 숫자 인자가 소수이면 재구성 전에는 `positionMs` · `percent` 에서 형 변환 예외가 나고, 위임 뒤에는 소수점 아래를 버린다 | 입력 범위 밖 (CR-10). Dart 쪽은 정수만 보낸다 (D-7) |
| O-12 | 플레이어 동작은 성공했는데 `result.success` 가 예외를 던지면 재구성 전에는 그것을 잡아 `result.error` 를 부르고, 위임 뒤에는 예외가 밖으로 나간다 | 채널 응답 객체가 예외를 던지는 경우는 한 호출에 두 번 응답할 때뿐이며 이 코드에서는 생기지 않는다 (D-8) |
| O-13 | 길이를 모르는 DASH 곡은 결과를 기억하지 않으므로, HEAD · GET 이 올 때마다 초기화 세그먼트와 세그먼트 전부에 HEAD 를 다시 보낸다 (세그먼트 4개짜리 곡에서 요청 2번에 HEAD 8건) | 규칙 PX-38 은 "모르는 결과는 다시 조회한다" 까지만 정한다. 다시 조회하는 범위는 테스트로 고정하지 않았다. 세그먼트가 많은 곡에서 CDN 이 길이를 주지 않으면 요청마다 조회가 반복된다 |
| O-14 | 단일 파일 · DASH 의 GET 응답에 `Access-Control-Allow-Origin: *` 가 붙는다 | 규칙에 없고 테스트로 고정하지 않았다. 프록시는 허용 호스트 검사 (PX-11 ~ PX-13) 로 접근을 막는다 |
| O-15 | 길이를 모르는 HEAD 응답에 `Content-Length: -1` 이 나갔다 (NanoHTTPD 가 HEAD 응답에 붙임). PX-17 · PX-19 · PX-38 의 테스트가 실패해 발견 | 버그로 판정해 수정 (`8e5b417`). 기록: `docs/incidents/2026-11-17-head-content-length-minus-one.md`. 이 표의 다른 항목과 달리 지금 동작으로 고정한 것이 아니다 |
