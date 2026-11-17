# 업무 규칙 (Business Rules) - dash-seek

요구사항: `aidlc-docs/inception/requirements/requirements-dash-seek.md` (FR-10 ~ FR-13). 앞 작업의 규칙 문서 (`dart-playback-tests`, `android-native-tests` 의 `business-rules.md`) 가 지금 동작의 기준이고, 이 문서는 **바뀌는 규칙과 새 규칙** 만 적는다. 여기에 없는 규칙은 그대로다.

## 0. 흐름

```text
탐색(위치 P, DASH 곡)
  Dart DlnaBackend.seek
    -> 채널 registerTrackStream {..., startPositionMs: P}
         Kotlin: 매니페스트에서 P 가 속한 세그먼트 k 를 찾고, "초기화 세그먼트 + k 번째부터" 를 새 주소로 등록
         <- {proxyUrl, startOffsetMs: k 번째 세그먼트의 시작 시각}
    -> 스피커에 새 주소로 다시 재생 (SetAVTransportURI + Play)
    -> 이후 폴링: 스피커가 알려 준 위치를 시작 오프셋으로 보정해 알림
```

## 1. Kotlin: `DashManifest` (세그먼트 시각)

`SegmentTemplate` 의 `timescale` (없으면 1) 과 `SegmentTimeline` 의 `<S d="..." r="..."/>` 로 세그먼트의 시작 시각을 계산한다. `d` 는 timescale 단위의 길이, `r` 은 같은 길이가 r 번 더 반복됨을 뜻한다.

| ID | 조건 | 결과 |
| --- | --- | --- |
| DS-01 | `segmentStartMs(index)` | 앞 세그먼트들의 `d` 합 × 1000 ÷ timescale (정수, 버림). 0 번째는 0. 예: timescale 44100, `<S d="176400" r="2"/><S d="88200"/>` 이면 0, 4000, 8000, 12000 |
| DS-02 | `segmentIndexAt(positionMs)` | 시작 시각이 `positionMs` 이하인 세그먼트 가운데 마지막 것의 번호. 예: 위 매니페스트에서 0 → 0, 3999 → 0, 4000 → 1, 11999 → 2, 12000 → 3 |
| DS-03 | `positionMs` 가 0 이하 | 0 |
| DS-04 | `positionMs` 가 곡 길이 이상 | 마지막 세그먼트의 번호 (`segmentCount - 1`) |
| DS-05 | `d` 가 없거나 숫자가 아니거나 0 이하인 `<S>` 가 하나라도 있음, 또는 timescale 이 0 이하 | 시각을 알 수 없는 매니페스트. `segmentIndexAt` 은 항상 0, `segmentStartMs` 는 항상 0. `parse` 는 지금처럼 성공한다 (`segmentCount` 등은 그대로) |
| DS-06 | 기존 필드 (`initializationUrl`, `mediaTemplate`, `startNumber`, `segmentCount`), `segmentUrl` | 바뀌지 않는다. 기존 `DashManifestTest` 4개가 수정 없이 통과한다 |

| ID | 속성 | 범주 |
| --- | --- | --- |
| P-DS-1 | 어떤 timescale 과 세그먼트 길이 목록이든, `segmentStartMs` 는 번호에 대해 줄어들지 않고, `segmentIndexAt(segmentStartMs(i))` 의 시작 시각은 `segmentStartMs(i)` 와 같다 (길이가 같은 시각으로 버림되는 세그먼트가 이어지면 번호는 달라도 시각은 같다) | 왕복 |
| P-DS-2 | 어떤 위치든 `k = segmentIndexAt(p)` 는 0 이상 `segmentCount` 미만이고, `segmentStartMs(k) ≤ max(p, 0)` 이며, `k` 가 마지막이 아니면 `p < segmentStartMs(k + 1)` 이다 | 불변 조건 |

## 2. Kotlin: 프록시 (`TidalStreamProxyServer`, `DashSegmentInputStream`)

