# RED 판정 표 - router 담당

unit `android-native-tests` 의 Code Generation 계획 Step 4.4 산출물이다. 승인된 테스트 경계 표 (`red-seam-table-router.md`) 대로 쓴 테스트를 뼈대 (`PlaybackCommandRouter.handle` 이 항상 `NotImplemented`, `channelArguments` 가 항상 빈 맵, `sendCommandResult` 가 아무것도 보내지 않음) 에 실행한 결과다. 사람 판정 (관문 2) 을 받기 전이며, 고정 (커밋) 하지 않았다.

## 합계

| 전체 | FAILED | ERROR | PASSED (보호) | RED 인정 ✅ | 불인정 ❌ |
| --- | --- | --- | --- | --- | --- |
| 37 | 33 | 0 | 4 | 33 | 0 |

- 예시 기반 31개: FAILED 29, 보호 2 (CR-03, PC-01 (b))
- 속성 6개: FAILED 4, 보호 2 (P-CR-1, P-CR-6)
- 경계 표 5절의 예상과 모두 같다. RED 로 예상했는데 통과한 것, 보호로 예상했는데 실패한 것은 없다
- 실패 33개는 모두 기대값 비교 실패 (`AssertionError`) 다. 컴파일 오류 · 이름 오류 · fake 오류 · 생성기 오류는 없었다

## 실행

```sh
cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :app:testDebugUnitTest \
  --tests "*PlaybackCommandRouterTest*" --tests "*ChannelAdapterTest*"
```

- 두 번 실행했고 결과가 같았다 (37개 실행, 33개 실패). 아래 표는 두 번째 실행 (2026-11-17) 의 결과 XML 에서 옮겼다
- 결과 XML: `build/app/test-results/testDebugUnitTest/TEST-com.example.tidal_connect_lite.PlaybackCommandRouterTest.xml` (32개, 실패 29, 오류 0, 건너뜀 0, 0.107초), `...ChannelAdapterTest.xml` (5개, 실패 4, 오류 0, 건너뜀 0, 0.013초). 이 프로젝트는 Gradle 출력이 저장소 루트의 `build/app/` 아래에 생긴다 (`android/app/build/` 가 아님)
- **이 두 XML 은 지금 폴더에 없다.** 내 실행 뒤에 프록시 담당이 자기 테스트만 골라 실행했고, Gradle 은 테스트 작업을 실행할 때마다 결과 폴더를 새로 채운다. 지금은 `TidalStreamProxyServerTest` 의 XML 만 있다. 위 수치와 아래 표는 내 실행 직후에 XML 에서 읽어 둔 값이다. 그쪽 결과를 덮어쓰지 않으려고 다시 실행하지 않았다
- 실행 시점에 같은 폴더에 프록시 담당의 `FakeCdnServer.kt`, `ProxyFixture.kt`, `ProxyGenerators.kt` 가 있었고 함께 컴파일되었다. 그쪽 파일 때문에 막힌 적은 없다. 그 파일들은 열지 않았다
- 마지막에 `:app:compileDebugUnitTestKotlin` (컴파일만, 테스트 실행 없음) 을 한 번 더 돌렸다. 그 사이에 생긴 `TidalStreamProxyServerTest.kt` 까지 테스트 파일 8개가 함께 컴파일된다 (BUILD SUCCESSFUL, 이름 충돌 없음)
- 속성 테스트의 seed 는 20261117 (기본값) 이다

## 판정 표

"표 행" 은 `red-seam-table-router.md` 2 · 3절의 행이다. 테스트 이름에는 (a) · (b) 표시를 넣지 않아 여기에 대응을 적었다. 표를 도는 테스트는 첫 줄에서 실패하므로 실패 종류에는 그 첫 줄의 값이 나온다.

### `PlaybackCommandRouterTest` (32개)

