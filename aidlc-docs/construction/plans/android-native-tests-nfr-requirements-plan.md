# NFR Requirements 계획 - android-native-tests

**이 unit 의 NFR 이란**: unit 1 과 같이 **테스트의 품질** (결정성, 실행 시간, 재현성, 유지보수성) 과 **테스트 도구 선택** 이다. 여기에 이 unit 고유의 요구가 하나 더 있다: `PlaybackCore` 를 재구성한 뒤에도 앱이 빌드되고 채널 계약이 그대로여야 한다.

## 사전 확인한 사실 (2026-11-17)

| 항목 | 확인 결과 |
| --- | --- |
| 빌드 환경 | Kotlin 2.1.0, Android Gradle Plugin 8.11.1, Gradle 8.14 (`android/settings.gradle.kts`, wrapper) |
| JDK | 이 셸에는 Java 가 PATH 에 없어 `./gradlew` 가 바로 실행되지 않는다. 설치된 JDK 는 Homebrew `openjdk@17` 과 Android Studio 내장 JDK 21. CI 는 JDK 17 (`check.yml`). 이 작업의 Kotlin 테스트는 `JAVA_HOME=/opt/homebrew/opt/openjdk@17` 로 실행한다 |
| 기존 Kotlin 테스트 | `DashManifestTest` 4개 통과 (JUnit 4.13.2). Gradle 시작을 포함해 약 40초, 다시 실행하면 약 8초 |
| `android.util.Log` | 단위 테스트 설정 `unitTests.isReturnDefaultValues = true` 를 넣으면 JVM 테스트에서 예외 없이 동작함 (탐침 테스트로 확인) |
| Flutter 타입 | `MethodCall`, `MethodChannel.Result` 를 JVM 단위 테스트에서 쓸 수 있음 (탐침 테스트로 확인). `PlaybackCore` 경계의 변환 (PC-01 ~ PC-03) 을 테스트할 수 있다 |
| `kotest-property` 6.2.7 | 최신 (2026-11-11 배포). JUnit 4 테스트 안에서 `runBlocking { checkAll(...) }` 로 실행됨, seed 지정 동작 (탐침 테스트로 확인). 이 버전은 Kotlin 표준 라이브러리 2.2.21 을 요구한다. 프로젝트의 Kotlin 은 2.1.0 이라 테스트 실행 경로에만 더 새 표준 라이브러리가 들어온다 (앱에는 들어가지 않음) |
| `kotest-property` 5.9.1 | 5.x 의 마지막 버전 (2024-06-06 배포). 같은 방식으로 실행됨 (탐침 테스트로 확인). 표준 라이브러리를 올리지 않는다 |
| `mockwebserver` 4.12.0 | 앱이 쓰는 OkHttp 4.12.0 과 같은 버전. 루프백에서 동작, 프록시 서버도 `127.0.0.1` 에 바인딩됨 (탐침 테스트로 확인) |
| `jqwik` | 최신 1.10.2. JUnit 5 플랫폼 엔진이라 실행기 설정을 바꿔야 한다. 탐침으로 확인하지 않았다 |

탐침 테스트와 임시 Gradle 변경은 확인 뒤 모두 되돌렸다 (`git status` 깨끗함).

## 실행 단계

- [x] 1. Functional Design 산출물 읽기 (규칙 58개, 속성 12개, 생성기 범위)
- [x] 2. 빌드 환경과 도구 후보를 탐침 테스트로 확인 (위 표)
- [x] 3. 아래 질문에 대한 답변 수집 · 모호성 분석
- [x] 4. `aidlc-docs/construction/android-native-tests/nfr-requirements/nfr-requirements.md` 생성
  - [x] 4.1 이 unit 에 배정된 NFR-01 (Kotlin 부분) · NFR-02 · NFR-03 · NFR-04 (Kotlin) 를 측정 기준과 함께 구체화
  - [x] 4.2 재구성 안전성 요구 (빌드 성공, 채널 계약 불변, 기존 테스트 유지)
  - [x] 4.3 범주별 평가와 해당 없음 근거, 확장 규칙에서 나오는 요구
- [x] 5. `aidlc-docs/construction/android-native-tests/nfr-requirements/tech-stack-decisions.md` 생성: 결정마다 선택 · 근거 · 버리는 대안
- [x] 6. 검증: 배정된 NFR 이 모두 문서에 있는지, 결정마다 근거가 있는지

