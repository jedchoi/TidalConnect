# NFR 설계 패턴 (NFR Design Patterns) - dart-playback-tests

`nfr-requirements.md` 의 테스트 품질 요구를 테스트 코드의 패턴으로 옮긴다. 패턴 ID 는 Code Generation 계획에서 참조한다. 구성 요소 (파일) 는 `logical-components.md` 에 있다.

## 1. 결정성 패턴

### DT-1 가짜 시간 안에서 실행

- **대상**: `DlnaBackend` 테스트 전부 (1초 폴링), 시간이 관여하는 속성 테스트
- **패턴**: 테스트 본문을 `fakeAsync((async) { ... })` 안에 둔다. 비동기 호출은 `await` 하지 않고 시작한 뒤, 결과 · 예외를 변수에 받아 두고 `async.flushMicrotasks()` 로 진행시킨다. 폴링은 `async.elapse(const Duration(seconds: 1))` 로 한 차례씩 돌린다
- **이유**: `fakeAsync` 본문은 동기 함수다. 그 안에서 `await` 하면 가짜 시간이 진행되지 않아 테스트가 멈춘다
- **먼저 확인할 것**: 가짜 MethodChannel 응답 (`FakeNativeChannel`) 이 `fakeAsync` 안에서 `flushMicrotasks()` 로 완료되는지를 `DlnaBackend` 의 첫 테스트로 확인한다. 안 되면 Application Design 계획 Q3 을 B (폴링 간격 주입) 로 바꾸는 변경을 요청한다

### DT-2 채널 가로채기의 설치와 해제

- **패턴**: `setUp` 에서 `FakeNativeChannel().install()`, 같은 자리에서 `addTearDown(channel.uninstall)` 을 등록한다. 테스트 파일 첫머리에서 `TestWidgetsFlutterBinding.ensureInitialized()` 를 호출한다
- **이유**: 해제를 빠뜨리면 다음 테스트가 이전 테스트의 응답 설정을 물려받는다 (NFR-03-D5)

### DT-3 테스트 간 격리

- **패턴**: 테스트마다 대상 객체와 fake 를 새로 만든다. `DlnaManager.instance` (운영 싱글톤) 는 쓰지 않고 항상 `DlnaManager.forTesting(...)`. `setUp` 에서 `SharedPreferences.setMockInitialValues({})` 로 저장소를 비운다. 백엔드는 `addTearDown(backend.dispose)` 로 정리한다
- **남는 공유 상태**: `TidalSdkNativeBridge` 의 정적 핸들러 등록 여부와 refresher. `DlnaBackend` 를 만들 때마다 refresher 가 덮어써지므로 테스트 결과에 영향이 없다. 주소 재발급 테스트 (DB-48, DB-49) 는 같은 테스트 안에서 백엔드를 만들고 바로 호출한다

### DT-4 실제 대기 금지

- **패턴**: fake 는 기본적으로 즉시 응답한다. `Future.delayed`, `sleep`, 실제 `Timer` 대기를 테스트에 쓰지 않는다

### DT-5 응답 시점을 테스트가 정하기

- **대상**: 취소 지점 (DB-14), 명령 직렬화 (DB-15, DB-42), 늦게 도착한 폴링 응답 (DB-29), 겹친 폴링 (DB-30), 탐색 중 재호출 (DM-22)
- **패턴**: fake 가 `Completer` 를 돌려주게 설정해 응답을 붙잡아 두고, 테스트가 중간 상태를 확인한 뒤 `complete` 한다. `FakeSoapClient`, `FakeApiClient`, `FakeSsdpDiscoveryService`, `FakeNativeChannel` 에 "다음 응답을 붙잡기" 기능을 둔다 (기본은 즉시 응답)

## 2. 검증 패턴

### VF-1 이벤트 기록과 문자열 표현

- **패턴**: `backend.events.listen(events.add)` 로 이벤트를 목록에 모은다. `BackendEvent` 를 한 줄 문자열로 바꾸는 함수 (`describeEvent`) 를 두어 순서 전체를 한 번에 비교한다

