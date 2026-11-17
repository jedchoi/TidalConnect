# 코드 요약 (Code Summary) - android-native-tests

작성일: 2026-11-17. 브랜치 `aidlc/test-reinforcement`. 계획: `aidlc-docs/construction/plans/android-native-tests-code-generation-plan.md` (Step 10개 모두 완료).

## 결과

| 항목 | 결과 |
| --- | --- |
| 새 Kotlin 테스트 | 82개 (예시 기반 69개 + 속성 13개). 전체 4개 → 86개 |
| 규칙 대응 | `business-rules.md` 의 규칙 53개 (CR 13, PC-01 ~ 02, PX 38) 모두에 테스트가 있음 (테스트 이름 맨 앞의 규칙 ID 로 대조) |
| 속성 대응 | `business-logic-model.md` 의 속성 12개 모두에 속성 테스트가 있음 |
| 발견한 버그 (FR-08) | 1건, 수정함: 길이를 모르는 HEAD 응답의 `Content-Length: -1` |
| 운영 코드 변경 | 새 파일 3개, 수정 3개 (`main` 대비 +334 −133 줄) |
| 실기기 확인 | 하지 않음. 아래 "실기기에서만 확정되는 부분" |
| 남은 의문 | 연속 반복 실행에서 프록시 테스트 1개가 가끔 실패한다 (약 135회 중 4회, 원인 미확인, 사용자가 수용). 아래 "알려 둘 점" |

Kotlin 쪽은 커버리지 목표가 없다 (NFR-01 의 80% 는 Dart 대상 4개 파일). 규칙마다 테스트가 있는지와 변형 확인으로 대신했다.

## 진행 방식

`tdd-red` → `tdd-green` → `tdd-refactor` 스킬의 흐름을 따랐다. 스킬은 Python 실습을 전제로 쓰여 있어 흐름과 금지 사항만 따르고 도구는 바꿨다 (`nfr-design-patterns.md` TW-1 ~ TW-9). 단계마다 에이전트를 나눴다.

| 단계 | 맡은 쪽 | 한 일 |
| --- | --- | --- |
| 뼈대 | 주 세션 | 인터페이스 · router · 변환 함수의 빈 뼈대, 프록시 생성자 |
| RED | 하위 에이전트 2개 (router 담당, 프록시 담당). 구현 본문을 읽지 않음 | 설계 문서만 보고 테스트 경계 표 → 테스트 작성 → RED 판정 표 |
| GREEN | RED 와 다른 새 하위 에이전트 | 고정된 테스트를 고치지 않고 router · 변환 함수 구현 |
| REFACTOR | GREEN 을 끝낸 그 에이전트 | 후보 표 → 승인된 후보를 하나씩 적용 |
| 버그 수정 | 또 다른 새 하위 에이전트 | 실패하는 프록시 테스트 3개를 통과시키는 수정, 문제 기록 초안 |
| 조율 | 주 세션 | 사람 관문 전달, 테스트 변경 여부 확인, diff 검토, 커밋, 변형 확인, 검증 |

사람 관문 3개를 모두 거쳤다: 테스트 경계 표 승인, "RED 확인 + A (버그로 처리)", "승인 + 나 (실패 로그는 감싸개)".

테스트 고정은 스냅샷 대신 커밋으로 했다. 고정 커밋은 `6acf424` 이고, 그 뒤 모든 단계에서 `git diff --exit-code 6acf424 -- android/app/src/test` 가 차이 없음을 확인했다.

## 파일

경로는 `android/app/src/main/kotlin/com/example/tidal_connect_lite/` (운영) 과 `android/app/src/test/kotlin/com/example/tidal_connect_lite/` (테스트) 아래다.

### 수정 (Modified)

