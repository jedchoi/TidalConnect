# 테스트 경계 표 (RED, Dart) - dash-seek

기준: `aidlc-docs/construction/dash-seek/functional-design/business-rules.md` 4절 · 5절. 바뀌지 않는 부분은 `dart-playback-tests` 의 DB 규칙. 사람 승인 없이 진행했다 (자동 승인 지시).

- 테스트 파일: `test/features/player/dlna_backend_test.dart` (DB · P-DB), `test/core/native/tidal_sdk_native_bridge_test.dart` (NB, 새 파일)
- 도우미: `test/helpers/playback_fixtures.dart` 에 `proxyUrlAt`, `DlnaBackendHarness.seek`, `DlnaBackendHarness.answerStartOffset` 추가. `test/helpers/generators.dart` 에 `offsetFlows`, `startRequests` 추가. 기존 도우미의 기본 동작은 그대로다
- 외부 경계 (가짜): MethodChannel (`FakeNativeChannel`), SOAP (`FakeSoapClient`), TIDAL API · 인증 (`FakeApiClient`, `FakeAuthRepository`), 시간 (`fake_async`). `DlnaManager` 와 `DlnaBackend` 는 실제 객체다
- 가짜 프록시 응답 (`answerStartOffset(O)`): `startPositionMs` > 0 인 등록에는 `{proxyUrl: proxyUrlAt(곡, startPositionMs), startOffsetMs: O}`, 그 밖에는 `{proxyUrl: proxyUrlFor(곡), startOffsetMs: 0}`
- 이벤트 표기: `position(위치초/길이초)`, `state(playing,buffering)`, `state(stopped)`, `started(id)`, `ended(id)`

## 1. NB: `TidalSdkNativeBridge.registerTrackStream`

| 규칙 ID | 경계 | 입력 | 기대값 |
| --- | --- | --- | --- |
| NB-01 | `registerTrackStream` → 채널 인자 | 인자 5개 + `startPosition` 42.9초 | 인자 맵이 기존 5개 키 + `startPositionMs: 42900` |
| NB-01 | 같음 | `startPosition` 생략 | `startPositionMs` 0 |
| NB-02 | 반환값 | 응답 `{proxyUrl: U, startOffsetMs: 28000}` | `url` U, `startOffset` 28000 밀리초 |
| NB-02 | 반환값 | 응답에 `startOffsetMs` 없음 / null / `'abc'` | `url` U, `startOffset` 0 |
| NB-03 | 반환값 | 채널 오류 | `url` `''`, `startOffset` 0, 예외 없음 |
| NB-03 | 반환값 | 응답 `{startOffsetMs: 28000}` (`proxyUrl` 없음) | `url` `''`, `startOffset` 0 |

## 2. DB: 바뀌는 규칙 (기존 테스트 수정)

| 규칙 ID | 경계 | 입력 | 기대값 |
| --- | --- | --- | --- |
| DB-05 | `play` → 채널 `registerTrackStream` 인자 전체 | 단일 파일 곡, 시작 위치 없음 | 기존 5개 키 + `startPositionMs: 0` (DB-50b) |
| DB-12 | `play` → SOAP · 채널 | DASH, `startPosition` 30초 | SOAP `Stop` · `SetAVTransportURI` · `Play` (Seek 없음), `startPositionMs` 30000 |
| DB-13 | `canSeek` | 생성 직후 / DASH 재생 뒤 / 단일 파일 재생 뒤 | true / true / true |
| DB-39 | `canSeek` (갭리스 전환 뒤) | 단일 파일 → DASH 로 전환 | true (그 밖의 단언은 그대로) |
| DB-45 | `seek` → SOAP | 단일 파일 곡 재생 중, 42.9초, `Seek` 거부 | SOAP `Seek` `00:00:42` 만, 예외 없음, 등록 호출 없음, 이벤트 없음 |
| DB-17 | 폴링 | 시작 오프셋 0 | 기존 DB-17 테스트 2개 그대로 (수정 없음) + DB-50 "처음부터" 테스트 |

