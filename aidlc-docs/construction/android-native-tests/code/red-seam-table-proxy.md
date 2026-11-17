# 테스트 경계 표 (RED 절차 1) - `TidalStreamProxyServer`

- unit: `android-native-tests`, 담당 범위: 프록시 (PX-01 ~ PX-38, P-PX-1 ~ P-PX-6)
- 상태: **사람 승인 대기 (관문 1)**. 이 표가 승인되기 전에는 테스트 코드를 쓰지 않는다
- 개정: 2판 (2026-11-17). 1판의 질문 Q-1 ~ Q-21 에 대한 문서 보완 (`business-rules.md` 3절의 "2026-11-17 보완" 과 PX-02 · 04 · 11 · 16 · 17 · 19 · 24 · 27 · 28 · 29 · 30 · 34 · 36 · 38, `nfr-requirements.md` NFR-01-A1 · NFR-05-A2, `nfr-design-patterns.md` TW-8, `logical-components.md` 3절) 을 다시 읽고 반영했다. 바뀐 내용은 6절의 "문서 보완으로 해결된 것" 에 있다
- 테스트 성격: 이미 있는 코드에 대한 **보호** 테스트. 처음부터 통과하는 것이 정상이고, 실패하면 규칙 문서와 코드가 다르다는 뜻이다
- 근거 문서: `business-rules.md` 3 · 4 · 7절, `business-logic-model.md` 2 · 3절, `domain-entities.md`, `nfr-requirements.md`, `tech-stack-decisions.md` (A2, A3, A5), `nfr-design-patterns.md` (TW, KD, KV, KP), `logical-components.md`, Code Generation 계획 Step 4
- 읽지 않은 것: `TidalStreamProxyServer.kt`, `DashSegmentInputStream.kt`, `DashManifest.kt` 등 구현 본문. 시그니처만 `grep` 으로 확인했다 (`class TidalStreamProxyServer(`, `val boundHost`, `const val PROXY_PORT`, `fun defaultHttpClient()`, `fun registerTrackStream(`, `var streamRefresher`)
- 기대값은 모두 규칙 문서의 값을 그대로 옮겼다. 판정은 HTTP 응답과 가짜 CDN 이 받은 요청 기록으로만 한다 (등록부 · 캐시를 직접 보지 않음)

## 0. 표에서 쓰는 약속

| 이름 | 뜻 |
| --- | --- |
| `PROXY` | `http://127.0.0.1:<프록시가 연 임시 포트>` |
| `CDN` | `http://127.0.0.1:<가짜 CDN 의 임시 포트>` (`FakeCdnServer`) |
| 기본 등록 | `registerTrackStream(trackId = "101", directUrl = "CDN/track.flac", manifestXml = "", allowedHost = "", mimeType = "audio/flac")`. 표의 "준비" 칸에는 기본 등록과 다른 인자만 적는다 |
| `BODY10` | 10바이트 `00 01 02 03 04 05 06 07 08 09` |
| `NEW10` | 10바이트 `10 11 12 13 14 15 16 17 18 19` (재발급된 주소의 내용) |
| `MPD3` | 유효한 DASH 매니페스트 (모양은 `DashManifestTest` 의 예와 같음): `initialization="CDN/dash/<고유 값>/init.mp4"`, `media="CDN/dash/<고유 값>/$Number$.mp4"`, `startNumber="1"`, `<S d="1"/>` 3개 (세그먼트 1 · 2 · 3) |
| `MPD3` 의 내용 | `init.mp4` = `INIT` (4바이트), `1.mp4` = `AAAA` (4), `2.mp4` = `BB` (2), `3.mp4` = `CCCCCC` (6). 이어 붙이면 `INITAAAABBCCCCCC` (16바이트) |
| `MPD3-noinit` | `MPD3` 에서 `initialization` 속성만 뺀 것. 이어 붙이면 `AAAABBCCCCCC` (12바이트) |
| 다른 주소 | `192.0.2.10` (문서용 예약 대역, 요청한 쪽 `127.0.0.1` 과 다름) |
| 재발급 기록 | 테스트가 `streamRefresher` 에 넣은 함수가 받은 `trackId` 목록 |
| CDN 기록 | `FakeCdnServer` 가 받은 요청 목록 (메서드 · 경로 · `Range`). 응답 본문을 다 읽은 뒤에 확인한다 (KD-5) |

- 표의 한 규칙 ID = 테스트 함수 1개. 같은 ID 의 여러 행 (a, b, ...) 은 그 함수 안에서 표로 돌린다 (KV-4)
- 테스트 이름: 역따옴표 한국어 문장, 규칙 ID 를 대괄호 없이 맨 앞에 (KV-4). JVM 메서드 이름에 쓸 수 없는 `/` · `.` 은 이름에 넣지 않는다 (예: `` `PX-07 ping 요청에 200 과 pong 을 돌려준다` ``)
- 모든 테스트 파일: `android/app/src/test/kotlin/com/example/tidal_connect_lite/TidalStreamProxyServerTest.kt`

## 1. 경계 (seam) 목록

| # | 경계 | 형태 | 테스트에서 쓰는 방법 |
| --- | --- | --- | --- |
| S-1 | 생성자 `TidalStreamProxyServer(boundHost, port, httpClient)` | 공개 생성자 | `TidalStreamProxyServer("127.0.0.1", port = 0, httpClient = <타임아웃 2초 OkHttpClient>)` (KD-1, KD-3). `start(timeout, daemon = true)` 로 시작 (`timeout` 은 NanoHTTPD 의 공개 기본 타임아웃 상수), `stop()` 으로 닫음, `listeningPort` 로 열린 포트를 읽음 (NanoHTTPD 에서 물려받은 공개 함수). `ProxyFixture` 가 감싼다 (KD-2) |
| S-2 | `registerTrackStream(trackId, directUrl, manifestXml, allowedHost, mimeType): String` | 공개 함수 | 직접 호출. 돌려준 주소 문자열을 그대로 다음 HTTP 요청에 쓴다 |
| S-3 | `streamRefresher: ((trackId: String) -> Map<String, Any?>?)?` | 공개 속성 (외부 경계: 운영에서는 Dart 로 되묻는 요청) | 테스트 함수를 대입한다. 함수는 받은 `trackId` 를 기록하고 정해 둔 맵 `{directUrl, manifestXml, mimeType}` · null · 예외 중 하나로 답한다 |
| S-4 | `GET /audio/{token}.{ext}` | HTTP | OkHttp 로 실제 요청 (`Range` 헤더 선택). 상태 · 헤더 · 본문 바이트로 판정 |
| S-5 | `HEAD /audio/{token}.{ext}` | HTTP | 같은 방식. 상태 · 헤더로 판정 (본문 없음) |
| S-6 | `GET /ping`, 그 밖의 경로 | HTTP | 같은 방식 |
| S-7 | CDN (프록시가 밖으로 보내는 HTTP) | 외부 경계 | `FakeCdnServer` (MockWebServer) 로 대신한다. 경로별 응답을 정하고 받은 요청을 기록한다 |

쓰지 않는 것: 등록부 · 길이 캐시 등 내부 상태, `PROXY_PORT` 상수 값 확인 (TW-9 change detector), `getWifiIpv4Address` (Android 의존, `tech-stack-decisions.md` A3).

## 2. 예시 기반 테스트 표

### 곡 등록 (PX-01 ~ PX-06)

