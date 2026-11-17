# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Run from the repo root. Flutter is pinned to 3.41.7 in CI (`.github/workflows/check.yml`); the README's "3.38 이상" is older.

```sh
flutter pub get
flutter run --dart-define-from-file=config/tidal.json   # TIDAL 키 필요; 없으면 디버그 assert로 중단
tool/check.sh                 # CI와 같은 전체 점검: format, analyze --fatal-infos, flutter test --coverage, 커버리지 검사, Kotlin 테스트
tool/check.sh --skip-android  # Kotlin 테스트 제외 (Gradle 없이 빠르게). 커버리지 검사는 실행

dart format --output=none --set-exit-if-changed --line-length 120 lib test tool   # 포맷 (줄 길이 120)
flutter analyze --fatal-infos
flutter test --coverage && dart tool/coverage_gate.dart   # 커버리지 검사만 (대상 4개 파일 각각 80% 이상)

flutter test test/features/player/                       # 디렉터리 단위
flutter test test/features/player/some_test.dart --plain-name "테스트 이름"   # 단일 테스트
(cd android && ./gradlew :app:testDebugUnitTest --tests "*DashManifestTest*") # 단일 Kotlin 테스트
```

`config/tidal.json`은 git에서 제외되어 있다. 형식은 `config/tidal.example.json`을 따른다. CI에는 `flutter build apk --debug --config-only`로 Gradle 설정만 생성하므로 `gradlew`와 `local.properties`는 저장소에 없다.

커버리지 검사의 대상 파일과 기준값은 `tool/coverage_gate.dart`의 상수다. `coverage/`는 git에서 제외되어 있다. `tool/check.sh`는 `JAVA_HOME`이 없고 `java`도 실행되지 않으면 JDK 17을 스스로 찾는다(`/usr/libexec/java_home -v 17` → Homebrew `openjdk@17`). CI는 점검이 통과하면 키 없는 debug APK를 빌드해 산출물 `app-debug-nokeys`로 올린다(빌드 확인용, 14일 보관).

## Architecture

**재생 상태의 단일 출처는 `PlayerManager`다** (`lib/features/player/data/player_manager.dart`). 화면은 이 notifier만 구독하고, 재생 상태는 출력 백엔드가 보내는 이벤트로만 바뀐다. 직접 상태를 바꾸는 코드를 추가하지 않는다.

**출력 백엔드는 두 개이며 `playback_backend.dart`의 같은 인터페이스를 따른다** (`lib/features/player/data/backends/`):
- phone: 네이티브 TIDAL Player SDK. Flutter → MethodChannel → Kotlin `PlaybackCore` → `TidalPlayerManager`. 이벤트는 EventChannel(`player_events`)로 돌아온다.
- dlna: 선택한 렌더러에 UPnP SOAP(`dlna/data/upnp_soap_client.dart`)으로 명령을 보낸다. 렌더러는 TIDAL URL을 직접 받지 못하므로 앱 안의 `TidalStreamProxyServer`(Kotlin, 로컬 HTTP)를 거친다. 프록시는 토큰이 든 URL을 단축 주소로 바꾸고, 허용된 호스트만 전달하며, DASH 세그먼트를 이어 붙여 제공한다.

**네이티브 쪽 소유 구조:** `PlaybackCore`(object, 프로세스 범위)가 인증 관리자, TIDAL 플레이어, 프록시 서버를 소유한다. Activity가 다시 만들어져도 재생이 끊기지 않도록 Activity에 묶지 않는다. 정지와 해제는 Flutter의 정지 명령으로만 일어난다.

**DASH 경로:** LOSSLESS 요청이어도 TIDAL이 DASH(MPD)로 응답하는 경우가 있다. MPD 해석은 `DashManifest.kt`, 세그먼트 스트림은 `DashSegmentInputStream.kt`가 맡는다. 실기기에서 깨진 적이 있으므로 (`62b2e9d`) 해석 로직을 바꾸면 `DashManifestTest.kt`를 함께 본다.

**의존성 주입:** `lib/core/providers.dart`의 Riverpod Provider가 모든 서비스를 연결한다. 테스트는 `test/helpers/`의 override와 fake 구현으로 Provider를 바꿔 끼운다.

**Audio 세션:** `wave_audio_handler.dart`(audio_service)가 잠금화면·알림·블루투스 버튼을 처리하고 `PlayerManager`에 명령을 전달한다.

**인증:** 토큰은 `flutter_secure_storage`에 저장하고 `TidalAuthRepository`가 갱신한다. 로그인 UI는 앱 안의 WebView(`tidal_webview_login_modal.dart`)다. 유료 계정 토큰은 `updateUserCredentials`로 네이티브 SDK에도 넘겨야 30초 제한이 풀린다.

## Docs and references

- `docs/dlna-compat.md`: 실기기 렌더러별 재생 결과 표. 렌더러를 시험하면 여기 행을 추가한다.
- `docs/failure-scenarios.md`: 스피커 전원 끄기·Wi-Fi 끊기 같은 장애 상황을 실기기에서 확인하는 점검표. 재생 경로를 고친 뒤 관련 항목을 해 본다.
- `docs/incidents/`: 문제의 원인과 수정을 남기는 곳. 버그를 고칠 때는 `README.md`의 절차(실패 테스트 → 별도 `fix:` 커밋 → 문서)를 따른다.
- `docs/superpowers/specs/`, `docs/superpowers/plans/`: 초기 설계와 구현 계획.
- `GEMINI.md`: Superpowers 스킬 안내(`.agents/skills/`). 스킬은 `.agents/skills/using-superpowers/SKILL.md`부터 읽는다.