## 3. DB: 시작 위치

| 규칙 ID | 경계 | 입력 | 기대값 |
| --- | --- | --- | --- |
| DB-50 | `play` → 채널 · SOAP · 이벤트 | DASH, `startPosition` 30.5초, 응답 오프셋 28초 | 인자 전체 (`startPositionMs: 30500`, `mimeType: audio/mp4`), SOAP 3개 (Seek 없음), 주소 `proxyUrlAt('101', 30500)`, 이벤트 `started(101)`, `state(playing,buffering)` |
| DB-50 | 폴링 | DASH, 요청 30초, 응답 오프셋 28초, `RelTime` 0 | `position(28/180)`, `state(playing)` |
| DB-50 | `play` · 폴링 | DASH, 시작 위치 0, `RelTime` 12 / 렌더러 길이 200 | `startPositionMs` 0, `position(12/200)` |
| DB-50b | `play` · 폴링 | 단일 파일, `startPosition` 30초, `RelTime` 31 / 길이 200 | `startPositionMs` 0, SOAP 끝에 `Seek` `00:00:30`, 주소 `proxyUrlFor('101')`, `position(31/200)` |

## 4. DB: DASH 곡의 탐색

곡 길이는 따로 적지 않으면 180초.

| 규칙 ID | 경계 | 입력 | 기대값 |
| --- | --- | --- | --- |
| DB-51 | `seek` → 채널 → SOAP 순서 | DASH 재생 중, `seek(42.9초)`, 등록 응답을 붙잡아 둠 | 붙잡힌 동안: 등록 인자 전체 (`trackId` 101, 같은 매니페스트 · 호스트 · MIME, `startPositionMs: 42900`), SOAP 없음. 풀면: `Stop` · `SetAVTransportURI` · `Play`, 주소 `proxyUrlAt('101', 42900)`, 예외 없음 |
| DB-51 | `seek` → SOAP 메타데이터 | 제목 · 가수 · 앨범 · 커버 · 길이 205 인 DASH 곡 | DB-09 와 같은 값, MIME `audio/mp4` |
| DB-51 | `seek` → TIDAL API | 재생 뒤 API 가 다른 매니페스트를 주도록 바꿈 | API 호출 없음, 등록 매니페스트는 처음 것 |
| DB-51, DB-39 | `seek` (갭리스 전환 뒤) | 단일 파일 101 → DASH 102 로 전환, `seek(61초)`, 응답 오프셋 60초 | 등록 `trackId` 102 · 다음 곡 매니페스트 · `startPositionMs` 61000, API 호출 없음, 메타데이터 제목 `곡 102`, 이벤트 `position(60/240)`, `state(playing,buffering)` |
| DB-45, DB-39 | `seek` (갭리스 전환 뒤) | DASH 101 → 단일 파일 102 로 전환, `seek(42초)` | SOAP `Seek` `00:00:42` 만, 등록 없음 |
| DB-52 | `seek` → 이벤트 | `seek(42.9초)`, 응답 오프셋 40초 | 순서대로 `position(40/180)` (위치 40초, 길이 180초), `state(playing,buffering)`. `started` 없음. 스트리밍 잠금은 켜진 상태 |
| DB-52 | 폴링 (오프셋 = 응답값) | 탐색 (요청 42초, 응답 40초) 뒤 `RelTime` 0 | `position(40/180)`, `state(playing)`, 조회 1회 |
| DB-52 | 폴링 (`PLAYING` 미확인) | 탐색 전 `PLAYING` 확인, 탐색 (오프셋 60) 뒤 `STOPPED`/0 → `PLAYING`/1 | `position(60/180)`, `position(61/180)`, `state(playing)`, 조회 2회 (폴링 계속) |
| DB-52 | 폴링 (실패 횟수 0) | 탐색 전 무응답 2회, 탐색 뒤 무응답 3회 | 2회까지 이벤트 없음, 3회째 `state(stopped)`, `error(DLNA_UNREACHABLE)` |
| DB-52 | 폴링 (마지막 위치 = 오프셋) | (a) 5초 재생 뒤 오프셋 178 로 탐색, `PLAYING`/0 → `STOPPED`/0 (b) 178초 재생 뒤 오프셋 30 으로 탐색, 같은 응답 | (a) `position(178/180)` ×2 와 `ended(101)` (b) `position(30/180)` ×2 와 `state(stopped)` |
| DB-52 | 폴링 (위치 기준 미정) | 오프셋 60 흐름에서 `RelTime` 60 (절대) 뒤 다시 탐색 (오프셋 60), `RelTime` 5 | `position(65/180)` (상대로 다시 판정) |
| DB-53 | `seek` 예외 · 상태 유지 | 오프셋 28 흐름, 등록이 채널 오류, `seek(90초)` | `PROXY_FAILED`, SOAP 없음, 이벤트 없음. 이어서 `RelTime` 0 폴링: 조회 1회, `position(28/180)` |
| DB-53 | `seek` 예외 | 등록 응답에 `proxyUrl` 없음 | `PROXY_FAILED`, SOAP 없음, 이벤트 없음 |
| DB-53b | `seek` 예외 · 오프셋 유지 | 오프셋 28 흐름, 응답 오프셋 88, SOAP `Play` 거부 | `DLNA_PLAY_FAILED` (메시지에 기기 이름), 이벤트 없음. 이후 위치를 알린다면 모두 `position(28/180)` |
| DB-57 | `seek` (일시정지 상태) | `pause()` 성공 뒤 `seek(61초)`, 응답 오프셋 60 | SOAP `Stop` · `SetAVTransportURI` · `Play` · `Pause`, 이벤트 `position(60/180)`, `state(stopped)` |
| DB-57 | 같음 | `pause()` → `resume()` 뒤 탐색 | SOAP 3개 (Pause 없음), `state(playing,buffering)` |
| DB-57 | 같음 | `pause()` → 새 `play` 뒤 탐색 | 같음 |
| DB-57 | 같음 | `pause()` 가 거부된 뒤 탐색 | 같음 |
| DB-59 | `seek` (다음 곡 등록됨) | 다음 곡 102 등록 뒤 탐색 | SOAP `Stop` · `SetAVTransportURI` · `Play` · `SetNextAVTransportURI` (주소 `proxyUrlFor('102')`, 제목 `곡 102`, 길이 240). 등록 호출은 101 만, API 호출 없음. 이후 `TrackURI` 가 102 면 `started(102)` |
| DB-59 | 같음 (다시 보내기 실패) | 다시 보낸 `SetNextAVTransportURI` 거부 | 탐색은 예외 없음. 이후 `TrackURI` 가 102 여도 `started(102)` 없음. 이후 `setNext(103)` 은 조회 · `SetNextAVTransportURI` 를 실행 |
| DB-60 | 직렬화 | `SetAVTransportURI` 를 붙잡고 `seek(20초)`, `seek(40초)` | 붙잡힌 동안 등록 `startPositionMs` [20000], SOAP `Stop` · `SetAVTransportURI`, 둘 다 미완료. 풀면 [20000, 40000], SOAP 6개, 주소 `proxyUrlAt('101', 40000)` |
| DB-60 | 직렬화 | 붙잡고 `seek(20초)`, `play(102)` | 붙잡힌 동안 등록 `trackId` [101]. 풀면 [101, 102], SOAP 6개, 주소 `proxyUrlFor('102')` |
| DB-60 | 직렬화 | 붙잡고 `seek(20초)`, `setNext(102)` | 붙잡힌 동안 등록 [101], SOAP 2개. 풀면 SOAP `Stop` · `SetAVTransportURI` · `Play` · `SetNextAVTransportURI` |
| DB-61 | `seek` (곡 없음) | `play` 전, 42.9초 | SOAP `Seek` `00:00:42` 만, 등록 없음 |
| DB-61 | `seek` (곡 없음) | DASH 재생 → `stop()` 뒤, 42.9초 | SOAP `Seek` `00:00:42` 만, 등록 없음, 이벤트 없음 |