| 규칙 ID | 경계 | 준비 (등록 내용, 가짜 CDN 응답) | 요청 | 기대값 (상태 · 헤더 · 본문, 가짜 CDN 이 받은 요청) | 테스트 파일 |
| --- | --- | --- | --- | --- | --- |
| PX-01 | S-1, S-2, S-6 | 기본 등록 | (등록 결과 확인) + 돌려준 주소의 호스트 · 포트로 `GET /ping` | 주소가 `http://127.0.0.1:<포트>/audio/<토큰>.flac` 형식. `<토큰>` 은 `[0-9a-f]` 16자. `<포트>` 는 `listeningPort` 와 같고, 그 주소의 `/ping` 이 200 | `TidalStreamProxyServerTest.kt` |
| PX-02 a | S-2 | `mimeType = "audio/flac"` | (등록 결과 확인) | 주소가 `.flac` 로 끝남 | 같음 |
| PX-02 b | S-2 | `mimeType = "audio/mp4"` | (등록 결과 확인) | `.m4a` | 같음 |
| PX-02 c | S-2 | `mimeType = "audio/m4a"` | (등록 결과 확인) | `.m4a` | 같음 |
| PX-02 d | S-2 | `mimeType = "audio/aac"` | (등록 결과 확인) | `.m4a` | 같음 |
| PX-02 e | S-2 | `mimeType = "audio/mpeg"` | (등록 결과 확인) | `.mp3` | 같음 |
| PX-02 f | S-2 | `mimeType = "application/octet-stream"` | (등록 결과 확인) | `.m4a` (그 밖) | 같음 |
| PX-02 g | S-2 | `mimeType = "audio/x-flac; codecs=mp4"` (`flac` 과 `mp4` 가 함께 있음) | (등록 결과 확인) | `.flac` (판정 순서: `flac` 이 먼저) | 같음 |
| PX-02 h | S-2 | `mimeType = "audio/mpeg; codecs=aac"` (`mpeg` 과 `aac` 가 함께 있음) | (등록 결과 확인) | `.m4a` (판정 순서: `mp4` · `m4a` · `aac` 가 `mpeg` 보다 먼저) | 같음 |
| PX-03 | S-2, S-4 | `mimeType = ""`. CDN `GET /track.flac` → 200, `BODY10` | 돌려준 주소로 GET | 주소가 `.m4a` 로 끝남. 응답 200, `Content-Type: audio/mp4` | 같음 |
| PX-04 a | S-2, S-4 | `directUrl = ""`, `manifestXml = MPD3`, `mimeType = "audio/flac"`. CDN 은 `MPD3` 의 내용 | 돌려준 주소로 GET | 주소가 `.m4a` 로 끝남 (`.flac` 이 아님). 응답 200, `Content-Type: audio/mp4` | 같음 |
| PX-04 b (대조) | S-2, S-4 | `directUrl = "CDN/track.flac"` 과 `manifestXml = MPD3` 둘 다 있음, `mimeType = "audio/flac"`. CDN `GET /track.flac` → 200, `BODY10` | 돌려준 주소로 GET | 주소가 `.flac` 로 끝남. 응답 200, `Content-Type: audio/flac`, 본문 `BODY10` (직접 주소가 있으므로 넘어온 MIME 을 쓰고 단일 파일로 중계, `business-logic-model.md` 2.1 · 2.2) | 같음 |
| PX-05 | S-2, S-4 | 기본 등록을 같은 인자로 2번. CDN `GET /track.flac` → 200, `BODY10` | 두 주소로 각각 GET | 두 주소의 토큰이 서로 다름. 두 응답 모두 200, 본문 `BODY10` | 같음 |
| PX-06 a | S-2, S-4 | 3곡 등록 (`trackId` `"1"` · `"2"` · `"3"`, `directUrl` `CDN/t1.flac` · `t2` · `t3`). CDN 은 각각 200 과 서로 다른 1바이트 본문 (`01`, `02`, `03`) | 세 주소로 각각 GET | 셋 다 200, 본문이 각각 `01`, `02`, `03` (3개까지는 지워지지 않음) | 같음 |
| PX-06 b | S-2, S-4 | a 에 이어 4번째 곡 등록 (`"4"`, `CDN/t4.flac` → 200, `04`) | 네 주소로 각각 GET | 1번째 주소는 404, 본문 `Not Found`. 2 · 3 · 4번째는 200, 본문 `02`, `03`, `04` | 같음 |

### 요청 처리 (PX-07 ~ PX-15)

| 규칙 ID | 경계 | 준비 (등록 내용, 가짜 CDN 응답) | 요청 | 기대값 (상태 · 헤더 · 본문, 가짜 CDN 이 받은 요청) | 테스트 파일 |
| --- | --- | --- | --- | --- | --- |
| PX-07 | S-6 | 등록 없음 | `GET /ping` | 200, `Content-Type` 의 type/subtype 가 `text/plain`, 본문 `pong` | 같음 |
| PX-08 a | S-6 | 등록 없음 | `GET /` | 404, 본문 `Not Found` | 같음 |
| PX-08 b | S-6 | 등록 없음 | `GET /foo` | 404, 본문 `Not Found` | 같음 |
| PX-08 c | S-6 | 등록 없음 | `GET /audio` (끝에 `/` 없음) | 404, 본문 `Not Found` | 같음 |
| PX-08 d | S-6 | 등록 없음 | `GET /ping2` | 404, 본문 `Not Found` | 같음 |
| PX-09 a | S-4 | 등록 없음 | `GET /audio/0000000000000000.flac` | 404, 본문 `Not Found`. CDN 기록 0건 | 같음 |
| PX-09 b | S-4 | 기본 등록 1건. CDN `GET /track.flac` → 200, `BODY10` | 등록된 토큰의 마지막 글자만 바꾼 토큰으로 GET | 404, 본문 `Not Found`. CDN 기록 0건 | 같음 |
| PX-09 c | S-4 | 기본 등록 1건 | `GET /audio/` (토큰이 빈 문자열) | 404, 본문 `Not Found`. CDN 기록 0건 | 같음 |
| PX-10 a | S-2, S-4 | `directUrl = ""`, `manifestXml = ""` | 돌려준 주소로 GET | 404, 본문 `Not Found`. CDN 기록 0건 | 같음 |
| PX-10 b | S-2, S-4 | `directUrl = ""`, `manifestXml = ""`, `allowedHost = "192.0.2.10"` | 돌려준 주소로 GET | 404 (403 이 아님: 내용 확인이 접근 제어보다 먼저, `business-logic-model.md` 2.2) | 같음 |
| PX-11 a | S-4 | `allowedHost = "192.0.2.10"`. CDN `GET /track.flac` → 200, `BODY10` | 돌려준 주소로 GET | 403, 본문 `Forbidden`. CDN 기록 0건 | 같음 |
| PX-11 b | S-4 | `allowedHost = "localhost"`. CDN 같음 | 돌려준 주소로 GET | 403, 본문 `Forbidden`. CDN 기록 0건 (비교는 문자열 그대로) | 같음 |
| PX-12 a | S-4 | `allowedHost = ""`. CDN `GET /track.flac` → 200, `BODY10` | 돌려준 주소로 GET | 200, 본문 `BODY10` | 같음 |
| PX-12 b | S-4 | `allowedHost = "127.0.0.1"`. CDN 같음 | 돌려준 주소로 GET | 200, 본문 `BODY10` | 같음 |
| PX-13 a | S-4 | `allowedHost = "192.0.2.10"` 으로 1건 등록 | `GET /audio/0000000000000000.flac` (미등록), 대조로 등록된 주소에도 GET | 미등록 토큰은 404, 본문 `Not Found`. 등록된 주소는 403 (요청한 쪽이 허용되지 않은 주소임을 확인) | 같음 |
| PX-13 b | S-4 | `allowedHost = "192.0.2.10"` 으로 4건 등록 (1번째가 밀려남) | 1번째 주소와 2번째 주소로 GET | 1번째는 404, 2번째는 403 | 같음 |
| PX-14 a | S-4 | 기본 등록 (주소는 `/audio/<토큰>.flac`). CDN `GET /track.flac` → 200, `BODY10` | `GET /audio/<토큰>.m4a` | 200, `Content-Type: audio/flac`, 본문 `BODY10` | 같음 |
| PX-14 b | S-4 | 같음 | `GET /audio/<토큰>` (확장자 없음) | 200, `Content-Type: audio/flac`, 본문 `BODY10` | 같음 |
| PX-14 c | S-4 | 같음 | `GET /audio/<토큰>.flac.bak` (`.` 이 둘) | 200, `Content-Type: audio/flac`, 본문 `BODY10` (토큰은 첫 `.` 앞까지) | 같음 |
| PX-15 a | S-5 | 등록 없음 | `HEAD /audio/0000000000000000.flac` | 404 (PX-09) | 같음 |
| PX-15 b | S-5 | `directUrl = ""`, `manifestXml = ""` | 돌려준 주소로 HEAD | 404 (PX-10) | 같음 |
| PX-15 c | S-5 | `allowedHost = "192.0.2.10"`. CDN `HEAD /track.flac` → 200, `Content-Length: 10` | 돌려준 주소로 HEAD | 403. CDN 기록 0건 (PX-11) | 같음 |
| PX-15 d | S-5 | `allowedHost = ""`. CDN `HEAD /track.flac` → 200, `Content-Length: 10` | 돌려준 주소로 HEAD | 200 (PX-12) | 같음 |
| PX-15 e | S-5 | `allowedHost = "127.0.0.1"`. CDN 같음 | 돌려준 주소로 HEAD | 200 (PX-12) | 같음 |
| PX-15 f | S-5 | `allowedHost = "192.0.2.10"` 으로 1건 등록 | `HEAD /audio/0000000000000000.flac` | 404 (PX-13) | 같음 |