| 파일 | 내용 |
| --- | --- |
| `PlaybackCore.kt` | `onMethodCall` 의 분기 16개를 `channelArguments` → `router.handle` → `sendCommandResult` 한 줄로 바꿈. router 가 부르는 운영 구현 3개 (`authControls`, `deviceControls`, `proxyRegistrar`) 를 기존 private 함수에 연결. 실패 로그용 `LoggingPlayerControls` 추가. `runPlayerAction` · `requirePlayerManager` 삭제. 그 밖의 함수 본문은 그대로 (+86 −113) |
| `TidalPlayerManager.kt` | `: PlayerControls` 와 `override` 8개. 주석 1줄. 함수 본문은 그대로 |
| `TidalStreamProxyServer.kt` | 생성자에 `port`, `httpClient` 추가 (기본값은 기존 동작). 주소의 포트를 실제로 열린 포트로. 길이를 모르는 HEAD 응답에서 `Content-Length` 를 쓰지 않게 수정 (버그 수정) |
| `android/app/build.gradle.kts` | `testOptions { unitTests.isReturnDefaultValues = true }`, `testImplementation` 2개 (`io.kotest:kotest-property:6.2.7`, `com.squareup.okhttp3:mockwebserver:4.12.0`) |

### 생성 (Created)

| 파일 | 내용 |
| --- | --- |
| `PlaybackContracts.kt` | `CommandResult`, `PlayerControls`, `AuthControls`, `DeviceControls`, `ProxyRegistrar`. 로직 없음 |
| `PlaybackCommandRouter.kt` | 채널 메서드 16개의 분배, 인자 해석, 성공 값, 오류 변환. Android · Flutter 타입을 import 하지 않음 |
| `ChannelAdapter.kt` | `channelArguments`, `sendCommandResult`. Flutter 타입에 닿는 변환 |
| `PbtSupport.kt` (테스트) | 고정 seed (20261117), `PBT_SEED` 환경 변수, 실행 횟수 설정 |
| `RouterFakes.kt`, `RouterGenerators.kt` (테스트) | 협력 인터페이스 4개의 fake, router 속성의 생성기 |
| `PlaybackCommandRouterTest.kt` (테스트) | 테스트 26개 + 속성 6개 (CR-01 ~ CR-13, P-CR-1 ~ P-CR-6) |
| `ChannelAdapterTest.kt` (테스트) | 테스트 5개 (PC-01, PC-02) |
| `FakeCdnServer.kt`, `ProxyFixture.kt`, `ProxyGenerators.kt` (테스트) | `MockWebServer` 를 감싼 가짜 CDN, 프록시를 임시 포트로 띄우는 도우미, 프록시 속성의 생성기 |
| `TidalStreamProxyServerTest.kt` (테스트) | 테스트 38개 + 속성 7개 (PX-01 ~ PX-38, P-PX-1 ~ P-PX-6) |
| `docs/incidents/2026-11-17-head-content-length-minus-one.md` | 버그의 원인과 수정 기록 |

이 unit 의 다른 산출물 (같은 폴더): `red-seam-table-router.md`, `red-seam-table-proxy.md` (테스트 경계 표, 승인본), `red-result-router.md`, `red-result-proxy.md` (RED 판정 표), `refactor-candidates.md` (리팩토링 후보 표, 승인본).

## RED · GREEN · REFACTOR 결과

### RED

| 대상 | 테스트 | 실패 | 통과 ("보호") | 테스트 쪽 오류 |
| --- | --- | --- | --- | --- |
| router · 채널 변환 | 37 | 33 (모두 기대값 불일치) | 4 (CR-03, P-CR-1, P-CR-6, PC-01 b) | 0 |
| 프록시 | 45 | 3 (PX-17, PX-19, PX-38) | 42 | 0 |

- 테스트 경계 표를 만들면서 에이전트가 "문서만으로는 정할 수 없다" 고 보고한 32건 (router 11, 프록시 21) 을 규칙 문서에 보완했다
- 프록시의 실패 3개는 원인이 하나였다 (아래 "버그"). 사람 판정: 버그로 처리하고 실패하는 그대로 고정

