# 코드 요약 (Code Summary) - ci-quality-gate

작성일: 2026-11-17. 브랜치 `aidlc/test-reinforcement`. 계획: `aidlc-docs/construction/plans/ci-quality-gate-code-generation-plan.md` (Step 7개 모두 완료).

## 결과

| 항목 | 결과 |
| --- | --- |
| 커버리지 검사 | `tool/coverage_gate.dart`. 대상 4개 파일이 각각 80% 이상인지 검사. 지금 수치는 100.0 / 99.4 / 99.2 / 98.7% 로 통과 |
| 새 Dart 테스트 | 22개 (예시 기반 17개 + 속성 5개). 전체 262개 → 284개 |
| 규칙 대응 | 계획의 검사 규칙 13개 (GT-01 ~ 13) 와 속성 5개 (P-GT-1 ~ 5) 모두에 테스트가 있음 |
| 로컬 점검 | `tool/check.sh` 가 커버리지를 모아 검사하고, JDK 17 을 스스로 찾는다 |
| CI | 점검 뒤 키 없는 debug APK 를 빌드해 `app-debug-nokeys` 로 올린다 (14일 보관). **실제 workflow 실행은 확인하지 못함** (푸시하지 않았다) |
| 변형 확인 | 21개 중 19개 감지, 2개 살아남음 (아래) |

## 진행 방식

unit 2 와 같이 `tdd-red` → `tdd-green` → `tdd-refactor` 흐름을 따랐고 단계마다 에이전트를 나눴다.

| 단계 | 맡은 쪽 |
| --- | --- |
| 뼈대, 검증, 요약, 커밋 | 주 세션 |
| RED: 테스트 경계 표 → 테스트 → 판정 표 | 하위 에이전트 A (규칙 표와 뼈대의 시그니처만 봄) |
| GREEN, 연결 (`check.sh` · `check.yml` · 문서), REFACTOR | 하위 에이전트 B |

사람 관문 3개를 모두 거쳤다: 테스트 경계 표 승인, "RED 확인", 리팩토링 후보 승인. 테스트는 커밋 `7d9ad11` 로 고정했고, 그 뒤 모든 단계에서 `git diff --exit-code 7d9ad11 -- test/tool` 이 차이 없음을 확인했다.

## 파일

### 생성 (Created)

| 파일 | 내용 |
| --- | --- |
| `tool/coverage_gate.dart` | lcov 해석 (`parseLcov`), 판정 (`evaluateCoverage`), 보고서 (`formatReport`), 실행 (`runCoverageGate`, `main`). 대상 4개와 기준값 80 은 파일 위쪽의 상수. `dart:io` 와 `dart:math` 만 쓴다 |
| `test/tool/coverage_gate_test.dart` | 테스트 17개 + 속성 5개. 생성기도 이 파일 안에 있다 |

### 수정 (Modified)

| 파일 | 내용 |
| --- | --- |
| `tool/check.sh` | `flutter test --coverage` 로 바꾸고 이어서 `dart tool/coverage_gate.dart`. 포맷 검사 대상에 `tool` 추가. Kotlin 단계 앞에서 JDK 17 탐색 (`JAVA_HOME` 이 없고 `java` 도 실행되지 않을 때만) |
| `.github/workflows/check.yml` | "점검" 뒤에 "debug APK 빌드 (키 없음)", "APK 산출물 업로드" (`actions/upload-artifact@v7`, `app-debug-nokeys`, `retention-days: 14`, `if-no-files-found: error`) |
| `.gitignore` | `coverage/` 제외 |
| `CLAUDE.md` | Commands 절: 점검 내용, 커버리지 검사만 돌리는 명령, JDK 탐색, CI 산출물 |
| `README.md` | "점검" 절: 커버리지 기준, JDK 안내, CI 산출물이 빌드 확인용이라는 안내 |

이 unit 의 다른 산출물 (같은 폴더): `red-seam-table.md` (테스트 경계 표, 승인본), `red-result.md` (RED 판정 표), `refactor-candidates.md` (리팩토링 후보 표, 승인본).

## RED · GREEN · REFACTOR 결과

- **RED**: 22개 모두 기대값 비교 실패 (뼈대가 빈 결과만 돌려줌). 테스트 쪽 오류 0. 표를 만들면서 에이전트가 규칙만으로 정할 수 없다고 보고한 15곳을 계획 파일의 "규칙 보완" 표로 정했다 (보고서 형식, `end_of_record` 누락, `\r\n`, 한 대상에 `SF:` 여럿 등)
- **GREEN**: `tool/coverage_gate.dart` 구현. 22개 통과. 테스트가 규칙과 어긋나 멈춘 곳은 없었다
- **REFACTOR**: 후보 8개 중 5개 적용, 3개는 그대로 둠

