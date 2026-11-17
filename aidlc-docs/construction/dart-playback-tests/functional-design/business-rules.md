# 비즈니스 규칙 (Business Rules) - dart-playback-tests

대상 4개 컴포넌트가 **지금 코드에서 보이는 동작** 을 규칙으로 적었다. 규칙 하나가 Code Generation 에서 테스트 케이스 하나 이상이 된다. 판단 기준 (계획 Q1=A): 문서 · 주석의 의도와 다르거나 예외 · 잘못된 상태를 남기는 경우만 버그로 고치고, 그 밖에는 지금 동작을 고정한다.

규칙 ID: `PB` = `PhoneBackend`, `DB` = `DlnaBackend`, `DM` = `DlnaManager`, `WA` = `WaveAudioHandler`.

채널 메서드 이름과 인자 키는 `aidlc-docs/inception/reverse-engineering/api-documentation.md` C절 기준이다.

---

## 1. `PhoneBackend` (FR-01)

### 명령 → 채널 호출

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| PB-01 | `play(track)` | 채널 `playTrack` 을 `{trackId: track.id}` 로 1회 호출 |
| PB-02 | `play` 의 채널 호출이 실패, `isCancelled()` 가 false | `PlaybackException('PHONE_PLAY_FAILED', ...)` |
| PB-03 | `play` 의 채널 호출이 실패, `isCancelled()` 가 true | 예외 없음 |
| PB-04 | `pause()` | 채널 `pauseTrack` 호출. 실패하면 `PlaybackException('PHONE_PAUSE_FAILED', ...)` |
| PB-05 | `resume()` | 채널 `resumeTrack` 호출. 실패하면 `PlaybackException('PHONE_RESUME_FAILED', ...)` |
| PB-06 | `seek(position)` | 채널 `seekTrack` 을 `{positionMs: position.inMilliseconds}` 로 호출. 실패해도 예외 없음 |
| PB-07 | `stop()` | 채널 `stopTrack` 호출. 실패해도 예외 없음 |
| PB-08 | `setAudioQuality(q)` | 채널 `setAudioQuality` 를 `{quality: q}` 로 호출. 실패해도 예외 없음 |
| PB-09 | `setNext(track)` | 채널 `setNextTrack` 을 `{trackId: track.id}` 로 호출. `track` 이 null 이면 `{trackId: ''}`. 실패해도 예외 없음 |
| PB-10 | `canSeek` | 항상 true |

PB-06 ~ PB-09 의 "실패해도 예외 없음" 은 계획 Q2=A 로 확정한 규칙이다. `PlayerManager` 가 `seek` · `stop` 을 오류 처리 없이 호출하므로 (`player_manager.dart:354`, `:364`) 이 동작에 의존한다.

### 재생 시작 뒤 탐색 (pending seek)

SDK 는 IDLE 상태에서 seek 를 받지 않으므로 (코드 주석) 시작 위치는 재생이 시작된 뒤에 적용한다.

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| PB-11 | `play(track, startPosition: p)`, p > 0, 그 뒤 `state` 이벤트 `PLAYING` | `play` 직후에는 `seekTrack` 호출 없음. 첫 `PLAYING` 에서 `seekTrack {positionMs: p.inMilliseconds}` 1회. 다음 `PLAYING` 에서는 호출 없음 |
| PB-12 | `play(track)` (시작 위치 0), 그 뒤 `PLAYING` | `seekTrack` 호출 없음 |
| PB-13 | `play(startPosition: p)` 뒤 `PLAYING` 전에 `stop()` | 이후 `PLAYING` 이 와도 `seekTrack` 호출 없음 |
| PB-14 | `play(startPosition: p1)` 뒤 `PLAYING` 전에 `play(startPosition: 0)` | 이후 `PLAYING` 에서 `seekTrack` 호출 없음 (새 요청이 이전 시작 위치를 대체) |
| PB-15 | `play(startPosition: p)` 뒤 `state` 이벤트 `STALLED` | `seekTrack` 호출 없음 (`PLAYING` 에서만 적용) |