```text
BackendStateChanged(playing: true, buffering: true)  ->  state(playing,buffering)
BackendPositionChanged(12초, duration: 180초)         ->  position(12/180)
BackendTrackStarted('123', ...)                      ->  started(123)
BackendTrackEnded('123')                             ->  ended(123)
BackendError('DLNA_UNREACHABLE', ...)                ->  error(DLNA_UNREACHABLE)
```

- **이유**: `BackendEvent` 하위 클래스에 `==` 가 없어 객체끼리 비교할 수 없다. 문자열 목록은 실패 메시지가 읽기 쉽고, 상태 기반 속성의 모델 출력과도 같은 형식으로 비교할 수 있다. `StreamQuality` 같은 세부 필드는 필요한 테스트에서 `isA<...>().having(...)` 으로 따로 본다

### VF-2 호출 기록과 순서 단언

- **패턴**: fake 는 받은 호출을 순서대로 목록에 남긴다 (`FakeNativeChannel.calls`, `FakeSoapClient.calls`). 순서가 규칙인 경우 (DM-07, DB-07) 는 목록 전체를 기대 순서와 비교하고, 호출이 없어야 하는 경우 (DM-01, DB-02) 는 빈 목록임을 확인한다

### VF-3 예외 단언

- **패턴**: `throwsA(isA<PlaybackException>().having((e) => e.code, 'code', 'PHONE_PLAY_FAILED'))`. 메시지 문구는 비교하지 않는다. 예외: 기기 이름이 들어가야 하는 DB-10 은 `contains(기기 이름)` 으로 확인
- **`fakeAsync` 안에서**: 예외를 `catchError` 로 변수에 받아 `flushMicrotasks()` 뒤에 단언한다 (DT-1)

### VF-4 규칙 ID 표기

- **패턴**: 테스트 이름 앞에 규칙 ID 를 대괄호로 적는다. 속성은 속성 ID 를 적는다

```dart
test('[PB-02] 재생 명령이 실패하면 PHONE_PLAY_FAILED 예외를 던진다', ...);
property('[P-DM-1] 초를 시간 문자열로 보냈다가 다시 읽으면 같은 초가 된다', ...);
```

- **이유**: 규칙과 테스트를 서로 찾을 수 있다 (NFR-05-D4). 한 테스트가 여러 규칙을 검증하면 `[DB-18, DB-19]` 처럼 함께 적는다

### VF-5 묶음 구성

- **패턴**: 파일 하나가 컴포넌트 하나. `group` 은 `business-rules.md` 의 소절 (명령 → 채널 호출, 이벤트 변환, 폴링, 갭리스 등) 을 따른다. 속성 테스트는 같은 파일의 `group('속성', ...)` 에 둔다

## 3. 속성 테스트 패턴

### PT-1 도메인 생성기를 한곳에

- **패턴**: `domain-entities.md` 3절의 생성기를 `test/helpers/` 의 한 파일에 `kiri_check` 의 `Arbitrary` 조합으로 만든다. 테스트 파일은 가져다 쓰기만 한다
- **경계 값**: 범위의 양끝 (초 0 과 359999, 볼륨 −1000 · 0 · 100 · 1000, 빈 곡 목록, 빈 문자열 제목) 이 나오도록 생성기를 구성한다 (PBT-07)

### PT-2 seed 를 한곳에서 설정

- **패턴**: `test/helpers/` 의 설정 함수가 `KiriCheck.seed` 를 정한다. 환경 변수 `PBT_SEED` 가 정수면 그 값, 없으면 고정값. PBT 가 있는 테스트 파일은 `main()` 첫머리에서 이 함수를 부른다
- **재현**: 실패하면 `kiri_check` 가 `Falsifying example: ... (seed N)` 을 출력한다. `PBT_SEED=N flutter test <파일>` 로 다시 실행한다
- **탐색**: `PBT_SEED=$RANDOM flutter test` 처럼 seed 를 바꿔 직접 실행한다. CI 와 `tool/check.sh` 는 환경 변수를 주지 않아 고정값을 쓴다

### PT-3 모델과 한 단계씩 비교 (상태 기반)

