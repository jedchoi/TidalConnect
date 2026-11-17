# 기술 스택 결정 (Tech Stack Decisions) - android-native-tests

확인 환경: Kotlin 2.1.0, Android Gradle Plugin 8.11.1, Gradle 8.14, JDK 17 (2026-11-17). "탐침으로 확인" 은 임시 테스트를 이 프로젝트에서 실제로 실행해 본 것을 뜻한다 (확인 뒤 되돌림).

## 결정 요약

| # | 대상 | 선택 | `android/app/build.gradle.kts` 변경 |
| --- | --- | --- | --- |
| A1 | 속성 기반 테스트 프레임워크 | `io.kotest:kotest-property:6.2.7` | `testImplementation` 추가 |
| A2 | 가짜 CDN 서버 | `com.squareup.okhttp3:mockwebserver:4.12.0` | `testImplementation` 추가 |
| A3 | JVM 테스트에서의 `android.util.Log` | `unitTests.isReturnDefaultValues = true` | `testOptions` 추가 |
| A4 | 테스트 실행기 · 단언 | JUnit 4.13.2 (기존) | 없음 |
| A5 | 프록시 테스트의 HTTP 클라이언트 | OkHttp 4.12.0 (앱의 기존 의존성) | 없음 |
| A6 | fake 작성 방식 | 직접 작성, mock 라이브러리 없음 | 없음 |
| A7 | seed 관리 | 고정 seed (unit 1 과 같은 값), `PBT_SEED` 환경 변수 | 없음 |
| A8 | 로컬 JDK | JDK 17 을 `JAVA_HOME` 으로 지정 | 없음 |
| A9 | `PlaybackCore` 경계의 확인 | 변환 부분은 테스트, 나머지는 빌드와 코드 검토 | 없음 |

## A1. 속성 기반 테스트 프레임워크: `kotest-property` 6.2.7

- **결정 출처**: NFR Requirements 계획 Q1=A
- **PBT-09 요건 대조**

| 요건 | `kotest-property` | 확인 방법 |
| --- | --- | --- |
| 사용자 정의 생성기 | 지원 (`Arb` 와 `arbitrary { }`, `map`, `filter`, `bind`) | Kotest 의 공개 API |
| 자동 축소 | 지원 (기본 `Arb` 에 축소기가 있고 조합하면 따라온다) | Kotest 의 공개 API. 실패 출력의 축소 결과는 Code Generation 에서 확인한다 |
| seed 재현 | 지원 (`PropTestConfig(seed = ...)`) | 탐침으로 확인 |
| 기존 테스트 실행기 통합 | JUnit 4 테스트 메서드 안에서 `runBlocking { checkAll(...) }` 로 실행 | 탐침으로 확인 (100회 실행됨) |

- **근거**: 지금 관리되는 버전이다 (2026-11-11 배포). Kotest 의 테스트 프레임워크 전체가 아니라 속성 테스트 모듈만 쓰므로 실행기 (JUnit 4) 를 바꾸지 않는다
- **버리는 대안**
  - `kotest-property` 5.9.1: 표준 라이브러리를 건드리지 않지만 2024-06 이후 갱신이 없다
  - `jqwik`: JUnit 5 엔진이라 실행기 설정과 기존 테스트용 호환 엔진이 필요하다. 이 프로젝트에서 확인하지 않았다
- **알려진 부담**
  - 이 버전은 Kotlin 표준 라이브러리 2.2.21 을 요구한다. 프로젝트의 Kotlin 은 2.1.0 이라 **단위 테스트 실행 경로에만** 더 새 표준 라이브러리가 들어온다. 앱 (APK) 에는 들어가지 않는다 (`testImplementation`). 탐침에서는 컴파일과 실행 모두 문제가 없었다
  - Kotest 가 이후 더 새 Kotlin 을 요구하게 되면 프로젝트의 Kotlin 을 올리기 전에는 올릴 수 없다. 버전을 `6.2.7` 로 정확히 고정한다 (범위 지정 없음)
  - `checkAll` 은 `suspend` 함수다. 테스트마다 `runBlocking` 으로 감싼다 (`kotlinx-coroutines` 는 이미 앱의 의존성 경로에 있다)
  - 기본 실행 횟수가 1000회다. 속성마다 횟수를 명시한다 (NFR-04-A12)
- **라이선스**: Apache-2.0 (Kotest 저장소의 표기. 패키지 파일에서 직접 확인하지는 않았다)

## A2. 가짜 CDN 서버: `mockwebserver` 4.12.0

- **결정 출처**: NFR Requirements 계획 Q2=A
- **근거**: 앱이 쓰는 OkHttp (4.12.0) 와 같은 버전이라 버전 충돌이 없다. 경로별 응답 지정 (`Dispatcher`), 받은 요청의 메서드 · 헤더 기록 (`RecordedRequest`), 임시 포트 시작이 이미 있다. 탐침으로 루프백 동작을 확인했다
- **쓰는 방식**: `FakeCdnServer` 가 `MockWebServer` 를 감싼다. 경로마다 응답 (또는 응답 순서) 을 지정하고, 받은 요청을 기록에서 꺼내 본다. 테스트는 `FakeCdnServer` 만 쓰고 `MockWebServer` 를 직접 다루지 않는다
- **버리는 대안**: NanoHTTPD 로 직접 작성. 의존성은 늘지 않지만 응답 지정 · 요청 기록 · HEAD 처리를 직접 구현해야 한다
- **라이선스**: Apache-2.0 (OkHttp 와 같음)

## A3. `android.util.Log`: `unitTests.isReturnDefaultValues = true`

