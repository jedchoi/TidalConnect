# Functional Design 계획 - android-native-tests

**이 stage 가 정하는 것**: (1) `PlaybackCore.onMethodCall` 에서 `PlaybackCommandRouter` 로 옮길 명령 분배의 규칙 (메서드 16개의 인자 · 기본값 · 반환 맵 · 오류), (2) `TidalStreamProxyServer` 가 지금 어떻게 응답해야 하는지의 규칙. 두 규칙이 Code Generation 에서 테스트 케이스가 된다. 변환 · 상태 로직에서는 속성 (PBT-01) 을 식별한다.

unit 1 과 다른 점: 이 unit 은 운영 코드를 재구성한다 (`PlaybackCore` 에서 router 를 분리). router 의 규칙은 "지금의 `onMethodCall` 과 같은 결과" 가 기준이다.

## 실행 단계

- [x] 1. unit 정의 (`unit-of-work.md`), 요구사항 매핑, Application Design (`component-methods.md` 의 router · 인터페이스 시그니처) 읽기
- [x] 2. 대상 코드 읽기: `PlaybackCore.kt`, `TidalStreamProxyServer.kt`, `TidalPlayerManager.kt`, `TidalAuthManager.kt`, `DashManifest.kt`, `DashSegmentInputStream.kt`
- [x] 3. 아래 질문에 대한 답변 수집 · 모호성 분석
- [x] 4. `aidlc-docs/construction/android-native-tests/functional-design/business-logic-model.md` 생성
  - [x] 4.1 `PlaybackCommandRouter`: 메서드 분배, 인자 해석, 결과 3종 (성공 · 오류 · 미구현), 플레이어가 없을 때의 처리
  - [x] 4.2 `PlaybackCore` 와 router 의 경계: 무엇이 router 로 가고 무엇이 남는지, 채널 응답으로 옮기는 방식
  - [x] 4.3 `TidalStreamProxyServer`: 곡 등록 (토큰 · 확장자 · 최근 3곡 유지), 요청 처리 순서 (경로 → 등록 여부 → 접근 제어 → HEAD/GET), 단일 파일 중계 (Range, 만료 시 재발급 1회), DASH 중계 (세그먼트 연결, 전체 길이)
  - [x] 4.4 "테스트 가능한 속성 (Testable Properties)" 절 (PBT-01)
- [x] 5. `aidlc-docs/construction/android-native-tests/functional-design/business-rules.md` 생성: 번호가 붙은 규칙 (조건 → 기대 결과), 채널 메서드 표 (인자 · 기본값 · 반환), 프록시 응답 표 (상태 코드 · 헤더), FR-05 · FR-06 항목과의 대응, unit 1 의 테스트가 쓴 채널 문자열과의 대조
- [x] 6. `aidlc-docs/construction/android-native-tests/functional-design/domain-entities.md` 생성: `CommandResult`, 협력 인터페이스, `StreamInfo`, 프록시 URL 형식, PBT 생성기 범위
- [x] 7. 검증: FR-05 · FR-06 의 모든 항목이 규칙에 있는지, 규칙에 쓴 이름이 코드 또는 Application Design 에 있는지

프런트엔드 컴포넌트 문서는 만들지 않는다 (UI 없음).

## unit 1 에서 이어받는 결정

unit 1 의 Functional Design 계획에서 정한 두 가지를 이 unit 에도 그대로 적용한다. 다르게 하려면 Question 1 에서 알려 주세요.

- 테스트 입력은 채널 계약의 타입 범위 안에서만 만든다 (unit 1 Q3=A). router 는 타입이 틀린 인자를 "없는 인자" 와 같이 기본값으로 처리한다
- 숫자 인자 (`positionMs`, `percent`, `expiresInSeconds`) 는 정수 타입의 크기 (Int · Long) 와 상관없이 읽는다. 지금 코드는 `positionMs` 를 Int 로만 읽지만, 채널이 큰 값을 Long 으로 보내는 경우는 실제 재생 위치 범위에서 생기지 않는다

