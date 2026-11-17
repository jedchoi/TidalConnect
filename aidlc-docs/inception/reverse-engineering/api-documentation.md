# API 문서 (API Documentation)

이 앱은 서버 API를 제공하지 않는다. 아래 "REST API"는 (1) 앱이 호출하는 외부 TIDAL API, (2) Flutter와 Kotlin 사이의 플랫폼 채널 계약, (3) 앱 안의 로컬 프록시 HTTP 엔드포인트, (4) 앱이 렌더러에 보내는 UPnP SOAP 액션을 정리한다. 모든 내용은 코드에서 확인한 것이다.

## REST API

### A. TIDAL 인증 (`TidalConfig.authBaseUrl = https://auth.tidal.com/v1/oauth2`)

#### 로그인 페이지 (WebView)
- **Method**: GET (WebView 탐색)
- **Path**: `https://login.tidal.com/authorize`
- **목적**: 사용자 로그인과 authorization code 획득
- **요청**: query에 `code_challenge`, `code_challenge_method=S256` 등(`tidal_webview_login_modal.dart`)
- **응답**: redirect URI(기본값 `https://tidal.com/android/login/auth`, `TidalConfig`)로 code 전달

#### 토큰 발급 - client_credentials
- **Method**: POST
- **Path**: `/token`
- **목적**: 로그인 전 카탈로그 조회용 토큰(`getCatalogToken`)
- **요청**: form `grant_type=client_credentials` (클라이언트 키 인증)
- **응답**: JSON access token

#### 토큰 발급 - authorization_code
- **Method**: POST
- **Path**: `/token`
- **목적**: 로그인 code 교환
- **요청**: form `client_id`, `grant_type=authorization_code`, `code`, `code_verifier`, `redirect_uri`
- **응답**: access/refresh token, 만료 시간 → `AuthToken`

#### 토큰 갱신 - refresh_token
- **Method**: POST
- **Path**: `/token`
- **목적**: 사용자 토큰 갱신
- **요청**: form `client_id`, `grant_type=refresh_token`, `refresh_token`
- **응답**: 새 access token

### B. TIDAL API v1 (`https://api.tidal.com/v1`, `TidalApiClient` / `TidalAuthRepository`)
모든 요청은 `AuthInterceptor`가 토큰을 붙이고 401이면 `recoverFromUnauthorized()`로 복구를 시도한다. 응답은 JSON이며 목록은 `items`/`totalNumberOfItems` 형태를 `PageResult<T>`로 변환한다.

| Method | Path | 목적 | 주요 요청 파라미터 |
|---|---|---|---|
| GET | `/sessions` | userId, countryCode 획득 | - |
| GET | `/users/{userId}/favorites/albums` | 즐겨찾기 앨범 | offset, limit, 최신순 |
| GET | `/users/{userId}/favorites/playlists` | 즐겨찾기 플레이리스트 | offset, limit, 최신순 |
| GET | `/users/{userId}/favorites/tracks` | 즐겨찾기 트랙 | offset, limit, 최신순 |
| GET | `/users/{userId}/favorites/artists` | 즐겨찾기 아티스트 | offset, limit, 최신순 |
| GET | `/users/{userId}/favorites/ids` | 유형별 즐겨찾기 ID 집합 | - |
| POST | `/users/{userId}/favorites/{tracks,albums,artists,playlists}` | 즐겨찾기 추가 | form `trackIds`/`albumIds`/`artistIds`/`uuids` |
| DELETE | `/users/{userId}/favorites/{type}/{id}` | 즐겨찾기 삭제 | - |
| GET | `/albums/{albumId}/tracks` | 앨범 트랙 | offset, limit(기본 100) |
| GET | `/playlists/{playlistId}/tracks` | 플레이리스트 트랙 | offset, limit |
| GET | `/playlists/{playlistId}/items` | 플레이리스트 항목(대체 경로) | offset, limit |
| GET | `/artists/{artistId}/toptracks` | 인기 트랙 | limit(기본 20) |
| GET | `/artists/{artistId}/albums` | 아티스트 앨범 | offset, limit |
| GET | `/tracks/{trackId}/playbackinfopostpaywall` | 재생 정보(직접 URL 또는 DASH MPD) | `audioquality`, `playbackmode=STREAM`, `assetpresentation=FULL` |
| GET | `/featured/new/albums` | 신규 앨범 | limit 20 |
| GET | `/featured/recommended/playlists` | 추천 플레이리스트 | limit 20 |
| GET | `/featured/recommended/tracks` | 추천 트랙 | limit 20 |
| GET | `/search` | 통합 검색 | query, limit 등 |
| GET | `/search/{tracks,albums,playlists,artists}` | 유형별 검색 | query, limit |
| GET | `/tracks/{trackId}/similarTracks` | 비슷한 트랙 | limit(기본 30) |
| GET | `/tracks/{trackId}/radio` | 트랙 라디오(대체 경로) | limit |