## 5. DB: 위치 보정

"오프셋 O 흐름" = DASH 곡을 `startPosition` O 초로 재생하고 프록시가 O 초를 시작 오프셋으로 답한 상태. 곡 길이 180초.

| 규칙 ID | 경계 | 입력 | 기대값 |
| --- | --- | --- | --- |
| DB-54 | 폴링 (첫 `RelTime`) | 아래 경계 표 | 아래 경계 표 |
| DB-54 | 폴링 (기준 유지) | O 60, `RelTime` 3 → 70 | `position(63/180)`, `position(130/180)` (상대 유지) |
| DB-54 | 폴링 (기준 유지) | O 60, `RelTime` 60 → 1 | `position(60/180)`, `position(1/180)` (절대 유지) |
| DB-55 | 폴링 (상대) | 응답 오프셋 28500 밀리초 (O = 28), `RelTime` 5 | 위치 33초 |
| DB-55b | 폴링 (절대) | O 60, `RelTime` 59 → 61 | `position(59/180)`, `position(61/180)` |
| DB-55c | 폴링 (기준 미정) | O 60, `RelTime` 0 → 0 → 58 | `position(60/180)` ×2, 이어서 `position(58/180)` (0 으로는 기준을 정하지 않음) |
| DB-56 | 폴링 (길이) | O 60, `RelTime` 5, 렌더러 길이 120 | `position(65/180)` |
| DB-56 | 폴링 (길이 모름) | 곡 길이 0, O 60, `RelTime` 5, 렌더러 길이 120 | `position(65/-)`, `duration` null |
| DB-56b | 곡 끝 판정 (경계) | O 170, `PLAYING`/7 → `STOPPED` / `PLAYING`/6 → `STOPPED` | 177 → `ended(101)` / 176 → `state(stopped)` |
| DB-56b | 곡 끝 판정 (절대) | O 100, `PLAYING`/100 → `STOPPED` | `position(100/180)`, `state(playing)`, `state(stopped)` |
| DB-56b | 곡 끝 판정 (`RelTime` 0) | O 170, `PLAYING`/8 → `STOPPED`/0 | `position(178/180)`, `state(playing)`, `position(170/180)`, `ended(101)` |
| DB-58 | 갭리스 전환 | O 60 흐름에서 102 로 전환, 이어서 `RelTime` 5 / 렌더러 길이 200 | `started(102)`, `position(5/200)`, `state(playing)` |
| DB-58 | 새 `play` (오프셋) | O 60 흐름 뒤 단일 파일 102 재생, `RelTime` 5 / 길이 200 | `position(5/200)` |
| DB-58 | 새 `play` (기준) | O 60 흐름에서 `RelTime` 60 (절대) 뒤 DASH 102 를 O 60 으로 재생, `RelTime` 5 | `position(65/180)` |

