# 테스트 경계 표 (RED, Kotlin) - dash-seek

기준: `aidlc-docs/construction/dash-seek/functional-design/business-rules.md` 1절 (DS) · 2절 (PS) · 3절 (CR). 바뀌지 않는 부분의 기준은 `android-native-tests` 의 `business-rules.md` (CR, PX).
운영 코드는 시그니처와 문서 주석만 보았다 (`PlaybackContracts.kt`, `DashManifest.kt` 의 선언, `registerTrackStreamAt` 선언). 사람 승인 없이 진행했다 (자동 승인 지시).

테스트 폴더: `android/app/src/test/kotlin/com/example/tidal_connect_lite/`

## 1. 공통 입력

| 이름 | 내용 |
| --- | --- |
| 예시 매니페스트 (DS-01 의 예) | timescale 44100, `<S d="176400" r="2"/><S d="88200"/>`. 세그먼트 4개, 시작 시각 0 · 4000 · 8000 · 12000 ms, 곡 길이 14000 ms |
| `MPD4T` (프록시) | 위와 같은 시각. 초기화 세그먼트 `INIT`, 세그먼트 `AAAA` · `BB` · `CCCCCC` · `DDD`. 전체 `INITAAAABBCCCCCCDDD` (19바이트) |

## 2. `DashManifest` (`DashManifestTest.kt`)

경계: `DashManifest.parse(xml)` 의 결과에 `segmentStartMs(index)` · `segmentIndexAt(positionMs)` 호출.

| 규칙 ID | 경계 | 입력 | 기대값 | 테스트 파일 |
| --- | --- | --- | --- | --- |
| DS-01 | `segmentStartMs` | a 예시 매니페스트 / b timescale 없음 + `<S d="4" r="2"/><S d="2"/>` / c timescale 44100 + `<S d="1000" r="2"/>` / d 파일의 기존 매니페스트 (timescale 96000, `<S d="384000" r="3"/><S d="120000"/>`) | a `0, 4000, 8000, 12000` / b `0, 4000, 8000, 12000` / c `0, 22, 45` (버림) / d `0, 4000, 8000, 12000, 16000` | `DashManifestTest.kt` |
| DS-02 | `segmentIndexAt` | 예시 매니페스트, 위치 0 · 3999 · 4000 · 7999 · 8000 · 11999 · 12000 | 0 · 0 · 1 · 1 · 2 · 2 · 3 | 같음 |
| DS-03 | `segmentIndexAt` | 예시 매니페스트, 위치 0 · -1 · -4000 · `Long.MIN_VALUE` | 모두 0 | 같음 |
| DS-04 | `segmentIndexAt` | 예시 매니페스트, 위치 14000 · 14001 · 3600000 · `Long.MAX_VALUE` | 모두 3 | 같음 |
| DS-05 | `parse` + 두 함수 | a `d` 없는 `<S/>` 가 섞임 / b `d="abc"` / c `d="0"` / d `d="-5"` / e timescale 0 / f timescale -1 | 해석 성공 (null 아님), `segmentCount` 4 · 2 · 3 · 2 · 4 · 4, `initializationUrl` · `segmentUrl(0)` 그대로, 시작 시각 모두 0, 위치 -1 · 0 · 4000 · 12000 · 3600000 의 세그먼트 모두 0 | 같음 |
| DS-06 | 기존 필드 · `segmentUrl` | 기존 테스트 4개 (수정 없음) | 그대로 통과 | 같음 (기존) |

