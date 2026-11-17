# Unit of Work 계획 (Unit of Work Plan)

**분해 대상**: FR-01 ~ FR-09 (User Stories 는 SKIP 했으므로 스토리 대신 FR 을 unit 에 배정한다).

**왜 unit 수가 중요한가**: unit 하나마다 CONSTRUCTION 의 승인 관문이 최대 5개 생긴다 (Functional Design, NFR Requirements, NFR Design, Code Generation 계획, Code Generation 결과). unit 을 잘게 나누면 검토 단위가 작아지지만 승인 횟수가 늘어난다.

## 분해에 쓰는 사실 (Application Design 에서)

- 언어 · 도구가 다른 세 묶음: Dart (`flutter test`, Dart PBT 프레임워크), Kotlin (`./gradlew :app:testDebugUnitTest`, Kotlin PBT 프레임워크), CI 설정 (`tool/check.sh`, `check.yml`)
- Dart 안의 의존 순서: 공용 대체 지점 (`DlnaManager.forTesting(soapClient:)`, `FakeNativeChannel`, `FakeSoapClient`, 기존 fake 확장) → `DlnaManager` · `PhoneBackend` · `DlnaBackend` · `WaveAudioHandler` 테스트
- Kotlin 은 Dart 와 독립이다. Kotlin 안에서 `PlaybackCommandRouter` 와 `TidalStreamProxyServer` 도 서로 독립이다
- CI 의 커버리지 검사는 Dart 테스트가 80% 를 넘은 뒤에 켜야 한다

## 실행 단계

### Part 1 - Planning
- [x] 1. 요구사항, Application Design 산출물 읽기
- [x] 2. 아래 질문에 대한 답변 수집 · 모호성 분석
- [x] 3. 계획 승인 받기

### Part 2 - Generation
- [x] 4. unit 정의와 책임으로 `aidlc-docs/inception/application-design/unit-of-work.md` 생성 (unit 별: 이름, 목적, 포함하는 컴포넌트 · 파일, 배정된 FR · NFR, 실행할 CONSTRUCTION stage, 완료 기준)
- [x] 5. 의존성 매트릭스로 `aidlc-docs/inception/application-design/unit-of-work-dependency.md` 생성 (unit 간 의존, 진행 순서, 공유 자원)
- [x] 6. FR 을 unit 에 매핑한 `aidlc-docs/inception/application-design/unit-of-work-story-map.md` 생성 (스토리가 없으므로 FR · NFR 기준)
- [x] 7. unit 경계와 의존성 검증 (순환 없음, 진행 순서가 의존 순서와 맞음)
- [x] 8. 모든 FR · NFR 이 unit 에 배정되었는지 확인
- [x] 9. `aidlc-docs/aidlc-state.md` 에 unit 목록과 unit 별 stage 표시 반영

(Greenfield 전용 단계인 코드 구성 전략 문서화는 해당 없음: Brownfield)

## 질문

각 질문의 `[Answer]:` 뒤에 선택지 문자를 적어 주세요.

## Question 1 (그룹화)
unit 을 몇 개로 나눌까요?

A) 3개: 언어 · 도구 기준 (권장)
- `dart-playback-tests`: Dart 대체 지점 + `DlnaManager` · `PhoneBackend` · `DlnaBackend` · `WaveAudioHandler` 테스트 (FR-01 ~ FR-04)
- `android-native-tests`: Kotlin `PlaybackCommandRouter` 추출 + `TidalStreamProxyServer` 매개변수 + 두 테스트 (FR-05, FR-06)
- `ci-quality-gate`: `CoverageGate`, `tool/check.sh`, `check.yml` (FR-09)
- 승인 관문 약 12 ~ 13개. unit 마다 PBT 프레임워크 · 테스트 도구 결정이 하나로 모인다

B) 6개: 컴포넌트 기준
- `dart-test-foundation` (대체 지점 + `DlnaManager`), `dart-backends` (`PhoneBackend`, `DlnaBackend`), `dart-audio-handler` (`WaveAudioHandler`), `android-command-router`, `android-stream-proxy`, `ci-quality-gate`
- 승인 관문 약 25개. 검토 단위는 작지만 같은 도구 결정을 unit 마다 반복한다

C) 2개: 테스트 전체 + CI
- `playback-tests` (Dart + Kotlin 전부), `ci-quality-gate`
- 승인 관문 약 8개. 한 unit 의 설계 문서가 두 언어를 함께 다뤄 커진다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 2 (의존성 · 순서)
Dart 쪽과 Kotlin 쪽은 서로 독립입니다. 어느 쪽을 먼저 진행할까요? (CI unit 은 어느 경우든 마지막)

A) Dart 먼저 - 수치 목표 (NFR-01, 80%) 가 걸려 있고, 먼저 확인할 기술 위험 (`fake_async` 와 가짜 채널 조합) 이 Dart 에 있다 (권장)

B) Kotlin 먼저 - 운영 코드 변경이 가장 큰 `PlaybackCore` 재구성을 먼저 끝낸다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 3 (기술적 고려사항)
CI unit (`ci-quality-gate`) 은 비즈니스 로직이 없는 설정 · 스크립트 변경입니다. 이 unit 의 설계 stage 를 어떻게 할까요?

A) Functional Design 과 NFR Design 은 SKIP, NFR Requirements (검사 스크립트의 언어 · 도구 결정) 와 Code Generation 만 실행 (권장)

B) 설계 stage 3개 모두 SKIP, Code Generation 만 실행 (도구 결정은 Code Generation 계획에서)

C) 다른 unit 과 같이 설계 stage 3개 모두 실행

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 4 (그룹화)
테스트 작성 중 발견한 버그의 수정 (FR-08) 을 어디에 둘까요?

A) 발견한 unit 안에서 처리 - 그 unit 의 Code Generation 에서 실패 테스트 추가 → 별도 커밋으로 수정 → 요약에 기록 (권장)

B) 발견만 기록해 두고, 모든 테스트 unit 이 끝난 뒤 별도 unit (`bug-fixes`) 에서 모아서 수정

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## 질문하지 않은 범주와 이유

- **팀 정렬**: 개인 프로젝트라 소유 경계 · 협업 모델이 없다 (`requirements.md` 의 앱 용도: 개인용)
- **비즈니스 도메인**: 기능 · 도메인 경계를 바꾸지 않는 테스트 보강이다. unit 은 도메인이 아니라 언어 · 도구 기준으로 나눈다 (Question 1)
- **코드 구성**: Greenfield 전용 범주다. 이 프로젝트는 Brownfield 이고 파일 위치는 Application Design 에서 정했다
