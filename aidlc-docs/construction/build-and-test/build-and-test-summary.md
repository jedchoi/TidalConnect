# 빌드 및 테스트 요약 (Build and Test Summary)

실행일: 2026-11-17. 브랜치 `aidlc/test-reinforcement` (푸시하지 않음).

## 빌드 상태 (Build Status)

- **빌드 도구 (Build Tool)**: Flutter 3.41.7, Gradle 8.14, JDK 17 (OpenJDK 17.0.20)
- **빌드 상태 (Build Status)**: Success
- **빌드 산출물 (Build Artifacts)**: `build/app/outputs/flutter-apk/app-debug.apk` (약 228MB). 키를 넣은 빌드와 키 없는 빌드 모두 성공
- **빌드 시간 (Build Time)**: 약 17초 (Gradle 캐시가 있는 상태)

## 테스트 실행 요약 (Test Execution Summary)

### 단위 테스트 (Unit Tests)

`tool/check.sh` 전체 실행 (약 31초, `JAVA_HOME` 없이).

| 구분 | 전체 | 통과 | 실패 |
| --- | --- | --- | --- |
| Dart (`flutter test --coverage`) | 284 | 284 | 0 |
| Kotlin (`:app:testDebugUnitTest`) | 86 | 86 | 0 |
| 합계 | 370 | 370 | 0 |

- 작업 전: Dart 95개, Kotlin 4개. 이번 작업으로 271개가 늘었다 (Dart 189, Kotlin 82)
- **커버리지 (Coverage)**: 대상 4개 파일 100.0% / 99.4% / 99.2% / 98.7% (기준 각 80%). 작업 전에는 0% / 0% / 15.4% / 기록 없음
- 포맷 검사와 `flutter analyze --fatal-infos` 통과
- **상태 (Status)**: Pass

### 통합 테스트 (Integration Tests)

- **테스트 시나리오 (Test Scenarios)**: 3 (`integration-test-instructions.md`)
- 시나리오 3 (커버리지 → 검사 → 점검 스크립트): 로컬에서 Pass. CI 에서의 실행은 확인하지 못함
- 시나리오 1 · 2 (채널 왕복, 실제 렌더러): **실행하지 않음.** 실기기가 필요하고, 요구사항에서 실기기 확인을 완료 기준 밖으로 정했다. 양쪽 unit 의 자동 테스트와 계약 대조표로만 확인했다
- **상태 (Status)**: 자동으로 확인할 수 있는 범위는 Pass, 실기기 범위는 미실행

### 성능 테스트 (Performance Tests)

- **상태 (Status)**: N/A. 서버가 없는 개인용 앱이고 성능 요구가 없다. 테스트 실행 시간만 기준이 있었다: 새 Dart 테스트로 늘어난 시간 1 ~ 4초, 새 Kotlin 테스트 약 2.6초, 커버리지 수집으로 늘어난 시간 4 ~ 5초 (모두 기준 안)

### 추가 테스트 (Additional Tests)

- **계약 테스트 (Contract Tests)**: N/A (서비스가 하나다). 채널 계약은 통합 시나리오 1 로 다룬다
- **보안 테스트 (Security Tests)**: N/A (확장 규칙 Security 를 끔). 테스트 · 문서 · 스크립트 · workflow 에 TIDAL 키 값이 없음을 검색으로 확인했다. CI 산출물에는 키를 넣지 않는다
- **E2E 테스트 (E2E Tests)**: 자동 테스트 없음. 사람이 하는 점검은 통합 시나리오 1 · 2 와 `docs/failure-scenarios.md`

## 알려진 문제

| 문제 | 영향 | 상태 |
| --- | --- | --- |
| Kotlin 프록시 테스트의 간헐 실패 (약 135회 중 4회, DASH 길이 계산 경로의 2초 제한 시간 초과) | `tool/check.sh` 와 CI 가 가끔 실패할 수 있다. 다시 실행하면 통과한다. 원인이 운영 코드에 있는지는 확인하지 못했다 | 사용자가 수용 (2026-11-17). 조사 방법은 unit 2 요약에 있다 |
| 실기기 확인 없음 | `PlaybackCore.onMethodCall` 의 위임 (`56d7bfe`) 과 HEAD 응답 변경 (`8e5b417`) 이 실제 동작 경로를 바꾼다 | 통합 시나리오 1 · 2 로 확인 필요 |
| CI workflow 의 실제 실행 미확인 | 새 step 두 개 (APK 빌드, 산출물 업로드) | 푸시 뒤 첫 실행에서 확인 |
| 살아남은 변형 4개 (router 2, 검사 스크립트 2) | 테스트가 잡지 못하는 잘못이 있다. 모두 실제 입력 범위 밖이거나 지금 결과에 영향이 없는 경우다 | 테스트를 더하려면 RED 로 돌아가 다시 고정한다 |
| `6acf424` ~ `8e5b417` 앞, `7d9ad11` ~ `168f2f0` 앞의 커밋은 테스트가 실패하는 상태 | `git bisect` 를 쓸 때 주의 | RED 를 커밋으로 고정한 결과 |

## 전체 상태 (Overall Status)

- **빌드 (Build)**: Success
- **전체 테스트 (All Tests)**: Pass (자동 테스트 370개). 실기기 통합 시나리오는 미실행
- **Operations 준비 (Ready for Operations)**: 해당 없음. 실행 계획에서 Operations 7 stage 가 모두 SKIP 이다

## 다음 단계 (Next Steps)

실행 계획의 Operations stage 가 모두 SKIP 이므로 이 stage 가 승인되면 workflow 가 끝난다. 그 뒤에 할 일:

1. 추적성 점검: `/traceability-check construction`
2. 실기기 확인 (통합 시나리오 1 · 2)
3. 푸시와 PR. 첫 CI 실행에서 새 step 을 확인한다