### HEAD (PX-16 ~ PX-20)

| 규칙 ID | 경계 | 준비 (등록 내용, 가짜 CDN 응답) | 요청 | 기대값 (상태 · 헤더 · 본문, 가짜 CDN 이 받은 요청) | 테스트 파일 |
| --- | --- | --- | --- | --- | --- |
| PX-16 a | S-5 | 기본 등록. CDN `HEAD /track.flac` → 200, `Content-Length: 123456` (본문 없음) | 돌려준 주소로 HEAD | 200, `Content-Length: 123456`, `Content-Type: audio/flac`, `Accept-Ranges: bytes`, 본문 0바이트. CDN 기록은 `HEAD /track.flac` 1건뿐 | 같음 |
| PX-16 b | S-5 | 기본 등록. CDN `HEAD /track.flac` → 200, `Content-Length: 0` | 돌려준 주소로 HEAD | 200, `Content-Length: 0` (0 을 그대로 알림. "헤더 없음" 이 아님) | 같음 |
| PX-17 a | S-5 | `directUrl = <닫힌 포트의 주소>/track.flac` (KD-4, 연결 실패) | 돌려준 주소로 HEAD | 200, `Content-Length` 헤더 없음, `Content-Type: audio/flac`, `Accept-Ranges: bytes` | 같음 |
| PX-17 b | S-5 | 기본 등록. CDN `HEAD /track.flac` → 200, `Content-Length` 헤더 없음 | 돌려준 주소로 HEAD | 200, `Content-Length` 헤더 없음, `Content-Type: audio/flac`, `Accept-Ranges: bytes`. CDN 기록은 `HEAD /track.flac` 1건 | 같음 |
| PX-17 c | S-5 | 기본 등록. CDN `HEAD /track.flac` → 404, `Content-Length: 55` | 돌려준 주소로 HEAD | 200, `Content-Length: 55` (오류 상태라도 길이가 있으면 PX-20 처럼 알림) | 같음 |
| PX-17 d | S-5 | 기본 등록. CDN `HEAD /track.flac` → 500, `Content-Length: 55` | 돌려준 주소로 HEAD | 200, `Content-Length: 55` | 같음 |
| PX-17 e | S-5 | 기본 등록. CDN `HEAD /track.flac` → 500, `Content-Length` 헤더 없음 | 돌려준 주소로 HEAD | 200, `Content-Length` 헤더 없음, `Content-Type: audio/flac`, `Accept-Ranges: bytes` | 같음 |
| PX-18 | S-5 | `directUrl = ""`, `manifestXml = MPD3`. CDN HEAD 응답의 `Content-Length`: `init.mp4` 100, `1.mp4` 1000, `2.mp4` 2000, `3.mp4` 300 | 돌려준 주소로 HEAD | 200, `Content-Length: 3400`, `Content-Type: audio/mp4`, `Accept-Ranges` 헤더 없음, 본문 0바이트. CDN 기록은 HEAD 4건 (`init.mp4`, `1.mp4`, `2.mp4`, `3.mp4` 각 1건, 순서는 보지 않음), GET 0건 | 같음 |
| PX-19 a | S-5 | PX-18 과 같되 `2.mp4` 의 HEAD 응답만 200, `Content-Length` 헤더 없음 | 돌려준 주소로 HEAD | 200, `Content-Length` 헤더 없음, `Content-Type: audio/mp4` | 같음 |
| PX-19 b | S-5 | PX-18 과 같되 `2.mp4` 의 HEAD 응답만 404, `Content-Length: 2000` (성공 상태가 아님. 길이 헤더는 있음) | 돌려준 주소로 HEAD | 200, `Content-Length` 헤더 없음, `Content-Type: audio/mp4` (단일 파일의 PX-17 c 와 달리 DASH 는 성공 상태가 아니면 "모름") | 같음 |
| PX-19 c | S-5 | `directUrl = ""`, `manifestXml` = `MPD3` 모양이되 주소가 모두 닫힌 포트를 가리킴 (연결 실패) | 돌려준 주소로 HEAD | 200, `Content-Length` 헤더 없음, `Content-Type: audio/mp4` | 같음 |
| PX-19 d | S-5 | `directUrl = ""`, `manifestXml = "not xml"` (해석할 수 없음) | 돌려준 주소로 HEAD | 200, `Content-Length` 헤더 없음. CDN 기록 0건 | 같음 |
| PX-20 a | S-5, S-3 | 기본 등록. CDN `HEAD /track.flac` → 401, `Content-Length: 77`. `streamRefresher` = `{directUrl: "CDN/new.flac", manifestXml: "", mimeType: ""}` 를 주는 함수 | 돌려준 주소로 HEAD | 200, `Content-Length: 77`. 재발급 기록 0건. CDN 기록은 `HEAD /track.flac` 1건뿐 (`/new.flac` 요청 없음) | 같음 |
| PX-20 b | S-5, S-3 | a 와 같되 CDN HEAD 가 403, `Content-Length: 77` | 돌려준 주소로 HEAD | a 와 같음 | 같음 |

