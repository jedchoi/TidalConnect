# Code Generation 계획 - ci-quality-gate

**이 계획이 Code Generation 의 유일한 기준이다.** Part 2 (생성) 는 아래 Step 을 순서대로 실행하고, 끝낸 Step 을 바로 `[x]` 로 표시한다. 계획에 없는 변경이 필요해지면 멈추고 이유를 요약에 적는다.

## unit 맥락

| 항목 | 내용 |
| --- | --- |
| workspace 루트 | `/Volumes/Mac990/Project/TidalConnect` (Brownfield) |
| 구현하는 요구사항 | FR-09, NFR-01 (검사 자동화), NFR-02. 스토리가 없어 FR 과 `nfr-requirements.md` 의 ID (`NFR-01-C*`, `FR-09-C*`, `NFR-02-C*`, `NFR-07-C*`), 아래 검사 규칙 (GT) · 속성 (P-GT) ID 로 추적한다 |
| 다른 unit 에 대한 의존 | unit 1 의 테스트가 만드는 커버리지 (대상 4개 파일 98% 이상), `test/helpers/pbt_config.dart` |
| 인터페이스 · 계약 | `tool/check.sh [--skip-android]` 의 사용법은 그대로. `coverage/lcov.info` (Flutter 가 만드는 형식) 를 읽는다 |
| 소유하는 데이터베이스 엔티티 | 없음 |
| 경계 | 새 파일: `tool/coverage_gate.dart`, `test/tool/coverage_gate_test.dart`. 수정: `tool/check.sh`, `.github/workflows/check.yml`, `.gitignore`, `CLAUDE.md`, `README.md`. `lib/`, `android/`, 기존 테스트는 바꾸지 않는다 |
| 적용 설계 | 결정 C1 ~ C10 (`tech-stack-decisions.md`). Functional Design · NFR Design 은 건너뛴 unit 이라, 검사 규칙과 속성을 이 계획에서 정한다 (아래) |

## 검사 규칙 (GT) 과 속성 (P-GT)

Functional Design 을 건너뛰었으므로 `CoverageGate` 의 동작을 여기서 정한다. 테스트는 이 표를 기준으로 쓴다.

