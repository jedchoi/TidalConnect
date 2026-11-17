# 컴포넌트 목록 (Component Inventory)

저장소는 단일 Flutter 패키지(`tidal_connect_lite`)와 그 Android 호스트 모듈(`:app`)로 이루어진다. 아래 "패키지"는 `lib/features/*`, `lib/core`, Android 네이티브 코드, 테스트 디렉터리를 논리 컴포넌트로 나눈 것이며, 이름은 `architecture.md`의 "컴포넌트 설명"과 같다.

## 애플리케이션 패키지
- main - 앱 진입점(`lib/main.dart`), 스플래시·자동 로그인, 탭 메인 화면 (`lib/features/main/`)
- auth - TIDAL OAuth(PKCE) 로그인, 토큰 저장·갱신, 네이티브 SDK 자격 증명 전달 (`lib/features/auth/`)
- player - `PlayerManager`, 대기열, 폰/DLNA 백엔드, audio_service 핸들러, 재생 UI, 최근 재생 (`lib/features/player/`)
- dlna - SSDP 탐색, 기기 선택 유지, UPnP SOAP 제어 (`lib/features/dlna/`)
- explore - 추천 콘텐츠와 최근 재생 홈 화면 (`lib/features/explore/`)
- search - 검색 화면과 검색 기록 (`lib/features/search/`)
- artist - 아티스트 상세 화면 (`lib/features/artist/`)
- favorites - 즐겨찾기 저장소, 내 보관함·앨범·플레이리스트 상세 (`lib/features/favorites/`)
- settings - 음질 설정, 설정 화면, 디버그 로그 (`lib/features/settings/`)
- android native - TIDAL Player/Auth SDK 구동, 플랫폼 채널, 로컬 스트림 프록시, DASH 처리 (`android/app/src/main/kotlin/com/example/tidal_connect_lite/`)

## 인프라 패키지
- 없음

## 공용 패키지
- core - Utilities - Provider 정의, 설정, 네이티브 브리지, 테마, 로거, 페이지네이터, 공용 위젯 (`lib/core/`)
- tidal_api - Clients/Models - TIDAL API v1 클라이언트, 인증 인터셉터, 도메인 모델 (`lib/features/tidal_api/`)

## 테스트 패키지
- Dart tests - Unit - `test/` 22개 테스트 파일(단위·위젯 테스트)과 `test/helpers/`(fakes, Provider override). 실기기·통합 테스트(`integration_test/`)는 없음
- Kotlin tests - Unit - `android/app/src/test/kotlin/com/example/tidal_connect_lite/DashManifestTest.kt` (JUnit 4)

## 전체 개수
- **전체 패키지**: 14
- **Application**: 10
- **Infrastructure**: 0
- **Shared**: 2
- **Test**: 2