| 테스트 (표 행) | 결과 | 실패 종류 (기대값과 실제값) | RED 인정 |
| --- | --- | --- | --- |
| `CR-01 표의 16개 메서드는 정해진 협력 객체 호출 1회와 정해진 성공 값을 만든다` (CR-01) | FAILED | AssertionError. `#1 initTidalAuth` 결과: 기대 `Success({status=initialized, sdk=com.tidal.sdk, clientId=test-client-id})`, 실제 `NotImplemented` | ✅ |
| `CR-02 인자 맵이 비어 있으면 표의 기본값을 쓴다` (CR-02 (a)) | FAILED | AssertionError. `#1 initTidalAuth` 결과: 기대 `Success({status=initialized, sdk=com.tidal.sdk, clientId=})`, 실제 `NotImplemented` | ✅ |
| `CR-02 일부 키만 있으면 없는 인자에만 기본값을 쓴다` (CR-02 (b)) | FAILED | AssertionError. `① updateUserCredentials` 결과: 기대 `Success({status=updated, userId=user-1})`, 실제 `NotImplemented` | ✅ |
| `CR-02 키는 있는데 값이 null 이면 없는 인자처럼 기본값을 쓴다` (CR-02 (c)) | FAILED | AssertionError. `① playTrack` 결과: 기대 `Success({status=playing, trackId=})`, 실제 `NotImplemented` | ✅ |
| `CR-03 표에 없는 메서드는 미구현이고 협력 객체를 부르지 않는다` (CR-03) | PASSED | - (뼈대가 모든 이름에 `NotImplemented` 를 돌려주고 fake 를 부르지 않는다) | 보호 |
| `CR-04 인증 초기화가 성공하면 status 가 initialized 인 성공 값이다` (CR-04 (a)) | FAILED | AssertionError. 기대 `Success({status=initialized, sdk=com.tidal.sdk, clientId=test-client-id})`, 실제 `NotImplemented` | ✅ |
| `CR-04 인증 초기화가 실패해도 오류가 아니라 status 가 init_failed 인 성공 값이다` (CR-04 (b)) | FAILED | AssertionError. 기대 `Success({status=init_failed, sdk=com.tidal.sdk, clientId=test-client-id})`, 실제 `NotImplemented` | ✅ |
| `CR-05 플레이어가 없으면 플레이어 동작 7개는 PLAYER_ERROR 다` (CR-05) | FAILED | AssertionError. `playTrack` 결과: 기대 `Error(PLAYER_ERROR, TIDAL Player가 초기화되지 않았습니다)`, 실제 `NotImplemented` | ✅ |
| `CR-06 플레이어가 없어도 stopTrack 은 오류가 아니라 stopped 다` (CR-06) | FAILED | AssertionError. 기대 `Success({status=stopped})`, 실제 `NotImplemented` | ✅ |
| `CR-07 플레이어가 예외를 던지면 PLAYER_ERROR 이고 메시지는 예외의 메시지다` (CR-07 (a)) | FAILED | AssertionError. `playTrack` 결과: 기대 `Error(PLAYER_ERROR, 재생 실패)`, 실제 `NotImplemented` | ✅ |
| `CR-07 예외의 메시지가 null 이면 메시지는 패키지 없는 예외 클래스 이름이다` (CR-07 (b)) | FAILED | AssertionError. `playTrack` 결과: 기대 `Error(PLAYER_ERROR, IllegalStateException)`, 실제 `NotImplemented` | ✅ |
| `CR-07 예외의 메시지가 빈 문자열이면 메시지도 빈 문자열 그대로다` (CR-07 (c)) | FAILED | AssertionError. `playTrack` 결과: 기대 `Error(PLAYER_ERROR, )` (빈 메시지), 실제 `NotImplemented` | ✅ |
| `CR-08 프록시 등록이 null 이면 NO_WIFI 오류다` (CR-08) | FAILED | AssertionError. 기대 `Error(NO_WIFI, Wi-Fi에 연결되어 있지 않아 스피커로 스트리밍할 수 없습니다.)`, 실제 `NotImplemented` | ✅ |
| `CR-09 enabled 가 true 이면 Wi-Fi 잠금을 건다` (CR-09 (a)) | FAILED | AssertionError. 기대 `Success(null)`, 실제 `NotImplemented` | ✅ |
| `CR-09 enabled 가 false 이면 Wi-Fi 잠금을 푼다` (CR-09 (b)) | FAILED | AssertionError. 기대 `Success(null)`, 실제 `NotImplemented` | ✅ |
| `CR-09 enabled 가 없으면 Wi-Fi 잠금을 푼다` (CR-09 (c)) | FAILED | AssertionError. 기대 `Success(null)`, 실제 `NotImplemented` | ✅ |
| `CR-10 숫자 인자가 Int 로 오면 그 값으로 넘긴다` (CR-10 (a)) | FAILED | AssertionError. `① seekTrack` 결과: 기대 `Success({status=seeked, positionMs=90000})`, 실제 `NotImplemented` | ✅ |
| `CR-10 숫자 인자가 Long 으로 와도 같은 값으로 넘기고 positionMs 는 Int 로 돌려준다` (CR-10 (b)) | FAILED | AssertionError. `① seekTrack` 결과: 기대 `Success({status=seeked, positionMs=90000})`, 실제 `NotImplemented` | ✅ |
| `CR-11 문자열 자리에 숫자가 오면 인자가 없는 것으로 보고 기본값을 쓴다` (CR-11 (a)) | FAILED | AssertionError. `① playTrack` 결과: 기대 `Success({status=playing, trackId=})`, 실제 `NotImplemented` | ✅ |
| `CR-11 정수 자리에 문자열이 오면 인자가 없는 것으로 보고 기본값을 쓴다` (CR-11 (b)) | FAILED | AssertionError. `① seekTrack` 결과: 기대 `Success({status=seeked, positionMs=0})`, 실제 `NotImplemented` | ✅ |
| `CR-11 불리언 자리에 다른 타입이 오면 false 로 본다` (CR-11 (c)) | FAILED | AssertionError. `enabled="true"` 결과: 기대 `Success(null)`, 실제 `NotImplemented` | ✅ |
| `CR-12 인증 협력 객체의 예외는 잡지 않고 그대로 전파한다` (CR-12 (a)) | FAILED | AssertionError. `initTidalAuth`: 예외가 전파되어야 하는데 결과 `NotImplemented` 가 돌아옴 | ✅ |
| `CR-12 기기 협력 객체의 예외는 잡지 않고 그대로 전파한다` (CR-12 (b)) | FAILED | AssertionError. `getPhoneVolume`: 예외가 전파되어야 하는데 결과 `NotImplemented` 가 돌아옴 | ✅ |
| `CR-12 프록시 협력 객체의 예외는 잡지 않고 그대로 전파한다` (CR-12 (c)) | FAILED | AssertionError. `registerTrackStream`: 예외가 전파되어야 하는데 결과 `NotImplemented` 가 돌아옴 | ✅ |
| `CR-13 같은 호출을 두 번 하면 두 번 모두 같은 결과다` (CR-13 (a)) | FAILED | AssertionError. `playTrack` 1회째: 기대 `Success({status=playing, trackId=101})`, 실제 `NotImplemented` | ✅ |
| `CR-13 플레이어는 호출할 때마다 조회한다` (CR-13 (b)) | FAILED | AssertionError. 플레이어가 없을 때: 기대 `Error(PLAYER_ERROR, TIDAL Player가 초기화되지 않았습니다)`, 실제 `NotImplemented` | ✅ |
| `P-CR-1 표에 없는 어떤 이름도 미구현이고 협력 객체 호출이 0회다` (P-CR-1) | PASSED | - (100회. CR-03 과 같은 이유) | 보호 |
| `P-CR-2 플레이어가 없으면 어떤 인자여도 7개 동작은 PLAYER_ERROR 이고 stopTrack 은 성공이다` (P-CR-2) | FAILED | AssertionFailedError (Kotest 가 감쌈, 원인은 AssertionError). 1회째에 실패. 입력 `RouterCall(method=setNextTrack, args={})`: 기대 `Error(PLAYER_ERROR, TIDAL Player가 초기화되지 않았습니다)`, 실제 `NotImplemented`. 출력에 seed 20261117 | ✅ |
| `P-CR-3 플레이어가 어떤 예외를 던져도 PLAYER_ERROR 이고 메시지는 예외의 메시지 또는 클래스 이름이다` (P-CR-3) | FAILED | AssertionFailedError (원인은 AssertionError). 1회째에 실패. 입력 `"setNextTrack"`, 메시지 없는 `RuntimeException`: 기대 `Error(PLAYER_ERROR, RuntimeException)`, 실제 `NotImplemented` | ✅ |
| `P-CR-4 인자는 어떤 값이든 협력 객체와 성공 값에 그대로 전달된다` (P-CR-4) | FAILED | AssertionFailedError (원인은 AssertionError). 첫 `checkAll` (`playTrack`) 의 1회째에 실패. 입력 `"604293"`: 기대 `Success({status=playing, trackId=604293})`, 실제 `NotImplemented` | ✅ |
| `P-CR-5 등록 인자는 그대로 전달되고 빠진 인자에는 기본값이 들어가며 돌려받은 URL 이 proxyUrl 이다` (P-CR-5) | FAILED | AssertionFailedError (원인은 AssertionError). 1회째에 실패. 축소된 입력: 다섯 인자 모두 없음, 반환 URL `http://192.0.2.254:65535/audio/0000000000000000.flac`: 기대 `Success({proxyUrl=http://192.0.2.254:65535/audio/0000000000000000.flac})`, 실제 `NotImplemented` | ✅ |
| `P-CR-6 어떤 호출이든 두 번 하면 결과가 같다` (P-CR-6) | PASSED | - (100회. 두 결과가 모두 `NotImplemented`, 호출 기록은 둘 다 비어 있음. 뼈대에서는 내용 없이 통과한다) | 보호 |

