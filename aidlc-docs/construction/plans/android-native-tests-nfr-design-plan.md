# NFR Design 계획 - android-native-tests

**이 stage 가 정하는 것**: NFR Requirements 의 요구 (결정성, 속도, 재현성, 재구성 안전성) 를 **Kotlin 테스트 코드와 재구성 작업의 패턴** 으로 옮긴다. 복원력 확장의 프로젝트 전체 항목 (RESILIENCY-14 · 15) 은 unit 1 에서 이미 다뤘으므로 이 unit 에는 없다.

## 실행 단계

- [x] 1. NFR Requirements 산출물 읽기 (`nfr-requirements.md` 의 35개 항목, `tech-stack-decisions.md` 의 결정 9개)
- [x] 2. 새로 추가된 TDD 스킬 3개 (`.claude/skills/tdd-red`, `tdd-green`, `tdd-refactor`) 와 그 도구 읽기
- [x] 3. 아래 질문에 대한 답변 수집 · 모호성 분석
- [x] 4. `aidlc-docs/construction/android-native-tests/nfr-design/nfr-design-patterns.md` 생성
  - [x] 4.1 결정성 패턴: 임시 포트, 서버 수명 관리, 짧은 타임아웃, 닫힌 포트로 연결 실패 만들기
  - [x] 4.2 검증 패턴: 결과 타입 단언, 호출 기록, HTTP 응답 단언, 규칙 ID 표기
  - [x] 4.3 속성 테스트 패턴: 생성기 구성, seed · 실행 횟수 설정, 모델 비교 (최근 3개 등록부)
  - [x] 4.4 재구성 패턴: 옮기는 순서, 동작 동일성을 지키는 방법, 채널 응답 변환의 위치
  - [x] 4.5 작업 방식 패턴: Question 1 의 답에 따른 테스트 작성 · 구현 순서
  - [x] 4.6 NFR Requirements 항목별 대응 표 (ND-1)
- [x] 5. `aidlc-docs/construction/android-native-tests/nfr-design/logical-components.md` 생성: 운영 코드의 새 구성 요소, 테스트 지원 구성 요소 (파일 · 책임 · 관계), 인프라 구성 요소 해당 없음 근거
- [x] 6. 검증: `nfr-requirements.md` 의 모든 항목에 대응 패턴 또는 구성 요소가 있는지

## 질문

`[Answer]:` 뒤에 선택지 문자를 적어 주세요.

## Question 1 (작업 방식)
이 unit 의 Code Generation 을 어떤 순서로 진행할까요?

배경: 지난 단계 사이에 `.claude/skills/` 에 TDD 스킬 3개가 추가되었습니다 (`tdd-red`: 설계 문서만 보고 실패하는 테스트 작성 → 사람 판정 → 테스트 고정, `tdd-green`: 고정된 테스트를 고치지 않고 최소 구현, `tdd-refactor`: 동작을 바꾸지 않는 구조 정리). 읽어 보니 이 스킬들은 Python 실습 모듈에 맞춰 쓰여 있어 이 프로젝트에 그대로는 쓸 수 없습니다.

| 스킬이 전제하는 것 | 이 프로젝트 |
| --- | --- |
| `pytest`, `ruff` 로 검증 | Kotlin 은 `./gradlew :app:testDebugUnitTest` |
| `tests/` · `backend/` 폴더를 복사해 고정하는 `tdd_snapshot.py` | 그 폴더들이 없다. 스크립트는 "tests/ · backend/ 가 없습니다" 로 끝난다 |
| git 을 쓰지 않음 | 이 작업은 브랜치에 단계별로 커밋하고 있다 |
| RED 와 GREEN 을 서로 다른 세션에서, RED 는 구현 코드 본문을 읽지 않고 작성 | 이 세션은 설계 단계에서 `PlaybackCore.kt` 를 이미 읽었다 |

이 unit 에서 TDD 가 맞는 부분은 `PlaybackCommandRouter` 입니다 (아직 없는 새 코드). `TidalStreamProxyServer` 는 이미 있는 코드라 테스트가 처음부터 통과합니다 (스킬의 표현으로 "보호" 테스트).

A) TDD 흐름을 이 프로젝트에 맞게 옮겨서 router 에 적용 (권장: 스킬을 추가하신 의도에 맞고, 테스트가 구현을 따라 쓰이는 것을 막는다)
- RED: `PlaybackCore.kt` 를 읽지 않은 별도 하위 에이전트가 설계 문서 (`business-rules.md` 의 CR 규칙, 인터페이스 시그니처) 만 보고 router 테스트를 쓴다. 먼저 테스트 경계 표를 보여 드려 승인받고, 실행 결과 (실패 사유 표) 를 보여 드려 "RED 확인" 을 받는다
- 고정: 스냅샷 스크립트 대신 테스트 파일을 커밋해 고정한다. 이후 그 커밋과 비교해 테스트가 바뀌지 않았는지 확인한다
- GREEN: 고정된 테스트를 고치지 않고 router 를 구현한다. 테스트가 이상해 보이면 고치지 않고 멈춰서 보고한다
- REFACTOR: `PlaybackCore.onMethodCall` 을 router 위임으로 바꾼다 (테스트 변경 없음, 빌드 확인)
- 프록시: 기존 코드라 테스트를 쓰고 "보호" 로 표시한다. unit 1 처럼 변형 확인으로 테스트가 잘못을 잡는지 본다
- 스킬 파일 자체는 고치지 않는다. 승인 관문이 2개 늘어난다 (테스트 경계 표, RED 판정)

B) unit 1 과 같은 방식 - 규칙 문서대로 구현과 테스트를 한 흐름에서 쓰고, 변형 확인으로 테스트를 검증한다. 추가 승인 관문이 없다. TDD 스킬은 쓰지 않는다

C) TDD 스킬을 먼저 이 프로젝트용으로 고친 뒤 (명령 · 폴더 · 스냅샷 스크립트) 그대로 따른다 - 스킬 수정은 이번 작업 범위 밖이라 별도 작업이 된다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## 질문하지 않은 범주와 이유

- **복원력 패턴**: 프로젝트 전체 항목 (RESILIENCY-14 · 15) 은 unit 1 의 NFR Design 에서 정했다. 이 unit 은 기존 복원력 동작 (주소 재발급, 오류 응답) 을 테스트로 고정할 뿐 새 패턴을 넣지 않는다
- **확장성 · 성능 패턴**: 해당 없음 (`nfr-requirements.md` 3절). 테스트 실행 횟수 조정 방법은 정해져 있다 (NFR-04-A12)
- **보안 패턴**: 보안 확장을 쓰지 않는다. 테스트 서버는 루프백에만 바인딩한다
- **논리 컴포넌트 (queue, cache, circuit breaker 등)**: 인프라 구성 요소를 추가하지 않는다. 새 운영 구성 요소 (router, 인터페이스) 는 Application Design 에서 정했다
- **결정성 · 검증 · 속성 테스트 패턴의 세부**: 도구가 정해져 (`mockwebserver`, `kotest-property`, JUnit 4) 사용자 선택이 필요한 지점이 없다