| 속성 ID | 생성기 | 확인 | 횟수 | 테스트 파일 |
| --- | --- | --- | --- | --- |
| P-DS-1 | `DashGenerators.timeline`: timescale ∈ {1, 1000, 44100, 48000, 96000}, `<S d r>` 묶음 1 ~ 6개 (`d` 1 ~ 500000, `r` 0 ~ 3) | 시작 시각이 번호에 대해 줄지 않음. `segmentStartMs(segmentIndexAt(segmentStartMs(i))) == segmentStartMs(i)`. 마지막에 참조 모델 (DS-01 의 식) 과 시작 시각 목록이 같음 | 100 | `DashManifestTest.kt`, `DashGenerators.kt` |
| P-DS-2 | 위 타임라인 + `DashGenerators.positionPick` (곡 안 · 세그먼트 경계 ±1 ms · 0 이하 · 곡 길이 밖) | `k` 가 0 이상 `segmentCount` 미만. `segmentStartMs(k) ≤ max(p, 0)`. `p ≤ 0` 이면 `k == 0`, 아니면 `k` 가 마지막이 아닐 때 `p < segmentStartMs(k + 1)` | 100 | 같음 |

## 3. 프록시 (`TidalStreamProxyServerTest.kt`)

경계: `registerTrackStreamAt(...)` 의 반환값 (`ProxyFixture.registerAt`), 프록시에 보낸 실제 HTTP GET · HEAD 의 응답, 가짜 CDN 이 받은 요청 기록.

| 규칙 ID | 경계 | 입력 | 기대값 | 테스트 파일 |
| --- | --- | --- | --- | --- |
| PS-01 | 등록 반환값 + GET | a 기본 등록, 위치 4000 / b MIME `audio/mpeg` · 빈 값 · DASH 등록 (`audio/flac`) / c 같은 곡 두 번 / d 등록 4번 (1 · 3 · 4 번째는 `registerTrackStreamAt`, 2 번째는 기존 `registerTrackStream`) | a `http://127.0.0.1:<열린 포트>/audio/<16자 16진수>.flac` / b 확장자 `mp3` · `m4a` · `m4a` / c 토큰이 다르고 두 주소 모두 본문을 줌 / d 1번째 404 `Not Found`, 2 ~ 4번째는 자기 본문 | `TidalStreamProxyServerTest.kt` |
| PS-02 | 등록 반환값 | `MPD4T`, 위치 0 · 3999 · 4000 · 5000 · 11999 · 12000 · -1 · 14000 · 3600000 | `startOffsetMs` 0 · 0 · 4000 · 4000 · 8000 · 12000 · 0 · 12000 · 12000 | 같음 |
| PS-03 | 등록 반환값 + GET | a 단일 파일, 위치 5000 / b 직접 주소와 매니페스트가 함께, 위치 5000 | `startOffsetMs` 0. 200, 본문은 CDN 의 10바이트 그대로, `Content-Type: audio/flac`, (a) `Content-Length: 10`, `Accept-Ranges: bytes`, CDN 은 Range 없는 GET 1건 | 같음 |
| PS-04 | 등록 반환값 + GET | a `not xml`, 위치 5000 / b `d` 없는 `<S/>` 가 섞인 매니페스트 / c timescale 0 | `startOffsetMs` 0. a 500 `Invalid DASH manifest` / b · c 200, `Content-Length: 19`, 본문 `INITAAAABBCCCCCCDDD` | 같음 |
| PS-05 | 기존 `registerTrackStream` (인자 5개) + GET | `MPD4T` | 반환값은 `.m4a` 주소 문자열. `Content-Length: 19`, 본문 `INITAAAABBCCCCCCDDD`. 위치 0 의 `registerTrackStreamAt` 도 같은 응답 | 같음 |
| PS-06 | GET + CDN 기록 | a `MPD4T`, 위치 5000 / b 초기화 세그먼트 없음, 위치 8000 / c 위치 12000 | a 본문 `INITBBCCCCCCDDD`, `audio/mp4`, `Accept-Ranges` 없음, CDN GET: init 1 · 1번 0 · 2 ~ 4번 각 1 / b 본문 `CCCCCCDDD`, CDN GET 1 · 2번 0, 합계 2 / c 본문 `INITDDD`, CDN GET 합계 2 | 같음 |
| PS-07 | GET · HEAD 의 헤더 | 위치 4000. a 길이를 모두 앎 / b 3번 세그먼트의 HEAD 에 길이 없음 (범위 안) / c 1번 세그먼트의 HEAD 에 길이 없음 (범위 밖) | a GET · HEAD `Content-Length: 15` / b GET 은 `Content-Length` 없음 + `Transfer-Encoding: chunked` + 본문 전체, HEAD 는 200 에 `Content-Length` 없음 / c GET · HEAD `Content-Length: 15` | 같음 |
| PS-08 | CDN 의 HEAD 기록 | a 위치 0 으로 등록해 GET → 같은 매니페스트를 위치 4000 으로 등록해 GET · HEAD / b 위치 8000 → 0 → 12000 | 경로마다 CDN HEAD 1건, 합계 5건 | 같음 |
| PS-09 | 위치 0 등록의 GET · HEAD | a `MPD4T` / b 2번 세그먼트 길이 모름 / c `<MPD><Period/></MPD>` / d HEAD 뒤 GET | a `startOffsetMs` 0, 200, 본문 19바이트, `Content-Length: 19`, `audio/mp4`, `Accept-Ranges` 없음, 경로마다 CDN GET 1건 / b chunked, 본문 전체 / c 500 `Invalid DASH manifest` / d 두 응답 모두 `Content-Length: 19`, CDN HEAD 합계 5 | 같음 |
| PS-10 | 세 주소의 GET | 같은 곡 · 매니페스트를 위치 0 · 4000 · 12000 으로 등록, 등록 순서와 다르게 조회 | 주소 3개가 서로 다름. 본문 `INITAAAABBCCCCCCDDD` · `INITBBCCCCCCDDD` · `INITDDD`. 위치 4000 주소를 다시 조회해도 `Content-Length: 15` 와 같은 본문 | 같음 |

