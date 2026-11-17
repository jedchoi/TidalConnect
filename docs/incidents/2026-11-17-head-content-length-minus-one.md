# 길이를 모르는 곡의 HEAD 응답에 `Content-Length: -1` 이 나감

- **발견일**: 2026-11-17
- **영향**: 로컬 프록시(`TidalStreamProxyServer`)가 곡의 길이를 알아내지 못한 HEAD 요청에 `Content-Length: -1` 헤더를 실어 응답했다. 조건은 두 가지다. 단일 파일 곡에서 CDN 에 연결하지 못했거나 CDN 의 HEAD 응답에 `Content-Length` 가 없는 경우, 그리고 DASH 곡에서 세그먼트 하나라도 길이를 모르거나 매니페스트를 해석하지 못한 경우다. 길이를 아는 HEAD 응답과 모든 GET 응답은 정상이었다. 실기기에서 증상이 관찰된 것은 아니며, 실기기 영향은 확인하지 않았다. 렌더러가 `-1` 을 어떻게 받아들이는지는 알지 못한다.
- **증상**: 테스트 보강 중 프록시 테스트 3개(PX-17, PX-19, PX-38)가 `Content-Length: 기대 <null>, 실제 <-1>` 로 실패해 발견했다. 재현 순서는 다음과 같다. CDN 의 HEAD 응답에 `Content-Length` 가 없는 곡을 등록하고, 등록이 돌려준 주소에 HEAD 를 보낸다. 응답은 200, 본문 0바이트이고 헤더에 `Content-Length: -1` 이 있다. 테스트 클라이언트(OkHttp)를 거치지 않고 원시 소켓으로 받은 응답에도 같은 헤더가 있었다.
- **원인**: `headResponse` 는 길이를 모를 때 `newChunkedResponse` 로 응답을 만들었고 `Content-Length` 를 직접 넣지 않았다. 바로 위 주석은 "길이를 모르면 알리지 않는다" 였다. 그런데 NanoHTTPD 2.3.1 의 `Response.send` 는 요청이 HEAD 이면 chunked 여부를 보지 않고 `sendContentLengthHeaderIfNotAlreadyPresent` 를 불러 `Content-Length` 를 쓴다. `newChunkedResponse` 는 길이를 `-1` 로 둔 응답을 만들기 때문에 그 값이 헤더에 그대로 나갔다. GET 은 같은 응답이 `Transfer-Encoding: chunked` 로 나가므로 문제가 없었다.
- **수정**: `8e5b417`. `TidalStreamProxyServer.headResponse` 에서 길이를 모를 때 `Response` 를 상속한 익명 객체로 응답을 만들고, `sendContentLengthHeaderIfNotAlreadyPresent` 를 재정의해 헤더를 쓰지 않게 했다. 길이를 아는 HEAD 응답과 GET 응답의 경로는 바꾸지 않았다. 수정 뒤 길이를 모르는 HEAD 응답의 헤더는 `Content-Type`, `Date`, `Connection` 이고, 단일 파일 곡이면 `Accept-Ranges: bytes` 가 더 있다.
- **추가한 테스트**: 새로 추가한 것은 없다. 이 문제를 찾아낸 테스트가 수정 전에 커밋(`6acf424`)되어 있었고, 수정 뒤 통과한다. `android/app/src/test/kotlin/com/example/tidal_connect_lite/TidalStreamProxyServerTest.kt` 의 다음 3개다.
  - `PX-17 단일 파일 HEAD 에서 CDN 에 연결하지 못하거나 길이가 없으면 Content-Length 없이 200 이다`
  - `PX-19 DASH HEAD 에서 세그먼트 하나라도 길이를 모르면 Content-Length 없이 응답한다`
  - `PX-38 세그먼트 길이 조회는 매니페스트당 한 번만 하고 모르는 결과는 다시 조회한다`
- **재발 방지**:
  - [ ] 실기기에서 길이를 모르는 곡의 DLNA 재생 확인
  - [ ] NanoHTTPD 버전을 올릴 때 `Response.send` 가 `sendContentLengthHeaderIfNotAlreadyPresent` 를 계속 부르는지 확인한다. 메서드가 없어지면 컴파일이 실패하고, 헤더를 다른 곳에서 쓰게 바뀌면 위 테스트 3개가 실패한다.