### GET: 단일 파일 중계 (PX-21 ~ PX-33)

| 규칙 ID | 경계 | 준비 (등록 내용, 가짜 CDN 응답) | 요청 | 기대값 (상태 · 헤더 · 본문, 가짜 CDN 이 받은 요청) | 테스트 파일 |
| --- | --- | --- | --- | --- | --- |
| PX-21 | S-4 | 기본 등록. CDN `GET /track.flac` → 200, `Content-Type: application/octet-stream`, `Content-Length: 10`, `BODY10` | 돌려준 주소로 GET (`Range` 없음) | 200, `Content-Type: audio/flac`, `Content-Length: 10`, `Accept-Ranges: bytes`, 본문 `BODY10`. CDN 기록은 `GET /track.flac` 1건, `Range` 없음 | 같음 |
| PX-22 | S-4 | 기본 등록. CDN `GET /track.flac` → 200, `Content-Length` 없이 chunked 로 `BODY10` | 돌려준 주소로 GET | 200, `Content-Length` 헤더 없음, `Transfer-Encoding: chunked`, 본문 `BODY10` | 같음 |
| PX-23 | S-4 | 기본 등록. CDN `GET /track.flac` → 206, `Content-Range: bytes 2-5/10`, 본문 `02 03 04 05` | 돌려준 주소로 GET, `Range: bytes=2-5` | CDN 기록의 `Range` 가 `bytes=2-5` | 같음 |
| PX-24 a | S-4 | PX-23 과 같음 (CDN 응답에 `Content-Length: 4`) | 돌려준 주소로 GET, `Range: bytes=2-5` | 206, `Content-Range: bytes 2-5/10`, `Content-Length: 4`, 본문 `02 03 04 05` | 같음 |
| PX-24 b | S-4 | 기본 등록. CDN `GET /track.flac` → 206, `Content-Range: bytes 0-9/10`, `Content-Length: 10`, `BODY10` | 돌려준 주소로 GET (`Range` 없음) | 206, `Content-Range: bytes 0-9/10`, 본문 `BODY10`. CDN 기록의 `Range` 없음 | 같음 |
| PX-25 | S-4 | 기본 등록. CDN `GET /track.flac` → 200, `BODY10` (`Range` 무시) | 돌려준 주소로 GET, `Range: bytes=2-5` | 206, `Content-Range` 헤더 없음, 본문 `BODY10` 전체 | 같음 |
| PX-26 a | S-4, S-3 | `directUrl = "CDN/old.flac"`. CDN `GET /old.flac` → 401, `GET /new.flac` → 200, `NEW10`. `streamRefresher` = `{directUrl: "CDN/new.flac", manifestXml: "", mimeType: ""}` | 돌려준 주소로 GET (`Range` 없음) | 200, 본문 `NEW10`. 재발급 기록 `["101"]` (1회). CDN 기록은 순서대로 `GET /old.flac`, `GET /new.flac` | 같음 |
| PX-26 b | S-4, S-3 | a 와 같되 `GET /old.flac` → 403, `GET /new.flac` → 206, `Content-Range: bytes 2-5/10`, 본문 `12 13 14 15` | 돌려준 주소로 GET, `Range: bytes=2-5` | 206, 본문 `12 13 14 15`. 재발급 기록 `["101"]`. CDN 기록은 순서대로 `GET /old.flac` (`Range: bytes=2-5`), `GET /new.flac` (`Range: bytes=2-5`) | 같음 |
| PX-27 a | S-4, S-3 | PX-26 a 와 같음 | 같은 주소로 GET 2번 | 두 번째 응답도 200, 본문 `NEW10`. 재발급 기록은 그대로 `["101"]` (1회). CDN 기록 전체는 순서대로 `GET /old.flac`, `GET /new.flac`, `GET /new.flac` (두 번째 요청은 `/old.flac` 을 거치지 않음) | 같음 |
| PX-27 b | S-4, S-3 | PX-31 a 와 같음 (처음 MIME `audio/flac`, 재발급 MIME `audio/mpeg`) | 같은 주소로 GET 2번 | 두 번째 응답도 200, `Content-Type: audio/mpeg`, 본문 `NEW10` (갱신된 MIME 이 유지됨). 재발급 기록은 `["101"]` (1회) | 같음 |
| PX-28 a | S-4, S-3 | `directUrl = "CDN/old.flac"`. CDN `GET /old.flac` → 401. `streamRefresher` 를 대입하지 않음 (null) | 돌려준 주소로 GET | 403, 본문 `Stream expired`. CDN 기록은 `GET /old.flac` 1건 | 같음 |
| PX-28 b | S-4, S-3 | a 와 같되 `streamRefresher` 가 null 을 돌려줌 | 돌려준 주소로 GET | 403, 본문 `Stream expired`. 재발급 기록 `["101"]`. CDN 기록 1건 | 같음 |
| PX-28 c | S-4, S-3 | a 와 같되 `streamRefresher` 가 `RuntimeException` 을 던짐 | 돌려준 주소로 GET | 403, 본문 `Stream expired`. 재발급 기록 `["101"]`. CDN 기록 1건 | 같음 |
| PX-28 d | S-4, S-3 | a 와 같되 `streamRefresher` 가 `{directUrl: "", manifestXml: "", mimeType: "audio/flac"}` 를 돌려줌 | 돌려준 주소로 GET | 403, 본문 `Stream expired`. 재발급 기록 `["101"]`. CDN 기록 1건 | 같음 |
| PX-28 e | S-4, S-3 | a 와 같되 `streamRefresher` 가 빈 맵 `{}` 을 돌려줌 (키가 모두 빠짐) | 돌려준 주소로 GET | 403, 본문 `Stream expired`. 재발급 기록 `["101"]`. CDN 기록 1건 | 같음 |
| PX-28 f | S-4, S-3 | a 와 같되 `streamRefresher` 가 `{directUrl: 42, manifestXml: null, mimeType: "audio/flac"}` 를 돌려줌 (값이 문자열이 아님) | 돌려준 주소로 GET | 403, 본문 `Stream expired`. 재발급 기록 `["101"]`. CDN 기록 1건 | 같음 |
| PX-29 a | S-4, S-3 | `directUrl = "CDN/old.flac"`. CDN `GET /old.flac` → 401, `GET /new.flac` → 401. `streamRefresher` = `{directUrl: "CDN/new.flac", ...}` | 돌려준 주소로 GET | 500, 본문 `CDN error: 401`. 재발급 기록 `["101"]` (1회뿐). CDN 기록은 `GET /old.flac`, `GET /new.flac` 2건뿐 | 같음 |
| PX-29 b | S-4, S-3 | a 와 같되 두 응답 모두 403 | 돌려준 주소로 GET | 500, 본문 `CDN error: 403`. 재발급 기록 · CDN 기록은 a 와 같음 | 같음 |
| PX-29 c | S-4, S-3 | a 와 같되 `GET /old.flac` → 401, `GET /new.flac` → 403 | 돌려준 주소로 GET | 500, 본문 `CDN error: 403` (재발급 뒤 응답의 코드). 재발급 기록 · CDN 기록은 a 와 같음 | 같음 |
| PX-30 | S-4, S-3 | `directUrl = "CDN/old.flac"`, `mimeType = "audio/flac"`. CDN `GET /old.flac` → 401, 그리고 `MPD3` 의 내용. `streamRefresher` = `{directUrl: "", manifestXml: MPD3, mimeType: ""}` | 돌려준 주소로 GET | 200, 본문 `INITAAAABBCCCCCC`, `Content-Type: audio/mp4`, `Accept-Ranges` 헤더 없음 (PX-34 의 DASH 중계). 재발급 기록 `["101"]` | 같음 |
| PX-31 a | S-4, S-3 | `directUrl = "CDN/old.flac"`, `mimeType = "audio/flac"`. CDN `GET /old.flac` → 403, `GET /new.flac` → 200, `NEW10`. `streamRefresher` = `{directUrl: "CDN/new.flac", manifestXml: "", mimeType: "audio/mpeg"}` | 돌려준 주소로 GET | 200, `Content-Type: audio/mpeg`, 본문 `NEW10` | 같음 |
| PX-31 b | S-4, S-3 | a 와 같되 재발급 결과의 `mimeType` 이 `""` | 돌려준 주소로 GET | 200, `Content-Type: audio/flac`, 본문 `NEW10` | 같음 |
| PX-31 c | S-4, S-3 | a 와 같되 재발급 결과가 `{directUrl: "CDN/new.flac"}` 뿐 (`mimeType` 키가 빠짐 = 빈 값, PX-28 의 보완 문구) | 돌려준 주소로 GET | 200, `Content-Type: audio/flac`, 본문 `NEW10` | 같음 |
| PX-32 a | S-4, S-3 | 기본 등록. CDN `GET /track.flac` → 404. `streamRefresher` = `{directUrl: "CDN/new.flac", ...}` (불리면 안 됨) | 돌려준 주소로 GET | 500, 본문 `CDN error: 404`. 재발급 기록 0건. CDN 기록 1건 | 같음 |
| PX-32 b | S-4, S-3 | a 와 같되 CDN 이 500 | 돌려준 주소로 GET | 500, 본문 `CDN error: 500`. 재발급 기록 0건. CDN 기록 1건 | 같음 |
| PX-33 | S-4 | `directUrl = <닫힌 포트의 주소>/track.flac` (KD-4) | 돌려준 주소로 GET | 500, 본문이 `Proxy error:` 로 시작 | 같음 |

