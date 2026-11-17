# RED 판정 표 (RED 절차 3 · 4) - `TidalStreamProxyServer`

- unit: `android-native-tests`, 담당 범위: 프록시 (PX-01 ~ PX-38, P-PX-1 ~ P-PX-6)
- 기준: 승인된 테스트 경계 표 `red-seam-table-proxy.md` (2판, 예시 90행 + 속성 7행)
- 상태: **사람 판정 대기 (관문 2)**. "RED 확인" 전에는 고정 (커밋) 하지 않는다
- 실행일: 2026-11-17, JDK 17 (`JAVA_HOME=/opt/homebrew/opt/openjdk@17`)
- 명령: `cd android && ./gradlew :app:testDebugUnitTest --tests "*TidalStreamProxyServerTest*"`
- 결과 XML: `build/app/test-results/testDebugUnitTest/TEST-com.example.tidal_connect_lite.TidalStreamProxyServerTest.xml` (저장소 루트 기준. 이 프로젝트에서는 결과가 `android/app/build/` 가 아니라 루트의 `build/app/` 아래에 생긴다)

## 1. 합계

| 항목 | 값 |
| --- | --- |
| 테스트 함수 | 45개 (예시 38개 = 규칙 38개, 속성 7개 = 속성 6개) |
| 보호 (PASSED) | 42개 |
| FAILED (기대값 비교 실패) | 3개: PX-17, PX-19, PX-38 |
| ERROR | 0개 |
| 불인정 (테스트 쪽 오류) | 0개 |
| 건너뜀 | 0개 (`@Ignore` 없음) |
| 표의 행 기준 | 예시 90행 중 82행 통과, 8행 실패 (PX-17 a · b · e, PX-19 a · b · c · d, PX-38 c). 속성 7행은 모두 통과 |
| 테스트 클래스 실행 시간 | 2.8초 (1회차 2.815초, 2회차 2.979초, 3회차 2.558초. 결과 XML 의 `time`) |

실패 8행은 모두 같은 한 가지다: **길이를 모르는 HEAD 응답에 `Content-Length` 헤더가 없어야 하는데 (PX-17, PX-19) 실제 응답에는 `Content-Length: -1` 이 있다.** 경계 표 5절의 F-1 에 해당한다. 그 밖의 단언은 실패한 행 안에서도 모두 맞았다.

## 2. 판정 표

판정: "보호" = 기존 코드를 지키는 테스트라 처음부터 통과하는 것이 정상. "RED 인정 대상" = 기대값 비교 실패 (단언을 고치지 않고 그대로 올림).