### 네이티브 이벤트 → `BackendEvent`

| ID | 입력 이벤트 | 기대 결과 |
| --- | --- | --- |
| PB-16 | `{type: state, state: PLAYING}` | `BackendStateChanged(playing: true, buffering: false)` |
| PB-17 | `{type: state, state: STALLED}` | `BackendStateChanged(playing: true, buffering: true)` |
| PB-18 | `{type: state, state: 그 밖의 값 또는 없음}` | `BackendStateChanged(playing: false, buffering: false)` |
| PB-19 | `{type: position, positionMs: n}` | `BackendPositionChanged(Duration(milliseconds: n), duration: 현재 길이)`. `positionMs` 가 없으면 0 |
| PB-20 | 현재 길이 | 마지막 `play(track)` 의 `track.durationSeconds` (0 이면 null), 또는 그 뒤에 온 `transition` 의 `durationMs` |
| PB-21 | `{type: transition, trackId, durationMs, audioQuality, bitDepth, sampleRate, codec, preview}` | `BackendTrackStarted(trackId, duration, quality: StreamQuality(...))`. `durationMs` 가 0 이하이거나 없으면 `duration` 은 null. `audioQuality` 가 없으면 `''`. `preview` 는 값이 true 일 때만 true |
| PB-22 | `{type: ended, trackId: id}` | `BackendTrackEnded(id)`. `trackId` 가 없으면 현재 곡 ID (마지막 `play` 또는 `transition`), 그것도 없으면 `''` |
| PB-23 | `{type: error, code, message}` | `BackendError(code, message)`. 없으면 각각 `'UNKNOWN'`, `'재생 오류'` |
| PB-24 | `type` 이 위 5개가 아님 (`phoneVolume` 포함) 또는 없음 | 이벤트 없음, 예외 없음 |
| PB-25 | 네이티브 이벤트 스트림에 오류 | 무시 (예외가 밖으로 나오지 않음) |
| PB-26 | `dispose()` | 네이티브 구독 취소, `events` 스트림 닫힘 |

---

## 2. `DlnaManager` (FR-03)

테스트의 "원격 스피커" 는 `isLocalSpeaker` 가 false 인 `DlnaDevice` 다.

### 제어 URL 선택

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| DM-01 | 폰 스피커 선택 상태에서 `playOnSelectedDevice`, `pauseCurrent`, `resumeCurrent`, `seek`, `stopCurrent`, `setVolume` | SOAP 호출 없이 true |
| DM-02 | 폰 스피커 선택 상태에서 `fetchVolume`, `syncPosition`, `getTransportState` | SOAP 호출 없이 null |
| DM-03 | 폰 스피커 선택 상태에서 `setNextOnSelectedDevice` | SOAP 호출 없이 false |
| DM-04 | 원격 스피커, 전송 명령 (재생 · 일시정지 · 탐색 · 정지 · 위치 · 상태 · 다음 곡) | `avTransportControlUrl` 로 보냄. 비어 있으면 `locationUrl` |
| DM-05 | 원격 스피커, 볼륨 명령 | `renderingControlUrl` 로 보냄. 비어 있으면 `locationUrl` |
| DM-06 | 원격 스피커인데 쓸 URL 이 모두 빈 문자열 | SOAP 호출 없이 실패 값 (bool 은 false, 조회는 null) |

