# 기술 스택 결정 (Tech Stack Decisions) - dart-playback-tests

확인 환경: Flutter 3.41.7, Dart 3.11.5 (2026-11-17). 버전과 날짜는 pub.dev 와 `flutter pub add --dev --dry-run` 결과에서 확인했다.

## 결정 요약

| # | 대상 | 선택 | `pubspec.yaml` 변경 |
| --- | --- | --- | --- |
| D1 | 속성 기반 테스트 프레임워크 | `kiri_check` 1.4.0 | `dev_dependencies` 에 추가 |
| D2 | 가짜 시간 | `fake_async` 1.3.3 | `dev_dependencies` 에 직접 선언 (이미 간접 의존) |
| D3 | 플랫폼 채널 대체 | `flutter_test` 의 테스트 바인딩 (`setMockMethodCallHandler`) | 없음 |
| D4 | 저장소 대체 | `SharedPreferences.setMockInitialValues` | 없음 |
| D5 | fake 작성 방식 | 직접 작성 (상속 · 구현), mock 라이브러리 없음 | 없음 |
| D6 | 테스트 실행기 · 단언 | `flutter_test` (기존) | 없음 |
| D7 | 커버리지 측정 | `flutter test --coverage` (lcov) | 없음 |
| D8 | seed 관리 | 고정 seed 를 `test/helpers/` 한곳에서 설정, 환경 변수로 변경 가능 | 없음 |

## D1. 속성 기반 테스트 프레임워크: `kiri_check` 1.4.0

- **결정 출처**: NFR Requirements 계획 Q1=A
- **PBT-09 요건 대조**

| 요건 | `kiri_check` | 확인 방법 |
| --- | --- | --- |
| 사용자 정의 생성기 | 지원 (`Arbitrary` 조합, `combine`, `map`, `filter` 계열) | 패키지 소스 `lib/src/arbitrary/` |
| 자동 축소 | 지원 (`maxShrinkingTries` 기본 100, 축소 정책 설정) | `lib/src/property/home.dart` |
| seed 재현 | 지원 (`forAll(..., seed:)`, 전역 `KiriCheck.seed`). 실패 메시지에 `Falsifying example: ... (seed N)` 출력 | `lib/src/property/top.dart`, `exception.dart` |
| 기존 테스트 실행기 통합 | `package:test` 위에서 동작 (`property(...)` 가 테스트 하나). `flutter test` 로 실행됨 | 의존성 `test: ^1.25.2`, dry-run 해석 성공 |

- **근거**: 지금도 관리된다 (최근 배포 2026-10-25). 실패 시 seed 를 출력하고 그대로 재현할 수 있다. 상태 기반 테스트 API 가 있어 PBT-06 속성에 쓸 수 있다
- **버리는 대안**: `glados` 1.1.7. 사용자는 더 많지만 (30일 다운로드 약 33,800 대 약 6,200) 마지막 배포가 2023-12-04 이고 상태 기반 API 가 없다
- **알려진 부담**
  - 사용자가 적다. 문제가 생기면 참고할 자료가 적다
  - 개발용 간접 의존 30개가 `pubspec.lock` 에 추가 · 변경된다 (`test`, `analyzer`, `coverage`, `timezone`, `date_kit` 등). 앱 번들에는 들어가지 않는다 (`dev_dependencies`)
  - `kiri_check` 와 `flutter_test` 가 같은 이름을 내보낼 수 있다. 충돌하면 import 에 `hide` 또는 접두어를 쓴다 (Code Generation 에서 확인)
  - 상태 기반 속성 P-DB-1 은 `fake_async` 안에서 돌려야 한다. `kiri_check` 의 상태 기반 API 가 `fake_async` 와 맞지 않으면, 응답 목록을 생성기로 만들어 `forAll` 안에서 모델과 한 단계씩 비교하는 방식으로 쓴다. 어느 쪽이든 PBT-06 의 요건 (모델, 명령마다 비교, 빈 순서 포함) 은 지킨다
- **라이선스**: Apache-2.0 (패키지의 `LICENSE` 파일)

## D2. 가짜 시간: `fake_async` 1.3.3

- **결정 출처**: Application Design 계획 Q3=A
- **근거**: `DlnaBackend` 의 `Timer.periodic` 을 운영 코드 변경 없이 제어한다. 이미 `pubspec.lock` 에 1.3.3 으로 있다 (flutter_test 의 간접 의존)
- **`dev_dependencies` 에 선언하는 이유**: `flutter_test` 는 `fake_async` 를 다시 내보내지 않는다 (`flutter_test.dart` 의 export 목록 확인). 테스트에서 직접 import 하려면 선언해야 하고, 선언하지 않으면 `depend_on_referenced_packages` 린트가 `--fatal-infos` 에 걸린다
- **버전 지정**: `flutter_test` 가 고정한 버전과 충돌하지 않게 `^1.3.0` 처럼 범위로 적는다 (dry-run 결과: 새 다운로드 없이 간접 → 직접 의존으로만 바뀜)
- **버리는 대안**: `DlnaBackend` 에 폴링 간격 · 타이머 주입 (운영 코드 변경). `fake_async` 안에서 가짜 채널 응답이 완료되지 않으면 이 대안으로 바꾸는 변경을 요청한다 (`application-design.md` 6절)

