# Code Generation 계획 - android-native-tests

**이 계획이 Code Generation 의 유일한 기준이다.** Part 2 (생성) 는 아래 Step 을 순서대로 실행하고, 끝낸 Step 을 바로 `[x]` 로 표시한다. 계획에 없는 변경이 필요해지면 멈추고 이유를 요약에 적는다.

사용자 지시 (2026-11-17): "tdd red/green/refactor를 활용해서 진행". 테스트 작성은 `tdd-red`, 구현은 `tdd-green`, 구조 정리는 `tdd-refactor` 스킬의 절차를 따른다.

## unit 맥락

| 항목 | 내용 |
| --- | --- |
| workspace 루트 | `/Volumes/Mac990/Project/TidalConnect` (Brownfield, 기존 구조 `android/app/src/main/kotlin/` · `android/app/src/test/kotlin/` 사용) |
| 구현하는 요구사항 | FR-05, FR-06, FR-07 (Kotlin 부분), FR-08 (이 범위에서 발견한 것). 스토리가 없어 FR 과 규칙 ID (`business-rules.md` 의 CR · PC · PX) · 속성 ID (`business-logic-model.md` 의 P-CR · P-PX) 로 추적한다 |
| 다른 unit 에 대한 의존 | 없음. unit 1 과 채널 계약 문자열을 공유한다 (`business-rules.md` 6절에서 대조함) |
| 인터페이스 · 계약 | MethodChannel 의 메서드 16개 · 인자 키 · 반환 맵, 프록시의 HTTP 경로와 응답. 바꾸지 않는다 |
| 소유하는 데이터베이스 엔티티 | 없음 |
| 경계 | 운영 코드: 새 파일 3개 (`PlaybackContracts.kt`, `PlaybackCommandRouter.kt`, `ChannelAdapter.kt`), 수정 3개 (`PlaybackCore.kt`, `TidalPlayerManager.kt`, `TidalStreamProxyServer.kt`), 설정 1개 (`android/app/build.gradle.kts`). Dart 코드는 바꾸지 않는다 |
| 적용 설계 | 패턴 TW · KD · KV · KP · KR (`nfr-design-patterns.md`), 구성 요소 (`logical-components.md`), 결정 A1 ~ A9 (`tech-stack-decisions.md`) |
| 실행 환경 | Gradle 명령은 `JAVA_HOME=/opt/homebrew/opt/openjdk@17` 로 실행한다 |

## TDD 스킬을 이 unit 에 쓰는 방식

스킬은 Python 실습 모듈 전제라, 절차와 금지 사항은 따르고 도구는 바꿔 쓴다 (`nfr-design-patterns.md` 1절, NFR Design 계획 Q1=A 로 승인됨).

| 스킬의 요구 | 이 계획에서 |
| --- | --- |
| RED 는 테스트 작성 전용 세션, 구현 코드 본문을 읽지 않음 | 하위 에이전트 2개 (router 담당, 프록시 담당) 가 설계 문서와 시그니처만 보고 쓴다. `PlaybackCore.kt`, `TidalPlayerManager.kt`, `TidalAuthManager.kt`, `TidalStreamProxyServer.kt`, `DashSegmentInputStream.kt` 의 본문을 읽지 않는다 |
| GREEN 은 구현 전용 세션 (RED 와 분리) | 새 하위 에이전트 (RED 를 쓴 에이전트와 다르고, 이 세션과도 다르다). 2026-11-17 사용자 지시로 변경: 에이전트를 나눠 자기편향을 줄인다 |
| REFACTOR 는 GREEN 을 끝낸 세션 그대로 | GREEN 을 끝낸 하위 에이전트를 이어서 실행 |
| `pytest`, `ruff` | `(cd android && ./gradlew :app:testDebugUnitTest)` |
| `tdd_snapshot.py lock / check / restore` | 테스트 파일을 커밋해 고정 (해시 기록) / `git diff --exit-code <해시> -- <테스트 폴더>` / `git checkout <해시> -- <테스트 폴더>` |
| `tdd_snapshot.py save / revert` (리팩토링 되돌리기 기준) | 후보마다 커밋 / 실패하면 `git checkout -- <파일>` 로 마지막 커밋으로 |
| 커버리지 80% | Kotlin 은 커버리지 도구가 없다. 규칙 ID 대조로 대신한다 (NFR-01-A1) |
| 사람 관문: 테스트 경계 표 승인, RED 판정, 리팩토링 후보 승인 | 그대로 둔다 (Step 4.2, 4.5, 6.2). 이 세 곳에서 멈추고 응답을 기다린다 |