| ID | 조건 | 결과 |
| --- | --- | --- |
| PS-01 | `registerTrackStreamAt(trackId, directUrl, manifestXml, allowedHost, mimeType, startPositionMs)` | 곡을 등록하고 `RegisteredStream(url, startOffsetMs)` 를 돌려준다. 주소의 형식 · 토큰 · 확장자 · 최근 3개 보관은 기존 등록 (PX-01 ~ PX-06) 과 같다 |
| PS-02 | DASH 등록 (`directUrl` 빈 값, `manifestXml` 있음), 매니페스트를 해석할 수 있음 | 시작 세그먼트 `k = segmentIndexAt(startPositionMs)`, `startOffsetMs = segmentStartMs(k)` |
| PS-03 | 단일 파일 등록 (`directUrl` 있음) | `startPositionMs` 를 무시한다. `startOffsetMs` 는 0, 응답은 기존과 같다 |
| PS-04 | DASH 등록인데 매니페스트를 해석할 수 없음, 또는 시각을 알 수 없는 매니페스트 (DS-05) | `startOffsetMs` 는 0, 시작 세그먼트 0. 등록 자체는 기존처럼 된다 (GET 은 PX-37 대로 500) |
| PS-05 | 기존 `registerTrackStream(...)` (인자 5개, 주소 문자열 반환) | 그대로 남는다. `startPositionMs` 0 으로 등록한 것과 같다 |
| PS-06 | 시작 세그먼트 `k` 로 등록한 DASH 곡의 GET | 본문은 초기화 세그먼트 (있으면) + `k` 번째부터 마지막까지의 세그먼트를 순서대로 이은 것. `k` 번째 앞의 세그먼트는 CDN 에 GET 하지 않는다. 타입 `audio/mp4`, `Accept-Ranges` 없음 (PX-34 와 같음) |
| PS-07 | 위 GET · HEAD 의 `Content-Length` | 초기화 세그먼트 + `k` 번째부터의 세그먼트 길이의 합. 길이를 모르는 세그먼트가 그 범위에 하나라도 있으면 GET 은 chunked, HEAD 는 `Content-Length` 없음 (PX-19, PX-35 와 같은 규칙을 그 범위에 적용) |
| PS-08 | 세그먼트 길이 조회 (HEAD) | 매니페스트당 한 번만 한다 (PX-38). 같은 매니페스트를 다른 시작 세그먼트로 다시 등록해도 길이를 모두 아는 상태면 CDN 에 HEAD 를 다시 보내지 않는다 |
| PS-09 | `k = 0` 으로 등록한 DASH 곡 | 응답이 기존과 같다 (PX-34 ~ PX-38 그대로) |
| PS-10 | 같은 곡을 다른 위치로 여러 번 등록 | 등록마다 주소가 다르고 서로 영향을 주지 않는다 (각 주소는 자기 시작 세그먼트의 본문을 준다) |

| ID | 속성 | 범주 |
| --- | --- | --- |
| P-PS-1 | 어떤 세그먼트 내용 · 개수 · 길이와 어떤 시작 위치든, GET 본문은 초기화 세그먼트 + `segmentIndexAt(위치)` 번째부터의 세그먼트를 이은 것과 같고 `Content-Length` 는 그 길이와 같으며, 돌려준 `startOffsetMs` 는 `segmentStartMs(segmentIndexAt(위치))` 와 같다 | 왕복 (등록 → 조회) |

## 3. Kotlin: 채널 (`PlaybackCommandRouter`, `PlaybackContracts`, `PlaybackCore`)

앞 작업의 CR 규칙 가운데 `registerTrackStream` 에 해당하는 부분이 바뀐다.

| ID | 조건 | 결과 |
| --- | --- | --- |
| CR-14 | `registerTrackStream` 의 인자 | 기존 5개에 `startPositionMs` 가 더해진다. 정수 타입의 크기 (Int · Long) 와 상관없이 읽어 Long 으로 넘긴다. 없거나 null 이거나 숫자가 아니면 0 (CR-02, CR-10, CR-11 과 같은 방식) |
| CR-15 | `ProxyRegistrar.registerTrackStream(trackId, directUrl, manifestXml, allowedHost, mimeType, startPositionMs)` | `RegisteredStream(url, startOffsetMs)?` 를 돌려준다. Wi-Fi 가 없으면 null |
| CR-16 | 등록 성공 | 성공 값 `{proxyUrl: <url>, startOffsetMs: <Long>}`. 기존 키 `proxyUrl` 은 그대로다 |
| CR-17 | 등록 결과 null | 기존과 같이 `NO_WIFI` 오류 (CR-08) |
| CR-18 | 그 밖의 메서드 15개 | 바뀌지 않는다 |

