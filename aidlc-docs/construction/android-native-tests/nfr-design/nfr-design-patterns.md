# NFR 설계 패턴 (NFR Design Patterns) - android-native-tests

`nfr-requirements.md` 의 요구를 Kotlin 테스트 코드와 재구성 작업의 패턴으로 옮긴다. 패턴 ID 는 Code Generation 계획에서 참조한다. 구성 요소 (파일) 는 `logical-components.md` 에 있다.

## 1. 작업 방식 패턴 (계획 Q1=A)

`PlaybackCommandRouter` 와 채널 응답 변환은 아직 없는 새 코드라 TDD 흐름으로 만든다. `TidalStreamProxyServer` 는 이미 있는 코드라 보호 테스트를 쓴다.

TDD 스킬 (`.claude/skills/tdd-red`, `tdd-green`, `tdd-refactor`) 은 Python 실습 모듈 전제라 그대로 쓸 수 없어, 흐름과 금지 사항을 아래처럼 옮긴다. 스킬 파일은 고치지 않는다.

| 스킬의 방식 | 이 unit 에서 |
| --- | --- |
| RED 와 GREEN 을 다른 세션에서 | RED 는 별도 하위 에이전트가 한다 (TW-2) |
| RED 는 구현 코드 본문을 읽지 않음 | 하위 에이전트에게 읽을 문서를 지정하고 `PlaybackCore.kt` 등의 열람을 금지한다 (TW-2) |
| `pytest`, `ruff` | `./gradlew :app:testDebugUnitTest` (JDK 17) |
| `tdd_snapshot.py` 로 고정 · 비교 · 되돌리기 | 테스트 파일을 커밋해 고정하고 그 커밋과 비교한다 (TW-5) |
| 커버리지 80% 기준 | Kotlin 은 커버리지 도구가 없다. 규칙마다 테스트가 있는지로 대신한다 (NFR-01-A1) |
| git 명령 금지 | 이 작업은 커밋으로 진행한다 (사용자 승인 사항) |

### TW-1 시그니처 뼈대를 먼저

- **이유**: 테스트가 가리킬 타입이 없으면 컴파일이 안 되어 실행 자체가 불가능하다. 스킬은 테스트 쪽의 이름 오류로 인한 실패를 RED 로 인정하지 않는다
- **패턴**: RED 전에 Application Design (`component-methods.md`) 의 시그니처대로 뼈대만 만든다: `CommandResult`, 협력 인터페이스 4개, `PlaybackCommandRouter` (모든 호출에 `NotImplemented` 를 돌려줌), 채널 응답 변환 함수 (아무 일도 하지 않음). 뼈대에는 규칙이 들어가지 않는다
- **결과**: 테스트는 컴파일되고, 기대값 불일치로 실패한다 (RED 인정). "모르는 메서드는 미구현" (CR-03) 처럼 뼈대에서 이미 통과하는 테스트는 "보호" 로 표시한다

### TW-2 RED: 구현을 읽지 않은 하위 에이전트가 테스트 작성

- **읽는 것**: `business-rules.md` (CR · PC 규칙, 메서드 표, 오류 표), `business-logic-model.md` (속성 P-CR-1 ~ 6), `domain-entities.md`, `nfr-requirements.md`, 이 문서, `component-methods.md` 의 시그니처, 뼈대 파일, 기존 `DashManifestTest.kt` (작성 형식), Code Generation 계획
- **읽지 않는 것**: `PlaybackCore.kt`, `TidalPlayerManager.kt`, `TidalAuthManager.kt`, `TidalStreamProxyServer.kt` 의 본문
- **쓰는 것**: router 용 fake 4개, router 용 생성기, `PlaybackCommandRouterTest.kt`, 채널 응답 변환 테스트
- **문서에 없는 것은 지어내지 않고 질문으로 돌려보낸다**

### TW-3 테스트 경계 표 승인 (사람 관문 1)