### 명령 전달

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| DM-07 | `playOnSelectedDevice(streamUrl, metadata)` 성공 | SOAP 순서: `Stop` → `SetAVTransportURI(streamUrl, metadata)` → `Play`. `Play` 결과를 반환 |
| DM-08 | `SetAVTransportURI` 가 false | `Play` 를 보내지 않고 false |
| DM-09 | 처음의 `Stop` 이 false | 무시하고 계속 진행 (PAUSED 상태 렌더러 초기화용, 코드 주석) |
| DM-10 | SOAP 클라이언트가 예외 | false |
| DM-11 | `pauseCurrent` / `resumeCurrent` / `stopCurrent` | 각각 SOAP `Pause` / `Play` / `Stop`, 그 결과를 반환 |
| DM-12 | `seek(seconds)` | SOAP `Seek` 에 `HH:MM:SS` (각 부분 2자리 이상, 0 채움) 전달. 예: 3725 → `01:02:05` |
| DM-13 | `fetchVolume()` | SOAP `GetVolume` 결과를 0 ~ 100 으로 자른 값. 응답이 없으면 null |
| DM-14 | `setVolume(v)` | v 를 0 ~ 100 으로 자른 값을 SOAP `SetVolume` 에 전달, 그 결과를 반환 |
| DM-15 | `syncPosition()` | SOAP `GetPositionInfo` 의 `RelTime`, `TrackDuration`, `TrackURI` 를 `DlnaPosition(progressSeconds, durationSeconds, trackUri)` 로. 응답이 없으면 null. `TrackURI` 가 없으면 `''` |
| DM-16 | 시간 문자열 해석 | `H:MM:SS` → 초. 초 부분의 소수는 버림 (`0:03:25.500` → 205). 빈 문자열, `NOT_IMPLEMENTED`, 콜론으로 3부분이 아닌 값 → 0. 숫자가 아닌 부분은 0 으로 계산 |
| DM-17 | `setNextOnSelectedDevice(streamUrl, metadata)` | SOAP `SetNextAVTransportURI`, 그 결과를 반환 |
| DM-18 | `getTransportState()` | SOAP `GetTransportInfo` 결과 (문자열 또는 null) |

### 탐색과 선택

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| DM-19 | `selectDevice(원격 기기)` | `selectedDeviceNotifier` 가 그 기기. 저장소 `selected_speaker_udn` 에 UDN 저장 |
| DM-20 | `selectDevice(폰 스피커)` | `selectedDeviceNotifier` 가 폰 스피커. 저장소에서 `selected_speaker_udn` 삭제 |
| DM-21 | `discoverDevices()` 진행 | 시작 시 `isSearchingNotifier` true, 끝나면 false. `devicesNotifier` 는 폰 스피커만 있는 목록으로 초기화된 뒤 기기가 발견될 때마다 늘고, 끝나면 탐색 결과 전체가 됨. 반환값은 탐색 결과 |
| DM-22 | 탐색 중에 `discoverDevices()` 를 다시 호출 | 탐색 서비스를 다시 부르지 않고 현재 목록 반환 |
| DM-23 | 탐색 서비스가 예외 | 현재 목록 반환, `isSearchingNotifier` false |
| DM-24 | 폰 스피커 선택 상태, 저장된 UDN 의 기기가 탐색 결과에 있음 | 그 기기를 자동 선택 |
| DM-25 | 폰 스피커 선택 상태, 저장된 UDN 이 없거나 탐색 결과에 없음 | 폰 스피커 유지 |
| DM-26 | 원격 스피커 선택 상태, 그 기기가 탐색 결과에 없음, 재생 중 아님 | 폰 스피커로 전환, `messageNotifier` 에 `"<기기 이름>"을(를) 찾지 못해 폰 스피커로 전환했습니다.` 저장된 UDN 은 지우지 않음 (다음 탐색에서 복원, 코드 주석) |
| DM-27 | 원격 스피커 선택 상태, 그 기기가 탐색 결과에 있음 | 선택 유지, 안내 문구 없음 |
| DM-28 | `isPlaybackActive` 가 true 를 반환 | 탐색 결과와 상관없이 선택을 바꾸지 않음 (DM-24, DM-26 모두 적용 안 됨) |
| DM-29 | DM-26 으로 폰 스피커가 된 뒤 다시 탐색했더니 그 기기가 보임 | DM-24 에 따라 다시 자동 선택 |