### GREEN

`PlaybackCommandRouter.kt` 와 `ChannelAdapter.kt` 구현 (+112 −6). router 32개 · 변환 5개 통과. 테스트가 규칙 문서와 어긋나 멈춘 곳은 없었다.

### REFACTOR

| # | 후보 | 결과 |
| --- | --- | --- |
| 1 | `TidalPlayerManager` 에 `PlayerControls` 구현 선언 | 적용 (`2b5a3d8`) |
| 2 | `PlaybackCore.onMethodCall` → router 위임, 운영 구현 3개 연결, 쓰이지 않는 함수 삭제 | 적용 (`56d7bfe`) |
| 7 | 오래된 주석 수정 | 적용 (`4236cd8`) |
| 3 ~ 6 | router 내부 정리 (정수 읽기 도우미, 예외 구조, 오류 상수, 성공 값 묶기) | 그대로 둠. 분기가 규칙 문서의 메서드 표와 1:1 인 지금 모양이 대조하기 쉽고 묶는 이득이 작다 |

후보 2 에서 정한 것:

- 실패 로그 (O-8): `LoggingPlayerControls` 감싸개가 플레이어가 던진 예외를 재구성 전과 같은 `Log.e` 로 남기고 다시 던진다. 플레이어가 없을 때의 로그 한 줄은 남지 않는다 (오류 응답은 같다)
- 채널 객체가 없는 상태의 `initTidalAuth`: 아무 일도 하지 않고 `init_failed` 로 응답한다 (O-6. 생기지 않는 상태)
- 테스트가 잡지 못하는 두 가지를 컴파일 결과 (`javap`) 로 확인했다: `deviceControls` 의 함수 4개가 자기 자신이 아니라 `PlaybackCore` 의 private 함수를 부른다, `router` 가 운영 구현 3개보다 뒤에 초기화된다

## 검증 결과 (계획 Step 7, 9)

| # | 확인 | 결과 |
| --- | --- | --- |
| 9.1 | Kotlin 테스트 전체 (`:app:testDebugUnitTest`) | 86개 통과, 실패 0, 건너뜀 0 (router 32, 변환 5, 프록시 45, 기존 `DashManifestTest` 4) |
| 9.2 | 규칙 ID 대조 | 규칙 53개 · 속성 12개가 모두 테스트 이름에 있음. 빠진 ID 없음, 목록에 없는 ID 없음 |
| 9.3 | 10회 연속 실행 (`--rerun-tasks`) | **기준 미충족.** 10회 중 9회 통과, 첫 회에 프록시 테스트 1개 실패. 추가 반복에서도 가끔 재현됨. 아래 "알려 둘 점" |
| 9.4 | 실행 시간 합계 (결과 XML) | 2.5 ~ 2.7초 (기준 30초). 프록시가 약 2.5초, 나머지는 0.2초 미만. 속성 실행 횟수는 계획대로 (router 100회, 프록시 100 / 50 / 25회) |
| 9.5 | 8765 포트를 다른 프로세스가 점유한 상태 | 86개 통과 |
| 9.6 | `tool/check.sh` 전체 | 모든 점검 통과 (포맷, 분석, Flutter 테스트 262개, Kotlin 테스트) |
| 9.7 | `flutter build apk --debug --dart-define-from-file=config/tidal.json` | 성공 |
| 9.8 | `git diff main -- android/app/src/main` 검토 | 채널 이름 상수 변경 없음. `PlaybackCore` 의 변경은 후보 2 의 커밋 하나뿐이고 남은 함수 본문 변경 없음. `ensureProxyServer` 의 프록시 생성 호출 변경 없음 |
| 9.9 | 비밀 값 · 금지 패턴 | 테스트 · 문서에 클라이언트 ID · 시크릿 0건. `Thread.sleep`, `@Ignore`, 사설 대역 주소 없음. 복제 파일 없음 |

