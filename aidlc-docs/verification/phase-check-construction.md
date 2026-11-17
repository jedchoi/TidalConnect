# Traceability Check 결과 — ② Construction (Construction → Operations)

- **점검 시각**: 2026-11-17T07:43:54Z
- **회차**: 2 (1회차: 미통과, GAP 2건 = FR-09 · NFR-02 의 CI 실행 근거 없음. 푸시와 초안 PR #1 로 CI 를 실행한 뒤 다시 점검)
- **대상 결정**: 인자 `construction`
- **입력 파일**:
  - `aidlc-docs/inception/requirements/requirements.md`
  - `aidlc-docs/inception/plans/execution-plan.md`, `aidlc-docs/aidlc-state.md` (User Stories 는 SKIP)
  - `aidlc-docs/inception/application-design/components.md`, `component-methods.md`, `unit-of-work.md`, `unit-of-work-story-map.md`
  - `aidlc-docs/construction/plans/` 의 코드 생성 계획 3개 (`dart-playback-tests`, `android-native-tests`, `ci-quality-gate`)
  - `aidlc-docs/construction/{dart-playback-tests,android-native-tests,ci-quality-gate}/` 의 설계 문서와 `code/code-summary.md`
  - 테스트 파일: `test/features/player/{phone_backend,dlna_backend,wave_audio_handler}_test.dart`, `test/features/dlna/dlna_manager_test.dart`, `test/tool/coverage_gate_test.dart`, `android/app/src/test/kotlin/com/example/tidal_connect_lite/{PlaybackCommandRouterTest,ChannelAdapterTest,TidalStreamProxyServerTest}.kt`
  - 실행 결과: `aidlc-docs/construction/build-and-test/build-and-test-summary.md` (2026-11-17 의 `tool/check.sh` 전체 실행: Dart 284 · Kotlin 86 통과)
  - 보류 근거: `aidlc-docs/audit.md`

## 1. 요약

| 항목 | 값 |
| --- | --- |
| 판정 | 통과 |
| 정방향 대상 수 | 14 (FR 9 · NFR 5 · AC 0) |
| OK | 13 |
| GAP | 0 |
| Deferred | 1 |
| N/A | 0 (User Story · AC 고리는 stage SKIP 으로 전체 N/A) |
| ORPHAN (역방향) | 0 |
| 커버리지 | ② 요구 → 테스트 14/14, 테스트 → 실행 통과: 로컬 14/14, CI 2/2 (CI 를 요구하는 FR-09 · NFR-02) |

1회차의 GAP 2건 (CI 실행 근거 없음) 은 초안 PR #1 의 CI 실행 (run 44039821871, success) 으로 해소되었다. Deferred 1건 (NFR-03) 은 그대로다.

## 2. 정방향 추적 (요구 → 하위 산출물)

### ② Construction (6고리)

User Stories stage 를 SKIP 했으므로 "User Story" 고리는 모든 행에서 N/A 다. 요구사항은 `unit-of-work-story-map.md` 에서 unit 으로 바로 이어진다. 테스트는 이름의 규칙 ID 로 대조했다.

| ID | User Story | Unit | 구현 계획 Step | 소스 · 테스트 | 실행 결과 | 상태 | 대상 · 사유 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| FR-01 `PhoneBackend` 테스트 | N/A (SKIP) | `dart-playback-tests` | dart 계획의 PhoneBackend 테스트 Step | `phone_backend_test.dart` (`[PB-01]` ~ `[PB-26]`, `[P-PB-1]` ~ `[P-PB-5]`, 39개) | PASS (Dart 284개 통과) | OK | 규칙 PB 26개 모두 테스트 이름에 있음 |
| FR-02 `DlnaBackend` 테스트 | N/A | `dart-playback-tests` | dart 계획의 DlnaBackend 테스트 Step | `dlna_backend_test.dart` (`[DB-01]` ~ `[DB-49]`, `[P-DB-1]` ~ `[P-DB-5]`, 61개) | PASS | OK | |
| FR-03 `DlnaManager` 테스트 | N/A | `dart-playback-tests` | dart 계획의 DlnaManager 테스트 Step | `dlna_manager_test.dart` (`[DM-01]` ~ `[DM-29]`, `[P-DM-1]` ~ `[P-DM-6]`, 40개) | PASS | OK | |
| FR-04 `WaveAudioHandler` 테스트 | N/A | `dart-playback-tests` | dart 계획의 WaveAudioHandler 테스트 Step | `wave_audio_handler_test.dart` (`[WA-01]` ~ `[WA-23]`, `[P-WA-1]` ~ `[P-WA-2]`, 27개) | PASS | OK | |
| FR-05 `TidalStreamProxyServer` 테스트 | N/A | `android-native-tests` | android 계획 Step 3.4, 4, 7 | `TidalStreamProxyServerTest.kt` (`PX-01` ~ `PX-38`, `P-PX-1` ~ `P-PX-6`, 45개) | PASS (Kotlin 86개 통과) | OK | 간헐 실패는 NFR-03 행 |
| FR-06 `PlaybackCore` 테스트 | N/A | `android-native-tests` | android 계획 Step 4, 5 | `PlaybackCommandRouter.kt`, `ChannelAdapter.kt` / `PlaybackCommandRouterTest.kt` (`CR-01` ~ `CR-13`, `P-CR-1` ~ `P-CR-6`, 32개), `ChannelAdapterTest.kt` (`PC-01`, `PC-02`, 5개) | PASS | OK | 요구사항대로 router 로 검증. `PlaybackCore` 의 Android 연결부 (PC-03 ~ PC-07) 는 테스트 대상에서 제외한다고 story map 에 적혀 있음 |
| FR-07 테스트 용이성을 위한 운영 코드 변경 | N/A | `dart-playback-tests`, `android-native-tests` | dart 계획 Step 2 / android 계획 Step 3, 5, 6 | `dlna_manager.dart` (`forTesting` 의 `soapClient`), `PlaybackContracts.kt`, `PlaybackCommandRouter.kt`, `ChannelAdapter.kt`, `PlaybackCore.kt`, `TidalPlayerManager.kt`, `TidalStreamProxyServer.kt` (생성자) | PASS (전체 테스트 통과, debug APK 빌드 성공) | OK | 실기기 확인은 NFR-02 가 완료 기준 밖으로 정함 |
| FR-08 발견 버그 수정 | N/A | `dart-playback-tests`, `android-native-tests` | dart 계획 Step 16 / android 계획 Step 8 | Dart: 발견한 버그 없음. Kotlin: `TidalStreamProxyServer.kt` (`8e5b417`), `docs/incidents/2026-11-17-head-content-length-minus-one.md`, 테스트 `PX-17` · `PX-19` · `PX-38` | PASS | OK | 실패 테스트 → `fix:` 커밋 → 문서의 절차를 따름 |
| FR-09 CI 에 커버리지 점검과 APK 빌드 단계 추가 | N/A | `ci-quality-gate` | ci 계획 Step 1 ~ 4 | `tool/coverage_gate.dart`, `tool/check.sh`, `.github/workflows/check.yml` / `coverage_gate_test.dart` (`[GT-01]` ~ `[GT-13]`, `[P-GT-1]` ~ `[P-GT-5]`, 22개) | 로컬: PASS (`tool/check.sh`, 키 없는 APK 빌드). CI: PASS (run 44039821871: 점검 · APK 빌드 · 업로드 성공, 산출물 `app-debug-nokeys`, 14일 뒤 만료) | OK | `build-and-test-summary.md` 의 "CI 실행" |
| NFR-01 커버리지 목표 | N/A | 세 unit | dart 계획 Step 18 / android 계획 Step 9.2 / ci 계획 Step 6.1 | 위 테스트 파일들, `tool/coverage_gate.dart` | PASS: 대상 4개 100.0 / 99.4 / 99.2 / 98.7% (기준 80%). Kotlin 은 규칙 53개 모두에 테스트 | OK | |
| NFR-02 점검 통과 (로컬과 CI) | N/A | 세 unit | 각 계획의 검증 Step | `tool/check.sh`, `check.yml` | 로컬: PASS (`모든 점검 통과`). CI: PASS (run 44039821871 의 "점검" 단계 성공) | OK | `build-and-test-summary.md` 의 "CI 실행" |
| NFR-03 테스트 결정성 · 속도 | N/A | `dart-playback-tests`, `android-native-tests` | dart 계획 Step 18 / android 계획 Step 9.3 ~ 9.5 | 가짜 시계 (`fake_async`), 임시 포트, 고정 seed | Dart: 10회 동일. 속도: 기준 안. Kotlin: **10회 연속 동일 기준 미충족** (프록시 테스트 간헐 실패, 약 135회 중 4회) | Deferred | `audit.md` "간헐 실패 조사 중단 지시" (사용자: "멈춰. 그정도는 괜찮아."). 원인 미확인 상태로 수용 |
| NFR-04 속성 기반 테스트 | N/A | 세 unit | dart 계획의 속성 테스트 Step / android 계획 Step 2, 4 / ci 계획 Step 2 | Dart 속성 18개 + 5개 (`kiri_check`), Kotlin 속성 12개 (`kotest-property`) | PASS | OK | |
| NFR-05 유지보수성 | N/A | `dart-playback-tests` | dart 계획 Step 3, 18 | `test/helpers/` 의 fake · 도우미, 줄 길이 120 | PASS (포맷 검사 통과) | OK | |

## 3. 역방향 추적 (근거 없는 항목)

| 항목 | 위치 | 상태 | 사유 |
| --- | --- | --- | --- |
| `LoggingPlayerControls` | `PlaybackCore.kt` | OK | FR-07 의 재구성에서 실패 로그를 유지하려는 결정 (android 리팩토링 후보 표, 사용자 승인 "승인 + 나") |
| `tool/check.sh` 의 JDK 탐색 | `tool/check.sh` | OK | ci unit 의 NFR-07-C6 (NFR Requirements Q7=A, 사용자 승인). 상위 요구는 NFR-02 (점검 통과) |
| `docs/failure-scenarios.md`, `docs/incidents/README.md` | 저장소 | OK | 요구사항의 복원력 결정 사항 (RESILIENCY-14, 15) |
| `PbtSupport.kt`, 생성기 · fake · 도우미 파일 | 테스트 폴더 | N/A | 테스트 지원 파일 (NFR-04, NFR-05 를 받침) |
| `.gitignore` 의 `coverage/`, `pubspec.yaml` · `build.gradle.kts` 의 테스트 의존성 | 설정 | N/A | 기술 보조 항목 |
| 기존 테스트 99개 (Dart 95, Kotlin 4) | `test/`, `DashManifestTest.kt` | N/A | 이번 작업 전부터 있던 것 |
| 새 테스트 271개 | 위 테스트 파일 | OK | 모두 이름에 규칙 · 속성 ID 가 있고, 그 규칙이 FR-01 ~ 06 · FR-09 로 이어짐 |

ORPHAN 없음.

## 4. 일관성 경고

- `requirements.md` 의 NFR-03 은 "flaky 0건" 인데, 실제로는 Kotlin 프록시 테스트의 간헐 실패를 수용했다. 요구사항 문서에는 이 수용이 반영되어 있지 않다 (기록은 `audit.md` 와 unit 2 요약에만 있다)
- unit 단계에서 새 NFR 번호가 생겼다: `NFR-06` (android unit 의 재구성 안전성), `NFR-07` (ci unit 의 점검 도구 품질). `requirements.md` 에는 NFR-01 ~ 05 만 있다. 두 번호는 각 unit 의 `nfr-requirements.md` 에서만 정의된다
- `tech-stack-decisions.md` (ci) 와 ci 계획 Step 4.1 의 `dart run` 표기: 결정 문서는 정정했고 계획 본문에는 처음 표기가 남아 있다 (요약의 "계획과 달라진 점" 에 기록됨)

## 5. 보완 제안

| 대상 | 문제 | 보완할 산출물 | 담당 stage |
| --- | --- | --- | --- |
| NFR-03 | 요구사항과 수용한 상태가 다름 | `requirements.md` 의 NFR-03 에 수용 사실을 적거나, 간헐 실패의 원인을 조사해 고친다 | Requirements Analysis 또는 Code Generation (android-native-tests) |
| NFR-06, NFR-07 | 상위 요구사항 문서에 없는 번호 | `requirements.md` 에 두 항목을 더하거나, unit 문서에서 상위 요구 (NFR-02) 의 하위 번호로 바꾼다 | Requirements Analysis |

## 6. 한계

- AI 가 문서를 대조한 결과이며 기계 검증 (2.x `traceability.json` + 검사 엔진) 이 아님
- User Story · AC 가 없는 프로젝트라 (stage SKIP) FR · NFR 14개를 단위로 점검했다. AC 단위의 정상 · 경계 · 오류 구분은 하지 않았고, 대신 unit 의 규칙 ID (PB, DB, DM, WA, CR, PC, PX, GT) 가 테스트 이름에 있는지로 대조했다
- "실행 결과" 는 2026-11-17 의 로컬 실행과 CI 실행 1회 (`build-and-test-summary.md`) 다. CI 는 한 번 통과한 것이며, Kotlin 프록시 테스트의 간헐 실패 때문에 매번 통과한다는 뜻은 아니다
- ② 의 실행 결과 고리는 과정 확장이다 (2.x Gate 3 범위 밖)
- 실기기 동작은 요구사항 (NFR-02) 이 완료 기준 밖으로 정해 점검 대상이 아니다. 실기기에서 확인되지 않은 변경이 있다는 사실은 `build-and-test-summary.md` 의 "알려진 문제" 에 있다

## 7. 사람 확인

- [ ] 점검 결과 검토 완료 (승인자: [ ], 시각: [ ])