## unit 1 에서 이어받는 결정

- 속성 테스트의 seed 는 고정값을 쓰고 환경 변수 `PBT_SEED` 로 바꿀 수 있게 한다 (unit 1 NFR Requirements Q2=A). 값도 같은 20261117 을 쓴다
- 테스트 데이터에 실제 토큰 · 키 · 서명 주소를 넣지 않는다. 주소는 `127.0.0.1`, 문서용 예약 대역, `.test` 도메인만 쓴다
- fake 는 직접 작성한다 (mock 라이브러리 없음)

## 질문

각 질문의 `[Answer]:` 뒤에 선택지 문자를 적어 주세요.

## Question 1 (기술 스택 선택)
Kotlin 속성 기반 테스트 프레임워크로 무엇을 쓸까요? (PBT-09. A 와 B 는 이 프로젝트에서 실행되는 것을 확인했습니다)

A) `kotest-property` 6.2.7 - 지금 관리되는 버전 (6일 전 배포). 기존 JUnit 4 테스트 방식 그대로 쓴다. 테스트 실행 경로에만 Kotlin 표준 라이브러리 2.2.21 이 들어온다 (프로젝트의 Kotlin 은 2.1.0). 정확한 버전으로 고정한다 (권장)

B) `kotest-property` 5.9.1 - 5.x 의 마지막 버전 (2024-06). 표준 라이브러리를 건드리지 않아 프로젝트의 Kotlin 버전과 어긋나는 점이 없다. 더는 갱신되지 않는다

C) `jqwik` - 상태 기반 테스트 API 가 있다. JUnit 5 엔진이라 Gradle 의 테스트 실행기 설정을 바꾸고 기존 JUnit 4 테스트용 호환 엔진을 추가해야 한다. 이 프로젝트에서 확인하지 않았다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## Question 2 (기술 스택 선택)
프록시 테스트에서 TIDAL CDN 을 대신할 가짜 서버 (`FakeCdnServer`) 를 무엇으로 만들까요?

A) OkHttp `mockwebserver` 4.12.0 - 앱이 쓰는 OkHttp 와 같은 버전의 테스트용 서버. 경로별 응답 지정과 받은 요청 (메서드 · 헤더) 기록 기능이 이미 있다. 테스트 전용 의존성 1개가 추가된다 (권장)

B) NanoHTTPD 로 직접 작성 - 앱이 이미 쓰는 라이브러리라 의존성이 늘지 않는다. 응답 지정 · 요청 기록 · HEAD 처리를 직접 구현해야 한다

X) Other (please describe after [Answer]: tag below)

[Answer]: A (사용자 지시 "추천으로 진행해줘" 에 따라 권장안 기입)

## 질문하지 않은 범주와 이유

- **확장성 · 가용성 · 사용성**: 테스트 코드와 내부 구조 변경에는 해당 없음
- **성능**: 앱 성능 요구 없음. 테스트 실행 시간은 NFR-03 의 30초 기준을 Kotlin 테스트에도 적용한다 (Gradle 시작 시간 제외). 프록시 속성 테스트는 실제 HTTP 를 쓰므로 실행 횟수를 속성별로 정한다
- **보안**: 보안 확장을 쓰지 않는다. 테스트 서버는 루프백에만 바인딩한다
- **`android.util.Log` 처리**: `unitTests.isReturnDefaultValues = true` 로 정한다. 운영 코드에 로그 래퍼를 넣는 대안보다 변경이 작고, 탐침으로 동작을 확인했다
- **`PlaybackCore` 경계의 확인 수단**: Flutter 타입을 테스트에서 쓸 수 있으므로 변환 부분 (PC-01 ~ PC-03) 은 테스트한다. Android 시스템 서비스에 닿는 운영 구현 (PC-04 ~ PC-07) 은 `flutter build apk --debug` 성공과 코드 검토로 확인한다
- **JDK**: 로컬 실행은 `JAVA_HOME` 지정으로 해결된다. `tool/check.sh` 가 Java 를 찾지 못하는 문제를 스크립트에서 다룰지는 `ci-quality-gate` unit 의 범위다
