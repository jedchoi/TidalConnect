# NFR Requirements 계획 - ci-quality-gate

**이 unit 의 NFR 이란**: 앱의 품질 속성이 아니라 **점검 도구의 품질** 이다. 커버리지 검사 스크립트 (`CoverageGate`) 를 무엇으로 쓰고 어떻게 검증할지, 로컬 점검 (`tool/check.sh`) 과 CI (`check.yml`) 가 같은 내용을 유지하는지, CI 가 올리는 APK 에 무엇이 들어가는지를 정한다. Functional Design 은 건너뛰었으므로 (unit 계획 Q3=A) `unit-of-work.md` 의 Unit 3 과 FR-09 · NFR-01 · NFR-02 를 입력으로 삼는다.

## 사전 확인한 사실 (2026-11-17)

| 항목 | 확인 결과 |
| --- | --- |
| 지금의 `tool/check.sh` | `flutter pub get` → 포맷 검사 → `flutter analyze --fatal-infos` → `flutter test --reporter expanded` → Kotlin 단위 테스트 (`--skip-android` 로 생략 가능). 커버리지는 모으지 않는다 |
| 지금의 `check.yml` | `main` 푸시와 PR 마다 실행. JDK 17, Flutter 3.41.7 고정. `flutter build apk --debug --config-only` 로 Gradle 설정만 만든 뒤 `tool/check.sh` 실행. APK 는 만들지 않는다 |
| 커버리지 현재값 | 대상 4개 파일 모두 98% 이상 (unit 1 요약). 기준 80% 와의 여유가 크다 |
| `.gitignore` | `build/` 는 제외되어 있고 `coverage/` 는 없다. `flutter test --coverage` 는 `coverage/lcov.info` 를 만든다 |
| `tool/` | `check.sh` 하나뿐이다. Dart 스크립트나 그 테스트를 둔 선례는 없다 |
| 저장소 공개 범위 | GitHub 공개 (public) 저장소다. workflow 산출물은 로그인한 누구나 받을 수 있다 |
| TIDAL 키 | `--dart-define` 으로 빌드 때 넣는다 (`TidalConfig`). `config/tidal.json` 은 git 에서 제외. 키 없이 만든 debug APK 는 시작할 때 assert 로 멈춘다 (CLAUDE.md) |
| 로컬 Java | 개발 Mac 의 셸에는 Java 가 PATH 에 없어, `tool/check.sh` 의 Kotlin 단계가 `JAVA_HOME` 을 지정해야 실행된다 (unit 2 에서 확인). CI 는 `setup-java` 가 잡아 준다 |
| 프록시 테스트 간헐 실패 | Kotlin 프록시 테스트 1개가 연속 반복에서 가끔 실패한다 (약 135회 중 4회, 원인 미확인, 사용자가 수용). CI 에서도 가끔 실패할 수 있고 다시 실행하면 통과한다. 이 unit 에서는 다루지 않는다 |

## 실행 단계

- [x] 1. 입력 읽기: `unit-of-work.md` Unit 3, FR-09, NFR-01, NFR-02, 지금의 `check.sh` · `check.yml`
- [x] 2. 아래 질문에 대한 답변 수집 · 모호성 분석
- [x] 3. `aidlc-docs/construction/ci-quality-gate/nfr-requirements/nfr-requirements.md` 생성
  - [ ] 3.1 FR-09 · NFR-01 (검사 자동화) · NFR-02 를 측정 기준과 함께 구체화
  - [ ] 3.2 로컬과 CI 의 점검 내용 일치, 실행 시간, 실패 메시지의 요구
  - [ ] 3.3 범주별 평가와 해당 없음 근거, 확장 규칙 (PBT, Resiliency) 에서 나오는 요구
- [x] 4. `aidlc-docs/construction/ci-quality-gate/nfr-requirements/tech-stack-decisions.md` 생성: 결정마다 선택 · 근거 · 버리는 대안
- [x] 5. 검증: 배정된 요구사항이 모두 문서에 있는지, 결정마다 근거가 있는지

## 앞 unit 에서 이어받는 결정

- 커버리지 기준은 Dart 대상 4개 파일 각각 라인 커버리지 80% 이상이다 (NFR-01). 전체 평균 기준은 두지 않는다
- 로컬 `tool/check.sh` 와 CI 의 점검 내용을 같게 유지한다 (FR-09)
- 테스트 · 문서 · 스크립트에 실제 키를 넣지 않는다
- 속성 테스트를 쓰면 seed 는 고정 (20261117), `PBT_SEED` 로 바꿀 수 있게 한다

## 질문

각 질문의 `[Answer]:` 뒤에 선택지 문자를 적어 주세요.

## Question 1 (기술 스택 선택)
커버리지 검사 스크립트 (`CoverageGate`) 를 무엇으로 쓸까요? 하는 일은 `coverage/lcov.info` 를 읽어 대상 4개 파일의 라인 커버리지를 계산하고, 80% 미만이거나 파일이 lcov 에 없으면 실패하는 것입니다.