- **대상**: P-PB-5 (pending seek), P-DB-1 · P-DB-2 (폴링)
- **패턴**: 테스트 코드에 순수 Dart 모델을 둔다. 모델은 `business-logic-model.md` 의 상태 기계를 그대로 옮긴 것으로, 입력 하나를 받아 "나와야 할 이벤트 문자열 목록" (VF-1 형식) 과 "나와야 할 호출" 을 돌려준다. 생성기가 만든 입력 목록을 하나씩 실제 객체와 모델 양쪽에 넣고, 매 단계 뒤에 결과를 비교한다
- **빈 순서**: 생성기의 길이 범위를 0 부터로 해 입력이 없는 경우도 포함한다 (PBT-06). `domain-entities.md` 의 "1 ~ 30개" 는 "0 ~ 30개" 로 적용한다
- **모델의 독립성**: 모델은 운영 코드를 import 하지 않고, 운영 코드의 구조를 따라 쓰지 않는다. 상태 기계 도식에서 직접 작성한다

### PT-4 예시마다 새 객체

- **패턴**: `forAll` 본문 안에서 대상 객체와 fake 를 새로 만들고 끝에서 정리한다. 예시끼리 상태가 섞이면 축소 결과를 믿을 수 없다

### PT-5 속성 본문은 동기로

- **패턴**: 가짜 시간이 필요한 속성은 `forAll` 본문 안에서 `fakeAsync(...)` 를 호출한다. 본문 자체는 `async` 로 만들지 않는다
- **이유**: `kiri_check` 의 비동기 진행과 `fakeAsync` 를 섞지 않는다

### PT-6 실행 횟수와 시간 예산

- **패턴**: 기본 100회. 설정 함수 (PT-2) 에서 한 번에 정한다. 전체 실행 시간 증가가 30초를 넘으면 PT-3 대상 속성부터 `forAll(..., maxExamples: 50)` 으로 줄이고 그 사실을 Code Generation 요약에 적는다

### PT-7 축소를 끄지 않기

- **패턴**: `forAll` 의 축소 관련 설정을 건드리지 않는다. 사용자 정의 생성기는 `kiri_check` 의 조합 함수로 만들어 축소가 따라오게 한다 (직접 난수로 값을 만들지 않는다)

## 4. 조립 패턴

### AS-1 기본 전제를 만드는 함수

- **패턴**: 반복되는 준비를 `test/helpers/` 의 함수 · 묶음 객체로 둔다
  - 곡, 원격 기기, 스트림 정보 (단일 파일 / DASH) 를 만드는 함수: 인자를 생략하면 가짜 기본값
  - 원격 스피커가 선택된 `DlnaManager` 를 만드는 함수
  - `DlnaBackend` 테스트 묶음: 채널, SOAP, 인증, API, `DlnaManager`, 백엔드, 이벤트 목록을 한 객체로
- **기본값이 곧 성공 조건**: 묶음의 기본 상태는 `business-rules.md` 3절의 전제 (원격 스피커 선택, 토큰 있음, 스트림 정보 있음, SOAP 성공) 다. 각 테스트는 규칙이 요구하는 조건 하나만 바꾼다

### AS-2 가짜 값 규칙

- **패턴**: 기기 주소는 `http://192.0.2.10:1400/...` (문서용 예약 대역), CDN 주소는 `https://cdn.example.test/...`, 토큰은 `token-1`, 프록시 주소는 `http://192.0.2.1:8765/audio/<16자>.flac`. 조립 함수의 기본값으로 넣어 테스트가 주소를 직접 적지 않게 한다 (SEC-D1, SEC-D2)

### AS-3 기존 fake 는 기본 동작 유지

- **패턴**: 기존 fake 에 더하는 필드는 기본값이 지금 동작이다 (`FakeSsdpDiscoveryService.devices` 기본은 폰 스피커만, `FakeAuthRepository.validUserToken` 기본은 null → 지금의 `getValidUserToken` 결과와 같은지 Code Generation 에서 확인). `FakeBackend` 는 파일만 옮기고 기존 필드를 그대로 둔다 (NFR-05-D2)

