# 통합 테스트 안내 (Integration Test Instructions)

## 목적 (Purpose)

unit 사이의 맞물림을 확인한다. 이 프로젝트에서 unit 이 만나는 곳은 두 군데다.

1. Dart (`dart-playback-tests`) 와 Kotlin (`android-native-tests`) 사이의 MethodChannel 계약
2. 테스트 (`dart-playback-tests`) 가 만드는 커버리지와 그것을 검사하는 스크립트 (`ci-quality-gate`)

자동 통합 테스트 묶음은 따로 없다. 실기기 · 실제 스피커가 필요한 부분은 사람이 하는 점검표로 둔다 (요구사항에서 실기기 확인은 완료 기준 밖으로 정했다).

## 테스트 시나리오 (Test Scenarios)

### 시나리오 1: Dart `PhoneBackend` → Kotlin `PlaybackCommandRouter` (채널 계약)
- **설명 (Description)**: Dart 가 보내는 메서드 이름 · 인자 키 · 타입과, Kotlin 이 읽는 것 · 돌려주는 맵이 같은가
- **자동으로 확인되는 것**: 양쪽이 각자 같은 계약 문자열로 테스트된다. Dart 쪽은 가짜 채널로 보낸 호출을 기록해 단언하고 (`phone_backend_test.dart`), Kotlin 쪽은 같은 이름 · 키로 router 를 부른다 (`PlaybackCommandRouterTest.kt`). 두 쪽의 대조표는 `aidlc-docs/construction/android-native-tests/functional-design/business-rules.md` 6절
- **자동으로 확인되지 않는 것**: 실제 채널을 지나는 왕복. `PlaybackCore` 는 JVM 테스트로 실행할 수 없다
- **준비 (Setup)**: 키를 넣은 debug APK 를 폰에 설치 (`build-instructions.md`)
- **테스트 단계 (Test Steps)**: 로그인 → 곡 재생 → 일시정지 · 재개 → 탐색 → 다음 곡 → 음질 변경 → 볼륨 → 정지
- **기대 결과 (Expected Results)**: 각 동작이 화면 상태에 반영되고 오류 안내가 없다. logcat 의 `TIDAL_NATIVE_SDK` 태그에 `플레이어 동작 실패` 가 없다
- **정리 (Cleanup)**: 없음

### 시나리오 2: Dart `DlnaBackend` → Kotlin `TidalStreamProxyServer` → 렌더러
- **설명 (Description)**: 등록한 곡의 프록시 주소로 실제 렌더러가 HEAD · GET 을 보내 재생하는가
- **자동으로 확인되는 것**: 프록시의 HTTP 동작 (가짜 CDN 과 테스트 클라이언트로, `TidalStreamProxyServerTest.kt`), Dart 쪽의 등록 호출과 SOAP 명령 (`dlna_backend_test.dart`, `dlna_manager_test.dart`)
- **준비 (Setup)**: 같은 Wi-Fi 의 DLNA 스피커
- **테스트 단계 (Test Steps)**: 스피커 선택 → 곡 재생 → 탐색 → 다음 곡 (갭리스) → Wi-Fi 를 끈 채 재생 시도. 그리고 `docs/failure-scenarios.md` 의 항목
- **기대 결과 (Expected Results)**: 스피커에서 재생되고, Wi-Fi 가 없으면 안내가 나온다. 결과는 `docs/dlna-compat.md` 에 렌더러별로 적는다
- **특히 볼 것**: 길이를 모르는 곡의 HEAD 응답이 바뀌었다 (`8e5b417`, `Content-Length: -1` 을 보내지 않음). 재생 시작이 되는지 확인한다

### 시나리오 3: 테스트 커버리지 → `CoverageGate` → `tool/check.sh` → CI
- **설명 (Description)**: 테스트가 만든 `coverage/lcov.info` 를 검사 스크립트가 읽고, 점검 스크립트와 CI 가 그 결과로 실패 · 통과하는가
- **테스트 단계 (Test Steps)**: `tool/check.sh` 실행. 로컬에서는 자동이다
- **기대 결과 (Expected Results)**: 커버리지 표에 대상 4개가 나오고 `전체 통과 (기준 80%)`. 대상의 기록을 빼거나 80% 미만으로 낮춘 lcov 로는 종료 코드 1 (2026-11-17 확인)
- **확인되지 않은 것**: CI 에서의 실제 실행. 푸시한 뒤 GitHub Actions 의 `check` workflow 에서 "점검", "debug APK 빌드 (키 없음)", "APK 산출물 업로드" 가 차례로 성공하고 산출물 `app-debug-nokeys` 가 생기는지 본다

## 통합 테스트 환경 구성

따로 띄울 서비스는 없다. 시나리오 1 · 2 는 폰 (과 스피커), 시나리오 3 은 저장소만 있으면 된다.

## 통합 테스트 실행

```bash
tool/check.sh                                                          # 시나리오 3
flutter build apk --debug --dart-define-from-file=config/tidal.json   # 시나리오 1 · 2 의 준비
```

- **로그 위치 (Logs Location)**: 앱의 설정 탭 디버그 로그 (`DLNA_`, `UPNP_SOAP`, `PROXY`, `PLAYER` 태그), logcat
- 기대와 다르면 `docs/incidents/README.md` 의 절차로 기록한다