| 테스트 | 결과 | 실패 종류 (기대값과 실제값) | 판정 |
| --- | --- | --- | --- |
| `PX-01 등록하면 열린 포트와 16자 16진수 토큰이 든 주소를 돌려준다` | PASSED | - | 보호 |
| `PX-02 확장자는 MIME 에 든 낱말을 flac m4a mp3 순서로 판정해 정한다` (a ~ h) | PASSED | - | 보호 |
| `PX-03 MIME 이 빈 문자열이면 audio mp4 로 본다` | PASSED | - | 보호 |
| `PX-04 매니페스트만 있는 등록은 넘어온 MIME 과 상관없이 audio mp4 다` (a · b) | PASSED | - | 보호 |
| `PX-05 같은 곡을 다시 등록하면 새 토큰을 만들고 두 주소 모두 쓸 수 있다` | PASSED | - | 보호 |
| `PX-06 네 번째 곡을 등록하면 가장 오래된 등록이 지워지고 최근 3개만 남는다` (a · b) | PASSED | - | 보호 |
| `PX-07 ping 요청에 200 과 text plain 본문 pong 을 돌려준다` | PASSED | - | 보호 (F-5 통과) |
| `PX-08 audio 로 시작하지 않고 ping 도 아닌 경로는 404 Not Found 다` (a ~ d) | PASSED | - | 보호 (F-13 통과) |
| `PX-09 등록되지 않은 토큰은 404 다` (a ~ c) | PASSED | - | 보호 (F-14 통과) |
| `PX-10 직접 주소와 매니페스트가 모두 빈 등록은 404 다` (a · b) | PASSED | - | 보호 (F-15 통과) |
| `PX-11 허용 주소가 요청한 쪽의 주소와 다르면 403 Forbidden 이고 CDN 에 요청하지 않는다` (a · b) | PASSED | - | 보호 |
| `PX-12 허용 주소가 빈 값이거나 요청한 쪽의 주소와 같으면 통과한다` (a · b) | PASSED | - | 보호 |
| `PX-13 등록되지 않은 토큰은 허용되지 않은 주소에서 와도 404 다` (a · b) | PASSED | - | 보호 |
| `PX-14 토큰은 첫 점 앞까지이고 확장자가 다르거나 없어도 같은 곡을 찾는다` (a ~ c) | PASSED | - | 보호 |
| `PX-15 HEAD 요청도 등록 여부와 접근 제어를 GET 과 똑같이 거친다` (a ~ f) | PASSED | - | 보호 |
| `PX-16 단일 파일 HEAD 는 CDN 의 길이와 등록한 MIME 과 Accept-Ranges 를 알린다` (a · b) | PASSED | - | 보호 (F-2 통과: `123456`, `0`) |
| `PX-17 단일 파일 HEAD 에서 CDN 에 연결하지 못하거나 길이가 없으면 Content-Length 없이 200 이다` (a ~ e) | **FAILED** | AssertionError. a · b · e 행: `Content-Length` 기대 없음 (null), 실제 `-1`. c · d 행 (`Content-Length: 55`) 은 통과 | **RED 인정 대상** (F-1). 3절 |
| `PX-18 DASH HEAD 는 초기화 세그먼트와 모든 세그먼트의 길이 합계를 알린다` | PASSED | - | 보호 (F-2 `3400`, F-4 통과) |
| `PX-19 DASH HEAD 에서 세그먼트 하나라도 길이를 모르면 Content-Length 없이 응답한다` (a ~ d) | **FAILED** | AssertionError. a · b · c · d 행 모두: `Content-Length` 기대 없음 (null), 실제 `-1` | **RED 인정 대상** (F-1). 3절 |
| `PX-20 주소가 만료된 HEAD 는 주소를 갱신하지 않고 CDN 응답의 길이를 알린다` (a · b) | PASSED | - | 보호 (F-2 통과: `77`) |
| `PX-21 CDN 이 200 이면 본문을 그대로 중계하고 타입은 등록한 MIME 이다` | PASSED | - | 보호 |
| `PX-22 CDN 이 길이를 주지 않으면 길이 없이 chunked 로 본문 전체를 전달한다` | PASSED | - | 보호 (F-3 통과) |
| `PX-23 요청의 Range 헤더를 같은 값으로 CDN 요청에 넣는다` | PASSED | - | 보호 |
| `PX-24 CDN 이 206 과 Content-Range 를 주면 그대로 전달한다` (a · b) | PASSED | - | 보호 |
| `PX-25 Range 요청에 CDN 이 200 을 주면 Content-Range 없이 206 으로 전체를 전달한다` | PASSED | - | 보호 (F-7 통과) |
| `PX-26 CDN 이 401 이나 403 이면 재발급 함수를 한 번 불러 새 주소로 다시 요청한다` (a · b) | PASSED | - | 보호 |
| `PX-27 재발급 뒤 같은 토큰의 다음 요청은 갱신된 주소와 MIME 을 바로 쓴다` (a · b) | PASSED | - | 보호 |
| `PX-28 재발급에 실패하면 403 Stream expired 다` (a ~ f) | PASSED | - | 보호 |
| `PX-29 재발급으로 받은 주소도 401 이나 403 이면 다시 재발급하지 않고 500 CDN error 다` (a ~ c) | PASSED | - | 보호 |
| `PX-30 재발급 결과가 매니페스트뿐이면 DASH 중계로 응답한다` | PASSED | - | 보호 (F-4 통과) |
| `PX-31 재발급 결과에 MIME 이 있으면 그 MIME 을 쓰고 비어 있으면 처음 MIME 을 유지한다` (a ~ c) | PASSED | - | 보호 |
| `PX-32 CDN 의 그 밖의 실패는 500 CDN error 이고 재발급하지 않는다` (a · b) | PASSED | - | 보호 |
| `PX-33 CDN 에 연결하지 못하면 500 이고 본문이 Proxy error 로 시작한다` | PASSED | - | 보호 |
| `PX-34 유효한 매니페스트는 초기화 세그먼트와 세그먼트들을 순서대로 이어 붙여 전달한다` (a · b) | PASSED | - | 보호 (F-4 통과) |
| `PX-35 모든 세그먼트의 길이를 알면 Content-Length 는 합계다` | PASSED | - | 보호 |
| `PX-36 세그먼트 하나라도 길이를 모르면 길이 없이 chunked 로 본문 전체를 전달한다` (a · b) | PASSED | - | 보호 (F-3 통과) |
| `PX-37 매니페스트를 해석하지 못하면 500 Invalid DASH manifest 다` (a · b) | PASSED | - | 보호 |
| `PX-38 세그먼트 길이 조회는 매니페스트당 한 번만 하고 모르는 결과는 다시 조회한다` (a ~ c) | **FAILED** | AssertionError. c 행의 1번째 HEAD 응답: `Content-Length` 기대 없음 (null), 실제 `-1`. a · b 행과 c 행의 나머지 단언 (2 · 3번째 `Content-Length: 16`, `HEAD 2.mp4` 2건, 3번째에 HEAD 가 늘지 않음) 은 통과 | **RED 인정 대상** (F-1). PX-38 고유의 규칙 (한 번만 조회, 다시 조회) 은 맞았고, 실패한 단언은 PX-19 와 같은 것이다. 3절 |
| `P-PX-1 몇 번을 등록하든 주소는 정해진 형식이고 토큰이 서로 다르다` (100회) | PASSED | - | 보호 |
| `P-PX-2 어떤 MIME 문자열이든 확장자가 참조 표와 같다` (100회) | PASSED | - | 보호 |
| `P-PX-3 어떤 등록 순서에서도 최근 3개 모델에 있는 주소만 살아 있다` (25회) | PASSED | - | 보호 |
| `P-PX-4 어떤 허용 주소든 빈 값이거나 요청한 쪽의 주소와 같을 때만 통과한다` (50회) | PASSED | - | 보호 |
| `P-PX-5 어떤 Range 값이든 CDN 이 받은 Range 가 요청의 값과 같다` (50회) | PASSED | - | 보호 |
| `P-PX-6 어떤 바이트 내용이든 GET 으로 받은 본문이 CDN 의 내용과 같다` (25회) | PASSED | - | 보호 (F-18 통과: 길이 0 이 3번 나옴) |
| `P-PX-6 어떤 DASH 내용이든 본문이 세그먼트를 순서대로 이은 것과 같고 길이가 합계와 같다` (25회) | PASSED | - | 보호 |