### `ChannelAdapterTest` (5개)

| 테스트 (표 행) | 결과 | 실패 종류 (기대값과 실제값) | RED 인정 |
| --- | --- | --- | --- |
| `PC-01 인자가 맵이면 키와 값과 타입을 그대로 돌려준다` (PC-01 (a)) | FAILED | AssertionError. 기대 `{trackId=101, positionMs=90000, enabled=true}`, 실제 `{}` | ✅ |
| `PC-01 인자가 맵이 아니면 빈 맵을 돌려준다` (PC-01 (b)) | PASSED | - (뼈대가 항상 빈 맵을 돌려준다) | 보호 |
| `PC-02 성공 결과는 그 값으로 success 를 한 번 보낸다` (PC-02 (a)) | FAILED | AssertionError. 값 `{status=paused}`: 기대 `[[success, {status=paused}]]`, 실제 `[]` | ✅ |
| `PC-02 오류 결과는 코드와 메시지와 null 로 error 를 한 번 보낸다` (PC-02 (b)) | FAILED | AssertionError. 메시지 있음: 기대 `[[error, PLAYER_ERROR, TIDAL Player가 초기화되지 않았습니다, null]]`, 실제 `[]` | ✅ |
| `PC-02 미구현 결과는 notImplemented 를 한 번 보낸다` (PC-02 (c)) | FAILED | AssertionError. 기대 `[[notImplemented]]`, 실제 `[]` | ✅ |