---

## 3. `DlnaBackend` (FR-02)

전제: 원격 스피커가 선택된 `DlnaManager`, 사용자 토큰 있음, 스트림 정보 있음. 각 규칙은 여기서 달라지는 조건만 적는다.

### 재생 요청

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| DB-01 | `play(track)` 시작 | 진행 중이던 폴링 중지, 등록해 둔 다음 곡 정보 삭제, 채널 `stopTrack` 호출 (폰과 동시에 소리 나지 않게, 코드 주석) |
| DB-02 | 사용자 토큰 없음 | `PlaybackException('NOT_LOGGED_IN', ...)`. 스트림 조회 · 채널 등록 · SOAP 없음 |
| DB-03 | 스트림 정보 없음 (`getPlaybackInfo` 가 null) | `PlaybackException('NO_STREAM', ...)`. 채널 등록 · SOAP 없음 |
| DB-04 | 스트림 조회 | `getPlaybackInfo(track.id, quality: preferredQuality)`. `preferredQuality` 의 초기값은 `LOSSLESS`, `setAudioQuality(q)` 로 바뀜 |
| DB-05 | 프록시 등록 | 채널 `registerTrackStream` 을 `{trackId, directUrl: info.streamUrl, manifestXml: info.manifest, allowedHost: 선택 기기 locationUrl 의 호스트, mimeType: info.mimeType}` 로 호출. 호스트를 알 수 없으면 `''` |
| DB-06 | 프록시 URL 이 빈 값 (채널 오류, 예: `NO_WIFI`, 또는 응답에 `proxyUrl` 없음) | `PlaybackException('PROXY_FAILED', ...)`. SOAP 없음 |
| DB-07 | 성공 흐름의 순서 | (1) `BackendTrackStarted(track.id, duration, quality)` → (2) SOAP `Stop` · `SetAVTransportURI(프록시 URL, 메타데이터)` · `Play` → (3) 채널 `setStreamingLock {enabled: true}`, `BackendStateChanged(playing: true, buffering: true)`, 폴링 시작 |
| DB-08 | (1) 의 내용 | `duration` 은 `track.durationSeconds` (0 이면 null). `quality` 는 `StreamQuality(audioQuality, bitDepth, sampleRate)` (스트림 정보 값) |
| DB-09 | (2) 의 메타데이터 | `DidlMetadata(title, artist, album, albumArtUri, durationSeconds, mimeType)` 가 곡과 스트림 정보 값 |
| DB-10 | 스피커 재생 명령 실패 | `PlaybackException('DLNA_PLAY_FAILED', ...)`, 메시지에 기기 이름 포함. 폴링 시작 안 함, `setStreamingLock(true)` 없음 |
| DB-11 | `startPosition` > 0, 단일 파일 스트림 | 재생 명령 뒤 SOAP `Seek` (초 단위) |
| DB-12 | `startPosition` > 0, DASH 스트림 | `Seek` 없음 |
| DB-13 | `canSeek` | 초기값 true. DASH 곡을 보내면 false, 단일 파일 곡을 보내면 true |
| DB-14 | 진행 중 `isCancelled()` 가 true 가 됨 (토큰 조회 뒤 / 스트림 조회 뒤 / 프록시 등록 뒤 / 재생 명령 뒤) | 예외 없이 끝나고 그 뒤 단계는 실행하지 않음 |
| DB-15 | `play` 를 연달아 두 번 호출 | 두 번째 요청의 스피커 명령 (등록 · SOAP) 은 첫 번째 요청의 스피커 명령이 끝난 뒤에 시작 (섞이지 않음). 첫 번째가 실패해도 두 번째는 실행됨 |

