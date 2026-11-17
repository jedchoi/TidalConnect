# WaveConnect (tidal_connect_lite)

TIDAL 음원을 폰 스피커나 같은 Wi-Fi의 DLNA(UPnP) 스피커로 재생하는 Android 앱이다.

## 주요 기능

- TIDAL 계정 로그인(OAuth, 앱 안의 웹뷰)과 토큰 자동 갱신
- 즐겨찾기(앨범·아티스트·플레이리스트·트랙) 보기와 하트로 추가·삭제, 목록은 스크롤하면 끝까지 이어 받음
- 추천 탭(최근 재생 50곡 포함), 트랙·앨범·아티스트·플레이리스트 검색, 아티스트 화면
- 재생 대기열, 셔플, 반복, 다음/이전 곡, 갭리스 재생(폰 SDK setNext, DLNA SetNextAVTransportURI 지원 렌더러)
- 스트리밍 음질 선택(LOW·HIGH·LOSSLESS·HI_RES)과 실제 스트림 음질 배지
- 계정 국가 코드로 카탈로그 조회
- 출력 기기 전환: 폰 스피커(TIDAL Player SDK) ↔ DLNA 렌더러(앱 내부 프록시 경유)
- 잠금화면·알림·블루투스 버튼 제어, 백그라운드 재생, 볼륨 키로 스피커 볼륨 조절

## 구조

```
lib/
  core/          Provider, 공용 위젯, 테마, 네이티브 브리지, 유틸
  features/
    auth/        토큰 저장(보안 저장소), 로그인·갱신(TidalAuthRepository)
    tidal_api/   REST 클라이언트(Dio + AuthInterceptor), 모델
    player/      PlayerManager(재생 상태의 단일 출처), 출력 백엔드(phone/dlna), audio_service 핸들러
    dlna/        SSDP 탐색, UPnP SOAP 제어, 선택 기기 저장
    explore/ favorites/ search/ settings/ main/   화면
android/app/src/main/kotlin/.../
  PlaybackCore.kt              Flutter 채널, 인증·플레이어·프록시 연결
  TidalPlayerManager.kt        TIDAL Player SDK 래퍼(이벤트 → EventChannel)
  TidalStreamProxyServer.kt    DLNA용 로컬 HTTP 프록시(토큰 URL, 허용 호스트, HEAD, DASH 세그먼트 연결)
  DashManifest.kt              MPD 해석
```

재생 상태는 출력 백엔드가 보내는 이벤트로만 바뀐다. 화면은 `PlayerManager`의 notifier만 구독한다.
의존성은 `lib/core/providers.dart`의 Provider로 주입하고, 테스트는 override로 가짜 구현을 끼운다.

## 개발 환경 설정

1. `pubspec.lock` 기준 Flutter 3.38 이상, Android SDK(minSdk 26), JDK 17
2. TIDAL 개발자 대시보드에서 앱을 만들고 Redirect URI를 등록한다.
3. 키 파일을 만든다. `config/tidal.json`은 `.gitignore`에 들어 있다.

   ```sh
   cp config/tidal.example.json config/tidal.json
   # TIDAL_CLIENT_ID, TIDAL_CLIENT_SECRET, TIDAL_REDIRECT_URI 입력
   ```

4. 의존성을 받고 실행한다.

   ```sh
   flutter pub get
   flutter run --dart-define-from-file=config/tidal.json
   ```

   키 없이 실행하면 디버그 빌드에서 assert로 바로 알려 준다.

## 점검

```sh
tool/check.sh                 # 포맷, analyze, flutter test(커버리지 수집), 커버리지 검사, Kotlin 단위 테스트
tool/check.sh --skip-android  # Kotlin 테스트 제외 (커버리지 검사는 실행)
```

커버리지 검사(`tool/coverage_gate.dart`)는 재생 경로의 파일 4개(`phone_backend.dart`, `dlna_backend.dart`, `dlna_manager.dart`, `wave_audio_handler.dart`)가 각각 라인 커버리지 80% 이상인지 본다. 하나라도 모자라거나 기록이 없으면 점검이 실패한다.
Kotlin 테스트에는 JDK 17이 필요하다. `JAVA_HOME`이 없으면 스크립트가 macOS에 설치된 JDK 17을 찾아 쓴다.

GitHub Actions는 푸시와 PR마다 같은 `tool/check.sh`를 실행하고, 통과하면 debug APK를 산출물 `app-debug-nokeys`로 올린다(14일 보관).
`app-debug-nokeys`는 빌드 확인용이다. 키가 없어 설치하면 시작할 때 멈춘다. 설치용 APK는 로컬에서 `--dart-define-from-file=config/tidal.json`으로 만든다.

## DLNA 호환성

시험한 렌더러와 결과는 [docs/dlna-compat.md](docs/dlna-compat.md)에 기록한다.
DASH 스트림의 위치 이동: 요청한 위치가 속한 세그먼트(몇 초 단위)부터 새 주소로 다시 재생하는 방식이다. 옮길 때 짧게 끊기고, 요청한 위치보다 몇 초 앞에서 시작할 수 있다. 렌더러에 따라 동작이 다를 수 있으니 결과를 호환성 표에 적는다.

## 문제 해결

- 로그인 후 토큰 교환에 실패하면: 대시보드의 Redirect URI와 `TIDAL_REDIRECT_URI`가 같은지 확인한다.
- DLNA 스피커가 보이지 않으면: 폰과 스피커가 같은 Wi-Fi(같은 서브넷)인지, 공유기가 멀티캐스트를 막지 않는지 확인한다.
- 설정 탭 → 로그 콘솔에서 `TIDAL_AUTH`, `DLNA_`, `PROXY` 태그 로그를 볼 수 있다.