DB-54 경계 표 (테스트 1개, 표로 묶음):

| O (초) | 첫 `RelTime` | 기준 | 알리는 위치 |
| --- | --- | --- | --- |
| 10 | 8 (= O − 2) | 절대 | 8 |
| 10 | 7 | 상대 | 17 |
| 10 | 10 | 절대 | 10 |
| 9 | 7 (= O − 2) | 상대 (O < 10) | 16 |
| 9 | 9 | 상대 (O < 10) | 18 |
| 60 | 58 (= O − 2) | 절대 | 58 |
| 60 | 57 | 상대 | 117 |

## 6. 속성

| 속성 ID | 생성기 | 확인하는 것 |
| --- | --- | --- |
| P-DB-6 | `offsetFlows()`: O 10 ~ 3600초, 첫 `RelTime` 은 셋 중 둘꼴로 O − 2 의 ±6초 (최소 1), 나머지는 1 ~ 3600초, 이후 0 ~ 30초씩 늘어나는 값 0 ~ 8개. 곡 길이 36000초 | 첫 값이 O − 2 이상이면 알린 위치가 `RelTime` 그대로, 미만이면 O + `RelTime`. 알린 위치가 줄어들지 않음 |
| P-DB-7 | `startRequests()`: DASH 여부 × 시작 위치 (넷 중 하나꼴로 0. DASH 는 0 ~ 3599999 밀리초, 단일 파일은 0 또는 1000 밀리초 이상) | DASH: `startPositionMs` = 밀리초 값, `Seek` 0회. 단일 파일: `startPositionMs` 0, `Seek` 는 시작 위치 > 0 일 때만 1회 |