- 이미지: `https://resources.tidal.com/images/{uuid 경로}/{size}x{size}.jpg` (`tidalImageUrl`)
- `getPlaybackInfo`는 요청 음질이 실패하면 `lowerAudioQuality`로 한 단계 낮춰 재시도하는 한 번만 다시 시도한다(`audioQualityLadder`, `tidal_api_client.dart`). featured 계열은 `_withFallback`으로 대체 요청을 둔다.

### C. 플랫폼 채널 (Flutter <-> Kotlin)

#### MethodChannel `com.example.tidal_connect_lite/tidal_sdk` (Dart -> Kotlin, `PlaybackCore.onMethodCall`)
| Method | 인자 | 반환 |
|---|---|---|
| `initTidalAuth` | `clientId`, `clientSecret` | `{status: initialized/init_failed, sdk, clientId}` |
| `updateUserCredentials` | `userId`, `accessToken`, `expiresInSeconds`(기본 3600) | `{status: updated, userId}` |
| `clearUserCredentials` | - | `{status: cleared}` |
| `playTrack` | `trackId` | `{status: playing, trackId}` |
| `pauseTrack` | - | `{status: paused}` |
| `resumeTrack` | - | `{status: resumed}` |
| `seekTrack` | `positionMs` | `{status: seeked, positionMs}` |
| `stopTrack` | - | `{status: stopped}` |
| `skipToNext` | - | `{status: skipped_to_next}` |
| `setNextTrack` | `trackId` | `{status: next_track_set, trackId}` |
| `setAudioQuality` | `quality`(기본 LOSSLESS) | `{status: quality_set, quality}` |
| `getPhoneVolume` | - | int(백분율) |
| `setPhoneVolume` | `percent`(0~100) | - |
| `requestNotificationPermission` | - | - |
| `setStreamingLock` | `enabled` | - (Wi-Fi lock) |
| `registerTrackStream` | `trackId`, `directUrl`, `manifestXml`, `allowedHost`, `mimeType`(기본 audio/mp4) | `{proxyUrl}` 또는 오류 `NO_WIFI` |

플레이어 동작은 `runPlayerAction`으로 감싸며 플레이어가 없으면 "TIDAL Player가 초기화되지 않았습니다" 예외가 오류로 반환된다.

#### MethodChannel 역방향 (Kotlin -> Dart, `TidalSdkNativeBridge._installHandler`)
| Method | 인자 | 반환 |
|---|---|---|
| `refreshUserToken` | - | 갱신된 자격 증명 맵 또는 null (`CustomCredentialsProvider`가 사용) |
| `refreshTrackStream` | `trackId` | `{directUrl, manifestXml, mimeType}` 또는 null (프록시 CDN 주소 만료 시) |

#### EventChannel `com.example.tidal_connect_lite/player_events` (Kotlin -> Dart)
| `type` | 필드 | Dart 변환 (`PhoneBackend`) |
|---|---|---|
| `state` | `state`(SDK PlaybackState 이름) | `BackendStateChanged(playing: PLAYING 또는 STALLED, buffering: STALLED)` |
| `position` | `positionMs` (재생 중 500ms 주기) | `BackendPositionChanged` |
| `transition` | `trackId`, `durationMs`, `preview`, `audioQuality`, `bitDepth`, `sampleRate`, `codec` | `BackendTrackStarted` + `StreamQuality` |
| `ended` | `trackId` | `BackendTrackEnded` |
| `error` | `code`(예: `PRIVILEGES_REVOKED`), `message` | `BackendError` |
| `phoneVolume` | `percent` | `TidalSdkNativeBridge`의 볼륨 스트림 → `PlayerManager.onPhoneVolumeChanged` |

### D. 로컬 프록시 `TidalStreamProxyServer` (NanoHTTPD, `http://<LAN_IP>:8765`)

#### 오디오 스트림
- **Method**: GET, HEAD
- **Path**: `/audio/{token}.{ext}` (ext는 mime에서 결정, 예: `.mp4`)
- **목적**: 렌더러에 TIDAL 오디오를 짧은 URL로 제공
- **요청**: Range 헤더 지원(직접 CDN 중계). `allowedHost`가 지정되어 있으면 요청 IP가 그 값과 같아야 함
- **응답**: 오디오 바이트(직접 URL이면 CDN 중계, DASH면 세그먼트 연결 스트림). HEAD는 빈 본문과 길이/타입. 미등록 토큰 404, 허용되지 않은 IP 403, CDN URL 없음 400, 갱신 실패 시 403 `Stream expired`