| 속성 ID | 생성기 | 확인 | 횟수 | 테스트 파일 |
| --- | --- | --- | --- | --- |
| P-PS-1 | `ProxyGenerators.dashSeek`: 기존 `dashContent` (초기화 있음 · 없음, 세그먼트 1 ~ 8개, 각 1 ~ 4096바이트) + 세그먼트마다 `d` + timescale + 위치 | 참조 모델 (`DashTiming`) 로 구한 `k` 에 대해: `startOffsetMs` = `k` 번째의 시작 시각, 본문 = 초기화 + `k` 번째부터, `Content-Length` = 그 길이 | 25 | `TidalStreamProxyServerTest.kt`, `ProxyGenerators.kt`, `DashGenerators.kt` |

도우미: `ProxyFixture.registerAt(...)` 추가. `newDash` · `prepareDash` 에 `timescale` (기본 44100) 과 `timeline` (기본 null = 세그먼트마다 `<S d="1"/>`) 인자 추가. 기본값으로 만든 매니페스트 원문은 이전과 글자 단위로 같다.

## 4. 채널 (`PlaybackCommandRouterTest.kt`)

경계: `PlaybackCommandRouter.handle("registerTrackStream", args)` 의 결과와 `FakeProxyRegistrar` 가 받은 호출 기록 (`registerTrackStream(곡, 직접 주소, 매니페스트, 허용 주소, MIME, 시작 위치)`).