- **선택**: `android { testOptions { unitTests.isReturnDefaultValues = true } }`
- **근거**: JVM 단위 테스트에서 Android 프레임워크 메서드는 기본적으로 예외를 던진다. `TidalStreamProxyServer` 는 요청마다 `Log` 를 부르므로 이 설정이 없으면 테스트할 수 없다. 탐침으로 동작을 확인했다. 운영 빌드에는 영향이 없다
- **버리는 대안**: 운영 코드에 로그 래퍼를 넣어 테스트에서 바꿔 끼우기. 운영 코드 변경이 늘어난다
- **주의**: 이 설정은 모든 Android 메서드가 기본값 (0, null, false) 을 돌려주게 한다. 실수로 Android 클래스에 의존하는 테스트를 써도 예외 대신 기본값으로 지나갈 수 있다. 테스트 대상 (`PlaybackCommandRouter`, 프록시의 HTTP 처리) 은 `Log` 밖의 Android 클래스를 쓰지 않으므로 영향이 없다. `TidalStreamProxyServer.getWifiIpv4Address` (Android `ConnectivityManager`) 는 테스트하지 않는다

## A4. 테스트 실행기 · 단언: JUnit 4.13.2 (기존)

- 변경 없음. 기존 `DashManifestTest` 와 같은 방식 (`@Test`, `org.junit.Assert`). 한국어 테스트 이름은 역따옴표 함수 이름으로 쓴다

## A5. 프록시 테스트의 HTTP 클라이언트: OkHttp 4.12.0 (기존)

- **선택**: 테스트가 프록시에 요청을 보낼 때 앱의 OkHttp 를 쓴다. 타임아웃은 짧게 (수 초) 설정한다
- **프록시가 CDN 에 쓰는 클라이언트**: 생성자의 `httpClient` 매개변수로 타임아웃이 짧은 클라이언트를 넣는다 (연결 실패 테스트가 오래 걸리지 않게). 기본값 (운영) 은 지금 설정 그대로다

## A6. fake 작성 방식: 직접 작성

- **근거**: 협력 인터페이스 4개는 메서드가 적어 (3 ~ 8개) 직접 구현하는 편이 짧고 읽기 쉽다. unit 1 과 같은 방식이다
- **버리는 대안**: MockK · Mockito. 새 의존성과 다른 작성 방식이 들어온다

## A7. seed 관리: 고정 seed

- **결정 출처**: unit 1 NFR Requirements 계획 Q2=A 를 이어받음
- **선택**: 테스트 도우미 한 곳이 seed 를 정한다. 환경 변수 `PBT_SEED` 가 정수면 그 값, 없으면 20261117 (unit 1 과 같은 값). 속성마다 `PropTestConfig(seed = ..., iterations = ...)` 를 이 도우미로 만든다
- **재현**: Kotest 는 실패 시 seed 를 출력한다. `PBT_SEED=<seed> ./gradlew :app:testDebugUnitTest --tests "<테스트>"` 로 다시 실행한다. 실패 출력에 seed 와 축소된 입력이 실제로 나오는지는 Code Generation 에서 일부러 틀린 속성으로 확인한다 (unit 1 과 같은 확인)
- **주의**: Gradle 은 환경 변수를 테스트 프로세스에 그대로 넘긴다. 입력이 바뀌면 다시 실행되도록 테스트 작업의 입력으로 선언해야 하는지는 Code Generation 에서 확인한다

## A8. 로컬 JDK: JDK 17 을 `JAVA_HOME` 으로 지정

- **사실**: 이 작업을 실행하는 셸에는 Java 가 PATH 에 없다. 설치된 JDK 는 Homebrew `openjdk@17` 과 Android Studio 내장 JDK 21 이다. CI 는 JDK 17 (`.github/workflows/check.yml`)
- **선택**: 이 unit 의 Gradle 명령은 `JAVA_HOME=/opt/homebrew/opt/openjdk@17` 로 실행한다 (CI 와 같은 버전)
- **범위 밖**: `tool/check.sh` 가 Java 를 스스로 찾게 할지는 `ci-quality-gate` unit 에서 다룬다. 저장소의 파일은 이 결정으로 바뀌지 않는다

## A9. `PlaybackCore` 경계의 확인

- **사실**: `MethodCall`, `MethodChannel.Result` 는 JVM 단위 테스트에서 쓸 수 있다 (탐침으로 확인)
- **선택**
  - PC-01 ~ PC-03 (채널 호출 → router → 채널 응답 변환): 변환을 Android 에 의존하지 않는 작은 함수로 두고 단위 테스트한다. 함수의 위치와 이름은 NFR Design 에서 정한다
  - PC-04 ~ PC-07 (Android 시스템 서비스 · TIDAL SDK 에 닿는 운영 구현, 바꾸지 않는 부분): `flutter build apk --debug` 성공과 `git diff` 검토로 확인한다
- **한계**: PC-04 ~ PC-07 의 동작 동일성은 실기기에서만 확정된다. 실기기 확인은 범위 밖이다 (NFR-06-A6)

## `android/app/build.gradle.kts` 변경 예정 (Code Generation 에서 적용)

```kotlin
android {
    // ...
    testOptions {
        // JVM 단위 테스트에서 android.util.Log 호출이 예외를 내지 않게 한다.
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    // ... 기존 implementation 은 그대로
    testImplementation("junit:junit:4.13.2")
    testImplementation("io.kotest:kotest-property:6.2.7")              // 추가
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")    // 추가
}
```

`implementation` (앱에 들어가는 의존성) 은 바꾸지 않는다.
