# 도메인 엔티티 (Domain Entities) - dart-playback-tests

이 unit 은 새 엔티티를 만들지 않는다. 아래는 테스트가 입력 · 출력으로 다루는 기존 데이터와, 속성 기반 테스트의 생성기가 만들 값의 범위다.

## 1. 기존 엔티티

### 백엔드 이벤트 (`lib/features/player/data/backends/playback_backend.dart`)

| 엔티티 | 필드 | 쓰이는 곳 |
| --- | --- | --- |
| `BackendStateChanged` | `playing: bool`, `buffering: bool` (기본 false) | 두 백엔드의 출력 |
| `BackendPositionChanged` | `position: Duration`, `duration: Duration?` | 두 백엔드의 출력 |
| `BackendTrackStarted` | `trackId: String`, `duration: Duration?`, `quality: StreamQuality?` | 두 백엔드의 출력 |
| `BackendTrackEnded` | `trackId: String` | 두 백엔드의 출력 |
| `BackendError` | `code: String`, `message: String` | 두 백엔드의 출력 |
| `StreamQuality` | `audioQuality: String`, `bitDepth: int?`, `sampleRate: int?`, `codec: String?`, `preview: bool` | `BackendTrackStarted` 의 일부 |
| `PlaybackException` | `code: String`, `message: String` | 두 백엔드의 명령 실패 |

`BackendEvent` 의 하위 클래스는 `==` 를 정의하지 않을 수 있다. 테스트는 타입과 필드 값으로 비교한다 (비교 도우미는 NFR Design 에서 정한다).

### 곡 · 스트림

| 엔티티 | 필드 | 위치 |
| --- | --- | --- |
| `MediaTrack` | `id`, `title`, `artistName`, `albumTitle`, `coverUrl`, `durationSeconds`, `audioQuality` | `lib/features/tidal_api/domain/models/media_item.dart` |
| `TidalPlaybackInfo` | `streamUrl`, `manifest`, `manifestMimeType`, `mimeType` (기본 `audio/mp4`), `audioQuality`, `bitDepth?`, `sampleRate?`, 계산값 `isDash` (`streamUrl` 이 비고 `manifest` 가 있음) | `lib/features/tidal_api/data/tidal_api_client.dart` |
| `AuthToken` | `accessToken`, `refreshToken`, `expiresAt`, `userId`, `countryCode` | `lib/features/auth/domain/models/auth_token.dart` |

### DLNA

| 엔티티 | 필드 | 위치 |
| --- | --- | --- |
| `DlnaDevice` | `udn`, `friendlyName`, `locationUrl`, `avTransportControlUrl`, `renderingControlUrl`, `isLocalSpeaker`. 폰 스피커는 `DlnaDevice.localSpeaker` (`udn` 이 `local_speaker`, URL 은 모두 빈 값) | `lib/features/dlna/domain/models/dlna_device.dart` |
| `DlnaPosition` | `progressSeconds: int`, `durationSeconds: int`, `trackUri: String` | `lib/features/dlna/data/dlna_manager.dart` |
| `DidlMetadata` | `title`, `artist`, `album`, `albumArtUri`, `durationSeconds`, `mimeType` | `lib/features/dlna/data/upnp_soap_client.dart` |

### 채널 데이터 (타입 없는 맵)

| 데이터 | 형태 | 기준 |
| --- | --- | --- |
| 채널 호출 | 메서드 이름 + 인자 맵 | `api-documentation.md` C절의 MethodChannel 표 |
| 네이티브 이벤트 | `{type: ..., 그 밖의 필드}` | `api-documentation.md` C절의 EventChannel 표 |
| 주소 재발급 응답 | `{directUrl, manifestXml, mimeType}` 또는 null | 같은 절의 역방향 표 |

### 저장소

| 키 | 값 | 쓰는 컴포넌트 |
| --- | --- | --- |
| `selected_speaker_udn` (SharedPreferences) | 마지막에 고른 원격 스피커의 UDN. 폰 스피커를 고르면 키 삭제 | `DlnaManager` |

## 2. 엔티티 관계

```text
MediaTrack --(재생 요청)--> PhoneBackend / DlnaBackend --> BackendEvent
MediaTrack + TidalPlaybackInfo --> DidlMetadata (스피커에 보내는 곡 정보)
MediaTrack + TidalPlaybackInfo --> StreamQuality (BackendTrackStarted 에 실림)
DlnaDevice --(선택)--> DlnaManager --(제어 URL)--> SOAP
SOAP GetPositionInfo 응답 --> DlnaPosition --> BackendPositionChanged
MediaTrack --> MediaItem (audio_service, WaveAudioHandler 의 출력)
```