속성 P-CR-5 (등록 인자가 그대로 전달됨) 는 `startPositionMs` 와 `startOffsetMs` 를 포함하도록 넓힌다.

`PlaybackCore` 의 `proxyRegistrar` 운영 구현은 `registerTrackStreamAt` 을 부르도록 바꾼다 (JVM 테스트 대상이 아니다. 앞 작업의 PC-06 과 같은 위치).

## 4. Dart: 채널 호출 (`TidalSdkNativeBridge.registerTrackStream`)

| ID | 조건 | 결과 |
| --- | --- | --- |
| NB-01 | `registerTrackStream(..., startPosition: Duration)` | 채널 인자에 `startPositionMs` (정수, 밀리초) 를 더해 보낸다. 생략하면 0 |
| NB-02 | 반환 | `ProxyRegistration(url, startOffset)`. `url` 은 응답의 `proxyUrl`, `startOffset` 은 응답의 `startOffsetMs` (밀리초). `startOffsetMs` 가 없거나 숫자가 아니면 0 |
| NB-03 | 채널 오류 또는 `proxyUrl` 없음 | `url` 이 빈 문자열, `startOffset` 0 (기존의 "빈 문자열 반환" 과 같은 뜻) |

## 5. Dart: `DlnaBackend`

### 바뀌는 규칙

| ID | 앞 작업의 규칙 | 바뀐 내용 |
| --- | --- | --- |
| DB-12 | `startPosition` > 0, DASH 스트림: `Seek` 없음 | SOAP `Seek` 는 여전히 보내지 않는다. 대신 등록할 때 `startPositionMs` 로 시작 위치를 넘긴다 (DB-50) |
| DB-13 | `canSeek`: DASH 곡이면 false | 항상 true (단일 파일 · DASH 모두) |
| DB-17 | 위치 응답: `Duration(seconds: RelTime)`, 길이는 렌더러 값 우선 | 시작 오프셋이 0 이면 그대로. 0 보다 크면 DB-54 ~ DB-56 |
| DB-39 | 갭리스 전환: `canSeek` 은 새 곡 기준 | `canSeek` 은 계속 true. 전환되면 시작 오프셋은 0 이 된다 (DB-58) |
| DB-45 | `seek(position)`: SOAP `Seek`, 결과 무시 | 지금 곡이 단일 파일이면 그대로. DASH 면 DB-51 |

### 새 규칙: 시작 위치

| ID | 조건 | 결과 |
| --- | --- | --- |
| DB-50 | `play(track, startPosition: P)`, DASH 스트림 | 채널 `registerTrackStream` 의 `startPositionMs` 가 P (밀리초). SOAP `Seek` 없음. 응답의 `startOffsetMs` 를 이 곡의 시작 오프셋으로 기억한다. `P` 가 0 이면 `startPositionMs` 는 0 이고 시작 오프셋도 0 |
| DB-50b | `play(track, startPosition: P)`, 단일 파일 스트림 | `startPositionMs` 는 0 으로 보낸다. 재생 명령 뒤 SOAP `Seek` (DB-11 그대로). 시작 오프셋 0 |

### 새 규칙: DASH 곡의 탐색