## 커밋

브랜치 `aidlc/test-reinforcement` 에 아래 "커밋" 표시 지점마다 로컬 커밋을 만든다 (푸시하지 않음). 이 계획의 승인을 그 커밋들에 대한 승인으로 본다.

역할 분담 (2026-11-17 사용자 지시): RED 는 하위 에이전트 2개, GREEN · REFACTOR 는 또 다른 하위 에이전트 1개가 맡는다. 이 세션은 조율, 사람 관문 (테스트 경계 표 · RED 판정 · 리팩토링 후보) 전달, 테스트가 고정 커밋과 같은지 확인, 커밋만 한다. 준비 (Step 1 ~ 3) 와 검증 (Step 7 ~ 10) 은 이 세션이 한다.

주의: Step 4.6 의 고정 커밋은 **실패하는 테스트를 담는다** (RED). Step 5 가 끝날 때까지 이 브랜치의 Kotlin 테스트는 실패 상태다.

## 실행 단계

### 준비 (이 세션)

- [x] **Step 1. Gradle 설정** (결정 A1 ~ A3, NFR-06-A5)
  - [x] 1.1 `android/app/build.gradle.kts`: `testOptions { unitTests.isReturnDefaultValues = true }`, `testImplementation` 2개 (`io.kotest:kotest-property:6.2.7`, `com.squareup.okhttp3:mockwebserver:4.12.0`) 추가 (기존 파일 수정)
  - [x] 1.2 기존 `DashManifestTest` 4개 통과 확인 (NFR-02-A2)

- [x] **Step 2. 속성 테스트 도우미** (패턴 KP-1 · KP-2 · KP-5)
  - [x] 2.1 `android/app/src/test/kotlin/com/example/tidal_connect_lite/PbtSupport.kt` 새로 만듦: seed (환경 변수 `PBT_SEED` 또는 20261117) · 실행 횟수로 `PropTestConfig` 를 만드는 함수, `runBlocking` 으로 감싸는 함수
  - [x] 2.2 일부러 틀린 속성을 임시 파일로 실행해 실패 출력에 seed 와 축소된 입력이 나오는지 확인하고 임시 파일을 지운다
  - [x] 커밋: `test: Kotlin 단위 테스트 설정과 속성 테스트 도우미 추가`

- [x] **Step 3. 시그니처 뼈대와 프록시 생성자** (패턴 TW-1 · KR-4, FR-07)
  - [x] 3.1 `android/app/src/main/kotlin/com/example/tidal_connect_lite/PlaybackContracts.kt` 새로 만듦: `CommandResult`, `PlayerControls`, `AuthControls`, `DeviceControls`, `ProxyRegistrar` (`component-methods.md` 의 시그니처 그대로, 로직 없음)
  - [x] 3.2 `.../PlaybackCommandRouter.kt` 새로 만듦: 뼈대. `handle` 은 모든 호출에 `CommandResult.NotImplemented` 를 돌려준다
  - [x] 3.3 `.../ChannelAdapter.kt` 새로 만듦: 뼈대. 인자 변환은 빈 맵을 돌려주고, 응답 변환은 아무것도 보내지 않는다
  - [x] 3.4 `.../TidalStreamProxyServer.kt` 수정: 생성자에 `port` (기본 `PROXY_PORT`), `httpClient` (기본 지금 설정) 추가, 돌려주는 주소의 포트를 실제로 열린 포트로 (동작 동일, NFR-06-A4)
  - [x] 3.5 기존 테스트 통과, `flutter build apk --debug --dart-define-from-file=config/tidal.json` 성공 확인
  - [x] 커밋: `refactor: 명령 분배용 인터페이스 뼈대 추가, 프록시 포트와 HTTP 클라이언트 주입 가능하게`

