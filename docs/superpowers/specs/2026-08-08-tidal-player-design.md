# Tidal Connect Lite - 시스템 기획 및 설계 명세서

- **작성일**: 2026-08-08
- **주제**: 안드로이드용 라이트 Tidal 플레이어 & DLNA 오디오 렌더러 컨트롤러
- **타겟 플랫폼**: 안드로이드 (Flutter)
- **주요 목표**: mconnect Player lite의 번거로운 메뉴 진입 방식(Browser -> Tidal -> My Collection)을 개선하여, 앱 실행 시 즉시 '내 즐겨찾기(My Collection)'를 보여주고 동일 네트워크의 UPnP/DLNA 스피커(Chord Poly 등)로 음원을 스트리밍 재생하는 하위호환 전용 플레이어 개발.

---

## 1. 개요 및 핵심 요구사항

1. **내 즐겨찾기(My Collection) 즉시 진입**: mconnect Player lite와 달리, 앱 실행 즉시 사용자의 Tidal 즐겨찾기 목록을 첫 화면에 표시.
2. **영구 자동 로그인**: OAuth 2.0 Access/Refresh 토큰을 안드로이드 보안 저장소(`EncryptedSharedPreferences`)에 암호화하여 저장하고, 앱 실행 시 자동으로 토큰을 검증/갱신하여 무재로그인 환경 제공.
3. **로컬 DLNA/UPnP 스피커 탐색 및 스트리밍**: 동일 Wi-Fi 네트워크 내의 오디오 렌더러 스피커를 SSDP (`M-SEARCH`)로 탐색하고, Tidal의 음원 URL(FLAC/AAC)을 UPnP `AVTransport` (`SetAVTransportURI`, `Play`, `Pause`, `Seek`) 프로토콜을 통해 Chord Poly 스피커로 직접 전송 및 재생.
4. **하드웨어 볼륨 버튼 연동**: 안드로이드 스마트폰의 측면 물리 볼륨 버튼(Up/Down) 이벤트를 감지하여, 현재 연결된 DLNA 스피커의 UPnP `RenderingControl` (`SetVolume`) 명령으로 직접 제어.

---

## 2. 기술 스택 및 아키텍처

- **프레임워크**: Flutter 3.x (Dart 3.x)
- **상태 관리**: `flutter_riverpod`
- **보안 저장소**: `flutter_secure_storage` (Android `EncryptedSharedPreferences` / KeyStore)
- **네트워크 & API**: `dio` / `http` (Tidal REST API 통신)
- **DLNA / UPnP 프로토콜**: 순수 Dart SSDP 소켓 클라이언트 (UDP `239.255.255.250:1900`) 및 `AVTransport:1`, `RenderingControl:1` XML SOAP RPC 클라이언트
- **하드웨어 볼륨 감지**: `flutter_volume_controller`
- **디자인 테마**: Dark Elegant Tidal (`#121212` 딥 차콜 배경, `#1E1E2E` 서피스 카드, `#00FFFF` 네온 시안 포인트 컬러)

```
+-------------------------------------------------------------------+
|                        Flutter UI 레이어                          |
|  [탭 1: 즐겨찾기]  [탭 2: 추천]  [탭 3: 검색]  [탭 4: 설정]     |
|                 +---------------------------------+               |
|                 |  미니 플레이어 & 출력 스피커 선택  |               |
+-----------------+---------------------------------+---------------+
                                  |
                   상태 관리 (Riverpod State)
                                  |
        +-------------------------+-------------------------+
        |                                                   |
[Tidal 인증 & API 서비스]                         [DLNA / UPnP 컨트롤러]
 - OAuth 2.0 PKCE / Device Auth                   - SSDP 네트워크 탐색 (M-SEARCH)
 - 토큰 자동 갱신 (Auto Refresh)                  - AVTransport (SetURI, Play, Pause, Seek)
 - EncryptedSharedPreferences 보관                 - RenderingControl (SetVolume)
        |                                                   |
        v                                                   v
   Tidal Cloud                                       Chord Poly / 스피커들
 (REST Streaming API)                                (로컬 Wi-Fi 네트워크)
```

---

## 3. 상세 UI / UX 명세

