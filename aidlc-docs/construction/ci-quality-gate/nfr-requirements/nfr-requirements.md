# NFR 요구사항 (NFR Requirements) - ci-quality-gate

이 unit 은 커버리지 검사 스크립트 (`CoverageGate`) 를 만들고 `tool/check.sh` 와 `.github/workflows/check.yml` 을 고친다. 아래 요구는 **점검 도구의 품질** 에 대한 것이다. 앱의 실행 성능 · 가용성 요구는 이 unit 에 없다.

ID 는 `requirements.md` 의 번호를 잇는다 (`NFR-01-C1` = NFR-01 을 이 unit 에서 구체화한 첫 항목. unit 1 의 `-D`, unit 2 의 `-A` 와 구분해 `-C` 를 쓴다). 근거의 Q 번호는 `plans/ci-quality-gate-nfr-requirements-plan.md` 의 질문이다.

## 1. 배정된 요구사항의 구체화

### NFR-01 커버리지 (검사 자동화)

| ID | 요구 | 측정 |
| --- | --- | --- |
| NFR-01-C1 | `CoverageGate` 는 `coverage/lcov.info` 에서 대상 4개 파일 (`lib/features/player/data/backends/phone_backend.dart`, `lib/features/player/data/backends/dlna_backend.dart`, `lib/features/dlna/data/dlna_manager.dart`, `lib/features/player/data/wave_audio_handler.dart`) 의 라인 커버리지를 각각 계산한다 | 예시 기반 테스트 |
| NFR-01-C2 | 대상 파일 하나라도 80% 미만이면 종료 코드가 0 이 아니다. 정확히 80% 는 통과다 | 경계값 테스트 (79.9%, 80%, 80.1%) |
| NFR-01-C3 | 대상 파일이 lcov 에 없거나 실행 가능한 줄이 0 이면 실패다 (파일을 옮기거나 지워서 검사를 피해 가는 것을 막는다) | 예시 기반 테스트 |
| NFR-01-C4 | `lcov.info` 가 없거나 읽을 수 없으면 실패하고, 먼저 `flutter test --coverage` 를 실행하라는 안내를 출력한다 | 예시 기반 테스트 |
| NFR-01-C5 | 대상이 아닌 파일의 커버리지는 결과에 영향을 주지 않는다. 전체 평균 기준은 두지 않는다 | 속성 테스트 |
| NFR-01-C6 | 대상 목록과 기준값 (80) 은 스크립트 안의 상수로 한곳에 둔다 (Q3=A) | 코드 검토 |
| NFR-01-C7 | 지금의 코드에서 검사가 통과한다 (대상 4개 모두 98% 이상) | `tool/check.sh` 실행 |

### FR-09 CI 와 로컬 점검

| ID | 요구 | 측정 |
| --- | --- | --- |
| FR-09-C1 | `tool/check.sh` 의 Dart 테스트 단계가 커버리지를 함께 모으고 (`flutter test --coverage`), 이어서 `CoverageGate` 를 실행한다. 테스트를 두 번 실행하지 않는다 | 스크립트 검토, 실행 로그 |
| FR-09-C2 | CI 는 커버리지 검사를 따로 구현하지 않고 `tool/check.sh` 를 그대로 실행한다. 로컬과 CI 의 점검 내용이 같다 | `check.yml` 검토 |
| FR-09-C3 | CI 는 점검이 통과한 뒤 debug APK 를 빌드해 workflow 산출물로 올린다. 실행 조건은 점검과 같다 (`main` 푸시와 PR 마다, Q5=A). 점검이 실패하면 빌드 · 업로드를 하지 않는다 | `check.yml` 검토, 실제 workflow 실행 |
| FR-09-C4 | CI 의 APK 는 TIDAL 키 없이 빌드한다 (Q4=A). 저장소에 키용 Secret 을 만들지 않는다. 산출물 이름에 실행할 수 없는 빌드임이 드러나야 하고 (예: `app-debug-nokeys`), `README.md` 에 "빌드 확인용, 설치하면 시작할 때 멈춘다, 설치용은 로컬에서 만든다" 를 적는다 | `check.yml` · 문서 검토 |
| FR-09-C5 | 산출물 보관 기간은 14일이다 (Q6=A) | `check.yml` 의 `retention-days` |
| FR-09-C6 | `--skip-android` 는 지금처럼 Kotlin 단계만 건너뛴다. 커버리지 검사는 건너뛰지 않는다 | 실행 |
| FR-09-C7 | `coverage/` 를 `.gitignore` 에 넣는다 | `git status` |
| FR-09-C8 | 명령이 바뀐 부분을 `CLAUDE.md` 의 Commands 절과 `README.md` 에 반영한다 | 문서 검토 |