## 3. 실패한 행의 관찰

### 관찰 (사실)

실패한 8행 모두에서 상태는 200, 본문은 0바이트였고, 다른 헤더 단언은 맞았다. 다른 것은 `Content-Length` 하나다.

| 행 | 준비 | 기대 | 관찰한 응답 (테스트 클라이언트가 본 헤더 전부) | 가짜 CDN 이 받은 요청 |
| --- | --- | --- | --- | --- |
| PX-17 a | 직접 주소가 닫힌 포트 | `Content-Length` 없음 | 200, `Content-Type: audio/flac`, `Date`, `Accept-Ranges: bytes`, `Connection: keep-alive`, **`Content-Length: -1`**, 본문 0바이트 | 0건 |
| PX-17 b | CDN HEAD 200, 길이 헤더 없음 | 같음 | a 와 같음 | `HEAD /track.flac` 1건 |
| PX-17 e | CDN HEAD 500, 길이 헤더 없음 | 같음 | a 와 같음 | `HEAD /track.flac` 1건 |
| PX-19 a | `2.mp4` 의 HEAD 가 200, 길이 헤더 없음 | 같음 | 200, `Content-Type: audio/mp4`, `Date`, `Connection: keep-alive`, **`Content-Length: -1`**, 본문 0바이트 (`Accept-Ranges` 없음) | HEAD 4건 (`init.mp4`, `1.mp4`, `2.mp4`, `3.mp4` 각 1건, 순서는 실행마다 다름) |
| PX-19 b | `2.mp4` 의 HEAD 가 404, `Content-Length: 2000` | 같음 | PX-19 a 와 같음 | HEAD 4건 (각 1건) |
| PX-19 c | 매니페스트 주소가 모두 닫힌 포트 | 같음 | PX-19 a 와 같음 | 0건 |
| PX-19 d | 매니페스트 `not xml` | 같음 | PX-19 a 와 같음 | 0건 |
| PX-38 c (1번째 HEAD) | `2.mp4` 의 1번째 HEAD 가 길이 헤더 없음 | 같음 | PX-19 a 와 같음. 2번째 · 3번째 HEAD 응답은 `Content-Length: 16` | 1번째 요청 뒤 HEAD 4건, 2번째 요청 뒤 8건 (4개 경로 모두 다시 조회), 3번째 요청 뒤에도 8건 |

