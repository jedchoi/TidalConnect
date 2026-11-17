# 빌드 안내 (Build Instructions)

대상: WaveConnect (`tidal_connect_lite`). Flutter 앱 하나와 그 안의 Android 네이티브 모듈이다. unit 3개 (`dart-playback-tests`, `android-native-tests`, `ci-quality-gate`) 는 모두 이 한 프로젝트 안에 있어 빌드는 하나다.

## 사전 조건 (Prerequisites)

- **빌드 도구 (Build Tool)**: Flutter 3.41.7 (Dart 3.11.5). CI 는 이 버전으로 고정되어 있다 (`.github/workflows/check.yml`). Android 쪽은 Gradle 8.14, Android Gradle Plugin 8.11.1, Kotlin 2.1.0 (Flutter 가 Gradle wrapper 를 만든다)
- **JDK**: 17. `tool/check.sh` 는 `JAVA_HOME` 이 없으면 macOS 에 설치된 JDK 17 을 스스로 찾는다. `flutter build` 와 `./gradlew` 를 직접 부를 때 Java 가 PATH 에 없으면 `JAVA_HOME` 을 지정한다 (예: `JAVA_HOME=/opt/homebrew/opt/openjdk@17`)
- **의존성 (Dependencies)**: `pubspec.yaml` (Dart), `android/app/build.gradle.kts` (Kotlin). 이번 작업에서 더한 것은 테스트 전용이다: `fake_async`, `kiri_check` (Dart), `kotest-property 6.2.7`, `mockwebserver 4.12.0` (Kotlin)
- **환경 변수 · 설정 (Environment)**: TIDAL 키 파일 `config/tidal.json` (git 에서 제외. 형식은 `config/tidal.example.json`). 실행 가능한 앱을 만들 때만 필요하다. 테스트와 키 없는 빌드에는 필요 없다
- **시스템 요구사항 (System Requirements)**: macOS 또는 Linux, Android SDK. debug APK 는 약 230MB 다

## 빌드 단계 (Build Steps)

저장소 루트에서 실행한다.

### 1. 의존성 설치
```bash
flutter pub get
```

### 2. 환경 구성
```bash
cp config/tidal.example.json config/tidal.json   # 처음 한 번. 값을 채운다
```
`android/gradlew` 와 `android/local.properties` 는 저장소에 없다. `flutter build` 가 만들고, 테스트만 돌릴 때는 다음으로 만든다.
```bash
flutter build apk --debug --config-only
```

### 3. 빌드
```bash
# 폰에 설치할 debug APK (키 포함)
flutter build apk --debug --dart-define-from-file=config/tidal.json

# release APK. 키 파일 옵션을 빼면 로그인 화면에서 오류가 난다
flutter build apk --release --dart-define-from-file=config/tidal.json

# 빌드가 되는지만 확인 (키 없음, CI 가 올리는 것과 같다. 설치하면 시작할 때 멈춘다)
flutter build apk --debug
```

### 4. 빌드 성공 확인
- **예상 출력 (Expected Output)**: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`
- **빌드 산출물 (Build Artifacts)**: `build/app/outputs/flutter-apk/app-debug.apk` (release 는 `app-release.apk`)
- **흔한 경고 (Common Warnings)**: `WIFI_MODE_FULL_HIGH_PERF is deprecated` (기존 코드), Flutter Gradle 플러그인의 `ApkVariant is deprecated`, javac 의 `obsolete options` 경고. 모두 이번 작업 전부터 있던 것이고 빌드에 지장이 없다

## 문제 해결 (Troubleshooting)

### `Unable to locate a Java Runtime`
- **원인 (Cause)**: Java 가 PATH 에 없다 (macOS 의 `/usr/bin/java` 는 JDK 가 없어도 있는 대역이다)
- **해결 (Solution)**: `JAVA_HOME` 을 JDK 17 로 지정하거나 `brew install openjdk@17`. `tool/check.sh` 는 스스로 찾는다

### `./gradlew: No such file or directory`
- **원인 (Cause)**: Gradle wrapper 가 아직 만들어지지 않았다
- **해결 (Solution)**: `flutter build apk --debug --config-only`

### 설치한 앱이 시작할 때 멈추거나 로그인 페이지에서 오류
- **원인 (Cause)**: `--dart-define-from-file=config/tidal.json` 없이 빌드해 클라이언트 ID 가 비어 있다. debug 는 assert 로 멈추고 release 는 TIDAL 로그인 페이지가 오류를 낸다
- **해결 (Solution)**: 키 파일 옵션을 붙여 다시 빌드한다

### `flutter analyze` 가 `material.dart` 폐기 예정 안내로 실패
- **원인 (Cause)**: Flutter 가 3.41.7 보다 새 버전이다
- **해결 (Solution)**: 3.41.7 을 쓴다 (`check.yml` 의 주석 참고)