### 폴링 (1초 간격)

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| DB-16 | 재생 성공 뒤 1초마다 | SOAP `GetTransportInfo` 와 `GetPositionInfo` 를 각 1회 |
| DB-17 | 위치 응답 있음 | `BackendPositionChanged(Duration(seconds: RelTime), duration)`. `duration` 은 렌더러의 `TrackDuration` 이 0 보다 크면 그 값, 아니면 곡의 길이 |
| DB-18 | 상태 `PLAYING` | `BackendStateChanged(playing: true)` |
| DB-19 | 상태 `TRANSITIONING` | `BackendStateChanged(playing: true, buffering: true)` |
| DB-20 | 상태 `PAUSED_PLAYBACK` | `BackendStateChanged(playing: false)` |
| DB-21 | 그 밖의 상태 문자열, 또는 상태만 null | 상태 이벤트 없음 |
| DB-22 | `PLAYING` 을 한 번도 보지 못한 채 `STOPPED` 또는 `NO_MEDIA_PRESENT` | 상태 이벤트 없음, 폴링 계속 (재생 시작 전의 일시적 정지, 코드 주석) |
| DB-23 | `PLAYING` 을 본 뒤 `STOPPED` 또는 `NO_MEDIA_PRESENT`, 마지막 위치 ≥ 길이 − 3초 | 폴링 중지, `BackendTrackEnded(trackId)` 1회 |
| DB-24 | DB-23 과 같지만 길이를 모름 | 폴링 중지, `BackendTrackEnded(trackId)` 1회 |
| DB-25 | `PLAYING` 을 본 뒤 `STOPPED`, 마지막 위치 < 길이 − 3초 | 폴링 중지, `BackendStateChanged(playing: false)`. `BackendTrackEnded` 없음 (스피커 쪽에서 직접 정지, 코드 주석) |
| DB-26 | 마지막 위치 | 0 보다 큰 위치만 기억. 정지 시점에 렌더러가 0 을 알려도 직전 위치로 판정 |
| DB-27 | 상태와 위치가 모두 null, 연속 3회 | 폴링 중지, `BackendStateChanged(playing: false)`, `BackendError('DLNA_UNREACHABLE', ...)` |
| DB-28 | 모두 null 이 1 ~ 2회 뒤 정상 응답 | 실패 횟수 초기화 (이후 다시 3회 연속이어야 DB-27) |
| DB-29 | 응답을 기다리는 사이 `stop()` 또는 새 `play` | 늦게 도착한 응답은 버림 (이벤트 없음) |
| DB-30 | 이전 확인이 아직 끝나지 않았는데 다음 1초가 됨 | 그 차례는 건너뜀 (SOAP 요청을 겹쳐 보내지 않음) |
| DB-31 | 폴링이 멈추는 모든 경우 (`stop`, 곡 끝, 응답 없음, 새 `play`) | 채널 `setStreamingLock {enabled: false}` |

### 갭리스 (`setNext`)

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| DB-32 | `setNext(track)` | 스트림 조회 → 채널 `registerTrackStream` → SOAP `SetNextAVTransportURI(프록시 URL, 메타데이터)` |
| DB-33 | 같은 곡으로 `setNext` 를 다시 호출 | 아무 호출 없음 |
| DB-34 | `setNext(null)`, 등록된 다음 곡 있음 | SOAP `SetNextAVTransportURI('')` 로 등록 삭제 |
| DB-35 | `setNext(null)`, 등록된 다음 곡 없음 | 아무 호출 없음 |
| DB-36 | 폰 스피커 선택 상태에서 `setNext` | 아무 호출 없음 |
| DB-37 | 렌더러가 `SetNextAVTransportURI` 를 거부 (false) | 그 기기 (UDN) 에는 이후 `setNext` 를 시도하지 않음 |
| DB-38 | 스트림 정보 없음, 프록시 URL 빈 값, 또는 준비하는 사이 선택 기기가 바뀜 | `SetNextAVTransportURI` 없음 |
| DB-39 | 폴링에서 `TrackURI` 가 현재 주소와 다르고, 등록해 둔 다음 곡 주소와 경로 · 쿼리가 같음 (호스트 표기는 달라도 됨) | `BackendTrackStarted(다음 곡 ID, duration, quality)`. 그 차례에는 위치 · 상태 이벤트 없음. 이후의 `BackendTrackEnded` 는 새 곡 ID. `canSeek` 은 새 곡 기준 |
| DB-40 | `TrackURI` 가 빈 값이거나, 현재 주소와 같거나, 등록한 주소와 다름 | 전환 없음 (일반 폴링 규칙 적용) |
| DB-41 | `setNext` 뒤 새 `play` | 등록 정보가 지워져, 이후 `TrackURI` 가 바뀌어도 DB-39 가 일어나지 않음 |
| DB-42 | `setNext` 와 `play` 가 겹침 | DB-15 와 같은 직렬화 대상 (스피커 명령이 섞이지 않음) |