## 5. 복원력

### RS-1 복원력 테스트 방식 (RESILIENCY-14, 계획 Q1=B)

이 앱에는 서버가 없어 DR 전략이 N/A 다 (요구사항 후속 Q4=E). 따라서 DR 훈련 시나리오는 없고, 기기 안의 복구 동작을 다음 두 층으로 검증한다.

**(1) 자동 테스트 (이번 작업)**

| 장애 상황 | 기대 동작 | 규칙 |
| --- | --- | --- |
| 스피커가 응답하지 않음 | 3회 연속 무응답 뒤 폴링 중지, 재생 상태 정지, `DLNA_UNREACHABLE` 알림 | DB-27, DB-28 |
| Wi-Fi 없음 (프록시 주소를 못 받음) | `PROXY_FAILED` 예외, 스피커에 명령을 보내지 않음 | DB-06 |
| 선택한 스피커가 탐색에서 사라짐 | 재생 중이 아니면 폰 스피커로 전환하고 안내, 다시 보이면 자동 선택 | DM-26, DM-28, DM-29 |
| SOAP 명령 실패 · 예외 | false · null 반환, 예외가 밖으로 나오지 않음 | DM-06, DM-08, DM-10 |
| CDN 서명 주소 만료 | 네이티브의 재발급 요청에 새 스트림 정보 반환 | DB-48, DB-49 |
| 스피커 쪽에서 직접 정지 | 재생 상태 정지, 다음 곡으로 넘어가지 않음 | DB-25 |

**(2) 실기기 장애 상황 점검표 (제안, 선택 항목)**

`docs/failure-scenarios.md` 를 새로 만든다 (이 unit 의 Code Generation 에서 작성).

| # | 해 볼 것 | 기대 동작 |
| --- | --- | --- |
| 1 | 스피커 재생 중 스피커 전원을 끈다 | 약 6 ~ 7초 안에 "스피커가 응답하지 않습니다" 안내, 재생 표시가 정지로 바뀜 |
| 2 | 스피커 재생 중 폰의 Wi-Fi 를 끈다 | 1번과 같은 안내. 그 상태에서 다른 곡을 누르면 Wi-Fi 확인 안내 |
| 3 | 재생하지 않는 상태에서 선택한 스피커를 끄고 기기 탐색을 한다. 다시 켜고 탐색한다 | 폰 스피커로 바뀌고 안내 문구가 나옴. 다시 탐색하면 그 스피커가 자동 선택됨 |
| 4 | 스피커 재생을 오래 일시정지했다가 재개한다 (서명 주소의 만료 시간은 확인하지 못했다. 1시간 이상 두고 해 본다) | 재생이 이어짐 (주소가 만료되었으면 새 주소로 다시 받아 재생) |
| 5 | 스피커의 버튼이나 리모컨으로 재생을 멈춘다 | 앱의 재생 표시가 정지로 바뀌고 다음 곡으로 넘어가지 않음 |
| 6 | 화면을 끈 채 스피커 재생을 30분 둔다 | 끊기지 않음 |
| 7 | 재생 중 앱을 최근 앱 목록에서 밀어낸다 | 재생이 멈춤 |

- **일정**: 정해진 주기 없음. 새 렌더러를 시험할 때, 또는 재생 경로 (`lib/features/player/data/`, `lib/features/dlna/data/`, Kotlin 프록시) 를 고친 뒤에 해 본다
- **결과 추적**: `docs/dlna-compat.md` 의 해당 렌더러 행 비고에 적는다. 기대와 다르면 RS-2 의 절차로 넘어간다
- **이번 작업의 완료 기준 아님**: 실기기 확인은 범위 밖이다 (NFR-02). 점검표는 문서로만 만든다

### RS-2 가벼운 장애 대응 · 오류 교정 절차 (RESILIENCY-15, 계획 Q2=A)

`docs/incidents/README.md` 에 절차와 양식을 둔다 (이 unit 의 Code Generation 에서 작성).

**절차**