길이를 아는 HEAD 응답은 값이 그대로 나갔다 (F-2 의 행 모두 통과): `123456` (PX-16 a), `0` (PX-16 b), `55` (PX-17 c · d), `3400` (PX-18), `77` (PX-20 a · b), `16` (PX-38 a · c).

길이를 모르는 **GET** 응답에는 `Content-Length` 가 없고 `Transfer-Encoding: chunked` 가 있었다 (PX-22, PX-36 a · b 통과). `-1` 은 HEAD 응답에서만 나왔다.

### 도우미 탓인지 가려낸 것

테스트 클라이언트 (OkHttp) 가 헤더를 채우거나 바꾼 것이 아닌지 확인하려고, 임시 탐침 테스트로 프록시에 원시 소켓 (`java.net.Socket`) 으로 HEAD 를 보내 응답 바이트를 그대로 찍었다 (탐침은 실행 뒤 지웠다. 4절).

```text
(PX-17 b 와 같은 준비, HEAD)            (PX-19 d 와 같은 준비, HEAD)          (PX-16 a 와 같은 준비, HEAD)
HTTP/1.1 200 OK                         HTTP/1.1 200 OK                       HTTP/1.1 200 OK
Content-Type: audio/flac                Content-Type: audio/mp4               Content-Type: audio/flac
Date: Tue, 17 Nov 2026 03:40:51 GMT     Date: Tue, 17 Nov 2026 03:40:51 GMT   Date: Tue, 17 Nov 2026 03:40:51 GMT
Accept-Ranges: bytes                    Connection: close                     Accept-Ranges: bytes
Connection: close                       Content-Length: -1                    Connection: close
Content-Length: -1                                                            Content-Length: 123456
```

원시 소켓에서도 `Content-Length: -1` 이 그대로 보였다. 따라서 도우미 (`ProxyFixture` 의 클라이언트) 탓이 아니고, **프록시가 실제로 그렇게 보낸다.** 테스트와 도우미는 고치지 않고 실패로 남겼다.

### 추정 (확인하지 않음)

- `-1` 을 프록시의 처리 코드가 넣는지 NanoHTTPD 가 응답을 내보낼 때 붙이는지는 구현 본문을 읽지 않아 알 수 없다. 경계 표 F-1 에서 "핸들러가 길이를 넣지 않았을 때 NanoHTTPD 가 스스로 `Content-Length` 를 붙이는지 문서가 정하지 않았다" 고 적어 둔 경우와 모양이 같다. GET 에서는 chunked 로 나가고 HEAD 에서만 `-1` 이 나오는 것으로 보아, 길이 없는 (chunked) 응답을 HEAD 로 보낼 때 라이브러리가 길이 헤더를 대신 쓰는 것일 수 있다
- 규칙 PX-17 은 "0 으로 알리면 렌더러가 빈 파일로 여긴다" 를 이유로 "`Content-Length` 없이" 라고 적었다. 실제 응답은 0 도 아니고 "없음" 도 아닌 `-1` 이다. 렌더러가 `-1` 을 어떻게 받아들이는지는 이 테스트로 알 수 없다