| # | 후보 | 결과 |
| --- | --- | --- |
| R1 | 보고서의 폭 계산을 `max` 로 | 적용 (`582ca22`) |
| R2 | 비율 칸 폭을 이름 있는 상수로 | 적용 (`e8a3f72`) |
| R3 | 기본 lcov 경로를 상수로 | 적용 (`c85aeca`) |
| R4 | 대상 경로 비교를 함수로 분리 | 적용 (`66fcd49`) |
| R5 | lcov 한 줄을 합칠 때 임시 맵을 만들지 않게 | 적용 (`2b65a50`) |
| R6 ~ R8 | 판정 함수 분리, 인덱스 정리, README 의 파일 이름 중복 | 그대로 둠 |

후보마다 테스트 22개 통과, 포맷, 고정 비교, 스크립트 출력 (통과하는 실제 lcov, 실패 · 기록 없음이 섞인 lcov) 이 적용 전과 글자 단위로 같은지를 확인했다.

## 검증 결과 (계획 Step 6)

| # | 확인 | 결과 |
| --- | --- | --- |
| 6.1 | `tool/check.sh` 전체 | 통과. Dart 284개, 커버리지 표에 대상 4개, Kotlin 86개 |
| 6.2 | 검사가 실패를 잡는지 (실제 lcov 를 고쳐서) | 대상 하나의 기록을 뺀 lcov: `0/0 기록 없음 실패`, 종료 코드 1. 대상 하나를 73.0% 로 낮춘 lcov: `57/78 73.0% 실패 6줄 부족`, 종료 코드 1. `set -e` 아래에서 뒤 명령이 실행되지 않음 |
| 6.3 | 변형 확인 | 21개 중 19개 감지 (아래) |
| 6.4 | `JAVA_HOME` 없이 `tool/check.sh` | 통과. `JAVA_HOME이 없어 찾은 JDK를 씁니다: /opt/homebrew/opt/openjdk@17` 출력 뒤 Kotlin 단계 실행 |
| 6.5 | `tool/check.sh --skip-android` | 통과. 커버리지 검사는 실행되고 Kotlin 단계는 건너뜀 |
| 6.6 | 실행 시간 | Dart 테스트 단계 6.0 ~ 7.5초 → 커버리지 수집 10.3 ~ 12.6초. 증가 약 4 ~ 5초 (기준 10초). 검사 스크립트 0.4초 |
| 6.7 | 키 없는 `flutter build apk --debug`, YAML 해석 | 빌드 성공. `check.yml` 은 YAML 로 해석되고 step 7개가 순서대로 읽힘 |
| 6.8 | 새 테스트 10회 연속 | 10회 모두 22개 통과 |
| 6.9 | 키 값 · 복제 파일 · `coverage/` | 스크립트 · workflow · 문서 · 테스트에 키 값 0건, `secrets.` 참조 없음, 복제 파일 없음, `git status` 에 `coverage/` 없음 |

### 변형 확인

| 대상 | 넣은 변형 | 감지 |
| --- | --- | --- |
| `tool/coverage_gate.dart` | 21개 (80% 경계, 기록 없음, 모자란 줄 수, 경로 비교, 비율 버림, 종료 코드, 안내 문구, 상수 등) | 19/21 |

살아남은 2개 (테스트를 추가하지 않았다. 추가하려면 RED 로 돌아가 다시 판정 · 고정해야 한다):

| 변형 | 관련 규칙 | 판단 |
| --- | --- | --- |
| 같은 줄의 기록이 여러 번 나올 때 "한 번이라도 실행되면 실행" 이 아니라 마지막 값으로 덮어씀 | GT-02 | 테스트에 "실행된 뒤 0 이 나오는 순서" 가 없다. Flutter 가 만드는 lcov 에는 같은 줄이 여러 번 나오지 않아 지금 결과에는 영향이 없다. 규칙의 빈틈이므로 테스트를 더할 만하다 |
| 줄의 앞뒤 공백을 떼지 않음 | GT-03 | 경로와 숫자는 따로 공백을 떼거나 해석 단계에서 무시되어 결과가 같았다. `\r\n` 경우를 테스트가 넣었지만 이 변형과 구분되지 않는다 |

## 확인하지 못한 것

- **CI 의 실제 실행.** 새 step 두 개와 `actions/upload-artifact@v7` 의 동작, 30분 제한 안에 끝나는지는 푸시해야 확인된다. 로컬에서는 같은 빌드 명령의 성공과 YAML 해석까지만 확인했다. `actionlint` 는 설치되어 있지 않아 실행하지 않았다
- **JDK 탐색의 나머지 분기.** 이 Mac 에서는 Homebrew 경로로 찾는 분기만 실행됐다. `/usr/libexec/java_home -v 17` 이 성공하는 분기와, JDK 를 찾지 못해 안내를 내고 실패하는 분기는 실행해 보지 못했다
- **Kotlin 프록시 테스트의 간헐 실패** (unit 2 요약) 는 그대로다. `tool/check.sh` 나 CI 가 그 때문에 가끔 실패하면 다시 실행한다