- **패턴**: 테스트를 쓰기 전에 표를 만들어 승인받는다. 열: 규칙 ID · 경계 (호출하는 공개 함수) · 입력 · 기대값 · 테스트 파일
- **경계는 공개 인터페이스만**: `PlaybackCommandRouter.handle`, 채널 응답 변환 함수. 내부 함수를 직접 부르지 않는다

### TW-4 RED 판정 (사람 관문 2)

- **패턴**: 테스트를 실행해 실패 사유 표를 만든다. 열: 테스트 · 결과 · 실패 종류 · RED 인정 여부
- **인정**: 기대값 비교 실패. **불인정**: 테스트 쪽의 컴파일 오류 · 이름 오류 · fake 오류 (테스트를 고쳐 다시 실행). **처음부터 통과**: 보호용이면 "보호" 로 표시, 아니면 기대값을 다시 확인
- "RED 확인" 을 받기 전에는 고정하지 않는다

### TW-5 커밋으로 고정

- **패턴**: RED 판정을 받은 테스트 파일과 fake · 생성기를 한 커밋으로 남기고 그 해시를 기록한다. 이후 `git diff --exit-code <해시> -- <테스트 파일들>` 이 0 이면 테스트가 바뀌지 않은 것이다
- **고정 뒤 테스트를 고쳐야 하면**: 구현 단계에서 고치지 않는다. 멈추고 보고한 뒤, RED 단계로 돌아가 고치고 다시 판정받아 새 커밋으로 고정한다

### TW-6 GREEN: 테스트를 고치지 않고 구현

- **패턴**: 실패 테스트를 통과시킬 만큼만 `PlaybackCommandRouter` 와 변환 함수를 구현한다. 계획에 적힌 파일만 바꾼다
- **금지**: 테스트 수정 · 삭제 · 건너뛰기, 테스트 입력일 때만 맞는 값을 돌려주는 구현, 테스트 추가 (부족하면 보고)
- **끝 확인**: 전체 Kotlin 테스트 통과, TW-5 의 비교가 0

### TW-7 REFACTOR: `PlaybackCore` 를 router 위임으로

- **패턴**: GREEN 상태에서 `PlaybackCore.onMethodCall` 을 router 호출로 바꾸고 협력 인터페이스의 운영 구현을 연결한다 (4절). 테스트는 바꾸지 않는다
- **끝 확인**: Kotlin 테스트 통과, TW-5 의 비교가 0, 앱 빌드 성공

### TW-8 프록시는 보호 테스트

- **패턴**: 이미 있는 코드이므로 테스트가 처음부터 통과하는 것이 정상이다. unit 1 처럼 운영 코드를 일부러 틀리게 바꿔 테스트가 실패하는지 확인하고 되돌린다 (변형 확인)
- **작성 주체**: 이 세션 (프록시 코드를 이미 읽었다). 규칙 문서 (`business-rules.md` 3절) 의 기대값을 그대로 쓴다

### TW-9 테스트 안티패턴 점검

스킬의 `test-antipatterns.md` 를 Kotlin 에 맞춰 적용한다.

| 안티패턴 | 이 unit 에서 지킬 것 |
| --- | --- |
| 동어반복 | 기대값은 규칙 문서의 값을 그대로 적는다 (`mapOf("status" to "playing", "trackId" to "101")`). 구현과 같은 식으로 계산하지 않는다 |
| 구현 결합 | router 의 내부 함수를 부르거나 내부 상태를 들여다보지 않는다. 프록시는 등록부를 직접 보지 않고 HTTP 응답으로 판정한다 |
| Change detector | 상수 값만 다시 확인하는 테스트를 쓰지 않는다 (예: `PROXY_PORT == 8765`). 규칙이 드러나는 동작을 본다 |
| Mock 단언 | fake 가 불렸는지만 보지 않는다. 결과 (`CommandResult`) 와 fake 가 받은 인자를 함께 본다 |

## 2. 결정성 패턴

### KD-1 임시 포트

- **패턴**: 프록시는 `TidalStreamProxyServer("127.0.0.1", port = 0)` 으로 만들고 시작한 뒤 실제로 열린 포트를 쓴다. 가짜 CDN 도 임시 포트로 시작한다. 테스트에 포트 번호를 적지 않는다 (NFR-03-A2)