`configurePbt()` 의 고정 seed (20261117), 속성당 100개 입력.

## 7. 정한 것

규칙만으로 정할 수 없어, 규칙의 뜻에 가장 가까운 쪽으로 정하고 진행한 것.

| # | 정한 것 | 근거 |
| --- | --- | --- |
| D-1 | DB-51 의 "재생 명령" 은 SOAP `Stop` → `SetAVTransportURI` → `Play` 로 단언한다 | "`play` 와 같은" 명령이고 `play` 의 스피커 명령은 DM-07 · DB-07 에서 이 세 개다 |
| D-2 | DB-52 의 두 알림은 적힌 순서 (위치 → 상태) 로 단언한다 | 규칙이 그 순서로 적었고 DB-07 도 적힌 순서가 곧 순서다 |
| D-3 | DB-52 의 "곧바로 알리는 위치" 는 초 단위로 떨어지는 오프셋으로만 검증한다. 오프셋이 28.5초일 때 이 알림이 28초인지 28.5초인지는 검증하지 않는다 | 5절 머리말은 보정에 쓰는 O 만 "초 단위로 버림" 이라 했고, DB-52 의 값은 정하지 않았다. DB-55 (O + `RelTime`) 는 28.5초 → 33초로 검증한다 |
| D-4 | DB-53b 뒤 폴링이 계속되는지는 단언하지 않는다. "위치를 알린다면 예전 오프셋 기준" 만 본다 | 규칙은 "현재 주소와 시작 오프셋은 그대로" 만 적었다 |
| D-5 | DB-53 · DB-53b · DB-52 의 "현재 주소" 는 따로 단언하지 않는다 (스피커에 보낸 주소와 시작 오프셋으로만 확인) | 현재 주소는 공개 인터페이스로 볼 수 없다. 내부 상태를 들여다보지 않는다 |
| D-6 | DB-59 에서 다시 보낸 `SetNextAVTransportURI` 가 실패해도 `seek` 자체는 예외 없이 끝난다고 본다 | 탐색의 예외는 DB-53 · DB-53b 둘만 정해져 있다 |
| D-7 | 갭리스로 넘어간 뒤의 "지금 곡" 은 넘어간 곡이고, 그 곡의 스트림 정보는 `setNext` 때 받은 것이다 (DB-51, DB-45 를 전환 뒤에도 적용) | DB-39 가 기준을 새 곡으로 바꾸고, DB-51 은 "지금 곡" 과 "TIDAL API 를 다시 부르지 않는다" 를 요구한다 |
| D-8 | 탐색 뒤 스트리밍 잠금은 "마지막 호출이 켜짐이거나 호출 없음" 만 본다. 채널 호출 목록 전체는 비교하지 않는다 | 폴링을 "다시 시작" 할 때 잠금을 껐다 켜는지는 규칙에 없다 (DB-31 은 멈출 때만) |
| D-9 | P-DB-7 에서 단일 파일 곡의 시작 위치는 0 이거나 1초 이상만 만든다 | DB-11 은 `Seek` 를 "초 단위" 로 보낸다고만 하고, 0 초과 1초 미만일 때 `Seek` 를 보내는지는 어느 규칙에도 없다. 호출하는 쪽 (`PlayerManager`) 은 초 단위 위치를 쓴다 |
| D-10 | NB-02 의 "숫자가 아님" 은 없음 · null · `'abc'` 로 검증한다. `'28000'` 같은 숫자 문자열과 소수 (28000.5) 는 검증하지 않는다 | 규칙에 없다. Kotlin 은 Long 으로만 보낸다 (CR-16) |
| D-11 | NB 테스트는 새 파일 `test/core/native/tidal_sdk_native_bridge_test.dart` 에 둔다 | `test/` 가 `lib/` 의 경로를 따른다 (`test/core/utils` 등) |
| D-12 | DB-57 과 DB-59 가 함께 걸릴 때 (`Pause` 와 `SetNextAVTransportURI` 의 순서) 는 테스트하지 않는다 | 두 규칙 모두 "재생 명령 뒤" 라고만 한다 |