## 계획과 달라진 점 (CG-7)

### 계획에 없던 변경

| 변경 | 이유 |
| --- | --- |
| 검사 스크립트를 `dart run` 이 아니라 `dart tool/coverage_gate.dart` 로 실행 | `dart run` 은 출력 앞에 진행 표시를 줄바꿈 없이 내어 표의 첫 줄이 밀린다. `tech-stack-decisions.md` C1 을 정정함 |
| 계획 파일의 "규칙 보완" 표 (15곳) | RED 에이전트가 규칙만으로 정할 수 없다고 보고한 곳 |
| `dart:math` import | R1 (폭 계산을 `max` 로). 순수 Dart 라 `dart` 만으로 실행되는 데 영향이 없다 |
| REFACTOR 후보를 한 번에 적용하고 후보별 파일을 보관해 주 세션이 후보마다 다시 확인 · 커밋 | 후보 하나에 왕복 한 번씩 하면 다섯 번이라 줄였다. 커밋은 계획대로 후보마다 하나다 |

### 계획에서 뺀 항목

없음.

## 커밋

| 커밋 | 내용 |
| --- | --- |
| `a482f19` | chore: 커버리지 검사 스크립트 뼈대 추가, coverage/ 를 git 에서 제외 |
| `7d9ad11` | test: 커버리지 검사 스크립트 테스트 추가 (RED). **고정 커밋.** 새 테스트 22개가 실패한다 |
| `168f2f0` | feat: 대상 파일의 커버리지를 검사하는 스크립트 구현 (GREEN). 여기부터 전부 통과 |
| `ca075ef` | chore: tool/check.sh 에 커버리지 검사와 JDK 탐색 추가 |
| `f11d8c7` | ci: 점검 뒤 debug APK 를 빌드해 산출물로 올림 |
| `ce03eae` | docs: 커버리지 검사와 CI 산출물 안내 추가 |
| `582ca22`, `e8a3f72`, `c85aeca`, `66fcd49`, `2b65a50` | refactor: R1 ~ R5 |

사이사이에 진행 기록 커밋 (`docs(aidlc): ...`) 이 있고, 그 뒤에 이 요약을 담은 커밋이 있다. 푸시하지 않았다.

## 확장 규칙 준수

### Property-Based Testing

| 규칙 | 상태 | 근거 |
| --- | --- | --- |
| PBT-01 | compliant | 속성 5개를 계획에서 정하고 모두 구현 |
| PBT-02 | compliant | P-GT-1 (실행 기록 → lcov 문자열 → 해석의 왕복) |
| PBT-03 | compliant | P-GT-2 ~ P-GT-5 |
| PBT-04 · 05 · 06 | N/A | 멱등 연산 · 참조 구현 · 상태가 없다 |
| PBT-07 | compliant | 생성기를 테스트 파일 안에 둠 (파일 0 ~ 6개, 줄 0 ~ 40개, 기준값 1 ~ 100 등) |
| PBT-08 | compliant | `configurePbt()` 의 고정 seed (20261117), `PBT_SEED`. 실패 출력에 seed 가 나옴. 다만 P-GT-1 · P-GT-4 는 실패했을 때 입력이 축소되지 않고 그대로 출력된다 (seed 로 재현은 됨) |
| PBT-09 | compliant | `kiri_check` (기존 `dev_dependencies`). 새 의존성 없음 |
| PBT-10 | compliant | 규칙마다 예시 기반 테스트가 있고 속성은 그 위에 더함 |

### Resiliency

| 규칙 | 상태 | 근거 |
| --- | --- | --- |
| RESILIENCY-04 | compliant | 기존 GitHub Actions 에 커버리지 검사와 APK 빌드 · 업로드 추가. 배포 방식과 롤백은 요구사항에서 정한 대로 (로컬 빌드 후 직접 설치, `git revert`) |
| 그 밖 | N/A | 운영 경로에 새 외부 호출 · 저장소 · 배포 구성 없음 |

## 사용법 메모

- 전체 점검: `tool/check.sh` (Kotlin 제외: `--skip-android`)
- 커버리지 검사만: `flutter test --coverage && dart tool/coverage_gate.dart`
- 대상 파일이나 기준값을 바꾸려면 `tool/coverage_gate.dart` 위쪽의 상수 `coverageTargets`, `coverageThresholdPercent` 를 고친다
- 테스트가 고정 뒤에 바뀌었는지 확인: `git diff --exit-code 7d9ad11 -- test/tool`