## 질문

각 질문의 `[Answer]:` 뒤에 선택지 문자를 적어 주세요.

## Question 1 (비즈니스 규칙)
unit 1 에서는 "무엇을 버그로 보고 고칠지" 를 좁게 정했습니다 (문서 · 주석의 의도와 다르거나, 예외 · 잘못된 상태를 남기는 경우만 수정. 그 밖에는 지금 동작을 테스트로 고정하고 기록). 이 unit 에도 같은 기준을 쓸까요?

A) 같은 기준 (좁게) - 실기기 확인이 완료 기준에 없으므로 동작 변경을 최소로 한다 (권장)

B) 넓게 - 일관성이 없거나 더 나은 동작이 분명한 곳도 고친다 (수정마다 실패 테스트 + 별도 커밋)

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 2 (오류 처리)
요구사항 FR-05 는 "CDN URL 없음 → 400" 을 검증 항목으로 적었지만, 실제 코드는 직접 주소와 매니페스트가 모두 비어 있으면 그보다 먼저 404 를 돌려줍니다. `proxyDirectCdn` 의 400 분기 (`"CDN URL required"`) 는 지금 코드에서 도달할 수 없습니다. 어떻게 할까요?

A) 요구사항만 고친다 - FR-05 의 항목을 "직접 주소와 매니페스트가 모두 비면 404" 로 정정한다. 도달할 수 없는 400 분기는 코드에 그대로 둔다 (권장: 동작이 바뀌지 않는다)

B) 요구사항을 고치고 도달할 수 없는 400 분기도 지운다 - 동작은 바뀌지 않고 코드만 정리된다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 3 (비즈니스 시나리오)
Application Design 에서 적어 둔 프록시의 두 가지 동작입니다. 각각 테스트로 재현한 뒤 어떻게 할까요?

- (가) 렌더러가 Range 헤더를 보냈는데 CDN 이 Range 를 무시하고 200 으로 전체를 주면, 프록시는 `Content-Range` 없이 206 으로 응답한다 (`proxyDirectCdn` 의 상태 결정). TIDAL CDN 은 실제로 Range 를 지원하므로 이 경우가 생긴 적이 있는지는 알 수 없다
- (나) 서명 주소가 만료된 상태에서 HEAD 요청이 오면 주소를 갱신하지 않고 길이 없는 응답을 준다. GET 요청은 갱신 후 다시 시도한다

A) 둘 다 지금 동작을 테스트로 고정하고 관찰 사항으로 기록한다 - 어느 쪽도 문서 · 주석에 적힌 의도와 어긋난다고 단정할 수 없고, 고친 결과를 실기기에서 확인할 수 없다 (권장)

B) (가) 만 고친다 - CDN 이 200 을 주면 프록시도 200 으로 응답한다. (나) 는 고정한다

C) 둘 다 고친다 - (가) 는 B 와 같이, (나) 는 HEAD 에서도 만료 시 주소를 갱신한다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## 질문하지 않은 범주와 이유

- **도메인 모델**: 새 타입 (`CommandResult`, 협력 인터페이스 4개) 은 Application Design 에서 시그니처까지 정했다
- **연동 지점**: 채널 계약은 바꾸지 않는다. CDN 대체 방식 (`FakeCdnServer`) 은 Application Design 에서 정했고 구현 수단은 NFR Requirements 에서 정한다
- **데이터 흐름**: 등록 → 토큰 → 요청 → 중계의 흐름은 코드와 주석으로 확인된다
- **`initTidalAuth` 의 초기화 순서** (인증 공급자 생성 → 토큰 갱신 연결 → 플레이어 생성): router 가 아니라 `PlaybackCore` 안의 `AuthControls` 구현에 그대로 남는다. router 는 성공 여부만 받아 반환 맵을 만든다
- **프런트엔드 컴포넌트**: UI 없음