A) Dart 스크립트 (`tool/coverage_gate.dart`, `dart run` 으로 실행) - 프로젝트의 언어와 같고 새 도구가 필요 없다. lcov 해석 부분을 `test/` 의 테스트로 검증할 수 있고, 이미 있는 `kiri_check` 로 속성 테스트도 쓸 수 있다 (권장)

B) 셸 스크립트 (`tool/check.sh` 안의 `awk`) - 파일이 늘지 않는다. 해석 로직을 자동 테스트하기 어렵고, macOS 와 Linux 의 `awk` 차이를 신경 써야 한다

C) Python 스크립트 - 쓰기 쉽다. 프로젝트에 Python 이 없어 CI 와 로컬 양쪽에 Python 을 전제로 두게 된다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 2 (유지보수성 · PBT)
Question 1 이 A 일 때, lcov 해석 로직을 어떻게 검증할까요? (확장 규칙 PBT 는 "전체 강제" 로 켜져 있습니다. 해석과 비율 계산은 순수 함수라 속성 테스트의 대상이 됩니다)

A) 예시 기반 테스트 + 속성 테스트 - 예시: 정상 파일, 대상 파일 없음, 80% 경계, 빈 파일, 깨진 줄. 속성: 어떤 줄 실행 기록이든 계산한 비율이 직접 센 값과 같다, 대상이 아닌 파일의 기록은 결과에 영향을 주지 않는다 (권장)

B) 예시 기반 테스트만 - 로직이 수십 줄이라 예시로 충분하다고 본다. PBT 규칙은 이 unit 에서 "해당 없음" 으로 기록한다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 3 (유지보수성)
검사 대상 파일 목록과 기준값 (80%) 을 어디에 둘까요?

A) 스크립트 안의 상수 - 대상 4개와 기준값이 한 파일에 보인다. 바꿀 때 스크립트를 고친다 (권장)

B) 따로 둔 설정 파일 (예: `tool/coverage_targets.txt`) - 대상을 늘릴 때 스크립트를 건드리지 않는다. 파일이 하나 더 생긴다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 4 (보안 · 기술 스택 선택)
CI 가 올리는 debug APK 에 TIDAL 키를 넣을까요? 이 저장소는 공개 저장소라 workflow 산출물을 로그인한 누구나 받을 수 있습니다.

A) 키 없이 빌드 - APK 는 "빌드가 되는지" 의 확인용이다. 설치하면 시작할 때 assert 로 멈춘다. 폰에 설치할 APK 는 지금처럼 로컬에서 `--dart-define-from-file=config/tidal.json` 으로 만든다. 산출물 이름과 문서에 "키 없음, 실행 불가" 를 적는다 (권장)

B) GitHub Secret 으로 키를 넣어 빌드 - 산출물을 받아 바로 설치할 수 있다. 공개 저장소의 산출물에 클라이언트 ID · 시크릿이 들어가므로 누구나 APK 에서 꺼낼 수 있다

C) APK 를 올리지 않고 빌드만 확인 - FR-09 의 "산출물 업로드" 를 빼는 것이므로 요구사항을 고쳐야 한다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 5 (성능 · 기술 스택 선택)
APK 빌드와 업로드를 언제 실행할까요? (debug APK 빌드는 CI 에서 수 분이 더 걸리고, 산출물은 약 230MB 입니다)

A) 점검과 같은 조건 (`main` 푸시와 PR 마다), 점검이 통과한 뒤에 - PR 에서도 빌드가 깨지는지 바로 안다. 매번 수 분이 더 걸린다 (권장)

B) `main` 푸시에서만 - PR 은 빠르다. 빌드가 깨진 것을 병합한 뒤에야 안다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 6 (신뢰성)
올린 APK 산출물을 며칠 보관할까요? (GitHub 기본값은 90일입니다)

A) 14일 - 최근 빌드 확인에는 충분하고 저장 공간을 덜 쓴다 (권장)

B) 90일 (기본값 그대로)

C) 7일

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 7 (사용성)
`tool/check.sh` 가 Java 를 스스로 찾게 할까요? 지금은 개발 Mac 의 셸에 Java 가 PATH 에 없어, `JAVA_HOME` 을 지정하지 않으면 Kotlin 단계가 "Unable to locate a Java Runtime" 으로 실패합니다.

A) 찾게 한다 - `JAVA_HOME` 이 없고 `java` 도 PATH 에 없으면 macOS 의 `/usr/libexec/java_home -v 17` 과 Homebrew `openjdk@17` 순서로 찾아 쓰고, 못 찾으면 무엇을 설치 · 지정해야 하는지 알려 주고 실패한다. 이미 지정되어 있으면 건드리지 않는다. CI 의 동작은 그대로다 (권장)

B) 그대로 둔다 - `CLAUDE.md` 의 Commands 절에 `JAVA_HOME` 을 지정하라는 안내만 더한다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 8 (사용성 · 유지보수성)
커버리지 검사가 실패하거나 통과했을 때 무엇을 출력할까요?

A) 대상 4개 파일의 표 (파일, 실행된 줄 / 전체 줄, 비율, 통과 여부) 를 항상 출력하고, 실패하면 기준에 못 미친 파일과 모자란 줄 수를 덧붙인다 (권장)

B) 통과하면 한 줄, 실패하면 못 미친 파일만 출력한다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)