### KD-2 서버 수명

- **패턴**: 프록시와 가짜 CDN 을 함께 띄우고 닫는 묶음 (`ProxyFixture`) 을 둔다. `@Before` 에서 만들고 `@After` 에서 닫는다. 속성 테스트처럼 한 테스트 안에서 여러 번 필요하면 `use { }` 로 감싼다. 서버 스레드는 데몬으로 띄워 테스트 프로세스가 끝나지 않는 일을 막는다 (NFR-03-A6, A7)

### KD-3 짧은 타임아웃

- **패턴**: 프록시가 CDN 에 쓰는 클라이언트와 테스트가 프록시에 쓰는 클라이언트 모두 타임아웃 2초로 만든다. 프록시 생성자의 `httpClient` 매개변수로 넣는다 (운영 기본값은 그대로)

### KD-4 연결 실패 만들기

- **패턴**: 가짜 CDN 을 하나 더 띄워 주소를 받은 뒤 바로 닫는다. 그 주소는 닫힌 포트라 연결이 즉시 거부된다 (PX-33). 기다리는 코드가 없다 (NFR-03-A3)

### KD-5 실제 대기 금지

- **패턴**: `Thread.sleep` 을 쓰지 않는다. 응답을 다 읽은 뒤에 가짜 CDN 의 기록을 확인한다 (요청 → 응답 완료 → 기록 확인 순서라 기다릴 것이 없다)

## 3. 검증 · 속성 테스트 패턴

### KV-1 결과 타입 단언

- **패턴**: `CommandResult` 는 값으로 비교한다. `assertEquals(CommandResult.Success(mapOf("status" to "paused")), result)`. 오류는 코드와 메시지를 함께 본다

### KV-2 fake 는 호출을 문자열로 기록

- **패턴**: fake 는 받은 호출을 `"playTrack(101)"` 같은 문자열로 순서대로 남긴다. 테스트는 결과와 호출 기록을 둘 다 단언한다. 호출이 없어야 하는 경우는 빈 목록임을 확인한다

### KV-3 HTTP 응답 단언

- **패턴**: 프록시 응답은 상태 코드, 필요한 헤더 (`Content-Type`, `Content-Length`, `Accept-Ranges`, `Content-Range`), 본문 바이트를 본다. 헤더가 없어야 하는 규칙 (PX-17, PX-25) 은 없음을 확인한다. 가짜 CDN 이 받은 요청 (메서드, 경로, `Range`) 도 함께 본다

### KV-4 규칙 ID 표기

- **패턴**: 테스트 이름은 역따옴표 함수 이름으로, 규칙 ID 를 맨 앞에 적는다. JVM 메서드 이름에는 대괄호를 쓸 수 없어 unit 1 의 `[PB-01]` 대신 `CR-03` 처럼 대괄호 없이 적는다

```kotlin
@Test
fun `CR-03 표에 없는 메서드는 미구현이고 협력 객체를 부르지 않는다`() { ... }
```

- router 테스트 (TDD 대상) 는 테스트 하나에 규칙 하나만 담는다. 메서드 표처럼 한 규칙이 여러 입력을 갖는 경우는 한 테스트 안에서 표를 돌린다

### KP-1 생성기와 설정을 한곳에

- **패턴**: `domain-entities.md` 4절의 생성기를 한 파일에 `Arb` 로 만든다. seed 와 실행 횟수는 도우미 함수 하나가 `PropTestConfig` 로 만들어 준다: seed 는 환경 변수 `PBT_SEED` 가 정수면 그 값, 없으면 20261117. 속성마다 실행 횟수를 인자로 넘긴다 (기본값 1000회를 쓰지 않는다, NFR-04-A12)

### KP-2 `runBlocking` 으로 감싸기

- **패턴**: `checkAll` 은 `suspend` 함수라 JUnit 4 테스트 메서드에서 `runBlocking { }` 으로 감싼다. 감싸는 코드는 도우미로 한 번만 쓴다