### 그 밖의 명령

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| DB-43 | `pause()` | SOAP `Pause`. 성공하면 `BackendStateChanged(playing: false)`, 실패하면 `PlaybackException('DLNA_PAUSE_FAILED', ...)` |
| DB-44 | `resume()` | SOAP `Play`. 성공하면 `BackendStateChanged(playing: true)`, 실패하면 `PlaybackException('DLNA_RESUME_FAILED', ...)` |
| DB-45 | `seek(position)` | SOAP `Seek` (초 단위). 결과는 무시 |
| DB-46 | `stop()` | 폴링 중지, SOAP `Stop`, `BackendStateChanged(playing: false)`. 이후 시간이 지나도 SOAP 조회 없음 |
| DB-47 | `dispose()` | 폴링 중지, `events` 스트림 닫힘 |

### 주소 재발급 (네이티브 → Dart)

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| DB-48 | 네이티브가 `refreshTrackStream {trackId}` 호출 | `getPlaybackInfo(trackId, quality: preferredQuality)` 결과로 `{directUrl, manifestXml, mimeType}` 반환 |
| DB-49 | 사용자 토큰 없음 또는 스트림 정보 없음 | null 반환 |

---

## 4. `WaveAudioHandler` (FR-04)

`PlayerManager` 는 실제 객체를 쓰고, 그 백엔드만 `FakeBackend` 다. "명령 전달" 은 `PlayerManager` 의 상태 변화 또는 `FakeBackend` 의 호출 기록으로 확인한다.

### 명령 전달

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| WA-01 | `play()` | `PlayerManager.resume()` |
| WA-02 | `pause()` | `PlayerManager.pause()` |
| WA-03 | `stop()` | `PlayerManager.stop()` 이 실행됨 (재생 상태 false, 백엔드 `stop` 호출) |
| WA-04 | `seek(position)` | `PlayerManager.seekTo(position.inSeconds)` |
| WA-05 | `skipToNext()` / `skipToPrevious()` | `PlayerManager.skipToNext()` / `skipToPrevious()` |
| WA-06 | `skipToQueueItem(i)` | `PlayerManager.playQueueIndex(i)` |
| WA-07 | `onTaskRemoved()` | WA-03 과 같음 (앱을 최근 목록에서 밀어내면 재생 중지, 코드 주석) |
| WA-08 | `androidAdjustRemoteVolume(raise)` / `(lower)` | `PlayerManager.adjustRemoteVolume(1)` / `(-1)`. `same` 은 아무 일 없음 |
| WA-09 | `androidSetRemoteVolume(v)` | `PlayerManager.setVolume(v)` |

### 상태 알림