### GET: DASH 중계 (PX-34 ~ PX-38)

| 규칙 ID | 경계 | 준비 (등록 내용, 가짜 CDN 응답) | 요청 | 기대값 (상태 · 헤더 · 본문, 가짜 CDN 이 받은 요청) | 테스트 파일 |
| --- | --- | --- | --- | --- | --- |
| PX-34 a | S-4 | `directUrl = ""`, `manifestXml = MPD3`. CDN 은 `MPD3` 의 내용 (HEAD 는 각 길이, GET 은 본문) | 돌려준 주소로 GET | 200, 본문 `INITAAAABBCCCCCC`, `Content-Type: audio/mp4`, `Accept-Ranges` 헤더 없음. CDN 기록의 GET 은 `init.mp4`, `1.mp4`, `2.mp4`, `3.mp4` 각 1건 | 같음 |
| PX-34 b | S-4 | `directUrl = ""`, `manifestXml = MPD3-noinit`. CDN 은 세그먼트 3개의 내용 | 돌려준 주소로 GET | 200, 본문 `AAAABBCCCCCC`, `Content-Type: audio/mp4`. CDN 기록에 `init.mp4` 요청 없음 | 같음 |
| PX-35 | S-4 | PX-34 a 와 같음 (HEAD 길이 4, 4, 2, 6) | 돌려준 주소로 GET | 200, `Content-Length: 16`, 본문 `INITAAAABBCCCCCC` | 같음 |
| PX-36 a | S-4 | PX-34 a 와 같되 `2.mp4` 의 HEAD 응답만 200, `Content-Length` 헤더 없음 (GET 은 정상) | 돌려준 주소로 GET | 200, `Content-Length` 헤더 없음, `Transfer-Encoding: chunked`, 본문 `INITAAAABBCCCCCC` | 같음 |
| PX-36 b | S-4 | PX-34 a 와 같되 `2.mp4` 의 HEAD 응답만 404, `Content-Length: 2` (성공 상태가 아님. GET 은 정상) | 돌려준 주소로 GET | 200, `Content-Length` 헤더 없음, `Transfer-Encoding: chunked`, 본문 `INITAAAABBCCCCCC` | 같음 |
| PX-37 a | S-4 | `directUrl = ""`, `manifestXml = "not xml"` | 돌려준 주소로 GET | 500, 본문 `Invalid DASH manifest`. CDN 기록 0건 | 같음 |
| PX-37 b | S-4 | `directUrl = ""`, `manifestXml = "<MPD><Period/></MPD>"` (`SegmentTemplate` 없음) | 돌려준 주소로 GET | 500, 본문 `Invalid DASH manifest`. CDN 기록 0건 | 같음 |
| PX-38 a | S-5, S-4 | PX-34 a 와 같음 | 같은 주소로 HEAD 뒤 GET | HEAD 응답 `Content-Length: 16`, GET 응답 `Content-Length: 16` 과 본문 `INITAAAABBCCCCCC`. CDN 기록 전체에서 HEAD 는 경로 4개에 각 1건 (합계 4건, 8건이 아님) | 같음 |
| PX-38 b | S-4 | PX-34 a 와 같음 | 같은 주소로 GET 2번 | 두 응답 모두 200, `Content-Length: 16`, 본문 `INITAAAABBCCCCCC`. CDN 기록 전체에서 HEAD 는 합계 4건, GET 은 합계 8건 | 같음 |

| PX-38 c | S-5 | PX-34 a 와 같되 `2.mp4` 의 HEAD 응답을 순서로 정함: 1번째는 200, `Content-Length` 헤더 없음, 2번째부터는 200, `Content-Length: 2` | 같은 주소로 HEAD 3번 | 1번째 응답: 200, `Content-Length` 헤더 없음. 2번째 응답: `Content-Length: 16` 이고 이때까지 CDN 기록의 `HEAD 2.mp4` 가 2건 (모르는 결과는 기억하지 않고 다시 조회). 3번째 응답: `Content-Length: 16` 이고 CDN 기록의 HEAD 합계가 2번째 뒤와 같음 (알게 된 결과는 기억) | 같음 |

`PX-37` 과 `PX-19 d` 의 해석할 수 없는 매니페스트는 `DashManifestTest.returnsNullForMissingTemplateOrMalformedXml` 이 null 을 기대하는 입력을 그대로 가져왔다.

행 수: 90행 (규칙 38개 = 테스트 함수 38개). 1판 75행에서 문서 보완에 따라 15행을 더했다 (PX-11 b, PX-16 b, PX-17 c · d · e, PX-19 b · c · d, PX-24 b, PX-27 b, PX-28 e · f, PX-31 c, PX-36 b, PX-38 c).

## 3. 속성 테스트 표

실행 횟수는 `pbt(iterations = N)` 로 명시한다 (`PbtSupport.kt`, seed 는 `PBT_SEED` 또는 20261117). 축소 설정은 건드리지 않는다 (KP-5). 생성기는 모두 `ProxyGenerators.kt` 에 둔다 (KP-1).