### KP-3 실행 횟수

| 속성 | 실행 횟수 | 이유 |
| --- | --- | --- |
| P-CR-1 ~ P-CR-6 (router) | 100 | 소켓을 쓰지 않아 빠르다 |
| P-PX-1, P-PX-2 (등록 · 확장자) | 100 | HTTP 요청이 없다 |
| P-PX-4, P-PX-5 (접근 제어, Range) | 50 | 예시마다 HTTP 요청 1 ~ 2회 |
| P-PX-3 (등록부 모델), P-PX-6 (내용 보존) | 25 | 예시마다 HTTP 요청이 여러 번이거나 본문이 크다 |

실행 시간 합계가 30초 (NFR-03-A5) 를 넘으면 아래 줄부터 줄이고, 줄인 값과 이유를 Code Generation 요약에 적는다.

### KP-4 등록부 모델 비교 (P-PX-3)

- **패턴**: 모델은 "최근에 등록한 3개의 주소" 목록이다. 등록 하나마다 지금까지 받은 모든 주소에 요청을 보내, 모델에 있는 주소는 404 가 아니고 모델에서 밀려난 주소는 404 인지 비교한다. 등록 0회 (아무 주소도 없음) 도 포함한다
- **CDN 을 거치지 않게**: 등록할 때 `allowedHost` 를 요청하는 쪽과 다른 주소로 두면, 등록된 주소는 403 (접근 제어에서 멈춤), 밀려난 주소는 404 가 된다. CDN 요청 없이 등록 여부만 구분된다

### KP-5 축소를 끄지 않기

- **패턴**: 생성기는 Kotest 의 기본 `Arb` 와 조합 함수로 만든다. 축소 관련 설정을 바꾸지 않는다. 실패 출력에 seed 와 축소된 입력이 나오는지는 일부러 틀린 속성으로 한 번 확인한다

## 4. 재구성 패턴

### KR-1 옮기는 순서

1. 뼈대 (TW-1): 새 파일만 추가. 기존 동작에 영향 없음
2. router 와 변환 함수 구현 (TW-6): 새 파일만 변경. `PlaybackCore` 는 아직 쓰지 않음
3. `TidalPlayerManager` 에 `PlayerControls` 구현 선언: `: PlayerControls` 와 `override` 만 추가
4. `PlaybackCore`: 협력 인터페이스의 운영 구현을 연결하고 `onMethodCall` 을 router 호출로 교체 (TW-7)
5. `TidalStreamProxyServer`: 생성자 매개변수 추가 (프록시 테스트 전에 필요하므로 프록시 작업의 첫 단계)

각 번호가 커밋 하나다. 문제가 생기면 그 커밋만 되돌린다.

### KR-2 고쳐 쓰지 않고 옮기기

- **패턴**: `PlaybackCore` 의 기존 private 함수 (`phoneVolumePercent`, `setPhoneVolumePercent`, `requestNotificationPermission`, `setWifiLock`, `ensureProxyServer`, `requestTokenFromDart`, `requestStreamFromDart`) 는 본문을 건드리지 않는다. 운영 구현은 이 함수들을 부르기만 한다. `initTidalAuth` 분기의 본문은 `AuthControls.initialize` 구현으로 그대로 옮긴다 (NFR-06-A3)

### KR-3 채널 응답 변환을 작은 함수로

- **패턴**: "채널 인자를 맵으로" 와 "`CommandResult` 를 채널 응답으로" 를 Flutter 타입에만 의존하는 함수 두 개로 둔다. `PlaybackCore.onMethodCall` 은 이 두 함수와 router 호출만 남는다. 두 함수는 JVM 단위 테스트로 검증한다 (PC-01, PC-02)

### KR-4 프록시 생성자

- **패턴**: `port` 와 `httpClient` 를 기본값이 있는 매개변수로 추가한다. 돌려주는 주소의 포트는 서버가 실제로 연 포트를 쓴다 (운영에서는 8765 로 같다). `PlaybackCore.ensureProxyServer` 의 `TidalStreamProxyServer(wifiIp)` 호출은 그대로 둔다 (NFR-06-A4)