### 판단이 필요한 것 (주 세션 · 사람)

규칙 문서 (PX-17, PX-19: "`Content-Length` 없이 응답") 와 관찰되는 응답 (`Content-Length: -1`) 중 어느 쪽을 맞출지. 테스트는 규칙 문장 그대로 단언하고 있다.

## 4. 불인정 (테스트 쪽 오류) 과 고친 것

- 불인정 0건. 테스트 4개 파일은 첫 컴파일에서 통과했고, 도우미 · 생성기 · 서버 수명 문제로 실패한 테스트는 없었다. 고친 테스트 쪽 오류도 없다
- router 담당이 같은 폴더에 쓰는 파일 (`RouterFakes.kt` 등 4개) 때문에 컴파일이 막힌 적도 없다. 그 파일들은 열거나 고치지 않았다
- 임시 탐침 2개를 `TidalStreamProxyServerTest.kt` 에 넣어 한 번씩 실행하고 지웠다 (최종 파일에 없음, `@Test` 45개)
  - 원시 소켓 탐침: 3절의 "도우미 탓인지" 확인용
  - 생성기 탐침: 고정 seed 에서 생성기가 실제로 만든 값을 확인. 바이트 길이에 0 이 3번 · 1 이 4번 · 65,536 이 9번, DASH 에 초기화 세그먼트 없음이 11번 · 세그먼트 수 1개와 8개 포함, 허용 주소에 빈 문자열 · `127.0.0.1` · `localhost` · 문서용 대역 · 임의 문자열이 모두, 등록 횟수에 0 과 10 이 나왔다
- `src/main` 은 고치지 않았다

## 5. 불안정 여부

같은 명령을 5번 실행했다 (처음 1번, 탐침을 지운 뒤 1번, `--rerun-tasks` 로 2번, 마지막 확인 1번). 5번 모두 45개 중 같은 3개가 같은 메시지로 실패했고 나머지 42개는 통과했다. ERROR 는 없었다.

| 실행 | 방식 | 결과 | 클래스 실행 시간 |
| --- | --- | --- | --- |
| 처음 | 일반 | 45 중 3 실패 | 2.473초 |
| 1회차 | 일반 (탐침 제거 뒤) | 45 중 3 실패 | 2.815초 |
| 2회차 | `--rerun-tasks` | 45 중 3 실패 (1회차와 같음) | 2.979초 |
| 3회차 | `--rerun-tasks` | 45 중 3 실패 (1회차와 같음) | 2.558초 |
| 마지막 | 일반 (최종 파일 확인) | 45 중 3 실패 (1회차와 같음) | 2.448초 |

닫힌 포트를 쓰는 행 (F-17: PX-17 a, PX-19 c, PX-33) 은 5번 모두 같은 결과였다. NFR-03-A4 의 10회 반복은 Step 9 의 몫이다.

가장 오래 걸린 테스트 (1회차): P-PX-6 DASH 0.43초, P-PX-3 0.41초, PX-37 0.14초, P-PX-4 0.14초. 30초 기준 (NFR-03-A5) 에 한참 못 미쳐 실행 횟수를 줄이지 않았다.

## 6. 경계 표 5절 (실패 가능 행) 의 결과