| ID | 규칙 | 근거 |
| --- | --- | --- |
| GT-01 | lcov 내용에서 `SF:<경로>` 가 파일을 시작하고, `DA:<줄 번호>,<실행 횟수>` 가 그 파일의 줄 기록이고, `end_of_record` 가 파일을 끝낸다. 파일의 전체 줄 수는 기록된 줄 번호의 개수, 실행된 줄 수는 실행 횟수가 1 이상인 줄 번호의 개수다 | NFR-07-C3 |
| GT-02 | 같은 파일의 기록이 여러 번 나오거나 같은 줄 번호가 여러 번 나오면 줄 번호별로 합친다. 한 번이라도 실행 횟수가 1 이상이면 실행된 줄이다 | NFR-07-C3 |
| GT-03 | 그 밖의 줄 (`TN:`, `LF:`, `LH:`, `FN:`, `BRDA:` 등), 빈 줄, 해석할 수 없는 `DA:` 줄 (숫자가 아님, 쉼표 없음), `SF:` 앞에 나온 `DA:` 줄은 무시한다. 예외를 던지지 않는다. `DA:` 의 셋째 항목 (체크섬) 은 있어도 무시한다 | NFR-07-C3 |
| GT-04 | 경로는 구분자 `\` 를 `/` 로 바꾼 뒤 비교한다. `SF:` 가 대상 경로와 같거나 `/<대상 경로>` 로 끝나면 그 대상의 기록이다 (절대 경로 허용). 앞뒤 공백은 뗀다 | NFR-07-C4 |
| GT-05 | 대상의 통과 조건은 `실행된 줄 × 100 ≥ 기준값 × 전체 줄` 이다 (정수 비교, 반올림 없음). 정확히 80% 는 통과다 | NFR-01-C2 |
| GT-06 | 대상의 기록이 없거나 전체 줄 수가 0 이면 그 대상은 실패이고, 사유는 "기록 없음" 이다 | NFR-01-C3 |
| GT-07 | 대상이 아닌 파일의 기록은 결과에 영향을 주지 않는다 | NFR-01-C5 |
| GT-08 | 전체 판정은 모든 대상이 통과할 때만 통과다 | NFR-01-C2 |
| GT-09 | 보고서는 대상을 상수에 적힌 순서대로 한 줄씩 항상 출력한다. 줄마다 경로, `실행된 줄/전체 줄`, 비율 (소수 첫째 자리까지, 버림), `통과` 또는 `실패` 가 있다. 기록이 없는 대상은 비율 자리에 `기록 없음` 을 쓴다. 마지막 줄은 전체 판정과 기준값이다 | NFR-07-C1 |
| GT-10 | 실패한 대상마다 "모자란 줄 수" 를 덧붙인다. 모자란 줄 수는 통과 조건을 만족하는 데 더 실행되어야 하는 최소 줄 수다 (`올림(기준값 × 전체 줄 / 100) − 실행된 줄`) | NFR-07-C1 |
| GT-11 | 실행 함수는 lcov 파일이 없거나 읽을 수 없으면 종료 코드 1 을 돌려주고, `flutter test --coverage` 를 먼저 실행하라는 안내를 출력한다 | NFR-01-C4 |
| GT-12 | 실행 함수의 종료 코드는 통과 0, 실패 1 이다. 인자가 없으면 `coverage/lcov.info` 를 읽고, 첫 인자가 있으면 그 경로를 읽는다 | FR-09-C1 |
| GT-13 | 대상은 `lib/features/player/data/backends/phone_backend.dart`, `lib/features/player/data/backends/dlna_backend.dart`, `lib/features/dlna/data/dlna_manager.dart`, `lib/features/player/data/wave_audio_handler.dart` 4개이고 기준값은 80 이다. 둘 다 스크립트의 상수다 | NFR-01-C1, C6 |

| ID | 속성 | 범주 |
| --- | --- | --- |
| P-GT-1 | 어떤 줄 실행 기록 (파일별 줄 번호 → 횟수) 이든, 그것을 lcov 문자열로 쓴 뒤 해석하면 파일별 전체 줄 수와 실행된 줄 수가 기록에서 직접 센 값과 같다 | 왕복 (PBT-02) |
| P-GT-2 | 어떤 lcov 내용이든, 대상이 아닌 파일의 기록을 임의로 더해도 대상별 결과와 전체 판정이 같다 | 불변 조건 (PBT-03) |
| P-GT-3 | 어떤 대상별 (실행된 줄, 전체 줄) 과 기준값에 대해서도, 전체 판정은 "모든 대상이 `실행된 줄 × 100 ≥ 기준값 × 전체 줄` 이고 전체 줄 > 0" 과 같다 | 불변 조건 (PBT-03) |
| P-GT-4 | 어떤 기록이든, 파일 기록의 순서를 섞거나 한 파일의 기록을 여러 덩어리로 나눠 써도 해석 결과가 같다 | 불변 조건 (PBT-03) |
| P-GT-5 | 실패한 어떤 대상이든, 실행되지 않은 줄 가운데 "모자란 줄 수" 만큼을 실행된 것으로 바꾸면 통과하고, 그보다 하나 적게 바꾸면 통과하지 못한다 | 불변 조건 (PBT-03) |

## 진행 방식

`CoverageGate` 는 unit 2 와 같이 `tdd-red` → `tdd-green` → `tdd-refactor` 의 흐름으로 만든다 (도구를 바꿔 쓰는 방식은 unit 2 의 `nfr-design-patterns.md` TW-1 ~ TW-9 와 같다). 단계마다 에이전트를 나눈다 (사용자 지시 2026-11-17: 에이전트를 나눠 자기편향을 줄인다).

| 단계 | 맡는 쪽 |
| --- | --- |
| 준비 (뼈대), 검증, 요약, 커밋 | 이 세션 |
| RED: 테스트 경계 표 → 테스트 → RED 판정 표 | 하위 에이전트 1개. 이 계획의 규칙 표와 뼈대의 시그니처만 본다 |
| GREEN: `coverage_gate.dart` 구현 | RED 와 다른 새 하위 에이전트. 테스트를 고치지 않는다 |
| 연결: `check.sh`, `check.yml`, 문서 | GREEN 을 끝낸 그 에이전트. 설정 변경이라 테스트 먼저 방식은 쓰지 않고, 이 세션이 실행해 확인한다 |
| REFACTOR | GREEN 을 끝낸 그 에이전트. 후보 표를 먼저 만든다 |

사람 관문은 세 곳이다 (Step 2.2, 2.5, 5.2). 이 세 곳에서 멈추고 응답을 기다린다. 테스트 고정은 커밋으로 한다 (`git diff --exit-code <해시> -- test/tool`).

## 커밋

브랜치 `aidlc/test-reinforcement` 에 아래 "커밋" 표시 지점마다 로컬 커밋을 만든다 (푸시하지 않음). 이 계획의 승인을 그 커밋들에 대한 승인으로 본다. Step 2.6 의 고정 커밋부터 Step 3 의 커밋 앞까지는 새 Dart 테스트가 실패하는 상태다.

## 실행 단계

### 준비 (이 세션)

- [ ] **Step 1. 뼈대와 설정** (FR-09-C7, NFR-07-C2)
  - [ ] 1.1 `.gitignore` 에 `coverage/` 추가 (기존 파일 수정)
  - [ ] 1.2 `tool/coverage_gate.dart` 뼈대 (새로 만듦): 상수 `coverageTargets`, `coverageThresholdPercent`, 타입 (`FileCoverage`, `TargetResult`, `GateResult`), 순수 함수 `parseLcov(String)`, `evaluateCoverage(String, {targets, thresholdPercent})`, `formatReport(GateResult)`, 실행 함수 `runCoverageGate(List<String> args, StringSink out)`, `main`. 본문은 빈 결과를 돌려준다
  - [ ] 1.3 `dart format`, `flutter analyze --fatal-infos`, 기존 `flutter test` 262개 통과 확인
  - [ ] 커밋: `chore: 커버리지 검사 스크립트 뼈대 추가, coverage/ 를 git 에서 제외`

### RED (`tdd-red` 스킬)

- [ ] **Step 2. 실패하는 테스트 작성과 고정** (NFR-01-C1 ~ C5, NFR-07-C1 ~ C4, PBT-01 ~ 10)
  - [ ] 2.1 하위 에이전트가 이 계획의 규칙 표만 보고 테스트 경계 표를 만든다 (열: 규칙 ID · 경계 · 입력 · 기대값). 경계는 `parseLcov`, `evaluateCoverage`, `formatReport`, `runCoverageGate`
  - [ ] 2.2 **사람 승인 대기 (관문 1)**
  - [ ] 2.3 승인된 표대로 `test/tool/coverage_gate_test.dart` 를 쓴다 (새로 만듦). 예시 기반 테스트는 GT-01 ~ GT-13, 속성 테스트는 P-GT-1 ~ P-GT-5. 테스트 이름 맨 앞에 `[GT-01]` 형식 (unit 1 의 Dart 테스트 표기). 생성기는 이 테스트 파일 안에 둔다. `runCoverageGate` 의 파일 읽기는 임시 폴더로 검증한다
  - [ ] 2.4 실행 → RED 판정 표. 테스트 쪽 오류는 RED 로 인정하지 않고 고쳐 다시 실행한다
  - [ ] 2.5 **사람 판정 대기 (관문 2)**: "RED 확인" 응답 전에는 고정하지 않는다
  - [ ] 2.6 고정: 테스트 파일을 커밋하고 해시를 이 계획 파일에 기록한다
  - [ ] 커밋: `test: 커버리지 검사 스크립트 테스트 추가 (RED)`

  고정 커밋 해시: (Step 2.6 에서 기록)

### GREEN (`tdd-green` 스킬)

- [ ] **Step 3. 고정된 테스트를 고치지 않고 구현** (NFR-01-C1 ~ C6, NFR-07-C1 ~ C4)
  - [ ] 3.1 새 하위 에이전트가 `tool/coverage_gate.dart` 를 구현한다. 테스트가 이상하면 고치지 않고 멈춰 보고한다
  - [ ] 3.2 완료 확인: 새 테스트 전부 통과, 기존 262개 통과, 테스트가 고정 커밋과 같음, 포맷 · 분석 통과
  - [ ] 커밋: `feat: 대상 파일의 커버리지를 검사하는 스크립트 구현 (GREEN)`

### 연결 (GREEN 을 끝낸 에이전트, 이 세션이 확인)

- [ ] **Step 4. 로컬 점검과 CI 에 연결** (FR-09-C1 ~ C8, NFR-07-C5 ~ C7)
  - [ ] 4.1 `tool/check.sh` (기존 파일 수정): `flutter test --coverage --reporter expanded` 로 바꾸고 이어서 `dart run tool/coverage_gate.dart`. 포맷 검사 대상에 `tool` 추가. Kotlin 단계 앞에 JDK 17 탐색 (결정 C7). 머리말 주석 갱신
  - [ ] 커밋: `chore: tool/check.sh 에 커버리지 검사와 JDK 탐색 추가`
  - [ ] 4.2 `.github/workflows/check.yml` (기존 파일 수정): "점검" 뒤에 키 없는 debug APK 빌드 step 과 `actions/upload-artifact` step (이름 `app-debug-nokeys`, `retention-days: 14`, `if-no-files-found: error`). 머리말 주석 갱신. `upload-artifact` 의 주 버전은 지금 배포된 최신을 확인해 적는다
  - [ ] 커밋: `ci: 점검 뒤 debug APK 를 빌드해 산출물로 올림`
  - [ ] 4.3 문서 (기존 파일 수정): `CLAUDE.md` 의 Commands 절 (커버리지 검사, JDK 탐색, `coverage/`), `README.md` 의 점검 명령 설명과 CI 산출물 안내 ("빌드 확인용, 키 없음, 설치하면 시작할 때 멈춘다")
  - [ ] 커밋: `docs: 커버리지 검사와 CI 산출물 안내 추가`

### REFACTOR (`tdd-refactor` 스킬)

- [ ] **Step 5. 동작을 바꾸지 않는 구조 정리**
  - [ ] 5.1 GREEN 을 끝낸 에이전트가 후보 표를 만든다 (열: 후보 · 위치 · 이유 · 동작 변화 위험 · 권고)
  - [ ] 5.2 **사람 승인 대기 (관문 3)**. 정리할 것이 없으면 "대상 없음"
  - [ ] 5.3 승인된 후보를 하나씩 적용하고 후보마다 테스트 · 고정 비교 뒤 커밋

### 검증과 마무리 (이 세션)

- [ ] **Step 6. 검증** (NFR-01-C7, NFR-02-C1 ~ C4, NFR-07-C5 ~ C7)
  - [ ] 6.1 `tool/check.sh` 전체 통과. 커버리지 표에 대상 4개가 나오는지 확인
  - [ ] 6.2 검사가 실패를 잡는지 확인: 대상 파일의 테스트 하나를 임시로 빼거나 lcov 를 고쳐 80% 미만 · 기록 없음을 만들고 종료 코드가 0 이 아닌지 본 뒤 되돌린다
  - [ ] 6.3 변형 확인: `coverage_gate.dart` 를 일부러 틀리게 바꿔 테스트가 실패하는지 확인하고 되돌린다. 잡지 못한 변형은 테스트를 직접 추가하지 않고 보고한다
  - [ ] 6.4 `JAVA_HOME` 이 없고 Java 가 PATH 에 없는 셸에서 `tool/check.sh` 의 Kotlin 단계가 실행되는지 확인
  - [ ] 6.5 `tool/check.sh --skip-android` 통과 (커버리지 검사는 실행됨)
  - [ ] 6.6 실행 시간: 고치기 전후 Dart 테스트 단계를 3회씩 측정, 증가 10초 이하
  - [ ] 6.7 키 없이 `flutter build apk --debug` 성공 (CI 의 빌드 step 과 같은 명령). `check.yml` 을 YAML 로 해석해 문법 확인
  - [ ] 6.8 새 테스트 10회 연속 실행, 결과 동일
  - [ ] 6.9 스크립트 · workflow · 문서에 키 값이 없는지, 복제 파일 (`*_new.*`, `*_modified.*`, `*_v2.*`) 이 없는지, `git status` 에 `coverage/` 가 나오지 않는지 확인
- [ ] **Step 7. 요약 문서**
  - [ ] 7.1 `aidlc-docs/construction/ci-quality-gate/code/code-summary.md` 새로 만듦: 수정 · 생성 파일, 규칙 · 속성별 테스트 대응, Step 6 의 실행 결과, 확인하지 못한 것 (CI 의 실제 실행은 푸시해야 확인됨), 계획과 달라진 점
  - [ ] 커밋: `docs(aidlc): Code Generation (ci-quality-gate) 요약`

## 요구사항 추적

| 요구사항 | 규칙 · 속성 | Step |
| --- | --- | --- |
| NFR-01-C1 ~ C6 | GT-01 ~ GT-13, P-GT-1 ~ P-GT-5 | 2 (테스트), 3 (구현) |
| NFR-01-C7 | 지금 코드에서 통과 | 6.1 |
| FR-09-C1, C2, C6 | `check.sh` 연결 | 4.1, 6.1, 6.5 |
| FR-09-C3 ~ C5 | `check.yml` | 4.2, 6.7 |
| FR-09-C7 | `.gitignore` | 1.1, 6.9 |
| FR-09-C8 | 문서 | 4.3 |
| NFR-02-C1 ~ C4 | 점검 통과 | 1.3, 3.2, 6.1, 6.7 |
| NFR-07-C1 ~ C4 | GT-01 ~ GT-04, GT-09, GT-10 | 2, 3 |
| NFR-07-C5 | 실행 시간 | 6.6 |
| NFR-07-C6 | JDK 탐색 | 4.1, 6.4 |
| NFR-07-C7 | 키 값 없음 | 6.9 |

## 범위 요약

- 새 파일 2개 (스크립트 1, 테스트 1), 수정 5개 (`check.sh`, `check.yml`, `.gitignore`, `CLAUDE.md`, `README.md`), 문서 1개 (요약)
- 전체 Step 7개. 사람 관문 3개 + 마지막 완료 승인
- 커밋 7개 이상
- 확인하지 못하는 것: 고친 workflow 의 실제 실행 (푸시해야 확인된다. 이 작업은 푸시하지 않는다)