| 규칙 ID | 경계 | 입력 | 기대값 | 테스트 파일 |
| --- | --- | --- | --- | --- |
| CR-14 (a) | 호출 기록 | `startPositionMs` 가 Int 4000 · Long 4000 · Int 0 · Long 3000000000 | 여섯 번째 인자 `4000` · `4000` · `0` · `3000000000` | `PlaybackCommandRouterTest.kt` |
| CR-14 (b) | 호출 기록 | `startPositionMs` 없음 · null · 문자열 `"4000"` · 불리언 `true` | 여섯 번째 인자 `0` | 같음 |
| CR-15 | 호출 기록 | 곡 `202`, 직접 주소 빈 값, 매니페스트 `<MPD id="m"/>`, 허용 주소 `192.0.2.20`, `audio/mp4`, 위치 61500 | 프록시 fake 에 `registerTrackStream(202, , <MPD id="m"/>, 192.0.2.20, audio/mp4, 61500)` 1건, 다른 fake 는 0건 | 같음 |
| CR-16 | 결과 | 등록 결과의 오프셋 0 · 60000 · 3000000000 (요청 위치는 61500) | `{proxyUrl: <주소>, startOffsetMs: <같은 값, Long>}` | 같음 |
| CR-17 | 결과 | 등록 결과 null, 위치 Int · Long · 없음 | 오류 `NO_WIFI`, 메시지 `Wi-Fi에 연결되어 있지 않아 스피커로 스트리밍할 수 없습니다.`, 등록 호출 1건 | 같음 |
| CR-18 | 결과 + 호출 기록 | 기존 `CR-01` 의 #1 ~ #16 행과 그 밖의 기존 테스트 (수정 없음) | 그대로 통과 | 같음 (기존) |

고친 기존 테스트 (등록 부분만):

| 테스트 | 바뀐 기대값 | 근거 |
| --- | --- | --- |
| `CR-01` #17 행 | 인자에 `startPositionMs: 4000`, 호출 기록 끝에 `, 4000`, 성공 값 `{proxyUrl, startOffsetMs: 4000L}` | CR-14 ~ CR-16 |
| `CR-02` (a) #9, (b) ③, (c) ⑥ | 호출 기록 끝에 `, 0`, 성공 값에 `startOffsetMs: 0L` | CR-14 (없으면 0), CR-16 |
| `CR-08` | 호출 기록 끝에 `, 0` (fake 의 새 시그니처) | CR-15 |
| `CR-11` (a) ③ | 호출 기록 끝에 `, 0`, 성공 값에 `startOffsetMs: 0L` | CR-14, CR-16 |
| `CR-12` (c) | 호출 기록 끝에 `, 0` | CR-15 |

| 속성 ID | 생성기 | 확인 | 횟수 | 테스트 파일 |
| --- | --- | --- | --- | --- |
| P-CR-5 (확장) | `RouterArbs.registration()` 에 `startPositionMs` (0 ~ 36000000, Int 또는 Long, 30% 는 없음) 추가. `RouterArbs.startOffsetMs()` (0 또는 0 ~ 36000000) | 호출 기록의 여섯 인자 (빠진 `startPositionMs` 는 0), 성공 값 `{proxyUrl, startOffsetMs}` 가 등록 함수의 반환값 | 100 | `PlaybackCommandRouterTest.kt`, `RouterGenerators.kt` |

`P-CR-6` 은 고치지 않았다. 생성기가 넓어져 `registerTrackStream` 호출에 `startPositionMs` 가 섞여 들어온다.

## 5. 정한 것 (규칙만으로 정할 수 없어 뜻에 가장 가까운 쪽을 고름)