| ID | 조건 | 결과 |
| --- | --- | --- |
| DB-51 | `seek(P)`, 지금 곡이 DASH | 순서대로: (1) 채널 `registerTrackStream` (같은 곡 ID · 매니페스트 · 허용 호스트 · MIME, `startPositionMs` = P 밀리초) (2) 스피커에 새 주소로 재생 명령 (`play` 와 같은 메타데이터). SOAP `Seek` 는 보내지 않는다. 스트림 정보는 재생을 시작할 때 받은 것을 다시 쓴다 (TIDAL API 를 다시 부르지 않는다) |
| DB-52 | DB-51 성공 뒤 | 현재 주소가 새 주소로 바뀌고, 시작 오프셋이 응답의 `startOffsetMs` 가 된다. 곧바로 `BackendPositionChanged(시작 오프셋, duration: 곡의 길이)` 와 `BackendStateChanged(playing: true, buffering: true)` 를 알린다. `BackendTrackStarted` 는 다시 알리지 않는다. 폴링은 새 흐름 기준으로 다시 시작한다 (`PLAYING` 을 아직 보지 못한 상태, 실패 횟수 0, 마지막 위치 = 시작 오프셋, 위치 기준 미정) |
| DB-53 | DB-51 에서 프록시 주소가 빈 값 | `PlaybackException('PROXY_FAILED', ...)`. 스피커에 명령을 보내지 않고, 현재 주소 · 시작 오프셋 · 폴링은 그대로다 |
| DB-53b | DB-51 에서 스피커 재생 명령 실패 | `PlaybackException('DLNA_PLAY_FAILED', ...)` (메시지에 기기 이름). 현재 주소와 시작 오프셋은 그대로다 |
| DB-57 | 일시정지 상태 (`pause()` 가 성공한 뒤 `resume()` 이나 새 `play` 가 없었음) 에서 DB-51 | 재생 명령 뒤에 SOAP `Pause` 를 보내고, `BackendStateChanged(playing: true, buffering: true)` 대신 `BackendStateChanged(playing: false)` 를 알린다 |
| DB-59 | DB-51 뒤, 미리 등록해 둔 다음 곡이 있었음 | 재생 명령 뒤에 같은 다음 곡 주소 · 메타데이터로 SOAP `SetNextAVTransportURI` 를 다시 보낸다 (재생 명령이 스피커의 다음 곡 등록을 지우기 때문). 등록 정보는 유지되어 이후 DB-39 (갭리스 전환) 가 그대로 일어난다. 다시 보낸 것이 실패하면 등록 정보를 지운다 (그 기기를 갭리스 불가로 표시하지는 않는다) |
| DB-60 | DB-51 은 `play` · `setNext` 와 같은 직렬화 대상 | 스피커 명령이 섞이지 않는다 (DB-15, DB-42) |
| DB-61 | 재생 중인 곡이 없을 때 (`stop()` 뒤, `play` 전) `seek` | 지금처럼 SOAP `Seek` 만 보낸다 (DB-45) |

### 새 규칙: 탐색 중의 폴링 (2026-11-17 추가, GREEN 에이전트가 발견한 위험)

탐색은 스피커에 `Stop` → `SetAVTransportURI` → `Play` 를 보낸다. 그 사이에 1초 폴링이 돌아 `STOPPED` 를 보면 "스피커가 멈춤" 이나 "곡이 끝남" 으로 잘못 판정해 다음 곡으로 넘어갈 수 있다.

| ID | 조건 | 결과 |
| --- | --- | --- |
| DB-62 | DB-51 의 탐색이 진행 중인 동안 (등록을 시작해서 스피커 명령과 알림이 끝나거나 예외로 끝날 때까지) 폴링 차례가 됨 | 그 차례를 건너뛴다: SOAP 조회 (`GetTransportInfo`, `GetPositionInfo`) 를 보내지 않고 이벤트도 알리지 않는다 |
| DB-62b | 탐색이 끝난 뒤 (성공 · 실패 모두) | 다음 차례부터 폴링이 이어진다. 성공했으면 DB-52 의 새 흐름 기준, 실패했으면 (DB-53, DB-53b) 그 전 상태 기준 |

### 새 규칙: 위치 보정 (시작 오프셋 > 0 인 흐름)

스피커가 알려 주는 `RelTime` 의 기준이 렌더러마다 다를 수 있다: 새 흐름의 처음을 0 으로 세는 경우 (상대) 와 곡 전체 기준 시각을 알려 주는 경우 (절대). 시작 오프셋을 O (초 단위로 버림) 라 한다.