## 추가분 (DB-62)

기준: `business-rules.md` 5절 "새 규칙: 탐색 중의 폴링" (2026-11-17 추가). 테스트는 `dlna_backend_test.dart` 의 group "탐색 중의 폴링 (dash-seek)". 탐색을 도중에 멈춰 두는 데는 기존 도우미의 응답 붙잡기 (`FakeNativeChannel.hold`, `FakeSoapClient.hold`) 를 쓴다. 곡 길이 180초.

| 규칙 ID | 경계 | 입력 | 기대값 |
| --- | --- | --- | --- |
| DB-62 (+ DB-62b 성공) | 폴링 (등록 대기 중) | `PLAYING`/5 를 본 뒤 등록 응답을 붙잡고 `seek(61초)` (응답 오프셋 60), 2초 진행 | 그 사이 `GetTransportInfo` 0회, `GetPositionInfo` 0회, 이벤트 없음. 풀면 `position(60/180)`, `state(playing,buffering)`. 다음 1초 (`RelTime` 0): 조회 각 1회, `position(60/180)`, `state(playing)` |
| DB-62 | 폴링 (스피커 명령 중, `STOPPED`) | `PLAYING`/5 를 본 뒤 스피커가 `STOPPED`/0 을 답하게 하고 `SetAVTransportURI` 를 붙잡은 채 탐색, 2초 진행 | SOAP 는 `Stop` · `SetAVTransportURI` 뿐, 이벤트 없음 (`state(stopped)` 없음). 풀면 예외 없이 `Play` 까지, 이벤트는 `position(60/180)`, `state(playing,buffering)` 뿐 |
| DB-62 (+ DB-62b 성공) | 폴링 (곡 끝 근처, `STOPPED`) | `PLAYING`/178 을 본 뒤 스피커가 `STOPPED`/0 을 답하게 하고 `Play` 를 붙잡은 채 `seek(31초)` (응답 오프셋 30), 2초 진행 | SOAP 는 `Stop` · `SetAVTransportURI` · `Play` 뿐, 이벤트 없음 (`ended(101)` 없음). 풀면 `position(30/180)`, `state(playing,buffering)`. 다음 1초 (`PLAYING`/1): `position(31/180)`, `state(playing)` |
| DB-62b (DB-53 실패) | 폴링 (실패 뒤) | 오프셋 28 흐름에서 `PLAYING`/0 을 본 뒤, 등록이 채널 오류가 되게 하고 응답을 붙잡은 채 `seek(90초)`, 2초 진행 | 그 사이 SOAP 없음, 이벤트 없음. 풀면 `PROXY_FAILED`, 이벤트 없음. 이어서 `PLAYING`/0 → `STOPPED`/0: 조회 2회, `position(28/180)`, `state(playing)`, `position(28/180)`, `state(stopped)` (탐색 전에 `PLAYING` 을 본 상태 그대로) |
| DB-62b (DB-53b 실패) | 폴링 (실패 뒤) | 오프셋 28 흐름에서 `PLAYING`/0 을 본 뒤, `Play` 를 거부하게 하고 붙잡은 채 `seek(90초)` (응답 오프셋 88), 2초 진행 | 그 사이 SOAP 는 재생 명령 3개뿐, 이벤트 없음. 풀면 `DLNA_PLAY_FAILED`, 이벤트 없음. 다음 1초 (`PLAYING`/0): 조회 1회, `position(28/180)`, `state(playing)` |

