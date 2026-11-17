# 단위 테스트 실행 (Unit Test Execution)

## 단위 테스트 실행

### 1. 모든 단위 테스트 실행

저장소 루트에서 실행한다. CI 도 같은 스크립트를 실행한다.

```bash
tool/check.sh                 # 포맷 → 분석 → Dart 테스트 (커버리지 수집) → 커버리지 검사 → Kotlin 테스트
tool/check.sh --skip-android  # Kotlin 테스트만 건너뜀
```

나눠서 실행할 때:

```bash
flutter test                                                   # Dart 전체
flutter test test/features/player/dlna_backend_test.dart       # 파일 하나
flutter test --coverage && dart tool/coverage_gate.dart        # 커버리지 검사만
(cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :app:testDebugUnitTest)                                      # Kotlin 전체
(cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :app:testDebugUnitTest --tests "*PlaybackCommandRouterTest*") # 클래스 하나
```

### 2. 테스트 결과 검토

- **기대 결과 (Expected)**: Dart 284개 통과, Kotlin 86개 통과, 실패 0. 마지막 줄 `모든 점검 통과`
- **테스트 커버리지 (Test Coverage)**: 대상 4개 파일 각각 라인 커버리지 80% 이상. 2026-11-17 기준 100.0% (`phone_backend.dart`), 99.4% (`dlna_backend.dart`), 99.2% (`dlna_manager.dart`), 98.7% (`wave_audio_handler.dart`). Kotlin 은 수치 기준이 없고 규칙마다 테스트가 있는지로 본다
- **테스트 보고서 위치 (Test Report Location)**: Dart 는 터미널 출력과 `coverage/lcov.info`. Kotlin 은 저장소 루트의 `build/app/test-results/testDebugUnitTest/` (XML) 와 `build/app/reports/tests/testDebugUnitTest/index.html`

unit 별 테스트:

| unit | 테스트 파일 | 수 |
| --- | --- | --- |
| `dart-playback-tests` | `test/features/player/phone_backend_test.dart`, `dlna_backend_test.dart`, `wave_audio_handler_test.dart`, `test/features/dlna/dlna_manager_test.dart` | 167 |
| `android-native-tests` | `android/app/src/test/kotlin/com/example/tidal_connect_lite/` 의 `PlaybackCommandRouterTest.kt`, `ChannelAdapterTest.kt`, `TidalStreamProxyServerTest.kt` | 82 |
| `ci-quality-gate` | `test/tool/coverage_gate_test.dart` | 22 |
| 기존 | Dart 95개, Kotlin `DashManifestTest.kt` 4개 | 99 |

### 3. 실패한 테스트 수정

1. 터미널 출력에서 실패한 테스트 이름을 찾는다. 이름 앞의 규칙 ID (`[DB-12]`, `CR-07`, `PX-25`, `[GT-05]`) 로 해당 unit 의 `business-rules.md` (ci-quality-gate 는 코드 생성 계획) 에서 규칙을 찾는다
2. 속성 테스트가 실패하면 출력의 seed 로 재현한다: `PBT_SEED=<seed> flutter test <파일>` 또는 `PBT_SEED=<seed> ./gradlew :app:testDebugUnitTest --rerun-tasks`
3. 코드를 고치고 다시 실행한다. 버그였다면 `docs/incidents/README.md` 의 절차를 따른다

### 알려진 불안정

- **Kotlin `TidalStreamProxyServerTest` 가 가끔 실패한다.** 전체를 이어서 반복하면 약 135회 중 4회꼴로 테스트 1개가 `SocketTimeoutException: Read timed out` 으로 실패한다 (DASH 길이 계산 경로). 원인은 확인하지 못했다. 다시 실행하면 통과한다. 자세한 내용은 `aidlc-docs/construction/android-native-tests/code/code-summary.md` 의 "알려 둘 점"
- **기존 `test/core/theme/app_theme_test.dart`** 는 `--test-randomize-ordering-seed=996956541` 에서 실패한다 (`google_fonts` 의 네트워크 요청). 기본 순서에서는 통과한다