#### 상태 확인
- **Method**: GET
- **Path**: `/ping`
- **목적**: 프록시 동작 확인
- **요청**: 없음
- **응답**: `200 text/plain "pong"` (그 밖의 경로는 404)

### E. UPnP (DLNA 렌더러, `UPnPSoapClient`, `SSDPDiscoveryService`)
- SSDP: UDP 멀티캐스트 M-SEARCH 반복 전송 후 응답의 LOCATION에서 기기 설명 XML을 받아 AVTransport/RenderingControl `controlURL`을 추출
- SOAP: POST `{controlUrl}`, 헤더 `SOAPACTION: "urn:schemas-upnp-org:service:<Service>:1#<Action>"`

| 서비스 | 액션 | 용도 |
|---|---|---|
| AVTransport:1 | `SetAVTransportURI` | 프록시 URL과 DIDL-Lite 메타데이터 설정 |
| AVTransport:1 | `SetNextAVTransportURI` | 다음 곡 미리 등록 |
| AVTransport:1 | `Play`, `Pause`, `Stop` | 재생 제어 |
| AVTransport:1 | `Seek` | `REL_TIME` 탐색 |
| AVTransport:1 | `GetTransportInfo` | 재생 상태 폴링 |
| AVTransport:1 | `GetPositionInfo` | 위치·길이 폴링 |
| RenderingControl:1 | `GetVolume`, `SetVolume` | 볼륨 |

## 내부 API

### PlaybackBackend (`lib/features/player/data/backends/playback_backend.dart`)
- **메서드**:
  - `Stream<BackendEvent> get events`
  - `bool get canSeek`
  - `Future<void> play(MediaTrack track, {Duration startPosition = Duration.zero, required IsCancelled isCancelled})`
  - `Future<void> pause()`, `resume()`, `seek(Duration position)`, `stop()`
  - `Future<void> setAudioQuality(String quality)`
  - `Future<void> setNext(MediaTrack? track)`
- **매개변수**: `quality`는 LOW, HIGH, LOSSLESS, HI_RES_LOSSLESS. `isCancelled`는 더 새로운 재생 요청이 있으면 true
- **반환 타입**: 모두 `Future<void>`, 실패 시 `PlaybackException(code, message)`

### PlayerManager (`lib/features/player/data/player_manager.dart`)
- **메서드**:
  - `void configure({authRepository, dlnaManager, apiClient})`
  - `void setQueue(List<MediaTrack> tracks, {int startIndex = 0})`
  - `void playQueueIndex(int index)`
  - `void togglePlayPause()`, `void seekTo(int seconds)`, `void skipToNext()`, `void skipToPrevious()`
  - `void toggleShuffle()`, `void toggleRepeat()`
  - `void onPhoneVolumeChanged(int phonePercent)`, `void adjustRemoteVolume(int direction)`, `void setVolume(int volumePercent, {bool isFinal = true})`
  - `setAudioQuality`, `resume`, `pause`(WaveAudioHandler·main.dart에서 호출)
- **매개변수**: 위 시그니처 참조
- **반환 타입**: void. 상태는 `ValueNotifier` 필드로 노출 — `currentTrackNotifier`, `isPlayingNotifier`, `isBufferingNotifier`, `progressSecondsNotifier`, `durationSecondsNotifier`, `qualityBadgeNotifier`, `isHiResNotifier`, `isShuffleNotifier`, `repeatModeNotifier`, `canSeekNotifier`, `queueNotifier`, `queueIndexNotifier`, `volumeNotifier`, `errorNotifier`(`PlayerError{id, message}`)

### TidalAuthRepository (`lib/features/auth/data/tidal_auth_repository.dart`)
- **메서드**: `initNativeSdk()`, `autoLogin()`, `getValidUserToken()`, `getCatalogToken()`, `recoverFromUnauthorized()`, `saveToken(AuthToken)`, `logout()`, 그리고 code 교환 메서드
- **매개변수**: 네이티브 연동은 `NativeCredentialsSink`(initialize, setUserCredentials, clearUserCredentials, setTokenRefresher) 주입 가능
- **반환 타입**: `Future<AuthToken?>`, `Future<String?>`(토큰 문자열), `Future<void>`

### TidalApiClient (`lib/features/tidal_api/data/tidal_api_client.dart`)
- **메서드**: `getFavoriteAlbums/Playlists/Tracks/Artists({userId, offset, limit})`, `getFavoriteIds({userId})`, `addFavorite/removeFavorite({userId, type, id})`, `getAlbumTracks`, `getPlaylistTracks`, `getArtistTopTracks`, `getArtistAlbums`, `getPlaybackInfo(trackId, {quality = 'LOSSLESS'})`, `getFeaturedAlbums/Playlists/Tracks()`, `searchTracks/Albums/Playlists/Artists(query, {limit = 20})`, `searchAll`, `getSimilarTracks(trackId, {limit = 30})`
- **매개변수**: 페이지 계열은 offset/limit
- **반환 타입**: `PageResult<T>`, `List<T>`, `SearchResults`, `TidalPlaybackInfo?`, `Map<FavoriteType, Set<String>>`. 오류는 `ApiFailure`로 분류