`tool/check.sh` 와 Gradle 명령은 `JAVA_HOME=/opt/homebrew/opt/openjdk@17` 을 지정해 실행했다 (이 셸의 PATH 에 Java 가 없다).

### 변형 확인 (Step 7)

운영 코드를 한 곳씩 일부러 틀리게 바꾸고 테스트가 실패하는지 확인한 뒤 되돌렸다. 버그 수정 뒤에 실행했다.

| 대상 | 넣은 변형 | 감지 |
| --- | --- | --- |
| `PlaybackCommandRouter` | 21개 (성공 값, 기본값, 오류 코드, 예외 메시지, 인자 순서, 플레이어 조회 시점 등) | 19/21 |
| `ChannelAdapter` | 4개 (인자를 버림, 오류의 코드 · 메시지 뒤바꿈, 미구현 · 성공 값) | 4/4 |
| `TidalStreamProxyServer` | 33개 (허용 호스트, 등록 개수, MIME · 확장자, 만료 재발급, Range, 상태 코드, HEAD 길이, DASH 길이 기억 등) | 33/33 |

이번 버그 수정을 되돌리는 변형은 PX-17 · PX-19 · PX-38 이 잡는다.

살아남은 2개 (테스트를 추가하지 않았다. 추가하려면 RED 로 돌아가 다시 판정 · 고정해야 한다):

| 변형 | 살아남은 이유 | 판단 |
| --- | --- | --- |
| `runPlayerAction` 이 `Exception` 대신 `Throwable` 을 잡음 | fake 가 `RuntimeException` 만 던진다 | CR-07 은 "예외" 라고만 적어 잡는 범위를 정하지 않았다. 구현은 재구성 전과 같이 `Exception` 만 잡는다 |
| `expiresInSeconds` 를 Int 로 잘라 넘김 | 테스트 입력에 Int 범위를 넘는 값이 없다 | 토큰 유효 시간은 초 단위라 실제 값은 Int 안이다. CR-10 의 "Long 으로 넘긴다" 는 타입만 확인된다 |

`PlaybackCore.kt` 의 운영 구현 3개, `LoggingPlayerControls`, `onMethodCall` 한 줄은 JVM 테스트가 실행하지 않으므로 변형 대상에서 뺐다. 이 부분은 테스트가 없다.

## 발견한 것 (Step 8)

### 버그 (FR-08): 1건, 수정함

길이를 알아내지 못한 HEAD 요청에 프록시가 `Content-Length: -1` 을 보냈다. 코드 주석의 의도는 "길이를 모르면 알리지 않는다" 였고, 프록시 코드는 이 헤더를 직접 넣지 않았다. NanoHTTPD 2.3.1 이 HEAD 응답이면 chunked 응답에도 `Content-Length` 를 쓰기 때문이었다.

- 발견: RED 에서 프록시 테스트 3개 (PX-17, PX-19, PX-38) 가 실패. 원시 소켓으로 받은 응답에서도 확인
- 판정: 사람이 버그로 판정 (주석의 의도와 다르고 올바른 헤더 값이 아님)
- 수정: `8e5b417`. 길이를 모르는 HEAD 응답에서 그 헤더를 쓰는 메서드만 막았다 (+5 −1). 길이를 아는 HEAD 와 GET 은 그대로
- 기록: `docs/incidents/2026-11-17-head-content-length-minus-one.md`
- 확인하지 못한 것: 렌더러가 `-1` 을 받았을 때와 헤더가 없을 때 각각 어떻게 동작하는지

### 규칙 문서가 틀렸던 곳: 1건

CR-10 을 보완하면서 "지금 코드 기준" 이라고 적었지만, 재구성 전의 `onMethodCall` 은 `positionMs` · `percent` 를 Int 로만 읽었다. GREEN 에이전트가 발견했다. 테스트와 router 는 CR-10 대로 (Long 도 읽음) 이고, 문서에 차이를 적었다 (O-7). Flutter 는 이 범위의 정수를 Int 로 보내므로 실제 입력에서는 차이가 없다.

