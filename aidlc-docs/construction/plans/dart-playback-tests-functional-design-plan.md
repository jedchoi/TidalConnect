# Functional Design 계획 - dart-playback-tests

**이 stage 의 "비즈니스 로직" 이란**: 이 unit 은 새 로직을 만들지 않는다. Functional Design 은 대상 4개 컴포넌트 (`PhoneBackend`, `DlnaBackend`, `DlnaManager`, `WaveAudioHandler`) 가 **지금 어떻게 동작해야 하는지** 를 규칙으로 적는다. 이 규칙이 Code Generation 에서 테스트 케이스가 된다. 변환 · 상태 로직에서는 속성 (PBT-01) 을 식별한다.

## 실행 단계

- [x] 1. unit 정의 (`unit-of-work.md`), 요구사항 매핑 (`unit-of-work-story-map.md`), Application Design 읽기
- [x] 2. 대상 코드 4개 파일과 호출하는 쪽 (`PlayerManager`) 읽기
- [x] 3. 아래 질문에 대한 답변 수집 · 모호성 분석
- [x] 4. `aidlc-docs/construction/dart-playback-tests/functional-design/business-logic-model.md` 생성
  - [x] 4.1 `PhoneBackend`: 명령 → 채널 호출 대응, 네이티브 이벤트 → `BackendEvent` 변환, 재생 시작 뒤 탐색 적용 (pending seek)
  - [x] 4.2 `DlnaBackend`: 재생 흐름 (토큰 → 스트림 정보 → 프록시 등록 → SOAP), 명령 직렬화, 폴링 상태 기계, 곡 끝 판정, 갭리스 전환, 주소 재발급
  - [x] 4.3 `DlnaManager`: 기기별 제어 URL 선택, SOAP 명령 전달, 시간 문자열 변환, 탐색과 선택 정리 (저장 · 복원 · 폰 스피커로 되돌림)
  - [x] 4.4 `WaveAudioHandler`: 명령 전달, 재생 상태 · 현재 곡 · 대기열 · 재생 정보 (로컬/원격) 알림
  - [x] 4.5 "테스트 가능한 속성 (Testable Properties)" 절: 컴포넌트별 속성과 분류 (PBT-01), 속성이 없는 컴포넌트는 근거와 함께 명시
- [x] 5. `aidlc-docs/construction/dart-playback-tests/functional-design/business-rules.md` 생성: 컴포넌트별 번호가 붙은 규칙 (조건 → 기대 결과), 오류 코드 표, FR-01 ~ FR-04 항목과의 대응
- [x] 6. `aidlc-docs/construction/dart-playback-tests/functional-design/domain-entities.md` 생성: 테스트가 다루는 데이터 (`BackendEvent` 5종, `StreamQuality`, `MediaTrack`, `DlnaDevice`, `DlnaPosition`, `DidlMetadata`, `TidalPlaybackInfo`, 채널 호출 · 이벤트 맵) 와 PBT 생성기가 만들 값의 범위
- [x] 7. 검증: FR-01 ~ FR-04 의 모든 항목이 규칙에 있는지, 규칙에 쓴 이름이 코드에 있는지

프런트엔드 컴포넌트 문서 (`frontend-components.md`) 는 만들지 않는다: 이 unit 에 UI 가 없다.

## 질문

각 질문의 `[Answer]:` 뒤에 선택지 문자를 적어 주세요.

## Question 1 (비즈니스 규칙 · 오류 처리)
테스트를 쓰다가 "지금 동작이 의도와 다른 것 같다" 싶은 곳을 만나면 무엇을 버그로 보고 고칠까요? (FR-08 의 판단 기준)

A) 좁게 - 다음 중 하나일 때만 버그로 보고 고친다: (1) 코드 주석 · `CLAUDE.md` · 기존 문서에 적힌 의도와 실제 동작이 다름, (2) 예외로 죽거나 상태가 잘못된 채 남음. 그 밖의 "어색하지만 일관된" 동작은 지금 동작 그대로 테스트로 고정하고 관찰 사항으로만 기록한다 (권장: 실기기 확인이 완료 기준에 없어 동작 변경의 위험이 크다)

B) 넓게 - 일관성이 없거나 더 나은 동작이 분명한 곳도 고친다 (수정마다 실패 테스트 + 별도 커밋)

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천대로 진행해줘" 에 따라 권장안 기입)

## Question 2 (오류 처리)
`PhoneBackend` 는 `play` · `pause` · `resume` 이 네이티브에서 실패하면 `PlaybackException` 을 던지지만, `seek` · `stop` · `setNext` · `setAudioQuality` 는 실패해도 아무것도 던지지 않습니다. 요구사항 FR-01 은 "네이티브 호출이 실패하면 `PlaybackException`" 이라고만 적었습니다. 어느 쪽을 규칙으로 삼을까요?

참고: `PlayerManager` 는 `_backend.seek(...)` 을 기다리지 않고 오류 처리 없이 호출하고 (`player_manager.dart:354`), `_backend.stop()` 도 try 없이 호출합니다 (`:364`, `:441`). 지금 이 네 메서드가 예외를 던지게 바꾸면 처리되지 않은 오류가 됩니다.

A) 지금 동작을 규칙으로 - `play` · `pause` · `resume` 만 예외, 나머지 넷은 실패를 무시한다고 테스트로 고정한다. FR-01 문구를 이에 맞게 정정한다 (권장)

B) 넷도 예외를 던지게 고친다 - `PhoneBackend` 와 함께 `PlayerManager` 의 호출부에 오류 처리를 추가한다 (운영 코드 변경이 `PlayerManager` 까지 넓어짐)

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천대로 진행해줘" 에 따라 권장안 기입)

## Question 3 (데이터 흐름 · 비즈니스 시나리오)
`PhoneBackend` 의 이벤트 변환을 속성 기반 테스트로 검증할 때, 네이티브 이벤트 맵을 어느 범위까지 만들어 넣을까요? 지금 코드는 필드가 빠진 경우는 기본값으로 처리하지만, 타입이 틀린 값 (예: `positionMs` 가 문자열) 이 오면 형 변환 예외가 납니다. Kotlin 쪽은 항상 정해진 타입으로 보냅니다.

A) 계약 범위 안에서 - 필드가 있거나 없고, 있으면 채널 계약의 타입인 맵만 만든다. "모르는 `type` 은 무시", "필드가 빠지면 기본값" 을 속성으로 검증한다. 타입이 틀린 입력은 범위 밖으로 두고 관찰 사항에 기록한다 (권장)

B) 임의의 값까지 - 타입이 틀린 값도 넣고, 어떤 맵이 와도 예외 없이 처리하도록 `PhoneBackend` 를 고친다 (운영 코드 변경: 방어적 형 변환)

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천대로 진행해줘" 에 따라 권장안 기입)

## 질문하지 않은 범주와 이유

- **도메인 모델**: 새 엔티티가 없다. 기존 모델 (`BackendEvent`, `DlnaDevice` 등) 을 그대로 쓴다
- **연동 지점**: 채널 · SOAP · TIDAL API 를 어떻게 대체할지는 Application Design 에서 정했다 (Q1 ~ Q3)
- **프런트엔드 컴포넌트**: 이 unit 에 UI 가 없다
- **비즈니스 로직 모델링의 나머지** (폴링 상태 기계, 곡 끝 판정, 갭리스, 선택 정리): 코드와 주석으로 의도가 확인된다. 의도가 불분명한 곳이 나오면 Question 1 의 기준을 적용한다
