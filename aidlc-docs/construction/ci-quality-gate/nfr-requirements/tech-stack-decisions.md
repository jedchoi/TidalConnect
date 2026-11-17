# 기술 스택 결정 (Tech Stack Decisions) - ci-quality-gate

질문은 `plans/ci-quality-gate-nfr-requirements-plan.md` 에 있다. 답은 모두 권장안 (A) 이다 (사용자 지시 "추천으로 진행해줘", 2026-11-17).

## 결정 요약

| # | 결정 | 선택 | 근거 질문 |
| --- | --- | --- | --- |
| C1 | `CoverageGate` 의 언어 | Dart 스크립트 `tool/coverage_gate.dart` | Q1=A |
| C2 | 검증 방법 | 예시 기반 테스트 + 속성 테스트 (`kiri_check`) | Q2=A |
| C3 | 대상 · 기준값의 위치 | 스크립트 안의 상수 | Q3=A |
| C4 | CI APK 의 키 | 넣지 않는다 | Q4=A |
| C5 | APK 빌드 실행 조건 | 점검과 같은 조건, 점검 통과 뒤 | Q5=A |
| C6 | 산출물 보관 | 14일 | Q6=A |
| C7 | 로컬 JDK 탐색 | `tool/check.sh` 가 찾는다 | Q7=A |
| C8 | 검사 출력 | 대상 4개의 표를 항상 출력 | Q8=A |
| C9 | 커버리지 수집 | `flutter test --coverage` (기존 테스트 단계를 바꿈) | NFR-01 |
| C10 | 산출물 업로드 | `actions/upload-artifact` | FR-09 |

## C1. `CoverageGate`: Dart 스크립트

- 위치: `tool/coverage_gate.dart`. 실행: `dart run tool/coverage_gate.dart` (인자 없으면 `coverage/lcov.info`)
- 근거: 프로젝트의 언어와 같아 새 도구가 필요 없다. `dart:io` 만 쓰므로 Flutter 없이 실행된다. 판정 함수를 `test/` 에서 import 해 검증할 수 있다
- 버리는 대안
  - 셸 (`awk`): 해석 로직을 자동 테스트하기 어렵고 macOS 와 Linux 의 `awk` 가 다르다
  - Python: 로컬과 CI 양쪽에 Python 을 전제로 두게 된다
  - `lcov` · `genhtml` 같은 외부 도구: 설치가 필요하고, 파일별 기준 판정은 어차피 따로 써야 한다
- 테스트 위치: `test/tool/coverage_gate_test.dart`. `tool/` 은 패키지 밖이라 상대 경로로 import 한다
- 포맷 검사 대상에 `tool` 을 더한다 (`dart format ... lib test tool`). `flutter analyze` 는 이미 저장소 전체를 본다

## C2. 검증: 예시 + 속성

- `kiri_check` 를 그대로 쓴다. 새 의존성 없음. seed 는 `test/helpers/pbt_config.dart`
- 속성과 생성기의 구체적인 목록은 Code Generation 계획에서 정한다 (Functional Design 을 건너뛴 unit)
- 버리는 대안: 예시만. 확장 규칙 PBT 가 전체 강제이고 해석 · 계산이 순수 함수라 뺄 이유가 없다

## C3. 대상 · 기준값: 스크립트 안의 상수

- 대상 4개의 경로와 `80` 을 스크립트 맨 위의 상수로 둔다
- 버리는 대안: 설정 파일. 대상이 4개로 고정이고 바꿀 일이 드물어 파일을 늘릴 이유가 없다

## C4. CI APK: 키 없음

- 이 저장소는 공개 저장소라 workflow 산출물을 로그인한 누구나 받을 수 있다. 키를 넣어 빌드하면 APK 에서 클라이언트 ID · 시크릿을 꺼낼 수 있다
- CI 의 APK 는 "빌드가 되는지" 의 확인용이다. 설치하면 시작할 때 assert 로 멈춘다
- 산출물 이름을 `app-debug-nokeys` 로 해 받는 사람이 알 수 있게 한다
- 설치용 APK 는 지금처럼 로컬에서 `--dart-define-from-file=config/tidal.json` 으로 만든다
- 버리는 대안: GitHub Secret 으로 키 주입 (키 노출), 업로드 생략 (FR-09 와 어긋남)

## C5 · C6. 빌드 조건과 보관

- `check.yml` 의 같은 job 에서 "점검" step 뒤에 "APK 빌드", "산출물 업로드" step 을 둔다. 앞 step 이 실패하면 뒤 step 은 실행되지 않는다 (GitHub Actions 기본 동작)
- 같은 job 에 두는 이유: Flutter · Gradle 준비를 다시 하지 않는다
- `retention-days: 14`
- 버리는 대안: `main` 푸시에서만 빌드 (PR 에서 빌드 깨짐을 모른다), 기본 90일 (약 230MB 가 오래 남는다)

## C7. 로컬 JDK 탐색

- `tool/check.sh` 의 Kotlin 단계 앞에서: `JAVA_HOME` 이 비어 있고 `java -version` 이 실패하면 `/usr/libexec/java_home -v 17` → `/opt/homebrew/opt/openjdk@17` 순서로 찾아 `JAVA_HOME` 을 그 실행 안에서만 지정한다
- macOS 의 `/usr/bin/java` 는 JDK 가 없어도 존재하는 대역 (stub) 이라 `command -v java` 만으로는 판단할 수 없다. 실제로 실행해 본다
- 못 찾으면 "JDK 17 이 필요하다, `JAVA_HOME` 을 지정하거나 `brew install openjdk@17`" 을 출력하고 실패한다
- CI (Linux, `setup-java`) 에서는 `JAVA_HOME` 이 이미 있어 이 분기를 타지 않는다
- 버리는 대안: 문서 안내만. 매번 손으로 지정해야 한다

## C8. 검사 출력

- 항상 표를 출력한다. CI 로그에서 지금 수치를 바로 볼 수 있다
- 실패 시 기준에 못 미친 파일과 모자란 줄 수를 덧붙인다
- 색 코드는 `check.sh` 의 `step` 함수가 내는 단계 제목에만 쓰고 스크립트 출력에는 쓰지 않는다 (테스트로 출력을 비교하기 쉽게)

## C9. 커버리지 수집

- `flutter test --reporter expanded` 를 `flutter test --coverage --reporter expanded` 로 바꾼다. 테스트는 한 번만 실행한다
- 결과는 `coverage/lcov.info`. `coverage/` 를 `.gitignore` 에 넣는다
- 버리는 대안: 커버리지 실행을 따로 두기 (테스트를 두 번 실행)

## C10. 산출물 업로드

- `actions/upload-artifact` 를 쓴다. 버전은 `check.yml` 의 다른 action (`checkout@v5`, `setup-java@v5`) 과 같은 방식으로 주 버전 태그로 적는다. 어느 주 버전을 쓸지는 Code Generation 에서 지금 배포된 최신을 확인해 정한다
- 업로드 대상: `build/app/outputs/flutter-apk/app-debug.apk`. 파일이 없으면 실패하게 한다 (`if-no-files-found: error`)