정한 것 (추가):

| # | 정한 것 | 근거 |
| --- | --- | --- |
| D-13 | 탐색이 끝난 뒤 첫 폴링은 "1초 뒤에 정확히 1회" 로 단언한다 | DB-62b 의 "다음 차례부터". 타이머를 그대로 두든 다시 만들든 1초 뒤 1회다 |
| D-14 | D-4 (DB-53b 뒤 폴링이 계속되는지는 단언하지 않음) 는 DB-62b 로 정해졌다. 새 테스트는 재생 명령 실패 뒤에도 폴링이 이어진다고 단언한다. 앞서 고정한 DB-53b 테스트는 그대로 둔다 (더 약한 단언이라 어긋나지 않음) | DB-62b "성공 · 실패 모두 다음 차례부터 폴링이 이어진다" |

### 추가분 (DB-62c)

기준: `business-rules.md` 5절 DB-62c (2026-11-17 추가). 같은 group 에 테스트 2개. 조회 응답은 `FakeSoapClient.hold('GetTransportInfo')`, 탐색은 `FakeNativeChannel.hold('registerTrackStream')` 로 붙잡는다. 곡 길이 180초, 시작 오프셋 0 인 DASH 곡.

| 규칙 ID | 경계 | 입력 | 기대값 |
| --- | --- | --- | --- |
| DB-62c (+ DB-62b 성공) | 탐색 전에 보낸 조회의 응답 | `PLAYING`/178 을 본 뒤 다음 조회 (`STOPPED`/0) 를 붙잡음 → 등록 응답을 붙잡은 채 `seek(31초)` (응답 오프셋 30) → 조회 응답을 풂 | 이벤트 없음 (`ended(101)` · `state(stopped)` 없음). 등록을 풀면 예외 없이 `position(30/180)`, `state(playing,buffering)`. 다음 1초 (`PLAYING`/1): 조회 1회, `position(31/180)`, `state(playing)` |
| DB-62c (+ DB-62b · DB-53 실패) | 같음, 탐색 실패 | 같은 준비에서 등록이 채널 오류 | 조회 응답을 풀어도 이벤트 없음. 등록을 풀면 `PROXY_FAILED`, 이벤트 없음. 이어서 `PLAYING`/179 → `STOPPED`/0: 조회 2회, `position(179/180)`, `state(playing)`, `position(0/180)`, `ended(101)` (폴링이 멈추지 않았고 `PLAYING` 을 본 상태가 유지됨) |

정한 것 (추가):

| # | 정한 것 | 근거 |
| --- | --- | --- |
| D-15 | 응답을 붙잡아 둔 동안에는 시간을 진행시키지 않는다 (탐색 중 새 폴링 차례는 DB-62 테스트가 따로 본다). 버린 조회가 끝난 뒤의 다음 차례는 평소처럼 1회 조회한다고 단언한다 | DB-62c 는 응답 하나를 버리는 규칙이고, DB-30 (앞의 확인이 끝나지 않으면 건너뜀) 과 섞이지 않게 한다 |