## 만든 파일

모두 `android/app/src/test/kotlin/com/example/tidal_connect_lite/` 아래다. `src/main` 은 고치지 않았다.

| 파일 | 내용 |
| --- | --- |
| `RouterFakes.kt` | `FakePlayerControls`, `FakeAuthControls`, `FakeDeviceControls`, `FakeProxyRegistrar` |
| `RouterGenerators.kt` | `RouterArbs` (생성기 모음), `RouterCall`, `RouterThrown`, `RouterRegistration` |
| `PlaybackCommandRouterTest.kt` | `@Test` 32개: CR 26개 + P-CR 6개 |
| `ChannelAdapterTest.kt` | `@Test` 5개: PC-01 2개 + PC-02 3개 |

## 고친 테스트 쪽 오류

없음. 첫 실행에서 컴파일되었고 ERROR 가 없었다.

첫 실행과 두 번째 실행 사이에 테스트 쪽을 두 가지 바꿨다. 기대값은 건드리지 않았다.

- `RouterGenerators.kt` 의 허용 주소 생성기를 `192.0.2.x` 로만 좁혔다 (처음에는 `198.51.100.x`, `203.0.113.x` 도 만들었다. 작업 지시의 "`192.0.2.x` 만" 에 맞춤)
- 120자를 넘는 줄 5개를 줄바꿈했다