| 속성 ID | 생성기 (`domain-entities.md` 4절의 범위) | 검증하는 것 | 실행 횟수 (KP-3) | 테스트 파일 |
| --- | --- | --- | --- | --- |
| P-PX-1 | 등록 횟수 0 ~ 10. 각 등록의 MIME 은 "MIME 문자열" 생성기에서 뽑는다. `directUrl` 은 `.test` 도메인의 고정 주소 (요청하지 않음) | 등록을 그 횟수만큼 하고 받은 주소 전부가 `http://127.0.0.1:<listeningPort>/audio/<[0-9a-f] 16자>.<flac · m4a · mp3 중 하나>` 형식이고, 토큰이 서로 다름 (같은 서버에서 속성 실행 전체에 걸쳐 누적한 토큰과도 겹치지 않음). HTTP 요청 없음. 서버 1개를 속성 안에서 재사용 | 100 | `TidalStreamProxyServerTest.kt` (생성기: `ProxyGenerators.kt`) |
| P-PX-2 | MIME 문자열: `audio/flac`, `audio/mp4`, `audio/m4a`, `audio/aac`, `audio/mpeg`, `application/octet-stream`, 빈 문자열 + 이 낱말들 (`flac`, `mp4`, `m4a`, `aac`, `mpeg`, 그 밖의 소문자 조각) 을 섞은 문자열 (예: `audio/x-flac; codecs=mp4`). 소문자만 만들고 공백만 있는 문자열은 만들지 않는다 (PX-02: 대문자 · 공백 MIME 은 입력 범위 밖) | `directUrl` 이 있는 등록 (PX-04 가 끼어들지 않게) 의 주소 확장자가 테스트 안의 참조 표와 같음. 참조 표 (PX-02 의 순서): `flac` 포함 → `flac`, 아니고 `mp4` · `m4a` · `aac` 포함 → `m4a`, 아니고 `mpeg` 포함 → `mp3`, 그 밖 (빈 문자열 포함) → `m4a`. HTTP 요청 없음 | 100 | 같음 |
| P-PX-3 | 등록 횟수 0 ~ 10 (`trackId` 는 순번, `allowedHost = "192.0.2.10"`, `directUrl` 은 가짜 CDN 주소) | **모델**: "최근에 등록한 주소 3개" 목록 (등록마다 끝에 넣고 3개를 넘으면 맨 앞을 뺌). 반복마다 새 서버 (`use { }`). 등록 0회 상태: `GET /audio/0000000000000000.flac` 이 404. 등록 하나마다: 지금까지 받은 모든 주소에 GET 을 보내 모델에 있는 주소는 403 (KP-4, 속성 문장으로는 "404 가 아님"), 모델에서 밀려난 주소는 404. 끝까지 CDN 기록 0건 (CDN 을 거치지 않고 등록 여부만 구분) | 25 | 같음 |
| P-PX-4 | 허용 주소: 빈 문자열, `127.0.0.1`, 문서용 예약 대역의 IPv4 (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`), `localhost`, 임의의 짧은 문자열 (공백이 아닌 인쇄 가능 ASCII 1 ~ 12자. 공백만 있는 `allowedHost` 는 입력 범위 밖) | 그 `allowedHost` 로 등록한 주소에 GET. `allowedHost` 가 `""` 또는 `"127.0.0.1"` 이면 200 과 CDN 본문 (`BODY10`), 그 밖 (`localhost` 포함, PX-11: 문자열 그대로 비교) 에는 403, 본문 `Forbidden`, 그 요청으로 CDN 기록이 늘지 않음. 서버 1개를 속성 안에서 재사용 | 50 | 같음 |
| P-PX-5 | Range 값: `bytes=a-b` (0 ≤ a ≤ b < 1,000,000) 와 `bytes=a-` | 기본 등록의 주소에 그 `Range` 로 GET 을 보내 응답을 다 읽은 뒤, CDN 이 받은 요청의 `Range` 헤더가 보낸 값과 글자 그대로 같음. CDN 은 항상 200 과 `BODY10` 으로 답한다 (응답 내용은 이 속성의 대상이 아님) | 50 | 같음 |
| P-PX-6 (단일 파일) | 바이트 내용: 길이 0 ~ 65,536 의 임의 바이트 열 (0, 1, 65,536 이 나오게 경계를 섞음) | CDN 이 그 내용을 200 으로 주는 주소를 등록하고 GET 으로 받은 본문이 그 내용과 바이트 단위로 같음 | 25 | 같음 |
| P-PX-6 (DASH) | DASH 내용: 초기화 세그먼트 있음/없음, 세그먼트 1 ~ 8개, 각 길이 1 ~ 4,096 의 임의 바이트 열 (초기화 세그먼트도 같은 범위) | 반복마다 고유 경로의 매니페스트를 만들어 등록하고 GET. 본문이 초기화 세그먼트 (있으면) + 세그먼트들을 순서대로 이은 것과 같고, `Content-Length` 가 그 길이의 합계와 같음 | 25 | 같음 |

속성 6개, 표의 행 7개, 테스트 함수 7개 (P-PX-6 은 단일 파일 · DASH 두 함수, 둘 다 이름 맨 앞에 `P-PX-6`, 각각 25회로 확정).

속성 테스트의 기대값은 입력에서 계산할 수밖에 없다 (참조 표, 모델, 이어 붙인 바이트). 같은 규칙의 리터럴 기대값은 2절의 예시 행 (PX-02, PX-06, PX-11 · 12, PX-23, PX-21 · 34 · 35) 이 맡는다 (NFR-04-A11).

## 4. 테스트 도우미 설계 요약

### `FakeCdnServer.kt` (`MockWebServer` 를 감쌈, 테스트는 `MockWebServer` 를 직접 다루지 않음)

| 제공하는 것 | 내용 |
| --- | --- |
| 시작 · 종료 | `127.0.0.1` 의 임시 포트로 시작 (KD-1, NFR-03-A1). `close()` 로 닫음 |
| `url(path)` | `http://127.0.0.1:<포트><path>` 문자열. 등록의 `directUrl` 과 매니페스트 안의 주소에 쓴다 |
| 경로별 응답 | 경로마다 GET 응답 (상태, 헤더, 본문 바이트, `Content-Length` 를 넣을지 chunked 로 보낼지) 과 HEAD 응답 (상태, `Content-Length` 값 또는 "헤더 없음") 을 따로 정할 수 있다. HEAD 응답에는 본문을 쓰지 않는다. HEAD 를 따로 정하지 않으면 GET 응답의 상태와 본문 길이를 `Content-Length` 로 알린다 |
| 응답 순서 | 한 경로의 GET · HEAD 각각에 응답 여러 개를 순서대로 정할 수 있다 (n 번째 요청에 n 번째 응답, 다 쓰면 마지막 응답을 반복). PX-38 c 가 쓴다 |
| 정하지 않은 경로 | 404 로 답하고 기록에는 남긴다 |
| 받은 요청 기록 | 도착 순서대로 `(method, path, range)` 목록. `range` 는 `Range` 헤더 값 또는 null. 메서드별 · 경로별로 세는 함수, 지금까지의 기록을 꺼내며 비우는 함수 (속성 테스트에서 반복마다 늘어난 건수를 볼 때) |
| 닫힌 포트의 주소 | 서버를 하나 더 띄워 주소를 받은 뒤 바로 닫아, 연결이 즉시 거부되는 주소를 돌려준다 (KD-4, PX-17 a, PX-19 c, PX-33) |

### `ProxyFixture.kt` (`ProxyFixture`, `ProxyResponse`)

| 제공하는 것 | 내용 |
| --- | --- |
| 수명 | 만들 때 `FakeCdnServer` 와 `TidalStreamProxyServer("127.0.0.1", port = 0, httpClient = <연결 · 읽기 · 쓰기 2초>)` 를 띄운다 (`start(timeout, daemon = true)`, `timeout` 은 NanoHTTPD 의 공개 기본 타임아웃 상수. 상수 이름은 작성 단계에서 시그니처로 확인). `close()` 가 둘 다 닫는다. `Closeable` 이라 `@Before` / `@After` 와 `use { }` 양쪽에 쓴다 (KD-2, KD-3) |
| `proxy`, `cdn` | 프록시 인스턴스 (S-2 `registerTrackStream`, S-3 `streamRefresher` 를 테스트가 직접 호출 · 대입) 와 가짜 CDN |
| `register(...)` | `registerTrackStream` 을 "기본 등록" 값으로 부르는 얇은 함수. 다른 인자만 이름으로 넘긴다. 규칙은 들어 있지 않다 |
| `get(urlOrPath, range = null)`, `head(urlOrPath)` | 프록시에 요청을 보내 `ProxyResponse` 를 돌려준다. 테스트용 OkHttp 클라이언트는 타임아웃 2초, 자동 재시도 끔, `Accept-Encoding: identity` (압축이 끼어 `Content-Length` 나 본문이 달라 보이는 일을 막음). 본문을 끝까지 읽고 돌려준다 (KD-5) |
| `ProxyResponse` | `status: Int`, `header(name): String?` (없으면 null), `body: ByteArray`, `bodyText` |
| 토큰 · 경로 | 돌려받은 주소에서 토큰을 꺼내는 함수 (정규식), `/audio/<토큰><접미사>` 경로를 만드는 함수 (PX-14, PX-09 b) |
| DASH 준비 | 초기화 세그먼트 (없을 수 있음) 와 세그먼트 바이트 목록을 받아 가짜 CDN 에 경로를 등록하고 그 주소를 담은 매니페스트 문자열을 돌려준다. 호출할 때마다 경로에 고유 값을 넣어 매니페스트 원문이 다르게 한다. 길이 기억은 서버 인스턴스마다이므로 (PX-38) 테스트마다 새 서버를 쓰는 예시 테스트에는 필요 없지만, 서버 하나를 반복에 재사용하는 속성 (P-PX-6 DASH) 에서 앞 반복의 길이가 나오지 않게 하려고 유지한다. 주소를 닫힌 포트로 향하게 한 매니페스트도 만들 수 있다 (PX-19 c) |
| 재발급 기록기 | `streamRefresher` 에 넣을 함수를 만든다: 받은 `trackId` 를 기록하고, 정해 둔 맵 · null · 예외로 답한다 |

`ProxyGenerators.kt`: 3절 표의 생성기 6개 (MIME 문자열, 등록 횟수, 허용 주소, Range 값, 바이트 내용, DASH 내용). Kotest 기본 `Arb` 와 조합 함수로만 만든다 (KP-5).

지키는 것: `Thread.sleep` 없음 (KD-5), 포트 번호를 적지 않음 (KD-1), 주소는 `127.0.0.1` · 문서용 예약 대역 · `.test` 만 (`domain-entities.md` 4절), `PROXY_PORT` 값 확인 같은 테스트 없음 (TW-9).

도우미 자체의 오류는 RED 로 인정되지 않으므로 (TW-4), 작성 단계에서 먼저 확인할 것: 본문 없는 HEAD 응답에 `Content-Length` 만 싣는 것, `Content-Length` 헤더가 없는 HEAD 응답, chunked 응답을 `MockWebServer` 로 만들 수 있는지.

## 5. 실패할 가능성이 있다고 보는 행

2판 기준이다. 문서 보완 (2026-11-17) 은 "응답 헤더가 클라이언트에 실제로 어떻게 보이는지 (NanoHTTPD 가 스스로 붙이거나 바꾸는 헤더) 는 정하지 않았다. 테스트 결과로 확인한다" 고 적었다. 그래서 F-1 ~ F-4, F-7 은 규칙 문장 그대로 단언하고 표시만 남긴다. 실패하면 "규칙 문서와 관찰되는 응답이 다름" 으로 RED 판정 표에 그대로 올린다 (단언을 느슨하게 고치지 않는다).

번호는 1판과 맞춰 두었다. 빠진 번호 (F-6, F-8 ~ F-12, F-16) 는 문서 보완으로 문서에 적힌 기대값이 되어 목록에서 뺐다 (6절).

| # | 행 | 단언할 것 | 불확실한 이유 |
| --- | --- | --- | --- |
| F-1 | PX-17 a · b · e, PX-19 a · b · c · d, PX-38 c (1번째 응답) | HEAD 응답에 `Content-Length` 헤더가 없음 (KV-3) | 핸들러가 길이를 넣지 않았을 때 NanoHTTPD 가 스스로 `Content-Length` 를 붙이는지 문서가 정하지 않았다 |
| F-2 | PX-16 a · b, PX-17 c · d, PX-18, PX-20 a · b, PX-38 a · c | HEAD 응답의 `Content-Length` 가 `123456` / `0` / `55` / `3400` / `77` / `16` | 본문이 없는 HEAD 응답에 핸들러가 정한 길이가 그대로 나가는지 문서가 정하지 않았다. PX-20 은 O-3 이 스스로 정정한 동작이기도 하다 |
| F-3 | PX-22, PX-36 a · b | `Content-Length` 헤더 없음, `Transfer-Encoding: chunked`, 본문 전체 | "길이 없이 (chunked)" 가 클라이언트에서 `Transfer-Encoding: chunked` 헤더로 보이는지는 NanoHTTPD · OkHttp 동작에 달려 있다 |
| F-4 | PX-18, PX-30, PX-34 a | `Accept-Ranges` 헤더가 없음 | 라이브러리가 스스로 붙이는 헤더가 있는지 문서가 정하지 않았다 |
| F-5 | PX-07 | `Content-Type` 의 type/subtype 가 `text/plain` (매개변수는 보지 않음), 본문 `pong` | `; charset=...` 이 붙는지 문서에 없어 type/subtype 만 본다 (이 방식으로 합의됨). 남는 위험은 본문 · 압축 쪽인데 테스트 클라이언트가 `Accept-Encoding: identity` 로 보낸다 |
| F-7 | PX-25 | 206, `Content-Range` 헤더 없음, 본문 `BODY10` 전체 | O-2 로 고정한, HTTP 규약에서 벗어난 응답이다. `Content-Range` 없는 206 을 OkHttp 가 그대로 넘겨주는지 문서가 정하지 않았다 |
| F-13 | PX-08 c · d (`/audio`, `/ping2`) | 404, 본문 `Not Found` | 규칙 문장 ("`/audio/` 로 시작하지 않고 `/ping` 도 아닌 경로") 을 글자 그대로 읽은 경계 입력이다. 구현이 `/ping` 을 앞부분 일치로 보면 d 가 실패한다. 보완 문구에 언급이 없어 1판 그대로 둔다 |
| F-14 | PX-09 c (`/audio/`) | 404, 본문 `Not Found` | 빈 토큰을 PX-14 의 토큰 정의에 따라 "등록되지 않은 토큰" 으로 읽었다. 빈 토큰을 따로 말한 문장은 없다 |
| F-15 | PX-10 b | 내용이 빈 등록 + 허용되지 않은 주소 → 404 | 근거는 `business-logic-model.md` 2.2 흐름도의 판정 순서다. 규칙 표에는 PX-13 (미등록 + 불허) 만 있다 |
| F-17 | PX-17 a, PX-19 c, PX-33 | 200 + `Content-Length` 없음 / 500 + `Proxy error:` 로 시작 | 닫은 포트를 OS 가 곧바로 다른 서버에 다시 내줄 수 있다 (KD-4 의 전제가 깨지는 경우). 문서 문제가 아니라 결정성 위험이다. 10회 반복 (NFR-03-A4) 에서 드러날 수 있다 |
| F-18 | P-PX-6 (단일 파일, 길이 0) | 200, 본문 0바이트 | 생성기 범위에 길이 0 이 명시돼 있어 넣는다. 길이 0 본문이 NanoHTTPD 를 거쳐 어떻게 나가는지는 문서가 정하지 않았다 |

## 6. 문서만으로 정할 수 없는 것

### 남은 질문

규칙 문구에 대한 미해결 질문: **없음**. 1판의 Q-1 ~ Q-21 은 모두 문서 보완으로 답을 받았다.

승인을 막지는 않지만 알려 둘 것이 4개 있다. 지어내지 않고 단언 범위를 좁혀 두었다.

| # | 관련 | 내용 | 표에서 |
| --- | --- | --- | --- |
| N-1 | PX-19, PX-36 ("연결하지 못한 경우") | 세그먼트 주소는 매니페스트의 틀 하나에서 나오므로 모든 세그먼트가 같은 호스트다. "세그먼트 하나만 연결 실패" 는 도우미로 만들 수 없다 | HEAD 는 주소 전부를 닫힌 포트로 한 PX-19 c 로 대신했다. GET (PX-36) 은 본문을 받을 수 없어 연결 실패 행이 없다 (a: 헤더 없음, b: 성공 상태 아님 두 경우만) |
| N-2 | PX-19 d | 해석할 수 없는 매니페스트의 HEAD 응답에서 `Content-Type` 이 무엇인지는 보완 문구에 없다 ("200, 길이 없음" 만 있음) | 상태 200 과 `Content-Length` 없음만 단언한다 |
| N-3 | PX-38 c | 모르는 결과를 다시 조회할 때 세그먼트 전부를 다시 묻는지 몰랐던 것만 묻는지는 문구에 없다 | `HEAD 2.mp4` 가 2건인 것과 응답의 `Content-Length: 16` 만 단언하고, 2번째 요청 뒤의 HEAD 합계 (8건인지) 는 단언하지 않는다 |
| N-4 | PX-38 ("기억하는 범위는 서버 인스턴스 하나") | 이 문장만을 확인하는 행 (서버 두 개에 같은 매니페스트를 등록) 은 넣지 않았다. 도우미가 가짜 CDN 하나에 프록시 둘을 띄워야 한다 | 원하면 PX-38 d 로 추가한다 |

### 문서 보완으로 해결된 것

| 1판 질문 | 답 (근거) | 표의 변화 |
| --- | --- | --- |
| Q-1 작성 주체 | 프록시 담당 하위 에이전트가 쓴다 (TW-8, `logical-components.md` 3절 정정) | 없음 |
| Q-2 대괄호 표기 | 대괄호 없이 규칙 ID 를 맨 앞에 (NFR-01-A1, NFR-05-A2 정정) | 없음 |
| Q-3 HEAD 상태 | HEAD 절의 모든 경우에 200 (PX-16) | 200 단언 유지. 유추가 아니라 문서 값이 됨 |
| Q-4 PX-17 의 범위 | "실패" = 연결 실패. 오류 상태 + 길이는 PX-20 처럼 그 길이를 알림. 길이가 없어도 `Content-Type` · `Accept-Ranges: bytes` 는 보냄 (PX-17). CDN 의 `Content-Length: 0` 은 0 그대로 (PX-16) | PX-16 b, PX-17 c · d · e 추가. PX-17 a · b 에 `Content-Type` · `Accept-Ranges` 단언 추가 |
| Q-5 "길이를 모름" | 세그먼트 HEAD 가 성공 상태가 아님 / `Content-Length` 없음 / 연결 실패 (PX-19, PX-36) | PX-19 b · c, PX-36 b 추가 (N-1) |
| Q-6 대소문자 · 공백 | 판정은 대소문자 구분. 대문자 · 공백 MIME, 공백 `allowedHost` 는 입력 범위 밖 (PX-02, 보완 문구) | 테스트하지 않음. 생성기도 만들지 않음 |
| Q-7 DASH 확장자 | 정한 MIME (`audio/mp4`) 으로 골라 `m4a` (PX-04) | PX-04 a 유지 (F-8 삭제) |
| Q-8 PX-13 조건 | 대신 쓴 조건을 인정 | PX-13 a · b 유지 |
| Q-9 `<코드>` | 재발급 뒤 두 번째 응답의 상태 코드 (PX-29) | PX-29 c 유지 (F-10 삭제) |
| Q-10 재발급 DASH 의 `Content-Type` | `audio/mp4` (PX-30) | PX-30 유지 (F-9 삭제) |
| Q-11 재발급 맵의 키 누락 · 문자열 아닌 값 | 빈 값으로 본다 (PX-28) | PX-28 e · f, PX-31 c 추가 |
| Q-12 갱신된 MIME 의 유지 | 다음 요청에도 유지 (PX-27) | PX-27 b 추가 |
| Q-13 해석 못 하는 매니페스트의 HEAD | 200, 길이 없음. GET 은 500 (PX-19) | PX-19 d 추가 (N-2) |
| Q-14 `initialization` 없는 매니페스트 | 유효. 본문은 세그먼트만 (PX-34) | PX-34 b 유지 (F-11 삭제) |
| Q-15 길이 기억 | 서버 인스턴스마다. 모르는 결과는 기억하지 않고 다시 조회. 세그먼트 HEAD 는 동시에 보내 순서 없음 (PX-38) | PX-38 c 추가. HEAD 는 계속 순서 없이 건수로 비교. 고유 경로는 속성 테스트용으로 유지 (F-16 삭제, N-3 · N-4) |
| Q-16 다른 메서드 · 쿼리 문자열 | 입력 범위 밖 (보완 문구) | 테스트하지 않음 |
| Q-17 206 의 `Content-Length` | CDN 값 (PX-24) | PX-24 a 에 `Content-Length: 4` 단언 추가 |
| Q-18 Range 없는 요청에 CDN 206 | 206 과 `Content-Range` 를 전달 (PX-24) | PX-24 b 추가 |
| Q-19 P-PX-6 실행 횟수 | 두 함수 각각 25회 | 3절에 확정으로 적음 |
| Q-20 `start` 의 `timeout` | NanoHTTPD 의 공개 기본 타임아웃 상수 | 1절 · 4절에 적음 |
| Q-21 시작 전 등록 | 입력 범위 밖 (보완 문구) | 테스트하지 않음 |
| F-12 `localhost` | 비교는 문자열 그대로. `localhost` 는 403 (PX-11) | PX-11 b 추가. P-PX-4 는 그대로. "실패 가능" 목록에서 뺌 |
