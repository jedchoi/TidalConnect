# RED 판정 표 (Kotlin) - dash-seek

- 실행: `cd android && JAVA_HOME=/opt/homebrew/opt/openjdk@17 ./gradlew :app:testDebugUnitTest --offline` (2026-11-17, 브랜치 `feat/dash-seek`, 운영 코드는 뼈대 `6aa9d69` 그대로)
- 결과 XML: `build/app/test-results/testDebugUnitTest/`
- 합계: 109개 실행, 19개 실패, 90개 통과, skip 0. 컴파일 오류 · 테스트 쪽 오류 없음
- 5회 실행했다. 최종 테스트 묶음으로는 1회 (위 숫자), 그 직전 묶음 (테스트 1개의 단언 1줄만 다름) 으로 3회 실행해 실패 목록이 매번 같았다. 알려진 `SocketTimeoutException: Read timed out` 은 5회 모두 나오지 않았다
- 경계 표: `red-seam-table-kotlin.md`

## 1. 합계

| 구분 | 수 | RED (기대값 비교 실패) | 통과 |
| --- | --- | --- | --- |
| 새 테스트 | 23 | 13 | 10 (보호) |
| 고친 기존 테스트 | 8 | 6 | 2 |
| 고치지 않은 기존 테스트 | 78 | 0 | 78 |
| 합계 | 109 | 19 | 90 |

파일별: `DashManifestTest` 11 (실패 5), `PlaybackCommandRouterTest` 37 (실패 9), `TidalStreamProxyServerTest` 56 (실패 5), `ChannelAdapterTest` 5 (실패 0).

## 2. 새 테스트

### `DashManifestTest.kt`

| 테스트 | 결과 | 실패 종류 | 판정 |
| --- | --- | --- | --- |
| `DS-01 세그먼트의 시작 시각은 …` | FAILED | AssertionError (`[0, 4000, 8000, 12000]` 기대, `[0, 0, 0, 0]`) | RED 인정 |
| `DS-02 위치가 속한 세그먼트는 …` | FAILED | AssertionError (위치 4000: 1 기대, 0) | RED 인정 |
| `DS-03 위치가 0 이하이면 0 번째 세그먼트다` | PASSED | - | 보호 (뼈대가 항상 0) |
| `DS-04 위치가 곡 길이 이상이면 마지막 세그먼트다` | FAILED | AssertionError (위치 14000: 3 기대, 0) | RED 인정 |
| `DS-05 길이를 알 수 없는 S 가 있거나 …` | PASSED | - | 보호 (뼈대가 항상 0, `parse` 는 기존 동작) |
| `P-DS-1 어떤 타임라인이든 …` | FAILED | AssertionFailedError (1번째 입력, 축소 뒤 timescale 96000 · `<S d="384000" r="1"/>`: 시작 시각 `[0, 4000]` 기대, `[0, 0]`) | RED 인정 (참조 모델과의 비교에서 실패. 규칙의 두 조건은 뼈대에서 통과한다, 경계 표 D-2) |
| `P-DS-2 어떤 위치든 …` | FAILED | AssertionFailedError (1번째 입력: 0 번째를 골랐는데 다음 세그먼트의 시각이 위치 이하) | RED 인정 |

### `PlaybackCommandRouterTest.kt`

| 테스트 | 결과 | 실패 종류 | 판정 |
| --- | --- | --- | --- |
| `CR-14 startPositionMs 는 Int 로 오든 Long 으로 오든 …` | FAILED | AssertionError (호출 기록 끝 `4000` 기대, `0`) | RED 인정 |
| `CR-14 startPositionMs 가 없거나 null 이거나 숫자가 아니면 0 으로 넘긴다` | PASSED | - | 보호 (뼈대가 항상 0 을 넘김) |
| `CR-15 등록 함수에 여섯 인자를 정해진 순서로 한 번 넘긴다` | FAILED | AssertionError (호출 기록 끝 `61500` 기대, `0`) | RED 인정 |
| `CR-16 등록에 성공하면 proxyUrl 과 Long 타입의 startOffsetMs 를 돌려준다` | FAILED | AssertionError (`{proxyUrl, startOffsetMs=0}` 기대, `{proxyUrl}`) | RED 인정 |
| `CR-17 등록 결과가 null 이면 …` | PASSED | - | 보호 (CR-08 과 같은 동작) |

### `TidalStreamProxyServerTest.kt`