| ID | 조건 | 결과 |
| --- | --- | --- |
| DB-54 | 시작 오프셋 > 0 인 흐름에서 0 보다 큰 `RelTime` 을 처음 받음 | 위치 기준을 한 번 정하고 그 흐름이 끝날 때까지 바꾸지 않는다. `O ≥ 10` 이고 `RelTime ≥ O − 2` 이면 절대, 아니면 상대 |
| DB-55 | 위치 기준이 상대 | 알리는 위치 = O + `RelTime` |
| DB-55b | 위치 기준이 절대 | 알리는 위치 = `RelTime` |
| DB-55c | 위치 기준이 정해지기 전 (`RelTime` 이 0) | 알리는 위치 = O |
| DB-56 | 시작 오프셋 > 0 인 흐름의 길이 | 렌더러의 `TrackDuration` 을 쓰지 않는다. 곡의 길이 (곡 정보에 없으면 null) 를 쓴다 |
| DB-56b | 곡 끝 판정 (DB-23 ~ DB-26) | 보정한 위치로 판정한다. "0 보다 큰 위치만 기억" 은 `RelTime` 이 0 보다 큰 경우를 뜻한다 |
| DB-58 | 갭리스 전환 (DB-39) 또는 새 `play` | 시작 오프셋 0, 위치 기준 초기화. 새 곡은 DB-17 그대로 |

| ID | 속성 | 범주 |
| --- | --- | --- |
| P-DB-6 | 어떤 시작 오프셋 O (≥ 10초) 와 0 보다 큰 `RelTime` 순서 (늘어나는 값) 든: 첫 값이 `O − 2` 이상이면 알리는 위치는 `RelTime` 그대로이고, 미만이면 `O + RelTime` 이다. 어느 쪽이든 알리는 위치는 줄어들지 않는다 | 불변 조건 |
| P-DB-7 | 어떤 `startPosition` 이든 DASH 곡의 `play` 가 채널에 보낸 `startPositionMs` 는 그 값의 밀리초이고, SOAP `Seek` 는 0회다. 단일 파일 곡이면 `startPositionMs` 는 0 이고 `Seek` 는 `startPosition` > 0 일 때만 1회다 | 불변 조건 |

### 그 밖

- `PlayerManager`, `WaveAudioHandler`, 재생 화면은 바꾸지 않는다. `canSeek` 이 true 가 되면 탐색 막대와 잠금화면의 탐색이 지금 코드로 열린다
- 앱 로그 (`DLNA_BACKEND` 태그) 에 DASH 탐색 요청과 정한 위치 기준 (상대 · 절대) 을 남긴다. 실기기에서 판정이 맞는지 볼 때 쓴다

### 규칙 보완 (2026-11-17, RED 에이전트가 빠졌다고 보고한 곳)

| 규칙 | 보완 |
| --- | --- |
| DB-51 | "재생 명령" 은 `play` 와 같은 SOAP 순서 (`Stop` → `SetAVTransportURI` → `Play`) 다. 갭리스로 넘어간 뒤의 "지금 곡" 은 넘어간 곡이고, 스트림 정보는 `setNext` 때 받은 것을 쓴다 |
| DB-52 | 곧바로 알리는 위치는 초 단위로 버린 시작 오프셋 (`Duration(seconds: O)`) 이다. 알림 순서는 위치 → 상태. 탐색 시점에 응답을 기다리던 폴링 결과는 버린다 (DB-29 와 같음). 스트리밍 잠금은 켜진 채로 둔다 (껐다 켜지 않는다). 탐색 직후 폴링을 따로 한 번 더 돌리지 않고 다음 1초 주기부터 확인한다 |
| DB-53b | 재생 명령이 실패하면 이벤트를 알리지 않고 예외만 던진다. 폴링은 멈추지 않고 그대로 둔다 (스피커가 멈춰 있으면 이후 폴링의 일반 규칙이 처리한다) |
| DB-57, DB-59 | 둘이 함께 걸리면 순서는 재생 명령 → `SetNextAVTransportURI` → `Pause` 다. 다시 보낸 `SetNextAVTransportURI` 가 실패해도 `seek` 은 예외 없이 끝난다 |
| DB-61 | "재생 중인 곡이 없음" 은 `play` 가 성공한 적이 없거나 `stop()` 을 부른 뒤를 뜻한다. 곡이 끝났거나 무응답으로 폴링이 멈춘 뒤에는 마지막 곡의 스트림 정보가 남아 있으므로 DB-51 (DASH) 또는 DB-45 (단일 파일) 를 따른다 |
| DB-11, P-DB-7 | 단일 파일 곡의 `Seek` 조건과 초 단위 변환은 지금 코드 그대로다 (`startPosition > 0` 이면 `inSeconds` 로 보냄) |
| 그 밖 | `playback_backend.dart` 의 `canSeek` 문서 주석 ("DASH 중계처럼 불가능한 경로가 있다") 을 DB-13 에 맞게 고친다 |