## 3. 생성기 범위 (PBT 입력)

속성 기반 테스트의 생성기는 아래 범위의 값을 만든다 (PBT-07: 기본 타입이 아니라 도메인에 맞는 값). 범위 밖으로 둔 입력과 그 이유는 `business-rules.md` 7절 관찰 사항에 있다.

| 생성기 | 만드는 값 | 쓰는 속성 |
| --- | --- | --- |
| 곡 ID | 숫자로 된 문자열, 1 ~ 12자리 | 전반 |
| 곡 (`MediaTrack`) | ID 는 위와 같음. 제목 · 아티스트 · 앨범은 빈 문자열 포함 임의의 문자열 (한글 · 기호 포함). `durationSeconds` 는 0 ~ 36000. `coverUrl` 은 빈 문자열 또는 `https://` 로 시작하는 유효한 주소 | P-WA-1, P-WA-2 |
| 곡 목록 | 곡 0 ~ 50개 | P-WA-2 |
| 네이티브 이벤트 맵 | `type` 은 5종 + `phoneVolume` + 임의 문자열 + 없음. 그 밖의 필드는 각각 "있음 (계약의 타입)" 또는 "없음". 숫자 필드는 0 이상 | P-PB-1, P-PB-3, P-PB-4 |
| 플레이어 상태 문자열 | `PLAYING`, `STALLED`, `NOT_PLAYING`, `IDLE` + 임의의 문자열 | P-PB-2 |
| 폰 백엔드 동작 순서 | `play(시작 위치 0 ~ 600초)`, 상태 이벤트, `stop()` 을 1 ~ 30개 이은 것 | P-PB-5 |
| 초 | 0 ~ 359999 (99:59:59 까지) | P-DM-1, P-DM-2, P-DB-5 |
| 볼륨 | −1000 ~ 1000 의 정수 | P-DM-3 |
| 소수 초 | 0 ~ 999 밀리초를 `.fff` 로 | P-DM-4 |
| 임의의 시간 문자열 | 길이 0 ~ 20 의 임의 문자열 (콜론 포함 빈도를 높임) | P-DM-4 |
| 원격 기기 (`DlnaDevice`) | `udn` 은 `uuid:` + 임의의 16진 문자열. `locationUrl` 은 `http://<IPv4>:<포트>/<경로>`. 제어 URL 두 개는 각각 빈 값 또는 같은 호스트의 주소 | P-DM-5, P-DM-6, P-DB-4 |
| 탐색 상황 | 탐색 결과 (원격 기기 0 ~ 5개, UDN 중복 없음) × 이전 선택 (폰 스피커 / 결과 안의 기기 / 결과 밖의 기기) × 저장된 UDN (없음 / 결과 안 / 결과 밖) × 재생 중 여부 | P-DM-6 |
| 폴링 응답 | 전송 상태 (`PLAYING`, `TRANSITIONING`, `PAUSED_PLAYBACK`, `STOPPED`, `NO_MEDIA_PRESENT`, 임의 문자열, null) × 위치 (null 또는 `RelTime` 0 ~ 곡 길이 + 10초, `TrackDuration` 0 또는 곡 길이) | P-DB-1, P-DB-2 |
| 폴링 응답 순서 | 폴링 응답 1 ~ 30개 | P-DB-1, P-DB-2 |
| 주소 변형 | 등록한 프록시 주소에 대해: 호스트를 다른 IPv4 · 호스트 이름으로, 포트를 다른 값으로, 스킴을 `https` 로, 앞뒤에 공백. 음성 사례용으로 경로의 토큰 한 글자 바꾸기, 쿼리 붙이기 | P-DB-3 |

## 4. 요구 데이터와의 대조 (FD-2)

| 요구사항이 다루는 데이터 | 이 문서의 엔티티 |
| --- | --- |
| FR-01 의 채널 호출 · 이벤트 5종 · `StreamQuality` · `PlaybackException` | 1절 백엔드 이벤트, 채널 데이터 |
| FR-02 의 프록시 URL · SOAP 메타데이터 · 폴링 응답 | `TidalPlaybackInfo`, `DidlMetadata`, `DlnaPosition` |
| FR-03 의 기기 · UDN 저장 · `DlnaPosition` | `DlnaDevice`, 저장소, `DlnaPosition` |
| FR-04 의 `playbackState` · `mediaItem` | `MediaTrack` → `MediaItem` (audio_service 타입) |

요구사항에 없는 엔티티: `AuthToken`. `DlnaBackend` 의 로그인 여부 분기 (DB-02, DB-49) 에 필요해 넣었다.