| 테스트 | 결과 | 실패 종류 | 판정 |
| --- | --- | --- | --- |
| `PS-01 registerTrackStreamAt 은 기존 등록과 같은 형식의 주소를 …` | PASSED | - | 보호 (뼈대가 기존 등록을 그대로 부름) |
| `PS-02 DASH 등록의 시작 오프셋은 …` | FAILED | AssertionError (위치 4000: 4000 기대, 0. 그 밖에 5행) | RED 인정 |
| `PS-03 단일 파일 등록은 시작 위치를 무시하고 …` | PASSED | - | 보호 |
| `PS-04 해석할 수 없거나 시각을 알 수 없는 매니페스트는 …` | PASSED | - | 보호 |
| `PS-05 기존 registerTrackStream 은 …` | PASSED | - | 보호 |
| `PS-06 시작 세그먼트가 있는 DASH GET 은 …` | FAILED | AssertionError (본문 15바이트 `INITBBCCCCCCDDD` 기대, 19바이트. CDN GET 1번 세그먼트 0건 기대, 1건) | RED 인정 |
| `PS-07 시작 세그먼트가 있는 DASH 의 Content-Length 는 …` | FAILED | AssertionError (`Content-Length` 15 기대, 19) | RED 인정 |
| `PS-08 같은 매니페스트를 다른 시작 세그먼트로 다시 등록해도 …` | PASSED | - | 보호 (HEAD 건수만 본다. 뼈대는 항상 전체를 한 번 조회) |
| `PS-09 시작 세그먼트 0 으로 등록한 DASH 곡의 응답은 기존과 같다` | PASSED | - | 보호 |
| `PS-10 같은 곡을 다른 위치로 여러 번 등록하면 …` | FAILED | AssertionError (위치 4000 주소의 본문 15바이트 기대, 19바이트. 그 밖에 3건) | RED 인정 |
| `P-PS-1 어떤 DASH 내용과 시작 위치든 …` | FAILED | AssertionFailedError (2번째 입력, ArrayComparisonFailure: 본문이 시작 세그먼트부터가 아님) | RED 인정 |

## 3. 고친 기존 테스트

| 테스트 | 결과 | 실패 종류 | 판정 |
| --- | --- | --- | --- |
| `CR-01 표의 16개 메서드는 …` (#17 행) | FAILED | AssertionError (#17: `{proxyUrl, startOffsetMs=4000}` 기대, `{proxyUrl}`). #1 ~ #16 행은 그 앞에서 통과 | RED 인정 (CR-14 ~ CR-16) |
| `CR-02 인자 맵이 비어 있으면 …` (#9 행) | FAILED | AssertionError (`startOffsetMs=0` 없음) | RED 인정 (CR-16) |
| `CR-02 일부 키만 있으면 …` (③ 행) | FAILED | AssertionError (`startOffsetMs=0` 없음) | RED 인정 (CR-16) |
| `CR-02 키는 있는데 값이 null 이면 …` (⑥ 행) | FAILED | AssertionError (`startOffsetMs=0` 없음) | RED 인정 (CR-16) |
| `CR-08 프록시 등록이 null 이면 NO_WIFI 오류다` | PASSED | - | 보호 (호출 기록의 여섯 번째 인자만 고침) |
| `CR-11 문자열 자리에 숫자가 오면 …` (③ 행) | FAILED | AssertionError (`startOffsetMs=0` 없음) | RED 인정 (CR-16) |
| `CR-12 프록시 협력 객체의 예외는 …` | PASSED | - | 보호 (호출 기록의 여섯 번째 인자만 고침) |
| `P-CR-5 등록 인자는 시작 위치까지 그대로 전달되고 …` | FAILED | AssertionFailedError (1번째 입력: `startOffsetMs` 없음) | RED 인정 (CR-14 ~ CR-16) |

표 형식 테스트 (`CR-01`, `CR-02`, `CR-11`) 는 행을 순서대로 돌다 등록 행에서 멈춘다. 등록 행은 각 표의 마지막 행이라 그 앞의 행은 모두 통과한 뒤다.

## 4. 고치지 않은 기존 테스트 (78개)

모두 통과.

| 파일 | 수 | 비고 |
| --- | --- | --- |
| `DashManifestTest.kt` | 4 | DS-06 |
| `TidalStreamProxyServerTest.kt` | 45 | `newDash` · `prepareDash` 의 기본값이 이전과 같아 입력이 바뀌지 않았다 |
| `PlaybackCommandRouterTest.kt` | 24 | CR-18. `P-CR-6` 은 생성기가 넓어져 `startPositionMs` 가 든 등록 호출도 받는다 |
| `ChannelAdapterTest.kt` | 5 | |

## 5. 불인정 실패

없음. 실패 19건은 모두 기대값 비교 실패다 (컴파일 오류, 도우미 · 생성기 오류, 타임아웃 없음).

## 6. 작성 중 고친 테스트 쪽 문제

| 문제 | 처리 |
| --- | --- |
| 공용 `registerArgs` 에 `startPositionMs` 를 넣었더니 `CR-08` · `CR-12` (c) 가 CR-14 때문에 실패했다 (자기 규칙과 무관한 실패) | 공용 인자에서 빼고 `CR-01` #17 행에만 넣었다 (경계 표 D-8) |
| `CR-14` (b) 가 결과 값까지 비교해 CR-16 때문에 실패했다 | 호출 기록만 비교하게 줄였다. 뼈대에서 통과하므로 보호로 표시 |
| `DS-04` 에 곡 길이 미만인 13999 를 넣었다 | 뺐다 (DS-02 의 범위) |