| # | 곳 | 정한 내용 | 근거 |
| --- | --- | --- | --- |
| D-1 | DS-02 와 DS-03 의 겹침 (위치 0, 0 번째와 1 번째의 시작 시각이 모두 0 ms 로 버림되는 타임라인) | 위치가 0 이하이면 DS-03 이 우선해 0 번째다. `P-DS-2` 는 `p ≤ 0` 일 때 `k == 0` 만 확인하고 "다음 세그먼트의 시각보다 앞" 은 `p > 0` 일 때만 확인한다. 참조 모델 (`DashTiming.indexAt`) 도 같다 | PS-05 · PS-09 (위치 0 의 등록은 기존과 같다). 기존 프록시 테스트의 매니페스트 (`<S d="1"/>`, timescale 44100) 는 모든 시작 시각이 0 ms 라, DS-02 를 글자 그대로 따르면 위치 0 에서 마지막 세그먼트가 되어 기존 45개가 깨진다 |
| D-2 | P-DS-1 | 규칙의 두 조건에 더해, 시작 시각 목록이 DS-01 의 식을 옮긴 참조 모델과 같은지도 본다 | 두 조건만으로는 모든 시각이 0 인 구현 (지금의 뼈대) 이 통과한다. 참조 표를 두는 방식은 기존 `P-PX-2` 와 같다 |
| D-3 | PS-07 의 "그 범위" | 시작 세그먼트 앞의 세그먼트만 길이를 모르면 `Content-Length` 를 알린다 (`PS-07 c`) | "길이를 모르는 세그먼트가 **그 범위에** 하나라도 있으면" 의 반대 경우. 문서에 직접 적힌 문장은 아니다 |
| D-4 | PS-08 의 HEAD 횟수 | "경로마다 1건, 합계 5건" 을 본다. 처음 등록이 중간부터일 때 (`PS-08 b`) 도 같다 | 첫 요청에서 전부 조회하는 구현과 범위만 조회하고 나중에 나머지를 조회하는 구현 모두 이 값이 된다. 조회 시점은 규칙에 없어 고정하지 않았다 |
| D-5 | PS-06 의 "CDN 에 GET 하지 않는다" | 시작 세그먼트 앞의 세그먼트에 대한 CDN **GET** 건수만 0 으로 본다. HEAD (길이 조회) 는 세지 않는다 | PS-08 이 길이 조회를 매니페스트 단위로 정한다 |
| D-6 | CR-14 의 Int 범위를 넘는 값 | Long 3000000000 을 그대로 넘기는 것을 확인한다 | "Long 으로 넘긴다". 앞 작업의 CR-10 은 Int 범위를 넘는 값을 입력 범위 밖으로 두었으나 그것은 Int 로 넘기는 인자의 이야기다 |
| D-7 | CR-14 의 "숫자가 아니면" | 문자열과 불리언만 넣었다. 소수 (Double) 는 넣지 않았다 | 앞 작업의 CR-10 · O-11 이 소수를 입력 범위 밖으로 둔다 |
| D-8 | CR-08 · CR-12 (c) | 시작 위치를 넣지 않은 인자 그대로 두고 호출 기록의 여섯 번째 인자만 `0` 으로 고쳤다 | 두 테스트가 자기 규칙 (NO_WIFI, 예외 전파) 만으로 판정되게 하려는 것. 시작 위치가 있는 경우는 CR-17 이 본다 |
| D-9 | CR-18 | 새 테스트를 만들지 않고 기존 `CR-01` #1 ~ #16 행 등 고치지 않은 테스트를 대응시켰다 | "바뀌지 않는다" 는 기존 테스트가 수정 없이 통과하는 것으로 확인된다 (DS-06 과 같은 방식) |
| D-10 | PS-04 의 "시각을 알 수 없는 매니페스트" 의 GET | 200 에 처음부터의 본문 (`Content-Length: 19`) | "시작 세그먼트 0. 등록 자체는 기존처럼 된다". 괄호의 "GET 은 PX-37 대로 500" 은 해석할 수 없는 매니페스트에만 해당한다고 읽었다 (DS-05: `parse` 는 성공) |

## 6. 테스트하지 않은 것

| 곳 | 이유 |
| --- | --- |
| `segmentStartMs(index)` 의 범위 밖 번호 (음수, `segmentCount` 이상) | 규칙에 없다 |
| timescale 이 숫자가 아닌 매니페스트 (`timescale="abc"`) | DS-05 는 "0 이하" 만 적는다. "없으면 1" 과 어느 쪽인지 정해져 있지 않다 |
| `r` 이 음수이거나 숫자가 아닌 `<S>` | 규칙에 없다 (세그먼트 수 계산은 기존 동작) |
| `PlaybackCore` 의 `proxyRegistrar` 가 `registerTrackStreamAt` 을 부르는 것 | 규칙 3절: JVM 테스트 대상이 아니다 |
| 주소 재발급 (PX-26 ~ PX-31) 뒤의 시작 세그먼트 유지 | 규칙에 없다 |