### NFR-02 점검 통과

| ID | 요구 | 측정 |
| --- | --- | --- |
| NFR-02-C1 | 고친 `tool/check.sh` 전체가 로컬에서 통과한다 (포맷, 분석, Dart 테스트 + 커버리지 검사, Kotlin 테스트) | 종료 코드 0 |
| NFR-02-C2 | 기존 테스트 (Dart 262개, Kotlin 86개) 를 고치지 않는다. 새 테스트는 `CoverageGate` 의 것만 더한다 | `git diff --stat` |
| NFR-02-C3 | 새 Dart 파일 (`tool/`, 그 테스트) 도 포맷 검사와 `flutter analyze --fatal-infos` 를 통과한다. 포맷 검사 대상에 `tool` 을 더한다 | `tool/check.sh` |
| NFR-02-C4 | 고친 `check.yml` 이 문법에 맞다. 실제 workflow 실행은 푸시해야 확인되므로, 푸시 전에는 로컬에서 같은 명령 (`flutter build apk --debug`) 을 키 없이 실행해 확인하고 "CI 실행은 확인하지 못함" 을 요약에 적는다 | 로컬 실행, 요약 문서 |

## 2. 점검 도구의 품질 (이 unit 고유)

| ID | 요구 | 근거 · 측정 |
| --- | --- | --- |
| NFR-07-C1 | `CoverageGate` 는 대상 4개 파일의 표 (파일, 실행된 줄 / 전체 줄, 비율, 통과 여부) 를 항상 출력한다. 실패하면 기준에 못 미친 파일과 모자란 줄 수를 덧붙인다 (Q8=A) | 출력을 검증하는 테스트 |
| NFR-07-C2 | 해석과 판정은 파일 · 프로세스에 의존하지 않는 순수 함수로 두고, 파일 읽기 · 출력 · 종료 코드는 `main` 에만 둔다 | 테스트가 문자열 입력만으로 판정을 검증 |
| NFR-07-C3 | lcov 의 줄 가운데 쓰는 것은 `SF:` (파일), `DA:<줄>,<횟수>` (줄 실행 기록), `end_of_record` 다. 그 밖의 줄과 해석할 수 없는 줄은 무시한다. 같은 파일의 기록이 여러 번 나오면 줄 번호별로 합친다 (한 번이라도 실행되면 실행된 줄) | 예시 기반 테스트 |
| NFR-07-C4 | 경로 비교는 저장소 루트 기준 상대 경로로 한다. lcov 의 `SF:` 가 절대 경로이거나 `\` 구분자여도 같은 파일로 본다 | 예시 기반 테스트 |
| NFR-07-C5 | 커버리지 수집으로 늘어나는 `tool/check.sh` 의 시간은 10초 이하다 (지금 Dart 테스트 약 6 ~ 9초) | 고치기 전후 3회 측정 |
| NFR-07-C6 | `tool/check.sh` 는 `JAVA_HOME` 이 없고 `java` 도 PATH 에 없을 때 macOS 의 `/usr/libexec/java_home -v 17`, Homebrew `openjdk@17` 순서로 JDK 를 찾아 쓴다. 못 찾으면 무엇을 설치 · 지정해야 하는지 알려 주고 실패한다. 이미 지정되어 있으면 건드리지 않는다. CI 의 동작은 그대로다 (Q7=A) | `JAVA_HOME` 을 지운 셸에서 실행 |
| NFR-07-C7 | 스크립트 · workflow · 문서에 키 값을 넣지 않는다 | 검색 |

## 3. 범주별 평가

| 범주 | 평가 |
| --- | --- |
| 확장성 | 해당 없음. 대상 파일 4개, lcov 는 수백 KB |
| 성능 | 점검 시간만 해당 (NFR-07-C5). CI 는 APK 빌드로 수 분이 늘어난다 (Q5=A 로 수용) |
| 가용성 | 해당 없음. 서버가 없다 |
| 보안 | 공개 저장소의 산출물에 키를 넣지 않는다 (FR-09-C4, NFR-07-C7). 확장 규칙 Security 는 꺼져 있다 |
| 신뢰성 | 검사가 조용히 통과하는 경우를 막는다: 대상 파일이 lcov 에 없음 · lcov 없음은 실패 (NFR-01-C3, C4). Kotlin 프록시 테스트의 간헐 실패 (unit 2 요약) 는 이 unit 에서 다루지 않는다. CI 가 그 때문에 실패하면 다시 실행한다 |
| 유지보수성 | 판정 로직을 순수 함수로 두고 테스트한다 (NFR-07-C2). 대상 · 기준값은 한곳 (NFR-01-C6) |
| 사용성 | 실패 메시지가 무엇을 고쳐야 하는지 알려 준다 (NFR-01-C4, NFR-07-C1, C6) |

## 4. 확장 규칙에서 나오는 요구

### Property-Based Testing (전체 강제, Q2=A)

| 규칙 | 이 unit 의 적용 |
| --- | --- |
| PBT-01 | 속성 후보: lcov 해석 · 비율 계산 · 판정. Functional Design 을 건너뛰었으므로 속성은 Code Generation 계획에서 정한다 |
| PBT-03 | 어떤 줄 실행 기록이든 계산한 실행 줄 수 · 전체 줄 수가 직접 센 값과 같다. 대상이 아닌 파일의 기록을 더해도 결과가 같다. 판정은 "모든 대상이 80% 이상" 과 같다 |
| PBT-02 | 실행 기록 → lcov 문자열 → 해석의 왕복 (생성기가 만든 기록과 해석 결과가 같다) |
| PBT-04 · 05 · 06 | 해당 없음. 멱등 연산 · 참조 구현 · 상태가 없다 (PBT-03 의 "직접 센 값" 이 오라클 역할을 겸한다) |
| PBT-07 | lcov 내용 생성기를 `test/helpers/generators.dart` 에 더하거나 새 테스트 파일 안에 둔다 (계획에서 정함) |
| PBT-08 | `test/helpers/pbt_config.dart` 의 고정 seed (20261117) 와 `PBT_SEED` 를 그대로 쓴다. 일반 `flutter test` 에 포함된다 |
| PBT-09 | `kiri_check` (이미 `dev_dependencies` 에 있음). 새 의존성 없음 |
| PBT-10 | 예시 기반 테스트 (정상, 대상 없음, 경계, 빈 파일, 깨진 줄) 와 병행 |

### Resiliency

| 규칙 | 이 unit 의 적용 |
| --- | --- |
| RESILIENCY-04 (CI/CD) | 기존 GitHub Actions 에 커버리지 검사와 APK 빌드 · 업로드를 더한다 (FR-09). 배포는 지금처럼 로컬 빌드 후 직접 설치이고, 롤백은 `git revert` 후 다시 빌드다 (요구사항 2차 Q3=B) |
| 그 밖 | 해당 없음. 운영 경로에 새 외부 호출 · 저장소 · 배포 구성이 없다 |

## 5. 배정 요구사항 대조 (NR-1)

| 배정 (`unit-of-work.md`) | 이 문서 |
| --- | --- |
| FR-09 커버리지 검사 단계 | NFR-01-C1 ~ C7, FR-09-C1, C2, C6 |
| FR-09 APK 빌드 · 업로드 | FR-09-C3 ~ C5 |
| FR-09 로컬과 CI 의 일치 | FR-09-C2 |
| NFR-01 (검사 자동화) | NFR-01-C1 ~ C7 |
| NFR-02 | NFR-02-C1 ~ C4 |
| 포함 파일: `.gitignore`, 문서 | FR-09-C7, C8 |