### KR-5 동작 동일성 확인

| 확인 | 수단 |
| --- | --- |
| 메서드 16개의 인자 · 반환 · 오류 | router 테스트 (CR-01 ~ CR-13) |
| 채널 응답으로의 변환 | 변환 함수 테스트 (PC-01, PC-02) |
| 채널 이름 · 남는 함수의 본문 | `git diff` 검토 |
| 컴파일 · 연결 | `flutter build apk --debug` |
| 실기기 동작 | 확인하지 못함. 요약에 적는다 (NFR-06-A6) |

## 5. NFR Requirements 항목별 대응 (ND-1)

| 요구 | 패턴 · 구성 요소 |
| --- | --- |
| NFR-01-A1 (CR · PX 규칙마다 테스트) | KV-4, TW-3 (경계 표가 규칙을 빠짐없이 나열), TW-8 |
| NFR-01-A2 (PC-01 ~ 03 테스트) | KR-3 |
| NFR-01-A3 (모든 테스트가 규칙 · 속성 검증) | TW-9, KV-4 |
| NFR-02-A1 (Kotlin 테스트 통과) | TW-6, TW-7 의 끝 확인 |
| NFR-02-A2 (기존 `DashManifestTest` 유지) | KR-1 (기존 테스트 파일을 건드리지 않음) |
| NFR-02-A3 (`tool/check.sh` 전체) | Code Generation 의 검증 단계. `JAVA_HOME` 지정 |
| NFR-02-A4 (Dart 점검 유지) | 이 unit 은 Dart 파일을 바꾸지 않음 |
| NFR-03-A1 (루프백만) | KD-1, KD-2 |
| NFR-03-A2 (고정 포트 없음) | KD-1, KR-4 |
| NFR-03-A3 (실제 대기 없음) | KD-3, KD-4, KD-5 |
| NFR-03-A4 (10회 같은 결과) | KD-2, KP-1 (고정 seed) |
| NFR-03-A5 (30초 이하) | KP-3, KD-3 |
| NFR-03-A6 (테스트 간 격리) | KD-2 |
| NFR-03-A7 (스레드 · 포트가 남지 않음) | KD-2 |
| NFR-04-A1 (속성 12개) | KV-4, TW-2 (router 속성), TW-8 (프록시 속성) |
| NFR-04-A2 ~ A5 (왕복 · 불변 · 결정성 · 오라클) | KP-1 |
| NFR-04-A6 (상태 기반, 모델) | KP-4 |
| NFR-04-A7 (생성기 한 파일) | KP-1 |
| NFR-04-A8 (축소) | KP-5 |
| NFR-04-A9 (고정 seed, 환경 변수, 실패 출력) | KP-1, KP-5 |
| NFR-04-A10 (일반 실행에 포함) | 같은 테스트 클래스 안에 속성을 둠. 제외 설정 없음 |
| NFR-04-A11 (예시 테스트와 함께) | TW-3 (규칙마다 예시 테스트), KV-4 |
| NFR-04-A12 (실행 횟수 명시) | KP-1, KP-3 |
| NFR-05-A1 (테스트와 같은 패키지) | `logical-components.md` |
| NFR-05-A2 (규칙 ID, 한국어 이름) | KV-4 |
| NFR-05-A3 (한국어 KDoc) | KR-1 의 새 파일 |
| NFR-06-A1 (빌드 성공) | TW-7, KR-5 |
| NFR-06-A2 (채널 계약 불변) | KR-5, router 테스트 |
| NFR-06-A3 (남는 함수 본문 유지) | KR-2 |
| NFR-06-A4 (프록시 기본값 = 지금 동작) | KR-4 |
| NFR-06-A5 (테스트 의존성이 앱에 안 들어감) | `tech-stack-decisions.md` A1, A2 (`testImplementation`) |
| NFR-06-A6 (확인하지 못한 부분 기록) | KR-5 |