### RED (`tdd-red` 스킬, 패턴 TW-2 ~ TW-5)

- [x] **Step 4. 실패하는 테스트 작성과 고정** (FR-05, FR-06, PBT-01 ~ 10)
  - [x] 4.1 `tdd-red` 스킬을 불러 절차를 확인한다. 하위 에이전트 2개가 설계 문서만 보고 테스트 경계 표를 만든다 (열: 규칙 ID · 경계 · 입력 · 기대값 · 테스트 파일)
    - router 담당: CR-01 ~ CR-13, PC-01 ~ PC-02, P-CR-1 ~ P-CR-6. 경계는 `PlaybackCommandRouter.handle` 과 `ChannelAdapter.kt` 의 함수
    - 프록시 담당: PX-01 ~ PX-38, P-PX-1 ~ P-PX-6. 경계는 `registerTrackStream` 과 HTTP 요청
  - [x] 4.2 **사람 승인 대기 (관문 1)**: 테스트 경계 표를 보여 주고 승인받는다
  - [x] 4.3 승인된 표대로 하위 에이전트가 테스트를 쓴다 (모두 `android/app/src/test/kotlin/com/example/tidal_connect_lite/` 에 새로 만듦)
    - router 담당: `RouterFakes.kt`, `RouterGenerators.kt`, `PlaybackCommandRouterTest.kt`, `ChannelAdapterTest.kt`
    - 프록시 담당: `FakeCdnServer.kt`, `ProxyFixture.kt`, `ProxyGenerators.kt`, `TidalStreamProxyServerTest.kt`
  - [x] 4.4 테스트 실행 → RED 판정 표 (열: 테스트 · 결과 · 실패 종류 · RED 인정). 테스트 쪽 오류 (컴파일 오류 · 이름 오류 · fake 오류) 는 RED 로 인정하지 않고 하위 에이전트가 고쳐 다시 실행한다
    - router · 변환 테스트: 뼈대라 실패하는 것이 정상. 뼈대에서 이미 통과하는 것 (예: CR-03) 은 "보호" 로 표시
    - 프록시 테스트: 기존 코드라 통과하는 것이 정상 ("보호"). 실패하는 것이 있으면 규칙 문서와 코드 중 어느 쪽이 다른지 표에 적는다
  - [x] 4.5 **사람 판정 대기 (관문 2)**: "RED 확인" 응답을 받기 전에는 고정하지 않는다
  - [x] 4.6 고정: 테스트 파일 8개를 커밋하고 해시를 이 계획 파일에 기록한다
  - [x] 커밋: `test: 명령 분배 · 프록시 테스트 추가 (RED)`

  고정 커밋 해시: `6acf424` (2026-11-17). 확인 명령: `git diff --exit-code 6acf424 -- android/app/src/test`. 이 커밋에서 프록시 테스트 3개 (PX-17, PX-19, PX-38) 는 실패 상태이며 Step 8 의 `fix:` 커밋에서 통과시킨다 (사람 판정: 버그로 처리)

### GREEN (`tdd-green` 스킬, 패턴 TW-6)

- [x] **Step 5. 고정된 테스트를 고치지 않고 구현** (FR-06, FR-07)
  - [x] 5.1 새 하위 에이전트 (GREEN 담당) 가 `tdd-green` 스킬의 절차를 따른다. 이 세션은 조율 · 테스트 변경 여부 확인 · 커밋만 맡는다. 시작 확인: 테스트가 고정 커밋과 같은지 (`git diff --exit-code`), 실패 테스트 목록 = 구현 대상
  - [x] 5.2 `PlaybackCommandRouter.kt` 구현 (CR-01 ~ CR-13): 실패 테스트를 규칙 묶음씩 통과시킨다
  - [x] 5.3 `ChannelAdapter.kt` 구현 (PC-01, PC-02)
  - [x] 5.4 프록시 테스트 가운데 실패가 남아 있으면 고치지 않고 정리해 보고한다 (Step 8 에서 처리)
  - [x] 5.5 테스트가 이상하다고 판단되면 **고치지 않고 멈춘다**. 테스트 이름 · 문서와 다른 점 · 근거 (규칙 ID) 를 보고한다
  - [x] 5.6 완료 확인: router · 변환 테스트 전체 통과, 기존 `DashManifestTest` 통과, 테스트가 고정 커밋과 같음
  - [x] 커밋: `feat: PlaybackCommandRouter 와 채널 응답 변환 구현 (GREEN)`