## 표와 달라진 점

경계 표의 행을 더하거나 빼지 않았다. 기대값도 표 그대로다. 표에 적히지 않았던 구현상의 선택만 적는다.

- 테스트 이름에 (a) · (b) 같은 행 표시를 넣지 않았다. 규칙 ID 뒤에 조건을 문장으로 적었다 (대응은 위 판정 표)
- 허용 주소 생성기: 표는 "`127.0.0.1` 또는 문서용 예약 대역의 IPv4" 인데 예약 대역 가운데 `192.0.2.0/24` 만 쓴다 (표의 범위 안)
- P-CR-6 의 "임의의 채널 호출" 에서 `initTidalAuth` 의 `clientId` · `clientSecret` 은 자격 증명용 영숫자 생성기를 다시 썼다 (`domain-entities.md` 4절에 이 두 인자의 생성기가 따로 없다)
- P-CR-5 는 빠진 인자의 기대값을 테스트에서 `?: ""` · `?: "audio/mp4"` 로 채워 기대 호출 문자열을 만든다. 기본값 리터럴은 규칙 문서의 값이다
- 예외 메시지 생성기의 글자 집합은 영숫자, 공백과 문장 부호 몇 개 (`. : - _ /`), 한글 음절 몇 개다. 길이 0 ~ 30

## 남은 의문

- **첫 단언 뒤의 부분은 아직 실행된 적이 없다.** 실패한 33개는 모두 첫 번째 결과 단언에서 멈췄다. 표를 도는 테스트의 둘째 줄부터, 결과 단언 뒤의 호출 기록 단언, P-CR-4 의 둘째 ~ 여섯째 `checkAll` 은 뼈대에서는 도달하지 못한다. 이 부분은 경계 표와 눈으로 대조했을 뿐이다. 여기에 테스트 쪽 오타가 있으면 GREEN 단계에서 처음 드러난다 (그때는 구현 세션이 고치지 않고 멈춰 보고해야 한다, 계획 Step 5.5)
- 생성기는 모두 한 번 이상 값을 만들었다 (P-CR-1 · P-CR-6 은 100회를 다 돌았고, 나머지는 첫 예시를 만들었다). 생성기 쪽 예외나 걸러내기 고갈은 없었다
- P-CR-6 은 뼈대에서 내용 없이 통과한다 (승인 때 정한 대로 "보호"). 구현 뒤에야 의미가 생긴다
- 프록시 담당의 `TidalStreamProxyServerTest.kt` 는 내 첫 실행 직전의 파일 목록에 없었고 지금은 있다. 두 쪽 테스트를 한꺼번에 돌리는 전체 실행은 하지 않았다 (컴파일만 함께 확인). 주 세션이 전체를 다시 실행하면 router 쪽 결과 XML 도 다시 생긴다