### 규칙 보완 (2026-11-17, Kotlin RED 에이전트가 보고한 곳)

| 규칙 | 보완 |
| --- | --- |
| DS-02, DS-03, P-DS-2 | 위치가 0 이하이면 DS-03 이 우선해 항상 0 번째다 (시작 시각이 0 으로 버림되는 세그먼트가 여럿이어도). 위치가 1 ms 이상이면 DS-02 그대로 "시작 시각이 위치 이하인 마지막 세그먼트" 다. 기존 테스트의 매니페스트 (`<S d="1"/>`, timescale 44100) 처럼 모든 시각이 0 으로 버림되는 타임라인에 1 ms 이상을 주면 마지막 세그먼트가 선택된다. 실제 TIDAL 매니페스트에서는 생기지 않는 입력이다 |
| DS-01 | 범위 밖 번호의 `segmentStartMs`, 숫자가 아닌 timescale, 음수 · 숫자가 아닌 `r` 은 정하지 않는다 (테스트 없음). 구현은 예외를 던지지 않는 쪽으로 한다: timescale 이 숫자가 아니면 없는 것과 같이 1, `r` 은 기존 `parse` 와 같은 방식 |
| PS-04 | 괄호의 "GET 은 PX-37 대로 500" 은 해석할 수 없는 매니페스트에만 해당한다. 시각을 알 수 없는 매니페스트 (DS-05) 는 해석은 되므로 GET 은 200 이고 처음부터의 본문이다 |
| PS-07 | 길이는 "초기화 세그먼트 + 시작 세그먼트부터" 의 범위만 본다. 시작 세그먼트 앞의 세그먼트만 길이를 모르면 `Content-Length` 를 알린다 |
| PS-06 | 주소 재발급 (PX-26 ~ PX-31) 은 단일 파일 곡에만 있으므로 시작 세그먼트와 무관하다. 재발급 결과가 DASH 로 바뀐 경우 (PX-30) 는 처음부터 보낸다 (지금 동작 그대로) |

## 6. 요구사항 대응

| 요구사항 | 규칙 · 속성 |
| --- | --- |
| FR-10 DASH 곡의 탐색 | DS-01 ~ DS-05, PS-01 ~ PS-10, CR-14 ~ CR-17, NB-01 ~ NB-03, DB-13, DB-51 ~ DB-53b, DB-60, P-DS-1 · 2, P-PS-1 |
| FR-11 중간 위치에서 시작 | DB-12, DB-50, DB-50b, P-DB-7 |
| FR-12 재생 위치 표시 | DB-17, DB-52, DB-54 ~ DB-56b, DB-58, P-DB-6 |
| FR-13 기존 동작 유지 | DS-06, PS-03, PS-05, PS-09, CR-18, DB-45, DB-50b, DB-57, DB-59, DB-61 |

## 7. 관찰 사항 · 위험

| # | 내용 |
| --- | --- |
| R-1 | DB-54 의 판정 기준 (10초, 2초) 은 추정이다. 실기기에서 로그로 확인한다. 시작 오프셋이 10초 미만이면 항상 상대로 보므로, 절대로 알려 주는 렌더러에서는 표시가 최대 10초쯤 앞설 수 있다 |
| R-2 | 중간 세그먼트부터 시작한 흐름을 재생하지 못하는 렌더러가 있을 수 있다. 자동 테스트로는 알 수 없다 |
| R-3 | 탐색에 쓰는 스트림 정보는 재생을 시작할 때 받은 것이다. 오래 일시정지한 뒤 탐색하면 조각 주소가 만료되었을 수 있다 (DASH 조각의 만료 재발급은 지금도 없다. 앞 작업의 PX-36) |
| R-4 | 탐색 단위가 세그먼트라, 요청한 위치보다 최대 세그먼트 길이만큼 앞에서 재생된다 |