### FavoritesRepository (`lib/features/favorites/data/favorites_repository.dart`)
- **메서드**: `setUser(String? userId)`, `isFavorite(FavoriteType, String id)`, `isPending(FavoriteType, String id)`, 토글(추가·삭제)
- **반환 타입**: `ChangeNotifier`로 변경 알림

### DlnaManager / UPnPSoapClient
- **메서드**: `DlnaManager.selectDevice(DlnaDevice)`, 탐색·선택 해제·위치 조회 등. `UPnPSoapClient.setAVTransportURI(controlUrl, streamUrl, DidlMetadata)`, `setNextAVTransportURI`, `play`, `pause`, `stop`, `seek(controlUrl, relTime)`, `getTransportInfo`, `getPositionInfo`, `getVolume`, `setVolume(controlUrl, volumePercent)`
- **반환 타입**: `Future<bool>`(성공 여부), `Future<String?>`, `Future<Map<String,String>?>`, `Future<int?>`

### 저장소 (SharedPreferences)
- `PlaybackSettings`(`load()`, `audioQuality` ValueNotifier), `RecentlyPlayedStore`(`load()`, `add(track)`), `SearchHistoryStore`, `SecureStorageService`(토큰, flutter_secure_storage)

## 데이터 모델

### MediaTrack
- **필드**: `id`, `title`, `artistName`, `albumTitle`, `coverUrl`, `durationSeconds`, `audioQuality`(기본 LOSSLESS)
- **관계**: 앨범·아티스트 이름을 문자열로 보유, `PlayQueue`와 `PlaybackBackend.play`의 입력
- **검증**: `fromJson`에서 누락 필드 기본값 처리, `resolveAudioQuality(json)`로 음질 결정

### MediaAlbum
- **필드**: `id`, `title`, `artistName`, `coverUrl`, `numberOfTracks`, `audioQuality`(기본 빈 문자열)
- **관계**: `getAlbumTracks`로 `MediaTrack` 목록
- **검증**: `fromJson` 기본값 처리

### MediaPlaylist
- **필드**: `id`(uuid), `title`, `description`, `coverUrl`, `numberOfTracks`
- **관계**: `getPlaylistTracks`로 `MediaTrack` 목록
- **검증**: `fromJson` 기본값 처리

### MediaArtist
- **필드**: `id`, `name`, `pictureUrl`
- **관계**: 인기 트랙, 앨범
- **검증**: `fromJson` 기본값 처리

### AuthToken
- **필드**: `accessToken`, `refreshToken`, `expiresAt`, `userId`, `countryCode`
- **관계**: `TidalAuthRepository`가 관리, secure storage에 저장
- **검증**: 만료 시간 기준 갱신 판단

### DlnaDevice
- **필드**: `udn`, `friendlyName`, `locationUrl`, `avTransportControlUrl`, `renderingControlUrl`, `isLocalSpeaker`
- **관계**: `DlnaManager`의 선택 기기, `DlnaBackend`의 대상
- **검증**: `isLocalSpeaker`로 폰 출력 구분

### TidalPlaybackInfo / StreamQuality / BackendEvent
- **필드**: `TidalPlaybackInfo` — `streamUrl`, `manifest`(DASH MPD 원문), `manifestMimeType`, `mimeType`(기본 audio/mp4), `audioQuality`, `bitDepth`, `sampleRate`, `isDash`(streamUrl 비고 manifest 있음). `StreamQuality` — `audioQuality`, `bitDepth`, `sampleRate`, `codec`, `preview`. `BackendEvent` — 위 EventChannel 표 참조
- **관계**: 재생 정보 → 프록시 등록, `StreamQuality` → `qualityBadgeNotifier`/`isHiResNotifier`
- **검증**: `isHiRes`는 `HI_RES` 포함 또는 24-bit 이상

### Kotlin: DashManifest / StreamInfo
- **필드**: `DashManifest` — `mediaTemplate`, `startNumber`, `segmentCount` 등(`segmentUrl(index)`가 `$Number$` 치환). `StreamInfo` — `trackId`, `directUrl`, `manifestXml`, `allowedHost`, `mimeType`
- **관계**: 프록시가 토큰별 `StreamInfo`를 LRU 맵에 보관
- **검증**: `DashManifest.parse`가 실패 시 null, `DashManifestTest.kt`가 검증