### 관찰 사항 추가: O-7 ~ O-15

`business-rules.md` 7절에 추가했다.

| # | 내용 |
| --- | --- |
| O-7, O-9 ~ O-12 | 위임 뒤에 생기지 않는 입력에서만 달라지는 동작 (Long 인자, 맵이 아닌 인자, `JSONObject`, 소수, 응답 객체의 예외) |
| O-8 | 실패 로그의 처리 결과 (감싸개) |
| O-13 | 길이를 모르는 DASH 곡은 요청마다 세그먼트 전부의 길이를 다시 조회한다. 테스트로 고정하지 않음 |
| O-14 | GET 응답에 `Access-Control-Allow-Origin: *` 가 붙는다. 규칙에 없고 테스트로 고정하지 않음 |
| O-15 | 위 버그의 기록 |

### 알려 둘 점: 프록시 테스트가 가끔 실패한다 (원인 미확인, 사용자가 수용)

전체 테스트를 이어서 반복하면 프록시 테스트 1개가 가끔 실패한다. 10회 연속 실행의 첫 회에서 처음 나왔고 (어느 테스트인지 기록하지 못함), 재현을 시도한 결과는 아래와 같다.

| 조건 | 횟수 | 실패 |
| --- | --- | --- |
| 전체, 10회 연속 (9.3) | 10 | 1 (첫 회) |
| 프록시 테스트만 | 25 | 0 |
| 전체 | 35 | 0 |
| 전체, CPU 10코어에 부하를 건 상태 | 20 | 0 |
| 전체, 실패하면 결과를 보관 | 70 | 3 |

합쳐서 전체 실행 약 135회 중 4회다 (변형 확인 등 다른 실행까지 합치면 약 240회 중 4회).

확인된 것:

- 보관된 3회는 `P-PX-6` (DASH) 2회, `PX-38` c 행 1회다. 모두 테스트 클라이언트의 `SocketTimeoutException: Read timed out` 이다
- 세 번 모두 DASH 전체 길이를 계산하는 경로 (`dashLength`: 세그먼트마다 HEAD 를 동시에 보냄) 를 거친다. `P-PX-6` 은 프록시의 응답 헤더를 기다리다 멈췄고, `PX-38` c 에서는 가짜 CDN 이 HEAD 4건 중 3건만 받았다
- 테스트 클라이언트와 프록시가 쓰는 CDN 클라이언트의 제한 시간이 둘 다 2초다 (`ProxyFixture`). 프록시 쪽 요청 하나가 2초에 걸리면 테스트 쪽도 같은 시각에 걸린다
- 속성의 seed 는 고정이라 입력은 매번 같다. 같은 입력으로 대부분 통과한다

배제한 것: CPU 부하 (부하를 걸고 20회 통과), 임시 포트 소진 (연속 실행 중 TIME_WAIT 소켓은 약 2500줄로 포트 범위에 한참 못 미침).

확인하지 못한 것: 2초 넘게 멈추는 구간이 프록시의 길이 계산 (운영 코드) 인지, 가짜 CDN · 테스트 도우미인지, 라이브러리 · OS 인지. 운영 코드라면 실기기에서 DASH 곡의 DLNA 재생 시작이 가끔 늦어지는 형태로 나타날 수 있다. 원인 조사를 시작했으나 사용자 지시로 중단했다 (2026-11-17, "그정도는 괜찮아").

영향: NFR-03-A4 (10회 연속 같은 결과) 는 첫 묶음에서 충족하지 못했다. `tool/check.sh` 나 CI 가 가끔 (약 2 ~ 3%) 프록시 테스트 1개로 실패할 수 있고, 다시 실행하면 통과한다. 실패 기록은 저장소에 넣지 않았다.