### REFACTOR (`tdd-refactor` 스킬, 패턴 TW-7 · KR-1 ~ KR-3)

- [ ] **Step 6. 동작을 바꾸지 않는 구조 정리** (FR-07, NFR-06)
  - [ ] 6.1 GREEN 을 끝낸 하위 에이전트가 이어서 `tdd-refactor` 스킬의 절차를 따른다. 시작 확인: GREEN 상태, 테스트가 고정 커밋과 같음. 후보 표를 만든다 (열: 후보 · 위치 · 이유 · 동작 변화 위험). 예상 후보:
    - `TidalPlayerManager` 에 `PlayerControls` 구현 선언 (`: PlayerControls`, `override`)
    - `PlaybackCore.onMethodCall` 의 `when` 분기 → router 위임. 같은 규칙 (메서드 분배) 이 `PlaybackCore` 와 router 두 곳에 있게 된 것을 한 곳으로. 협력 인터페이스의 운영 구현 3개를 기존 private 함수에 연결 (PC-04 ~ PC-06)
    - GREEN 에서 생긴 중복 (있으면)
  - [ ] 6.2 **사람 승인 대기 (관문 3)**: 후보 표를 보여 주고 승인받는다. 정리할 것이 없으면 "대상 없음"
  - [ ] 6.3 승인된 후보를 하나씩 적용한다. 후보마다: 범위 선언 (바뀌지 않는 것 포함) → 변경 → Kotlin 테스트 통과 · 테스트가 고정 커밋과 같음 확인 → 커밋. 실패하면 바로 되돌리고 원인을 보고한다
  - [ ] 6.4 완료 확인: Kotlin 테스트 통과, 테스트가 고정 커밋과 같음, `flutter build apk --debug` 성공
  - [ ] 커밋: 후보마다 `refactor: ...`

### 검증과 마무리 (이 세션)

- [ ] **Step 7. 변형 확인** (패턴 TW-8, NFR-01-A3)
  - [ ] 7.1 router · 변환 · 프록시의 운영 코드를 일부러 틀리게 바꿔 테스트가 실패하는지 확인하고 되돌린다
  - [ ] 7.2 잡지 못한 변형이 있으면 테스트를 직접 추가하지 않고 보고한다 (테스트 추가는 RED 로 돌아가 다시 판정 · 고정)

- [ ] **Step 8. 발견한 것 처리** (FR-08, Functional Design 계획 Q1=A 기준)
  - [ ] 8.1 RED · GREEN · 변형 확인에서 규칙과 다르게 동작한 곳을 정리한다
  - [ ] 8.2 기준에 해당하는 버그: 실패하는 테스트는 이미 있으므로 `lib` · Kotlin 수정 → 별도 커밋 `fix: ...` → `docs/incidents/YYYY-MM-DD-<이름>.md`
  - [ ] 8.3 규칙 문서가 틀린 것: 문서를 고치고, 테스트가 그 때문에 틀렸으면 RED 로 돌아가 다시 판정 · 고정
  - [ ] 8.4 버그가 아닌 것: `business-rules.md` 7절 관찰 사항에 추가. 해당이 없으면 "없음"