### 3.1 하단 바텀 네비게이션 바 (4개 탭)
1. **탭 1: 내 즐겨찾기 (My Collection - 첫 진입 메인 화면)**
   - 상단 프로필 요약 및 계정 상태 바.
   - 즐겨찾기 앨범 (Favorite Albums) 가로 스크롤 썸네일 그리드.
   - 내 플레이리스트 (My Playlists) 세로 리스트 뷰 (커버 아트 및 트랙 수 표시).
   - 즐겨찾기 트랙 (Favorite Tracks) 리스트 (터치 시 즉시 재생).
   - 즐겨찾기 아티스트 (Favorite Artists) 원형 프로필 가로 스크롤.
2. **탭 2: 추천 및 최근 재생 (Explore & Recent)**
   - 최근 재생한 곡 및 앨범 히스토리.
   - Tidal 데일리 믹스 및 추천 플레이리스트.
3. **탭 3: 음악 검색 (Search)**
   - Debounce 처리된 실시간 검색창.
   - 검색 결과 카테고리 칩 필터링 (전체 / 트랙 / 앨범 / 아티스트 / 플레이리스트).
4. **탭 4: 앱 설정 (Settings)**
   - Tidal 계정 정보 및 재인증/로그아웃 버튼.
   - 오디오 스트리밍 음질 선택 (LOW, HIGH, LOSSLESS, HI_RES).
   - DLNA 스피커 수동 재탐색 및 SSDP 네트워크 타임아웃 설정.

### 3.2 플레이어 컨트롤러 및 스피커 선택기
- **플로팅 미니 플레이어 (Mini Player)**: 하단 바텀 네비게이션 바로 위에 상시 플로팅 배치. 앨범 썸네일, 곡 제목, 아티스트명, 재생/일시정지 토글, 현재 출력 스피커 아이콘 노출.
- **풀스크린 플레이어 (Now Playing View)**:
  - 고화질 대형 앨범 아트워크.
  - 음질 정보 배지 (예: `FLAC 16-bit 44.1kHz` / `HI-RES`).
  - 재생 탐색 바 (Seekbar), 재생 제어 버튼 (이전 곡, 재생/일시정지, 다음 곡, 셔플/반복).
  - 우측 상단 스피커 선택 버튼 터치 시, 동일 Wi-Fi 상의 DLNA 스피커(Chord Poly, 핸드폰 스피커 등) 목록을 보여주는 바텀 시트 모달 오픈.
- **하드웨어 볼륨 동기화**:
  - 스마트폰 측면 물리 볼륨 Up/Down 버튼 조절 시, UPnP `RenderingControl`의 `SetVolume` 명령을 Chord Poly 스피커로 전달하고 화면에 볼륨 상태 토스트 팝업 표시.

---

## 4. 인증 및 데이터 보존 프로세스

```
앱 실행
  │
  ▼
EncryptedSharedPreferences 읽기 (flutter_secure_storage)
  │
  ├── [1] 토큰 유효함 ─────────────────────────┐
  ├── [2] 토큰 만료됨 ──► API로 토큰 자동 갱신 ─┤
  │                                             ▼
  └── [3] 토큰 없음 ──► Tidal OAuth 로그인 화면   [탭 1: 내 즐겨찾기] 1초 만에 진입!
```

---

## 5. 검증 및 테스트 전략

1. **단위 테스트 (Unit Test)**:
   - 토큰 보관 및 자동 갱신 로직 검증.
   - Tidal API JSON 응답 데이터 파싱 테스트 (앨범, 플레이리스트, 트랙).
   - UPnP SOAP XML 페이로드 생성기 테스트 (`AVTransport` & `RenderingControl`).
2. **통합 및 실기기 테스트 (Manual / Integration Test)**:
   - 안드로이드 Wi-Fi Multicast Lock 활성화 상태에서 로컬 Wi-Fi SSDP M-SEARCH 탐색 동작 확인.
   - Chord Poly DLNA 렌더러로 실제 Tidal FLAC 음원 스트리밍 재생 검증.
   - 안드로이드 실기기 물리 볼륨 버튼 조절 시 Chord Poly 볼륨 연동 동작 확인.