| ID | 조건 | 기대 결과 |
| --- | --- | --- |
| WA-10 | 생성 직후 | `playbackState` 가 한 번 알려짐: `processingState` idle, `playing` false |
| WA-11 | 재생 중 | `controls` 가 [이전, 일시정지, 다음], `playing` true |
| WA-12 | 재생 중 아님 | `controls` 가 [이전, 재생, 다음], `playing` false |
| WA-13 | `androidCompactActionIndices` | 항상 [0, 1, 2] |
| WA-14 | `PlayerManager.canSeekNotifier` 가 true / false | `systemActions` 에 `seek` 있음 / 없음 |
| WA-15 | `processingState` | 현재 곡 없음 → idle. 곡 있고 버퍼링 중 → buffering. 곡 있고 버퍼링 아님 → ready |
| WA-16 | `updatePosition` | `Duration(seconds: PlayerManager.progressSeconds)` |
| WA-17 | `queueIndex` | `PlayerManager.queueIndex` 가 0 이상이면 그 값, 음수면 null |
| WA-18 | 현재 곡 없음 | `mediaItem` 이 null |
| WA-19 | 현재 곡 있음 | `mediaItem` 의 `id`, `title`, `artist`, `album` 이 곡 값. `duration` 은 `PlayerManager.durationSeconds` 가 0 보다 크면 그 값, 아니면 곡의 길이, 둘 다 0 이면 null. `artUri` 는 `coverUrl` 이 비어 있으면 null |
| WA-20 | 대기열 변경 | `queue` 가 곡 목록과 같은 순서 · 같은 개수의 `MediaItem` 목록 |
| WA-21 | 폰 스피커 선택 | `androidPlaybackInfo` 가 로컬 재생 |
| WA-22 | 원격 스피커 선택 | `androidPlaybackInfo` 가 원격 재생: 절대 볼륨 방식, 최대 100, 현재 값은 `PlayerManager.volumeNotifier` |
| WA-23 | 선택 기기 변경 또는 볼륨 변경 | `androidPlaybackInfo` 가 다시 알려짐 |

---

## 5. 오류 코드 표

| 코드 | 종류 | 발생 | 규칙 |
| --- | --- | --- | --- |
| `PHONE_PLAY_FAILED` | `PlaybackException` | 폰 재생 시작 실패 | PB-02 |
| `PHONE_PAUSE_FAILED` | `PlaybackException` | 폰 일시정지 실패 | PB-04 |
| `PHONE_RESUME_FAILED` | `PlaybackException` | 폰 재개 실패 | PB-05 |
| `NOT_LOGGED_IN` | `PlaybackException` | 스피커 재생 시 사용자 토큰 없음 | DB-02 |
| `NO_STREAM` | `PlaybackException` | 스트림 정보 없음 | DB-03 |
| `PROXY_FAILED` | `PlaybackException` | 프록시 URL 을 받지 못함 (Wi-Fi 없음 포함) | DB-06 |
| `DLNA_PLAY_FAILED` | `PlaybackException` | 스피커 재생 명령 실패 | DB-10 |
| `DLNA_PAUSE_FAILED` | `PlaybackException` | 스피커 일시정지 실패 | DB-43 |
| `DLNA_RESUME_FAILED` | `PlaybackException` | 스피커 재개 실패 | DB-44 |
| `DLNA_UNREACHABLE` | `BackendError` 이벤트 | 스피커가 3회 연속 응답 없음 | DB-27 |
| `UNKNOWN` | `BackendError` 이벤트 | 네이티브 오류 이벤트에 코드 없음 | PB-23 |
| (네이티브가 준 코드) | `BackendError` 이벤트 | 네이티브 오류 이벤트, 예: `PRIVILEGES_REVOKED` | PB-23 |

---

## 6. 요구사항 대응