1. **기록**: 증상, 기기 · 렌더러 · 앱 버전, 재현 순서, 설정 탭 디버그 로그의 관련 줄을 적는다
2. **재현**: 가능하면 실패하는 자동 테스트로 재현한다. 실기기에서만 재현되면 그 사실과 재현 순서를 남긴다
3. **수정**: 수정은 별도 커밋 (`fix: ...`) 으로 하고, 2의 테스트가 통과하게 한다
4. **문서**: `docs/incidents/YYYY-MM-DD-<짧은 이름>.md` 를 양식대로 쓴다
5. **렌더러 문제면**: `docs/dlna-compat.md` 의 해당 행을 갱신한다

**양식 (문제 하나에 파일 하나)**

```markdown
# <한 줄 제목>

- **발견일**: YYYY-MM-DD
- **영향**: <무엇이 안 되었나, 어느 기기 · 렌더러에서>
- **증상**: <보인 현상, 재현 순서>
- **원인**: <왜 그랬나>
- **수정**: <커밋 해시, 바꾼 내용 한두 줄>
- **추가한 테스트**: <테스트 파일과 이름, 없으면 이유>
- **재발 방지**: - [ ] <남은 할 일이 있으면>
```

**이 절차와 다른 것의 관계**

- 감지: 모니터링 · 알림이 없다 (운영 서비스 없음). 문제는 사용자가 직접 보거나 앱 안의 오류 안내, 디버그 로그로 알게 된다
- 이번 작업의 FR-08 (발견 버그 수정) 도 이 절차를 따른다: 실패 테스트 → 별도 커밋 → 문서
- 개선 조치 추적: 양식의 "재발 방지" 체크박스

## 6. NFR Requirements 항목별 대응 (ND-1)

| 요구 | 패턴 · 구성 요소 |
| --- | --- |
| NFR-01-D1 ~ D4 (4개 파일 80%) | VF-5 (규칙마다 테스트), AS-1 (조건 하나씩 바꾸는 테스트를 싸게 만듦). 측정은 `tech-stack-decisions.md` D7 |
| NFR-02-D1 (`tool/check.sh --skip-android`) | 모든 패턴의 결과. 포맷 줄 길이 120 준수 |
| NFR-02-D2 (기존 테스트 유지) | AS-3 |
| NFR-02-D3 (analyze info 0) | `fake_async` · `kiri_check` 를 `dev_dependencies` 에 선언 (`tech-stack-decisions.md` D1, D2) |
| NFR-03-D1 (외부 접근 없음) | DT-2, AS-1, fake 구성 요소 전부 |
| NFR-03-D2 (실제 대기 없음) | DT-1, DT-4 |
| NFR-03-D3 (10회 같은 결과) | DT-3, PT-2 (고정 seed), PT-4 |
| NFR-03-D4 (30초 이하) | DT-4, PT-6 |
| NFR-03-D5 (순서 무관) | DT-2, DT-3 |
| NFR-04-D1 (속성 18개) | VF-4 (속성 ID 표기), VF-5 |
| NFR-04-D2 ~ D5 (왕복 · 불변 · 멱등 · 오라클) | PT-1, PT-4 |
| NFR-04-D6 (상태 기반, 모델) | PT-3, PT-5 |
| NFR-04-D7 (생성기) | PT-1 |
| NFR-04-D8 (축소) | PT-7 |
| NFR-04-D9 (고정 seed, 환경 변수) | PT-2 |
| NFR-04-D10 (일반 실행에 포함) | VF-5 (같은 파일의 `group`), 태그 · skip 없음 |
| NFR-04-D11 (예시 테스트와 함께) | VF-5 |
| NFR-05-D1 (`test/helpers/`) | `logical-components.md` |
| NFR-05-D2 (기존 fake 유지) | AS-3 |
| NFR-05-D3 (한국어 테스트 이름) | VF-4 |
| NFR-05-D4 (규칙 ID) | VF-4, VF-5 |
| NFR-05-D5 (운영 코드 변경 1곳) | DT-1 의 대안 조건, FR-08 절차 (RS-2) |
| SEC-D1, SEC-D2 (가짜 값) | AS-2 |