- [ ] **Step 9. 검증** (unit 완료 기준, NFR-01 ~ NFR-06)
  - [ ] 9.1 `(cd android && ./gradlew :app:testDebugUnitTest)` 전체: 통과 수 · 실패 수 기록 (NFR-02-A1, A2)
  - [ ] 9.2 규칙 ID 대조: CR 13개, PC-01 ~ 02, PX 38개, 속성 12개가 모두 테스트 이름에 있는지 (NFR-01-A1, A2, NFR-04-A1)
  - [ ] 9.3 10회 연속 실행 (`--rerun-tasks`), 결과 동일 (NFR-03-A4, A7)
  - [ ] 9.4 새 Kotlin 테스트의 실행 시간 합계 (결과 XML) 30초 이하 (NFR-03-A5). 넘으면 KP-3 에 따라 조정
  - [ ] 9.5 8765 포트를 점유한 상태에서 실행해 통과 (NFR-03-A2)
  - [ ] 9.6 `tool/check.sh` 전체 (Dart + Kotlin) 통과 (NFR-02-A3, A4)
  - [ ] 9.7 `flutter build apk --debug --dart-define-from-file=config/tidal.json` 성공 (NFR-06-A1)
  - [ ] 9.8 `git diff main -- android/app/src/main` 검토: 채널 이름 상수 변경 없음, `PlaybackCore` 에 남는 함수 본문 변경 없음, `ensureProxyServer` 의 프록시 생성 호출 변경 없음 (NFR-06-A2 ~ A4)
  - [ ] 9.9 테스트에 `config/tidal.json` 의 값 · 사설 대역 주소 · `Thread.sleep` 이 없는지 검색, 복제 파일 (`*_new.*`, `*_modified.*`, `*_v2.*`) 이 없는지 확인

- [ ] **Step 10. 요약 문서**
  - [ ] 10.1 `aidlc-docs/construction/android-native-tests/code/code-summary.md` 새로 만듦: 수정 · 생성 파일, 테스트 경계 표 (승인본), RED 판정 표, 리팩토링 후보와 결과, 규칙 · 속성별 테스트 대응, Step 9 의 실행 결과, 발견한 버그 · 관찰 사항, 실기기에서만 확정되는 부분 (NFR-06-A6), 계획에 없던 변경 · 계획에서 뺀 항목
  - [ ] 커밋: `docs(aidlc): Code Generation (android-native-tests) 요약`

## 요구사항 · 규칙 추적

| 요구사항 | 규칙 · 속성 | Step |
| --- | --- | --- |
| FR-06 | CR-01 ~ CR-13, PC-01 ~ PC-02, P-CR-1 ~ P-CR-6 | 4 (테스트), 5 (구현) |
| FR-06, FR-07 | PC-03 ~ PC-07 (`PlaybackCore` 경계) | 6 (위임), 9.7 · 9.8 (빌드 · 코드 비교) |
| FR-05 | PX-01 ~ PX-38, P-PX-1 ~ P-PX-6 | 3.4 (생성자), 4 (테스트), 7 (변형 확인) |
| FR-07 (Kotlin) | 인터페이스 · router · 변환 · 프록시 생성자 | 3, 5, 6 |
| FR-08 | 발견한 버그 | 8 |
| NFR-01 (Kotlin) | 규칙마다 테스트 | 4.1 (경계 표), 9.2 |
| NFR-02 | 점검 통과, 기존 테스트 유지 | 1.2, 3.5, 5.6, 6.4, 9.1, 9.6 |
| NFR-03 | 결정성 · 속도 | 4 (패턴 KD), 9.3 ~ 9.5 |
| NFR-04 (Kotlin) | 속성 12개, 모델, 생성기, seed | 2, 4 |
| NFR-05 (원칙 적용) | 파일 위치, 규칙 ID 표기, KDoc | 3, 4 |
| NFR-06 | 재구성 안전성 | 3.5, 6, 9.7, 9.8, 10 |

CR 13개, PC-01 ~ 02, PX 38개와 속성 12개가 모두 Step 4 에 들어 있다. PC-03 ~ 07 은 Step 6 과 9 에서 확인한다.

## 범위 요약

- 운영 코드: 새 파일 3개, 수정 3개. 설정 수정 1개 (`build.gradle.kts`)
- 테스트: 새 파일 9개 (테스트 3개, fake · 도우미 · 생성기 6개)
- 문서: 요약 1개 (`aidlc-docs/`), 버그를 고치면 `docs/incidents/` 에 추가
- 전체 Step 10개. 사람 관문 3개 (테스트 경계 표, RED 판정, 리팩토링 후보) + 마지막 완료 승인
- 커밋 6개 이상 (리팩토링 후보 · 버그 수정마다 추가)