다시 조사한다면: 문제 경로 (DASH 등록 → HEAD · GET) 만 반복하는 임시 테스트로 재현하고, 구간별 시각과 멈춘 순간의 스레드 덤프를 남긴다. 테스트 클라이언트의 제한 시간만 늘려 프록시 응답이 결국 몇 초에 오는지 보면 프록시 쪽 제한 시간에 걸린 것인지 알 수 있다.

## 실기기에서만 확정되는 부분 (NFR-06-A6)

재구성의 동작 동일성은 자동 테스트, 분기 대조표, 컴파일 결과 확인, 빌드로만 확인했다. 실기기에서는 실행하지 않았다.

- `PlaybackCore.onMethodCall` 의 위임 (`56d7bfe`): 재생 명령 경로 전체가 router 를 거친다. `PlaybackCore` 는 JVM 테스트로 실행할 수 없다
- 길이를 모르는 HEAD 응답의 변경 (`8e5b417`): 렌더러가 받는 응답이 달라진다

확인 순서 (후보 표 4.9): 로그인 → 재생 · 일시정지 · 탐색 · 다음 곡 · 음질 변경 · 볼륨 · 정지 → DLNA 스피커 재생 → Wi-Fi 를 끈 채 DLNA 재생 시도. 재생 경로를 고쳤으므로 `docs/failure-scenarios.md` 의 관련 항목도 해당한다.

## 계획과 달라진 점 (CG-7)

### 계획에 없던 변경

| 변경 | 이유 |
| --- | --- |
| GREEN · REFACTOR 를 주 세션이 아니라 하위 에이전트가 맡음 | 사용자 지시 (에이전트를 나눠 자기편향을 줄임). 계획 파일을 고쳐 반영함 (`6108f2a`) |
| 버그 수정도 주 세션이 아니라 새 하위 에이전트가 맡음 | 같은 이유. 계획 Step 8 은 주 세션으로 적혀 있었다 |
| Step 8 의 버그 수정을 Step 7 (변형 확인) 보다 먼저 함 | 프록시 테스트 3개가 실패하는 상태에서는 변형 확인의 결과를 읽기 어렵다 |
| RED 중 규칙 문서 보완 32건 | 구현을 읽지 않은 에이전트가 문서만으로 정할 수 없다고 보고한 곳 |
| 프록시 테스트도 하위 에이전트가 설계 문서만 보고 작성 | NFR Design TW-8 은 주 세션이 쓰기로 했었다. TDD 스킬 활용 지시에 맞춰 바꿈 |
| `LoggingPlayerControls` 감싸개 | 위임하면 실패 로그의 스택 트레이스가 사라지는 것을 REFACTOR 후보 표에서 발견. 사람이 선택지 "나" 로 결정 |
| `PlaybackContracts.kt` 의 문서 주석 1줄 수정 (주 세션) | 감싸개가 생기면서 "운영 구현은 `TidalPlayerManager`" 가 덜 정확해졌다 |
| `business-rules.md` 의 관찰 사항 O-7 ~ O-15 | 진행 중 발견한 차이의 기록 |

### 계획에서 뺀 항목

없음.

### 설계에서 정한 대안을 쓰지 않은 것

- 테스트 고정은 `tdd_snapshot.py` 대신 커밋으로 했다 (TW-5)
- 프록시 속성의 실행 횟수는 줄이지 않았다 (시간 기준 안)

## 커밋