| 요구사항 항목 (`requirements.md`) | 규칙 |
| --- | --- |
| FR-01: 7개 명령이 대응 채널 메서드를 올바른 인자로 호출 | PB-01, PB-04 ~ PB-09 |
| FR-01: 5종 이벤트 변환 | PB-16 ~ PB-24 |
| FR-01: 네이티브 호출 실패 → `PlaybackException` (정정: `play` · `pause` · `resume` 만) | PB-02, PB-04, PB-05, 그리고 PB-06 ~ PB-09 의 "예외 없음" |
| FR-01: 취소된 재생 요청은 상태를 바꾸지 않음 | PB-03 |
| FR-02: 등록 → `SetAVTransportURI` → `Play` 순서 | DB-05, DB-07 |
| FR-02: 폴링 결과 → 상태 · 위치 이벤트 | DB-16 ~ DB-21 |
| FR-02: 곡 끝 판정 (종료 허용치 3초, 1회만) | DB-22 ~ DB-26 |
| FR-02: 연속 3회 실패 | DB-27, DB-28 |
| FR-02: `setNext` 와 주소 비교 | DB-32 ~ DB-41 |
| FR-02: `stop` 뒤 타이머 해제 · 잠금 해제 | DB-31, DB-46 |
| FR-02: `NO_WIFI` → `PlaybackException` (코드는 `PROXY_FAILED`) | DB-06 |
| FR-03: 탐색 결과 반영, 선택 · 해제, UDN 저장 · 복원 | DM-19 ~ DM-29 |
| FR-03: 재생 제어, 볼륨 (0 ~ 100 제한), 상태 · 위치 조회, SOAP 실패 처리 | DM-01 ~ DM-18 |
| FR-04: 명령 전달 | WA-01 ~ WA-07 |
| FR-04: `playbackState` · `mediaItem` 반영 | WA-10 ~ WA-20 |
| FR-04: 기기 변경 시 재알림, 원격 볼륨 명령 | WA-08, WA-09, WA-21 ~ WA-23 |

요구사항에 없지만 80% 커버리지와 동작 고정을 위해 규칙에 넣은 것: pending seek (PB-11 ~ PB-15), 취소 지점 (DB-14), 명령 직렬화 (DB-15, DB-42), 주소 재발급 (DB-48, DB-49), `dispose` (PB-26, DB-47).

---

## 7. 관찰 사항 (지금 동작으로 고정, 수정하지 않음)

계획 Q1=A 의 기준에 따라 버그로 보지 않고 기록만 한다. 테스트 입력 범위에서 제외하는 것은 `domain-entities.md` 의 생성기 범위에 반영했다.

| # | 관찰 | 처리 |
| --- | --- | --- |
| O-1 | `PhoneBackend`: 네이티브 이벤트의 값 타입이 계약과 다르면 (예: `positionMs` 가 문자열) 형 변환 예외가 난다 | 계획 Q3=A: 입력 범위 밖. Kotlin 쪽은 정해진 타입으로만 보낸다 |
| O-2 | `DlnaManager.seek`: 음수 초를 넣으면 형식이 깨진 시간 문자열이 나온다 | 입력 범위 밖. 호출하는 `PlayerManager.seekTo` 가 0 이상으로 자른다 |
| O-3 | `DlnaManager` 시간 해석: `-1:00:00` 같은 음수 부분을 그대로 계산한다 | 규칙 없음. 렌더러 응답에 음수가 올 근거가 없다 |
| O-4 | `DlnaBackend`: 길이를 모르는 곡은 `PLAYING` 뒤 `STOPPED` 를 보면 위치와 상관없이 곡 끝으로 본다 | DB-24 로 고정 |
| O-5 | `DlnaBackend`: 재생 명령이 실패해도 그 전에 `BackendTrackStarted` 가 이미 나간다 | DB-07 순서로 고정. `PlayerManager` 가 예외를 받아 오류로 처리한다 |
| O-6 | `DlnaManager`: 선택된 원격 기기가 다시 탐색되어도 선택 객체는 예전 것을 그대로 쓴다 (제어 URL 이 바뀌었으면 예전 URL 사용) | DM-27 로 고정 |
| O-7 | `WaveAudioHandler`: `coverUrl` 이 URI 로 해석할 수 없는 문자열이면 `Uri.parse` 가 예외를 낸다 | 입력 범위 밖. TIDAL 커버 주소는 정해진 형식으로 만들어진다 |