## D3. 플랫폼 채널 대체: `flutter_test` 테스트 바인딩

- **결정 출처**: Application Design 계획 Q1=A
- **선택**: `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler` 로 MethodChannel 을 가로채고, 네이티브 → Dart 호출은 `handlePlatformMessage` 로 흉내 낸다. `FakeNativeChannel` 이 이를 감싼다
- **근거**: 새 의존성이 없다. 기존 테스트가 이미 `TestWidgetsFlutterBinding.ensureInitialized()` 를 쓴다. 채널 메서드 이름 · 인자 키가 실제로 검증된다
- **EventChannel**: `PhoneBackend(nativeEvents:)` 에 `StreamController` 를 주입하므로 EventChannel 자체는 가로채지 않는다

## D4. 저장소 대체: `SharedPreferences.setMockInitialValues`

- **근거**: `shared_preferences` 가 제공하는 테스트용 API 이고 기존 테스트 (`test/helpers/app_overrides.dart` 의 `TestApp`) 가 이미 쓴다. `DlnaManager` 에 저장소 주입 지점을 만들 필요가 없다

## D5. fake 작성 방식: 직접 작성

- **근거**: 기존 테스트가 모두 직접 작성한 fake 를 쓴다 (`FakeAdapter`, `FakeAuthRepository`, `FakeApiClient`, `FakeBackend`). NFR-05 가 기존 방식을 따르도록 요구한다
- **버리는 대안**: `mocktail` · `mockito`. 새 의존성과 다른 작성 방식이 섞인다

## D6. 테스트 실행기 · 단언: `flutter_test` (기존)

- 변경 없음. `kiri_check` 의 `property` 도 같은 실행기에서 돈다

## D7. 커버리지 측정: `flutter test --coverage`

- **근거**: Flutter 에 들어 있는 기능이고 새 도구가 필요 없다. `coverage/lcov.info` 의 파일별 `LF` (전체 줄) · `LH` (실행된 줄) 로 계산한다
- **이 unit 에서의 확인 방법**: 자동 검사 (`CoverageGate`) 는 `ci-quality-gate` unit 이 만든다. 이 unit 은 Code Generation 끝에 lcov 를 직접 계산해 4개 파일의 수치를 요약에 적는다
- **주의**: `coverage/` 폴더가 `.gitignore` 에 없다. 측정 결과를 커밋하지 않도록 이 unit 은 결과 파일을 저장소 밖 (작업용 임시 폴더) 에 만들고, `.gitignore` 추가는 `ci-quality-gate` unit 이 한다

## D8. seed 관리: 고정 seed

- **결정 출처**: NFR Requirements 계획 Q2=A
- **선택**: `test/helpers/` 의 한 파일이 `KiriCheck.seed` 를 고정값으로 설정한다. 환경 변수 (예: `PBT_SEED`) 가 있으면 그 값을 쓴다. PBT 를 쓰는 테스트 파일은 이 설정을 `setUpAll` 등에서 호출한다
- **근거**: 로컬과 CI 가 같은 입력으로 실행된다 (NFR-03-D3). 실패하면 `kiri_check` 가 seed 와 축소된 입력을 출력하므로 재현할 수 있다 (PBT-08)
- **버리는 대안**: 매 실행 무작위 seed. 더 많은 입력을 보지만 코드 변경과 무관한 CI 실패가 생길 수 있다
- **한계**: 고정 seed 는 새 입력을 자동으로 탐색하지 않는다. 탐색은 seed 를 바꿔 직접 실행해야 한다
- **속성당 실행 횟수**: 프레임워크 기본값 100. NFR-03-D4 (30초) 를 넘으면 `fake_async` 조립이 필요한 상태 기반 속성 (P-PB-5, P-DB-1, P-DB-2) 부터 줄이고, 줄인 값과 이유를 Code Generation 요약에 적는다

## `pubspec.yaml` 변경 예정 (Code Generation 에서 적용)

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  fake_async: ^1.3.0     # 추가 (이미 간접 의존)
  kiri_check: ^1.4.0     # 추가
```

`dependencies` (앱에 들어가는 의존성) 는 바꾸지 않는다.