| # | 결과 |
| --- | --- |
| F-1 (HEAD 에 `Content-Length` 없음) | **실패**. 8행 모두 `Content-Length: -1` |
| F-2 (HEAD 의 `Content-Length` 값) | 통과. 값이 그대로 나감 |
| F-3 (chunked) | 통과. `Content-Length` 없음, `Transfer-Encoding: chunked` |
| F-4 (`Accept-Ranges` 없음) | 통과 |
| F-5 (`/ping` 의 타입) | 통과 |
| F-7 (`Content-Range` 없는 206) | 통과 |
| F-13, F-14, F-15 (글자 그대로 읽은 경계 입력) | 통과 |
| F-17 (닫힌 포트 재사용) | 5번 실행에서 나타나지 않음 |
| F-18 (길이 0 본문) | 통과 |

## 7. 표와 달라진 점 · 남은 의문

### 표와 달라진 점

행을 더하거나 뺀 것은 없다. 구현하면서 정한 세부 사항만 적는다.

- PX-06 a · b 는 표대로 "a 에 이어" 같은 서버에서 이어서 실행한다 (실패 메시지에 a · b 를 구분해 적음). 다른 행은 행마다 새 프록시와 가짜 CDN 을 띄우고 닫는다
- 한 행이 실패해도 같은 테스트의 나머지 행을 끝까지 돌리고 마지막에 한꺼번에 실패시킨다. 실패한 행에는 프록시와 주고받은 응답 전체와 가짜 CDN 기록을 메시지에 덧붙인다 (3절의 관찰은 이 메시지에서 나왔다)
- 테스트 클라이언트는 연결을 재사용하지 않게 했다 (유휴 연결 0개인 연결 풀). 표에는 "타임아웃 2초, 재시도 끔, `Accept-Encoding: identity`" 만 있었다. 요청 헤더는 바꾸지 않는다
- `start` 의 `timeout` 은 `NanoHTTPD.SOCKET_READ_TIMEOUT` 을 썼다
- P-PX-1 은 "MIME 목록 (길이 0 ~ 10)" 생성기 하나로 등록 횟수와 MIME 을 함께 뽑는다 (목록의 길이가 등록 횟수)
- 경계 표 파일의 "상태: 사람 승인 대기" 줄은 그대로 두었다 (표를 고치지 말라는 지시에 따라)

### 남은 의문

- **F-1**: 3절의 판단 (문서와 응답 중 어느 쪽을 맞출지)
- **N-3 에 대한 관찰**: 모르는 결과를 다시 조회할 때 세그먼트 4개를 모두 다시 물었다 (PX-38 c 에서 2번째 요청 뒤 HEAD 합계 8건). 단언은 하지 않았다. 규칙에 적을지는 결정이 필요하다
- **규칙에 없는 헤더**: 원시 소켓으로 본 chunked GET 응답 (PX-22 와 같은 준비) 에 `Access-Control-Allow-Origin: *` 헤더가 있었다. 규칙 문서에 없는 헤더이고 단언하지 않았다. 다른 응답에도 있는지는 확인하지 않았다
- **시그니처 확인 중 본 한 줄**: `registerTrackStream` 의 매개변수 목록을 `sed` 로 볼 때 범위를 한 줄 넓게 잡아 본문 첫 줄 (`val token = newToken()`) 이 함께 출력되었다. 테스트 기대값에는 쓰지 않았다 (토큰 형식은 PX-01 에서 가져옴)

## 주 세션 확인 (2026-11-17, 판정 표 작성 뒤)

- 전체 실행 (`:app:testDebugUnitTest --rerun-tasks`): 86개 중 36개 실패. 프록시 3개 (PX-17, PX-19, PX-38), router 29개, 변환 4개. 두 에이전트의 표와 같다
- F-1 의 원인: `TidalStreamProxyServer.headResponse` 는 길이를 모를 때 `newChunkedResponse` 를 부르고 `Content-Length` 를 직접 넣지 않는다. 바로 위 주석은 "길이를 모르면 알리지 않는다 (0 으로 알리면 렌더러가 빈 파일로 여긴다)" 이다. 따라서 `Content-Length: -1` 은 NanoHTTPD 가 HEAD 응답에 붙인 것이고, 코드 주석의 의도와 실제 응답이 다르다
- 처리 (문서를 고칠지, 코드를 고칠지) 는 사람 판정 (관문 2) 에서 정한다