| 커밋 | 내용 |
| --- | --- |
| `551e573` | test: Kotlin 단위 테스트 설정과 속성 테스트 도우미 추가 |
| `ab02cd4` | refactor: 명령 분배용 인터페이스 뼈대 추가, 프록시 포트와 HTTP 클라이언트 주입 가능하게 |
| `6acf424` | test: 명령 분배 · 프록시 테스트 추가 (RED). **고정 커밋.** 이 커밋의 Kotlin 테스트는 36개가 실패한다 |
| `e913989` | feat: PlaybackCommandRouter 와 채널 응답 변환 구현 (GREEN). 프록시 3개 실패가 남음 |
| `2b5a3d8` | refactor: TidalPlayerManager 가 PlayerControls 를 구현하도록 선언 |
| `56d7bfe` | refactor: PlaybackCore.onMethodCall 을 PlaybackCommandRouter 위임으로 교체 |
| `4236cd8` | docs: 재구성 뒤 구조에 맞게 오래된 주석 수정 |
| `8e5b417` | fix: 길이를 모르는 HEAD 응답에 Content-Length: -1 이 나가던 문제 수정. 여기부터 Kotlin 테스트 전부 통과 |
| `e4466ff` | docs: HEAD 응답의 Content-Length: -1 문제 기록 |

사이사이에 진행 기록 커밋 (`docs(aidlc): ...`) 이 있고, 그 뒤에 이 요약을 담은 커밋이 있다. `6acf424` 부터 `8e5b417` 앞까지의 커밋은 Kotlin 테스트가 실패하는 상태다 (`git bisect` 를 쓸 때 주의). 푸시하지 않았다.

## 확장 규칙 준수

### Property-Based Testing

| 규칙 | 상태 | 근거 |
| --- | --- | --- |
| PBT-01 | compliant | 속성 12개가 모두 구현됨 (속성 테스트 13개. P-PX-6 은 단일 파일과 DASH 로 나눔) |
| PBT-02 | compliant | P-PX-6 (등록 → 조회 왕복) |
| PBT-03 | compliant | P-CR-1 ~ 5, P-PX-1 · 4 · 5 |
| PBT-04 | compliant | P-CR-6 (같은 호출 두 번의 결과가 같음) |
| PBT-05 | compliant | P-PX-2 (확장자 참조 표와 비교) |
| PBT-06 | compliant | P-PX-3 (등록마다 "최근 3개" 모델과 비교) |
| PBT-07 | compliant | `RouterGenerators.kt`, `ProxyGenerators.kt` 에 도메인 생성기. 범위는 `domain-entities.md` |
| PBT-08 | compliant | 축소 설정을 바꾸지 않음. 고정 seed (20261117), `PBT_SEED`. RED 에서 실패한 속성 4개의 출력에 seed 와 축소된 입력이 나오는 것을 확인. 일반 Gradle 테스트에 포함 |
| PBT-09 | compliant | `io.kotest:kotest-property:6.2.7` 이 `testImplementation` 에 있음 |
| PBT-10 | compliant | 규칙마다 예시 기반 테스트가 있고 속성은 그 위에 더함 |

### Resiliency

| 규칙 | 상태 | 근거 |
| --- | --- | --- |
| RESILIENCY-14 | compliant | 프록시의 장애 동작 (CDN 연결 실패, CDN 오류 응답, 주소 만료와 재발급 실패, 매니페스트 해석 실패, 세그먼트 길이 조회 실패) 을 자동 테스트로 고정 |
| RESILIENCY-15 | compliant | 발견한 버그를 `docs/incidents/README.md` 의 절차 (실패 테스트 → 별도 `fix:` 커밋 → 문서) 로 처리 |
| 그 밖 | N/A | 운영 경로에 새 외부 호출 · 저장소 · 배포 구성 없음 |

## 사용법 메모

- Kotlin 테스트: `(cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :app:testDebugUnitTest)`. 클래스 하나만: `--tests "*PlaybackCommandRouterTest*"`
- 결과 XML 은 `android/app/build` 가 아니라 저장소 루트의 `build/app/test-results/testDebugUnitTest/` 에 생긴다
- 속성 테스트 실패를 재현: 출력된 seed 로 `PBT_SEED=<seed> ./gradlew :app:testDebugUnitTest --rerun-tasks`
- 테스트가 고정 뒤에 바뀌었는지 확인: `git diff --exit-code 6acf424 -- android/app/src/test`
- `ci-quality-gate` unit 에서 정할 것: `tool/check.sh` 가 Java 를 스스로 찾게 할지
