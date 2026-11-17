# Code Generation 계획 - dash-seek

요구사항: `aidlc-docs/inception/requirements/requirements-dash-seek.md` (FR-10 ~ FR-13). 규칙: `aidlc-docs/construction/dash-seek/functional-design/business-rules.md`. 브랜치 `feat/dash-seek`.

사용자 지시 (2026-11-17): 모든 단계를 권장안으로 자동 승인하고 빠르게 진행한다. 그래서 `tdd-red` · `tdd-refactor` 스킬의 사람 관문 (테스트 경계 표, RED 판정, 리팩토링 후보) 은 멈추지 않고 주 세션이 검토해 통과시키며, 그 사실을 `audit.md` 에 "자동 승인" 으로 적는다. 그 밖의 방식은 앞 작업과 같다: 단계마다 다른 하위 에이전트, 테스트는 커밋으로 고정, 단계마다 커밋.

## 경계

| 구분 | 파일 |
| --- | --- |
| Kotlin 운영 (수정) | `DashManifest.kt`, `DashSegmentInputStream.kt`, `TidalStreamProxyServer.kt`, `PlaybackContracts.kt`, `PlaybackCommandRouter.kt`, `PlaybackCore.kt` |
| Dart 운영 (수정) | `lib/core/native/tidal_sdk_native_bridge.dart`, `lib/features/player/data/backends/dlna_backend.dart` |
| Kotlin 테스트 | `DashManifestTest.kt` (추가), `TidalStreamProxyServerTest.kt` (추가), `PlaybackCommandRouterTest.kt` · `RouterFakes.kt` · `RouterGenerators.kt` (등록 관련 수정), 도우미 (`ProxyFixture.kt` 등, 필요하면) |
| Dart 테스트 | `test/features/player/dlna_backend_test.dart` (수정 · 추가), `test/helpers/` (필요하면) |
| 문서 | `README.md`, `CLAUDE.md`, `docs/dlna-compat.md`, `docs/failure-scenarios.md` |
| 바꾸지 않는 것 | `PlayerManager`, `WaveAudioHandler`, 화면, `DlnaManager`, CI · 점검 스크립트 |

앞 작업에서 고정한 테스트 (`6acf424`, `7d9ad11`) 가운데 이번에 바뀌는 규칙 (DB-12, DB-13, DB-39, DB-45, CR 의 등록 부분, P-CR-5) 의 테스트는 고쳐야 한다. 이번 작업의 고정 커밋을 새로 만든다.

## 실행 단계

- [x] **Step 1. 뼈대** (주 세션): 새 시그니처만 넣는다. `DashManifest.segmentStartMs` · `segmentIndexAt` (0 을 돌려줌), `RegisteredStream`, `ProxyRegistrar` 의 새 시그니처, `TidalStreamProxyServer.registerTrackStreamAt` (기존 등록에 위임, 오프셋 0), Dart `ProxyRegistration` 과 `registerTrackStream(startPosition:)` (무시). 운영 코드가 컴파일되고 Dart 테스트 284개가 통과하는 상태
  - [x] 커밋: `chore: DASH 탐색용 시그니처 뼈대 추가`
- [x] **Step 2. RED** (하위 에이전트 2개: Kotlin 담당, Dart 담당. 규칙 문서와 시그니처만 봄)
  - [x] 2.1 테스트 경계 표 (`code/red-seam-table-kotlin.md`, `code/red-seam-table-dart.md`) → 멈추지 않고 테스트 작성 → 실행 → RED 판정 표 (`code/red-result-kotlin.md`, `code/red-result-dart.md`)
  - [x] 2.2 주 세션이 표와 결과를 검토하고 다시 실행해 확인 (자동 승인)
  - [x] 2.3 테스트를 커밋으로 고정, 해시 기록
  - [x] 커밋: `test: DASH 탐색 테스트 추가 (RED)`

  고정 커밋 해시: `375ca35` (2026-11-17). 확인 명령: `git diff --exit-code 375ca35 -- android/app/src/test`. Dart 쪽은 규칙 추가 (DB-62, DB-62c) 로 두 번 더 고정: `bc9dfed`, `7d41b2b` (`git diff --exit-code 7d41b2b -- test`)
- [x] **Step 3. GREEN** (RED 와 다른 하위 에이전트 2개: Kotlin 담당, Dart 담당. 테스트를 고치지 않음)
  - [x] 3.1 Kotlin: `DashManifest`, `DashSegmentInputStream`, `TidalStreamProxyServer`, `PlaybackCommandRouter` (DS, PS, CR-14 ~ 18)
  - [x] 3.2 Dart: `TidalSdkNativeBridge`, `DlnaBackend` (NB, DB)
  - [x] 3.3 주 세션 확인: 테스트 전부 통과, 테스트가 고정 커밋과 같음, 포맷 · 분석 · 커버리지 검사
  - [x] 커밋: `feat: 프록시가 DASH 곡을 중간 세그먼트부터 보냄`, `feat: DLNA 스피커에서 DASH 곡 탐색 지원`
- [x] **Step 4. REFACTOR** (GREEN 을 끝낸 에이전트): 후보 표 → 주 세션이 권고대로 자동 승인 → 적용. 후보마다 커밋. 없으면 "대상 없음"
- [x] **Step 5. 문서** (주 세션): `README.md` 의 알려진 제약, `CLAUDE.md` 의 DASH 경로 설명, `docs/dlna-compat.md` 와 `docs/failure-scenarios.md` 에 확인 항목
  - [x] 커밋: `docs: DASH 곡 탐색 지원 반영`
- [x] **Step 6. 검증** (주 세션)
  - [x] 6.1 `tool/check.sh` 전체 통과 (커버리지 검사 포함)
  - [x] 6.2 규칙 ID 대조 (DS, PS, CR-14 ~ 18, NB, DB-50 ~ 61, 속성 5개)
  - [ ] 6.3 변형 확인 (새 코드) — 하지 않음 (사용자 지시: 반복 테스트 중단)
  - [ ] 6.4 새 테스트 10회 반복 — 하지 않음 (사용자 지시: 반복 테스트 중단)
  - [x] 6.5 debug APK 빌드, 연결된 폰에 설치
- [x] **Step 7. 요약**: `aidlc-docs/construction/dash-seek/code/code-summary.md`
  - [x] 커밋: `docs(aidlc): Code Generation (dash-seek) 요약`

## 요구사항 추적

| 요구사항 | 규칙 | Step |
| --- | --- | --- |
| FR-10 | DS-01 ~ 05, PS-01 ~ 10, CR-14 ~ 17, NB-01 ~ 03, DB-13, DB-51 ~ 53b, DB-60 | 2, 3 |
| FR-11 | DB-12, DB-50, DB-50b | 2, 3 |
| FR-12 | DB-17, DB-52, DB-54 ~ 56b, DB-58 | 2, 3 |
| FR-13 | DS-06, PS-03, PS-05, PS-09, CR-18, DB-45, DB-57, DB-59, DB-61 | 2, 3, 6.1 |
| NFR-01 ~ 04 | 커버리지, 점검, 결정성, 속성 5개 | 2, 6 |

확인하지 못하는 것: 실제 스피커에서의 재생과 위치 기준 판정 (규칙 문서 7절 R-1, R-2). Step 6.5 에서 폰에 설치한 뒤 사용자가 확인한다.
