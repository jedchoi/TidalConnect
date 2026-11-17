package com.example.tidal_connect_lite

import io.kotest.property.checkAll
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

/**
 * `TidalStreamProxyServer`의 보호 테스트. 기대값은 `business-rules.md` 3절(PX-01 ~ PX-38)과
 * `business-logic-model.md` 3절(P-PX-1 ~ P-PX-6)의 값을 그대로 옮겼다.
 *
 * 프록시는 실제 서버를 `127.0.0.1`의 임시 포트에 띄우고, CDN만 [FakeCdnServer]로 대신한다.
 * 판정은 HTTP 응답과 가짜 CDN이 받은 요청 기록으로만 한다(등록부·캐시를 직접 보지 않는다).
 * 규칙 하나가 테스트 함수 하나이고, 조건이 여럿인 규칙은 함수 안에서 행(a, b, ...)으로 돌린다.
 */
class TidalStreamProxyServerTest {
    private val body10 = byteArrayOf(0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09)
    private val new10 = byteArrayOf(0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19)
    private val otherHost = "192.0.2.10"
    private val unregisteredPath = "/audio/0000000000000000.flac"

    /**
     * 행 단위 검사 모음. 한 행이 실패해도 나머지 행을 끝까지 돌리고, 마지막에 한꺼번에 실패시킨다.
     * 실패한 행에는 프록시와 주고받은 응답과 가짜 CDN의 기록을 덧붙인다.
     */
    private class ProxyChecks {
        val failures = mutableListOf<String>()
        private var current = ""

        fun <T> eq(what: String, expected: T, actual: T) {
            if (expected != actual) failures += "$current $what: 기대 <$expected>, 실제 <$actual>"
        }

        fun bytes(what: String, expected: ByteArray, actual: ByteArray) {
            if (!expected.contentEquals(actual)) {
                failures += "$current $what: 기대 ${expected.size}바이트 [${preview(expected)}], " +
                    "실제 ${actual.size}바이트 [${preview(actual)}]"
            }
        }

        fun truth(what: String, condition: Boolean, detail: String) {
            if (!condition) failures += "$current $what: $detail"
        }

        /** 새 프록시와 가짜 CDN으로 행 하나를 실행한다. */
        fun row(name: String, block: ProxyChecks.(ProxyFixture) -> Unit) {
            current = name
            val before = failures.size
            ProxyFixture().use { fx ->
                try {
                    block(fx)
                } catch (e: IOException) {
                    failures += "$name 요청 중 예외: ${e.javaClass.simpleName}: ${e.message}"
                }
                if (failures.size > before) {
                    failures += "$name 관찰한 응답: ${fx.exchanges()}"
                    failures += "$name CDN 기록: ${fx.cdn.requests()}"
                }
            }
        }

        private fun preview(bytes: ByteArray): String =
            if (bytes.size <= 32) proxyHex(bytes) else proxyHex(bytes.copyOf(32)) + " ..."
    }

    private fun table(block: ProxyChecks.() -> Unit) {
        val checks = ProxyChecks()
        checks.block()
        if (checks.failures.isNotEmpty()) fail(checks.failures.joinToString("\n"))
    }

    private fun ascii(text: String): ByteArray = text.toByteArray(Charsets.US_ASCII)

    private fun extensionOf(url: String): String = url.substringAfterLast('.')

    /** `MPD3`: 초기화 세그먼트 `INIT`과 세그먼트 `AAAA`, `BB`, `CCCCCC`. 이어 붙이면 `INITAAAABBCCCCCC`(16바이트). */
    private fun ProxyFixture.mpd3(): ProxyDash =
        prepareDash(ascii("INIT"), listOf(ascii("AAAA"), ascii("BB"), ascii("CCCCCC")))

    /** `MPD3-noinit`: 세그먼트 `AAAA`, `BB`, `CCCCCC`만. 이어 붙이면 `AAAABBCCCCCC`(12바이트). */
    private fun ProxyFixture.mpd3NoInit(): ProxyDash =
        prepareDash(null, listOf(ascii("AAAA"), ascii("BB"), ascii("CCCCCC")))

    /** 새 직접 주소(`/new.flac`)를 주는 재발급 함수. */
    private fun ProxyFixture.refreshToNewUrl(mimeType: String = ""): ProxyRefresherSpy = ProxyRefresherSpy {
        mapOf("directUrl" to cdn.url("/new.flac"), "manifestXml" to "", "mimeType" to mimeType)
    }

    // ---------------------------------------------------------------- 곡 등록

    @Test
    fun `PX-01 등록하면 열린 포트와 16자 16진수 토큰이 든 주소를 돌려준다`() {
        // PX-01: 주소 형식이 다르거나, 토큰이 16자 16진수 소문자가 아니거나, 포트가 실제로 열린 포트가 아니면 실패
        table {
            row("PX-01") { fx ->
                val url = fx.register()
                val match = Regex("""^http://127\.0\.0\.1:(\d+)/audio/([0-9a-f]{16})\.flac$""").matchEntire(url)
                truth("주소 형식", match != null, "http://127.0.0.1:<포트>/audio/<16자 16진수>.flac 이 아님: <$url>")
                if (match != null) {
                    val port = match.groupValues[1]
                    eq("주소의 포트", fx.proxy.listeningPort.toString(), port)
                    eq("그 주소의 ping 상태", 200, fx.get("http://127.0.0.1:$port/ping").status)
                }
            }
        }
    }

    @Test
    fun `PX-02 확장자는 MIME 에 든 낱말을 flac m4a mp3 순서로 판정해 정한다`() {
        // PX-02: 확장자 표의 값이 다르거나 판정 순서(flac → mp4·m4a·aac → mpeg → 그 밖)가 바뀌면 실패
        val cases = listOf(
            Triple("PX-02 a", "audio/flac", "flac"),
            Triple("PX-02 b", "audio/mp4", "m4a"),
            Triple("PX-02 c", "audio/m4a", "m4a"),
            Triple("PX-02 d", "audio/aac", "m4a"),
            Triple("PX-02 e", "audio/mpeg", "mp3"),
            Triple("PX-02 f", "application/octet-stream", "m4a"),
            Triple("PX-02 g", "audio/x-flac; codecs=mp4", "flac"),
            Triple("PX-02 h", "audio/mpeg; codecs=aac", "m4a"),
        )
        table {
            for ((name, mime, extension) in cases) {
                row(name) { fx ->
                    eq("MIME <$mime> 의 확장자", extension, extensionOf(fx.register(mimeType = mime)))
                }
            }
        }
    }

    @Test
    fun `PX-03 MIME 이 빈 문자열이면 audio mp4 로 본다`() {
        // PX-03: 빈 MIME 을 audio/mp4 로 바꾸지 않으면(Content-Type 이 비거나 다른 값) 실패
        table {
            row("PX-03") { fx ->
                fx.cdn.onGet("/track.flac", body10)
                val url = fx.register(mimeType = "")
                eq("확장자", "m4a", extensionOf(url))
                val response = fx.get(url)
                eq("상태", 200, response.status)
                eq("Content-Type", "audio/mp4", response.header("Content-Type"))
            }
        }
    }

    @Test
    fun `PX-04 매니페스트만 있는 등록은 넘어온 MIME 과 상관없이 audio mp4 다`() {
        // PX-04: DASH 등록에 넘어온 MIME(audio/flac)을 그대로 쓰면(.flac, audio/flac) 실패. 직접 주소가 있으면 넘어온 MIME 을 써야 한다
        table {
            row("PX-04 a") { fx ->
                val dash = fx.mpd3()
                val url = fx.register(directUrl = "", manifestXml = dash.manifest, mimeType = "audio/flac")
                eq("확장자", "m4a", extensionOf(url))
                val response = fx.get(url)
                eq("상태", 200, response.status)
                eq("Content-Type", "audio/mp4", response.header("Content-Type"))
            }
            row("PX-04 b") { fx ->
                val dash = fx.mpd3()
                fx.cdn.onGet("/track.flac", body10)
                val url = fx.register(manifestXml = dash.manifest, mimeType = "audio/flac")
                eq("확장자", "flac", extensionOf(url))
                val response = fx.get(url)
                eq("상태", 200, response.status)
                eq("Content-Type", "audio/flac", response.header("Content-Type"))
                bytes("본문", body10, response.body)
            }
        }
    }

    @Test
    fun `PX-05 같은 곡을 다시 등록하면 새 토큰을 만들고 두 주소 모두 쓸 수 있다`() {
        // PX-05: 같은 곡에 같은 토큰을 돌려주거나, 다시 등록할 때 앞 주소가 죽으면 실패
        table {
            row("PX-05") { fx ->
                fx.cdn.onGet("/track.flac", body10)
                val first = fx.register()
                val second = fx.register()
                truth("토큰", fx.tokenOf(first) != fx.tokenOf(second), "두 주소의 토큰이 같음: <$first>, <$second>")
                val firstResponse = fx.get(first)
                eq("첫 주소의 상태", 200, firstResponse.status)
                bytes("첫 주소의 본문", body10, firstResponse.body)
                val secondResponse = fx.get(second)
                eq("둘째 주소의 상태", 200, secondResponse.status)
                bytes("둘째 주소의 본문", body10, secondResponse.body)
            }
        }
    }

    @Test
    fun `PX-06 네 번째 곡을 등록하면 가장 오래된 등록이 지워지고 최근 3개만 남는다`() {
        // PX-06: 3개째에 벌써 지우거나, 4개째에도 지우지 않거나, 가장 오래된 것이 아닌 등록을 지우면 실패
        table {
            row("PX-06") { fx ->
                for (n in 1..4) fx.cdn.onGet("/t$n.flac", byteArrayOf(n.toByte()))
                val urls = (1..3).map { n -> fx.register(trackId = "$n", directUrl = fx.cdn.url("/t$n.flac")) }.toMutableList()
                // a: 3곡까지는 모두 남는다
                eq("a 1번째 상태", 200, fx.get(urls[0]).status)
                bytes("a 1번째 본문", byteArrayOf(0x01), fx.get(urls[0]).body)
                bytes("a 2번째 본문", byteArrayOf(0x02), fx.get(urls[1]).body)
                bytes("a 3번째 본문", byteArrayOf(0x03), fx.get(urls[2]).body)
                // b: 4번째를 등록하면 1번째만 지워진다
                urls += fx.register(trackId = "4", directUrl = fx.cdn.url("/t4.flac"))
                val evicted = fx.get(urls[0])
                eq("b 1번째 상태", 404, evicted.status)
                eq("b 1번째 본문", "Not Found", evicted.bodyText)
                val second = fx.get(urls[1])
                eq("b 2번째 상태", 200, second.status)
                bytes("b 2번째 본문", byteArrayOf(0x02), second.body)
                val third = fx.get(urls[2])
                eq("b 3번째 상태", 200, third.status)
                bytes("b 3번째 본문", byteArrayOf(0x03), third.body)
                val fourth = fx.get(urls[3])
                eq("b 4번째 상태", 200, fourth.status)
                bytes("b 4번째 본문", byteArrayOf(0x04), fourth.body)
            }
        }
    }

    // ---------------------------------------------------------------- 요청 처리

    @Test
    fun `PX-07 ping 요청에 200 과 text plain 본문 pong 을 돌려준다`() {
        // PX-07: 상태가 200 이 아니거나, 타입이 text/plain 이 아니거나, 본문이 pong 이 아니면 실패
        table {
            row("PX-07") { fx ->
                val response = fx.get("/ping")
                eq("상태", 200, response.status)
                eq("Content-Type 의 type/subtype", "text/plain", response.header("Content-Type")?.substringBefore(';')?.trim())
                eq("본문", "pong", response.bodyText)
            }
        }
    }

    @Test
    fun `PX-08 audio 로 시작하지 않고 ping 도 아닌 경로는 404 Not Found 다`() {
        // PX-08: 모르는 경로에 404 가 아닌 응답을 주거나, 경로를 앞부분 일치로 판정해 ping2 · audio 를 받아들이면 실패
        val cases = listOf("PX-08 a" to "/", "PX-08 b" to "/foo", "PX-08 c" to "/audio", "PX-08 d" to "/ping2")
        table {
            for ((name, path) in cases) {
                row(name) { fx ->
                    val response = fx.get(path)
                    eq("<$path> 상태", 404, response.status)
                    eq("<$path> 본문", "Not Found", response.bodyText)
                }
            }
        }
    }

    @Test
    fun `PX-09 등록되지 않은 토큰은 404 다`() {
        // PX-09: 등록되지 않은 토큰(한 글자만 다른 토큰, 빈 토큰 포함)에 404 가 아닌 응답을 주거나 CDN 에 요청하면 실패
        table {
            row("PX-09 a") { fx ->
                val response = fx.get(unregisteredPath)
                eq("상태", 404, response.status)
                eq("본문", "Not Found", response.bodyText)
                eq("CDN 기록 건수", 0, fx.cdn.requests().size)
            }
            row("PX-09 b") { fx ->
                fx.cdn.onGet("/track.flac", body10)
                val token = fx.tokenOf(fx.register())
                val other = token.dropLast(1) + if (token.last() == '0') '1' else '0'
                val response = fx.get(fx.audioPath(other, ".flac"))
                eq("상태", 404, response.status)
                eq("본문", "Not Found", response.bodyText)
                eq("CDN 기록 건수", 0, fx.cdn.requests().size)
            }
            row("PX-09 c") { fx ->
                fx.register()
                val response = fx.get("/audio/")
                eq("상태", 404, response.status)
                eq("본문", "Not Found", response.bodyText)
                eq("CDN 기록 건수", 0, fx.cdn.requests().size)
            }
        }
    }

    @Test
    fun `PX-10 직접 주소와 매니페스트가 모두 빈 등록은 404 다`() {
        // PX-10: 내용이 빈 등록에 400 이나 다른 상태를 주거나, 내용 확인보다 접근 제어를 먼저 해 403 을 주면 실패
        table {
            row("PX-10 a") { fx ->
                val response = fx.get(fx.register(directUrl = "", manifestXml = ""))
                eq("상태", 404, response.status)
                eq("본문", "Not Found", response.bodyText)
                eq("CDN 기록 건수", 0, fx.cdn.requests().size)
            }
            row("PX-10 b") { fx ->
                val response = fx.get(fx.register(directUrl = "", manifestXml = "", allowedHost = otherHost))
                eq("상태", 404, response.status)
            }
        }
    }

    @Test
    fun `PX-11 허용 주소가 요청한 쪽의 주소와 다르면 403 Forbidden 이고 CDN 에 요청하지 않는다`() {
        // PX-11: 허용되지 않은 주소의 요청을 중계하거나, 문자열 비교가 아니라 이름 해석으로 localhost 를 통과시키면 실패
        table {
            for ((name, host) in listOf("PX-11 a" to otherHost, "PX-11 b" to "localhost")) {
                row(name) { fx ->
                    fx.cdn.onGet("/track.flac", body10)
                    val response = fx.get(fx.register(allowedHost = host))
                    eq("allowedHost <$host> 상태", 403, response.status)
                    eq("allowedHost <$host> 본문", "Forbidden", response.bodyText)
                    eq("CDN 기록 건수", 0, fx.cdn.requests().size)
                }
            }
        }
    }

    @Test
    fun `PX-12 허용 주소가 빈 값이거나 요청한 쪽의 주소와 같으면 통과한다`() {
        // PX-12: 제한이 없는 등록이나 127.0.0.1 을 허용한 등록의 요청을 막으면 실패
        table {
            for ((name, host) in listOf("PX-12 a" to "", "PX-12 b" to "127.0.0.1")) {
                row(name) { fx ->
                    fx.cdn.onGet("/track.flac", body10)
                    val response = fx.get(fx.register(allowedHost = host))
                    eq("allowedHost <$host> 상태", 200, response.status)
                    bytes("allowedHost <$host> 본문", body10, response.body)
                }
            }
        }
    }

    @Test
    fun `PX-13 등록되지 않은 토큰은 허용되지 않은 주소에서 와도 404 다`() {
        // PX-13: 등록 여부보다 접근 제어를 먼저 봐서 미등록 토큰에 403 을 주면 실패
        table {
            row("PX-13 a") { fx ->
                val registered = fx.register(allowedHost = otherHost)
                val response = fx.get(unregisteredPath)
                eq("미등록 토큰 상태", 404, response.status)
                eq("미등록 토큰 본문", "Not Found", response.bodyText)
                eq("등록된 주소 상태(대조)", 403, fx.get(registered).status)
            }
            row("PX-13 b") { fx ->
                val urls = (1..4).map { n -> fx.register(trackId = "$n", allowedHost = otherHost) }
                eq("밀려난 1번째 상태", 404, fx.get(urls[0]).status)
                eq("남아 있는 2번째 상태", 403, fx.get(urls[1]).status)
            }
        }
    }

    @Test
    fun `PX-14 토큰은 첫 점 앞까지이고 확장자가 다르거나 없어도 같은 곡을 찾는다`() {
        // PX-14: 확장자까지 맞아야 찾거나, 토큰을 마지막 점 앞까지로 보면 실패
        val cases = listOf("PX-14 a" to ".m4a", "PX-14 b" to "", "PX-14 c" to ".flac.bak")
        table {
            for ((name, suffix) in cases) {
                row(name) { fx ->
                    fx.cdn.onGet("/track.flac", body10)
                    val token = fx.tokenOf(fx.register())
                    val response = fx.get(fx.audioPath(token, suffix))
                    eq("접미사 <$suffix> 상태", 200, response.status)
                    eq("접미사 <$suffix> Content-Type", "audio/flac", response.header("Content-Type"))
                    bytes("접미사 <$suffix> 본문", body10, response.body)
                }
            }
        }
    }

    @Test
    fun `PX-15 HEAD 요청도 등록 여부와 접근 제어를 GET 과 똑같이 거친다`() {
        // PX-15: HEAD 가 미등록 · 빈 등록 · 허용되지 않은 주소 판정을 건너뛰거나 GET 과 다른 상태를 주면 실패
        table {
            row("PX-15 a") { fx ->
                eq("미등록 토큰 상태", 404, fx.head(unregisteredPath).status)
            }
            row("PX-15 b") { fx ->
                eq("빈 등록 상태", 404, fx.head(fx.register(directUrl = "", manifestXml = "")).status)
            }
            row("PX-15 c") { fx ->
                fx.cdn.onHead("/track.flac", CdnHeadReply(200, 10))
                eq("허용되지 않은 주소 상태", 403, fx.head(fx.register(allowedHost = otherHost)).status)
                eq("CDN 기록 건수", 0, fx.cdn.requests().size)
            }
            row("PX-15 d") { fx ->
                fx.cdn.onHead("/track.flac", CdnHeadReply(200, 10))
                eq("제한 없는 등록 상태", 200, fx.head(fx.register(allowedHost = "")).status)
            }
            row("PX-15 e") { fx ->
                fx.cdn.onHead("/track.flac", CdnHeadReply(200, 10))
                eq("127.0.0.1 허용 등록 상태", 200, fx.head(fx.register(allowedHost = "127.0.0.1")).status)
            }
            row("PX-15 f") { fx ->
                fx.register(allowedHost = otherHost)
                eq("미등록 토큰 + 허용되지 않은 주소 상태", 404, fx.head(unregisteredPath).status)
            }
        }
    }

    // ---------------------------------------------------------------- HEAD

    @Test
    fun `PX-16 단일 파일 HEAD 는 CDN 의 길이와 등록한 MIME 과 Accept-Ranges 를 알린다`() {
        // PX-16: CDN HEAD 의 Content-Length 를 그대로 알리지 않거나(0 포함), 타입 · Accept-Ranges 가 다르거나, 상태가 200 이 아니면 실패
        table {
            row("PX-16 a") { fx ->
                fx.cdn.onHead("/track.flac", CdnHeadReply(200, 123456))
                val response = fx.head(fx.register())
                eq("상태", 200, response.status)
                eq("Content-Length", "123456", response.header("Content-Length"))
                eq("Content-Type", "audio/flac", response.header("Content-Type"))
                eq("Accept-Ranges", "bytes", response.header("Accept-Ranges"))
                eq("본문 길이", 0, response.body.size)
                eq("CDN 기록", listOf(CdnRequest("HEAD", "/track.flac")), fx.cdn.requests())
            }
            row("PX-16 b") { fx ->
                fx.cdn.onHead("/track.flac", CdnHeadReply(200, 0))
                val response = fx.head(fx.register())
                eq("상태", 200, response.status)
                eq("Content-Length", "0", response.header("Content-Length"))
            }
        }
    }

    @Test
    fun `PX-17 단일 파일 HEAD 에서 CDN 에 연결하지 못하거나 길이가 없으면 Content-Length 없이 200 이다`() {
        // PX-17: 길이를 모를 때 Content-Length 를 0 등으로 알리거나 타입 · Accept-Ranges 를 빼면 실패. 오류 상태라도 길이가 있으면 그 길이를 알려야 한다
        table {
            row("PX-17 a") { fx ->
                val response = fx.head(fx.register(directUrl = FakeCdnServer.closedPortUrl("/track.flac")))
                eq("상태", 200, response.status)
                eq("Content-Length", null, response.header("Content-Length"))
                eq("Content-Type", "audio/flac", response.header("Content-Type"))
                eq("Accept-Ranges", "bytes", response.header("Accept-Ranges"))
            }
            row("PX-17 b") { fx ->
                fx.cdn.onHead("/track.flac", CdnHeadReply(200, null))
                val response = fx.head(fx.register())
                eq("상태", 200, response.status)
                eq("Content-Length", null, response.header("Content-Length"))
                eq("Content-Type", "audio/flac", response.header("Content-Type"))
                eq("Accept-Ranges", "bytes", response.header("Accept-Ranges"))
                eq("CDN 기록", listOf(CdnRequest("HEAD", "/track.flac")), fx.cdn.requests())
            }
            row("PX-17 c") { fx ->
                fx.cdn.onHead("/track.flac", CdnHeadReply(404, 55))
                val response = fx.head(fx.register())
                eq("상태", 200, response.status)
                eq("Content-Length", "55", response.header("Content-Length"))
            }
            row("PX-17 d") { fx ->
                fx.cdn.onHead("/track.flac", CdnHeadReply(500, 55))
                val response = fx.head(fx.register())
                eq("상태", 200, response.status)
                eq("Content-Length", "55", response.header("Content-Length"))
            }
            row("PX-17 e") { fx ->
                fx.cdn.onHead("/track.flac", CdnHeadReply(500, null))
                val response = fx.head(fx.register())
                eq("상태", 200, response.status)
                eq("Content-Length", null, response.header("Content-Length"))
                eq("Content-Type", "audio/flac", response.header("Content-Type"))
                eq("Accept-Ranges", "bytes", response.header("Accept-Ranges"))
            }
        }
    }

    @Test
    fun `PX-18 DASH HEAD 는 초기화 세그먼트와 모든 세그먼트의 길이 합계를 알린다`() {
        // PX-18: 합계에서 초기화 세그먼트나 세그먼트 하나가 빠지거나, 타입이 audio/mp4 가 아니거나, Accept-Ranges 를 알리면 실패
        table {
            row("PX-18") { fx ->
                val dash = fx.newDash(hasInit = true, segmentCount = 3)
                fx.cdn.onHead(dash.initPath!!, CdnHeadReply(200, 100))
                fx.cdn.onHead(dash.segmentPath(1), CdnHeadReply(200, 1000))
                fx.cdn.onHead(dash.segmentPath(2), CdnHeadReply(200, 2000))
                fx.cdn.onHead(dash.segmentPath(3), CdnHeadReply(200, 300))
                val response = fx.head(fx.register(directUrl = "", manifestXml = dash.manifest))
                eq("상태", 200, response.status)
                eq("Content-Length", "3400", response.header("Content-Length"))
                eq("Content-Type", "audio/mp4", response.header("Content-Type"))
                eq("Accept-Ranges", null, response.header("Accept-Ranges"))
                eq("본문 길이", 0, response.body.size)
                for (path in dash.allPaths) eq("CDN HEAD $path 건수", 1, fx.cdn.count("HEAD", path))
                eq("CDN HEAD 합계", 4, fx.cdn.count("HEAD"))
                eq("CDN GET 합계", 0, fx.cdn.count("GET"))
            }
        }
    }

    @Test
    fun `PX-19 DASH HEAD 에서 세그먼트 하나라도 길이를 모르면 Content-Length 없이 응답한다`() {
        // PX-19: 길이를 모르는 세그먼트를 빼고 합계를 알리거나(오류 상태의 길이를 더하는 것 포함), 해석 못 하는 매니페스트의 HEAD 에 200 이 아닌 응답을 주면 실패
        table {
            row("PX-19 a") { fx ->
                val dash = dashWithHeadLengths(fx)
                fx.cdn.onHead(dash.segmentPath(2), CdnHeadReply(200, null))
                val response = fx.head(fx.register(directUrl = "", manifestXml = dash.manifest))
                eq("상태", 200, response.status)
                eq("Content-Length", null, response.header("Content-Length"))
                eq("Content-Type", "audio/mp4", response.header("Content-Type"))
            }
            row("PX-19 b") { fx ->
                val dash = dashWithHeadLengths(fx)
                fx.cdn.onHead(dash.segmentPath(2), CdnHeadReply(404, 2000))
                val response = fx.head(fx.register(directUrl = "", manifestXml = dash.manifest))
                eq("상태", 200, response.status)
                eq("Content-Length", null, response.header("Content-Length"))
                eq("Content-Type", "audio/mp4", response.header("Content-Type"))
            }
            row("PX-19 c") { fx ->
                val dash = fx.newDash(hasInit = true, segmentCount = 3, base = FakeCdnServer.closedPortUrl(""))
                val response = fx.head(fx.register(directUrl = "", manifestXml = dash.manifest))
                eq("상태", 200, response.status)
                eq("Content-Length", null, response.header("Content-Length"))
                eq("Content-Type", "audio/mp4", response.header("Content-Type"))
            }
            row("PX-19 d") { fx ->
                val response = fx.head(fx.register(directUrl = "", manifestXml = "not xml"))
                eq("상태", 200, response.status)
                eq("Content-Length", null, response.header("Content-Length"))
                eq("CDN 기록 건수", 0, fx.cdn.requests().size)
            }
        }
    }

    /** PX-18 과 같은 HEAD 길이(100, 1000, 2000, 300)를 가진 `MPD3`. */
    private fun dashWithHeadLengths(fx: ProxyFixture): ProxyDash {
        val dash = fx.newDash(hasInit = true, segmentCount = 3)
        fx.cdn.onHead(dash.initPath!!, CdnHeadReply(200, 100))
        fx.cdn.onHead(dash.segmentPath(1), CdnHeadReply(200, 1000))
        fx.cdn.onHead(dash.segmentPath(2), CdnHeadReply(200, 2000))
        fx.cdn.onHead(dash.segmentPath(3), CdnHeadReply(200, 300))
        return dash
    }

    @Test
    fun `PX-20 주소가 만료된 HEAD 는 주소를 갱신하지 않고 CDN 응답의 길이를 알린다`() {
        // PX-20: HEAD 에서 재발급 함수를 부르거나 새 주소로 다시 요청하거나, CDN 401 · 403 응답의 길이를 알리지 않으면 실패
        table {
            for ((name, status) in listOf("PX-20 a" to 401, "PX-20 b" to 403)) {
                row(name) { fx ->
                    fx.cdn.onHead("/track.flac", CdnHeadReply(status, 77))
                    val spy = fx.refreshToNewUrl()
                    fx.proxy.streamRefresher = spy.function
                    val response = fx.head(fx.register())
                    eq("CDN $status 일 때 상태", 200, response.status)
                    eq("CDN $status 일 때 Content-Length", "77", response.header("Content-Length"))
                    eq("재발급 기록", emptyList<String>(), spy.calls.toList())
                    eq("CDN 기록", listOf(CdnRequest("HEAD", "/track.flac")), fx.cdn.requests())
                }
            }
        }
    }

    // ---------------------------------------------------------------- GET: 단일 파일 중계

    @Test
    fun `PX-21 CDN 이 200 이면 본문을 그대로 중계하고 타입은 등록한 MIME 이다`() {
        // PX-21: 본문이 달라지거나, CDN 의 octet-stream 을 그대로 내보내거나, 길이 · Accept-Ranges 가 빠지면 실패
        table {
            row("PX-21") { fx ->
                val reply = CdnGetReply(200, body10, mapOf("Content-Type" to "application/octet-stream"))
                fx.cdn.onGet("/track.flac", reply)
                val response = fx.get(fx.register())
                eq("상태", 200, response.status)
                eq("Content-Type", "audio/flac", response.header("Content-Type"))
                eq("Content-Length", "10", response.header("Content-Length"))
                eq("Accept-Ranges", "bytes", response.header("Accept-Ranges"))
                bytes("본문", body10, response.body)
                eq("CDN 기록", listOf(CdnRequest("GET", "/track.flac", null)), fx.cdn.requests())
            }
        }
    }

    @Test
    fun `PX-22 CDN 이 길이를 주지 않으면 길이 없이 chunked 로 본문 전체를 전달한다`() {
        // PX-22: 길이를 모르는데 Content-Length 를 지어내 알리거나 본문이 잘리면 실패
        table {
            row("PX-22") { fx ->
                fx.cdn.onGet("/track.flac", CdnGetReply(200, body10, chunked = true))
                val response = fx.get(fx.register())
                eq("상태", 200, response.status)
                eq("Content-Length", null, response.header("Content-Length"))
                eq("Transfer-Encoding", "chunked", response.header("Transfer-Encoding"))
                bytes("본문", body10, response.body)
            }
        }
    }

    @Test
    fun `PX-23 요청의 Range 헤더를 같은 값으로 CDN 요청에 넣는다`() {
        // PX-23: Range 를 CDN 에 넘기지 않거나 값을 바꿔 넘기면 실패
        table {
            row("PX-23") { fx ->
                fx.cdn.onGet("/track.flac", rangeReply("bytes 2-5/10", byteArrayOf(0x02, 0x03, 0x04, 0x05)))
                fx.get(fx.register(), range = "bytes=2-5")
                eq("CDN 이 받은 Range", listOf<String?>("bytes=2-5"), fx.cdn.requests().map { it.range })
            }
        }
    }

    private fun rangeReply(contentRange: String, body: ByteArray): CdnGetReply =
        CdnGetReply(206, body, mapOf("Content-Range" to contentRange))

    @Test
    fun `PX-24 CDN 이 206 과 Content-Range 를 주면 그대로 전달한다`() {
        // PX-24: 206 을 200 으로 바꾸거나 Content-Range · 길이를 빼거나 본문이 그 구간이 아니면 실패. Range 없이 요청했어도 CDN 의 206 은 206 으로 전달해야 한다
        table {
            row("PX-24 a") { fx ->
                fx.cdn.onGet("/track.flac", rangeReply("bytes 2-5/10", byteArrayOf(0x02, 0x03, 0x04, 0x05)))
                val response = fx.get(fx.register(), range = "bytes=2-5")
                eq("상태", 206, response.status)
                eq("Content-Range", "bytes 2-5/10", response.header("Content-Range"))
                eq("Content-Length", "4", response.header("Content-Length"))
                bytes("본문", byteArrayOf(0x02, 0x03, 0x04, 0x05), response.body)
            }
            row("PX-24 b") { fx ->
                fx.cdn.onGet("/track.flac", rangeReply("bytes 0-9/10", body10))
                val response = fx.get(fx.register())
                eq("상태", 206, response.status)
                eq("Content-Range", "bytes 0-9/10", response.header("Content-Range"))
                bytes("본문", body10, response.body)
                eq("CDN 이 받은 Range", listOf<String?>(null), fx.cdn.requests().map { it.range })
            }
        }
    }

    @Test
    fun `PX-25 Range 요청에 CDN 이 200 을 주면 Content-Range 없이 206 으로 전체를 전달한다`() {
        // PX-25: 이 경우 200 으로 응답하거나 Content-Range 를 지어내 붙이거나 본문을 잘라 보내면 실패 (관찰 사항 O-2 로 고정한 동작)
        table {
            row("PX-25") { fx ->
                fx.cdn.onGet("/track.flac", body10)
                val response = fx.get(fx.register(), range = "bytes=2-5")
                eq("상태", 206, response.status)
                eq("Content-Range", null, response.header("Content-Range"))
                bytes("본문", body10, response.body)
            }
        }
    }

    @Test
    fun `PX-26 CDN 이 401 이나 403 이면 재발급 함수를 한 번 불러 새 주소로 다시 요청한다`() {
        // PX-26: 재발급 함수를 부르지 않거나 곡 ID 가 다르거나 여러 번 부르거나, 다시 요청할 때 처음의 Range 를 잃으면 실패
        table {
            row("PX-26 a") { fx ->
                fx.cdn.onGet("/old.flac", CdnGetReply(401))
                fx.cdn.onGet("/new.flac", new10)
                val spy = fx.refreshToNewUrl()
                fx.proxy.streamRefresher = spy.function
                val response = fx.get(fx.register(directUrl = fx.cdn.url("/old.flac")))
                eq("상태", 200, response.status)
                bytes("본문", new10, response.body)
                eq("재발급 기록", listOf("101"), spy.calls.toList())
                val expected = listOf(CdnRequest("GET", "/old.flac", null), CdnRequest("GET", "/new.flac", null))
                eq("CDN 기록", expected, fx.cdn.requests())
            }
            row("PX-26 b") { fx ->
                fx.cdn.onGet("/old.flac", CdnGetReply(403))
                fx.cdn.onGet("/new.flac", rangeReply("bytes 2-5/10", byteArrayOf(0x12, 0x13, 0x14, 0x15)))
                val spy = fx.refreshToNewUrl()
                fx.proxy.streamRefresher = spy.function
                val response = fx.get(fx.register(directUrl = fx.cdn.url("/old.flac")), range = "bytes=2-5")
                eq("상태", 206, response.status)
                bytes("본문", byteArrayOf(0x12, 0x13, 0x14, 0x15), response.body)
                eq("재발급 기록", listOf("101"), spy.calls.toList())
                val expected = listOf(
                    CdnRequest("GET", "/old.flac", "bytes=2-5"),
                    CdnRequest("GET", "/new.flac", "bytes=2-5"),
                )
                eq("CDN 기록", expected, fx.cdn.requests())
            }
        }
    }

    @Test
    fun `PX-27 재발급 뒤 같은 토큰의 다음 요청은 갱신된 주소와 MIME 을 바로 쓴다`() {
        // PX-27: 다음 요청이 옛 주소를 다시 거치거나 재발급 함수를 또 부르거나, 갱신된 MIME 이 처음 MIME 으로 돌아가면 실패
        table {
            row("PX-27 a") { fx ->
                fx.cdn.onGet("/old.flac", CdnGetReply(401))
                fx.cdn.onGet("/new.flac", new10)
                val spy = fx.refreshToNewUrl()
                fx.proxy.streamRefresher = spy.function
                val url = fx.register(directUrl = fx.cdn.url("/old.flac"))
                fx.get(url)
                val second = fx.get(url)
                eq("두 번째 상태", 200, second.status)
                bytes("두 번째 본문", new10, second.body)
                eq("재발급 기록", listOf("101"), spy.calls.toList())
                val expected = listOf(
                    CdnRequest("GET", "/old.flac", null),
                    CdnRequest("GET", "/new.flac", null),
                    CdnRequest("GET", "/new.flac", null),
                )
                eq("CDN 기록", expected, fx.cdn.requests())
            }
            row("PX-27 b") { fx ->
                fx.cdn.onGet("/old.flac", CdnGetReply(403))
                fx.cdn.onGet("/new.flac", new10)
                val spy = fx.refreshToNewUrl(mimeType = "audio/mpeg")
                fx.proxy.streamRefresher = spy.function
                val url = fx.register(directUrl = fx.cdn.url("/old.flac"), mimeType = "audio/flac")
                fx.get(url)
                val second = fx.get(url)
                eq("두 번째 상태", 200, second.status)
                eq("두 번째 Content-Type", "audio/mpeg", second.header("Content-Type"))
                bytes("두 번째 본문", new10, second.body)
                eq("재발급 기록", listOf("101"), spy.calls.toList())
            }
        }
    }

    @Test
    fun `PX-28 재발급에 실패하면 403 Stream expired 다`() {
        // PX-28: 재발급 함수가 없거나 null · 예외 · 빈 값(키 누락, 문자열 아닌 값 포함)인데 403 Stream expired 가 아닌 응답을 주면 실패
        val answers: List<Pair<String, ((String) -> Map<String, Any?>?)?>> = listOf(
            "PX-28 a" to null,
            "PX-28 b" to { _: String -> null },
            "PX-28 c" to { _: String -> throw RuntimeException("재발급 실패") },
            "PX-28 d" to { _: String -> mapOf("directUrl" to "", "manifestXml" to "", "mimeType" to "audio/flac") },
            "PX-28 e" to { _: String -> emptyMap<String, Any?>() },
            "PX-28 f" to { _: String -> mapOf("directUrl" to 42, "manifestXml" to null, "mimeType" to "audio/flac") },
        )
        table {
            for ((name, answer) in answers) {
                row(name) { fx ->
                    fx.cdn.onGet("/old.flac", CdnGetReply(401))
                    val spy = answer?.let { ProxyRefresherSpy(it) }
                    if (spy != null) fx.proxy.streamRefresher = spy.function
                    val response = fx.get(fx.register(directUrl = fx.cdn.url("/old.flac")))
                    eq("상태", 403, response.status)
                    eq("본문", "Stream expired", response.bodyText)
                    if (spy != null) eq("재발급 기록", listOf("101"), spy.calls.toList())
                    eq("CDN 기록", listOf(CdnRequest("GET", "/old.flac", null)), fx.cdn.requests())
                }
            }
        }
    }

    @Test
    fun `PX-29 재발급으로 받은 주소도 401 이나 403 이면 다시 재발급하지 않고 500 CDN error 다`() {
        // PX-29: 재발급을 두 번 이상 하거나, 500 이 아니거나, 본문의 코드가 재발급 뒤 두 번째 응답의 코드가 아니면 실패
        val cases = listOf(
            Triple("PX-29 a", 401 to 401, "CDN error: 401"),
            Triple("PX-29 b", 403 to 403, "CDN error: 403"),
            Triple("PX-29 c", 401 to 403, "CDN error: 403"),
        )
        table {
            for ((name, statuses, body) in cases) {
                row(name) { fx ->
                    fx.cdn.onGet("/old.flac", CdnGetReply(statuses.first))
                    fx.cdn.onGet("/new.flac", CdnGetReply(statuses.second))
                    val spy = fx.refreshToNewUrl()
                    fx.proxy.streamRefresher = spy.function
                    val response = fx.get(fx.register(directUrl = fx.cdn.url("/old.flac")))
                    eq("상태", 500, response.status)
                    eq("본문", body, response.bodyText)
                    eq("재발급 기록", listOf("101"), spy.calls.toList())
                    val expected = listOf(CdnRequest("GET", "/old.flac", null), CdnRequest("GET", "/new.flac", null))
                    eq("CDN 기록", expected, fx.cdn.requests())
                }
            }
        }
    }

    @Test
    fun `PX-30 재발급 결과가 매니페스트뿐이면 DASH 중계로 응답한다`() {
        // PX-30: 매니페스트만 받은 재발급을 실패로 처리하거나, 처음 MIME(audio/flac)을 타입으로 내보내면 실패
        table {
            row("PX-30") { fx ->
                fx.cdn.onGet("/old.flac", CdnGetReply(401))
                val dash = fx.mpd3()
                val spy = ProxyRefresherSpy { mapOf("directUrl" to "", "manifestXml" to dash.manifest, "mimeType" to "") }
                fx.proxy.streamRefresher = spy.function
                val url = fx.register(directUrl = fx.cdn.url("/old.flac"), mimeType = "audio/flac")
                val response = fx.get(url)
                eq("상태", 200, response.status)
                bytes("본문", ascii("INITAAAABBCCCCCC"), response.body)
                eq("Content-Type", "audio/mp4", response.header("Content-Type"))
                eq("Accept-Ranges", null, response.header("Accept-Ranges"))
                eq("재발급 기록", listOf("101"), spy.calls.toList())
            }
        }
    }

    @Test
    fun `PX-31 재발급 결과에 MIME 이 있으면 그 MIME 을 쓰고 비어 있으면 처음 MIME 을 유지한다`() {
        // PX-31: 재발급 MIME 을 무시하거나, 빈 MIME(키 누락 포함)으로 처음 MIME 을 덮어쓰면 실패
        val cases: List<Triple<String, (ProxyFixture) -> Map<String, Any?>, String>> = listOf(
            Triple(
                "PX-31 a",
                { fx: ProxyFixture -> mapOf("directUrl" to fx.cdn.url("/new.flac"), "manifestXml" to "", "mimeType" to "audio/mpeg") },
                "audio/mpeg",
            ),
            Triple(
                "PX-31 b",
                { fx: ProxyFixture -> mapOf("directUrl" to fx.cdn.url("/new.flac"), "manifestXml" to "", "mimeType" to "") },
                "audio/flac",
            ),
            Triple("PX-31 c", { fx: ProxyFixture -> mapOf("directUrl" to fx.cdn.url("/new.flac")) }, "audio/flac"),
        )
        table {
            for ((name, answer, contentType) in cases) {
                row(name) { fx ->
                    fx.cdn.onGet("/old.flac", CdnGetReply(403))
                    fx.cdn.onGet("/new.flac", new10)
                    val spy = ProxyRefresherSpy { answer(fx) }
                    fx.proxy.streamRefresher = spy.function
                    val url = fx.register(directUrl = fx.cdn.url("/old.flac"), mimeType = "audio/flac")
                    val response = fx.get(url)
                    eq("상태", 200, response.status)
                    eq("Content-Type", contentType, response.header("Content-Type"))
                    bytes("본문", new10, response.body)
                }
            }
        }
    }

    @Test
    fun `PX-32 CDN 의 그 밖의 실패는 500 CDN error 이고 재발급하지 않는다`() {
        // PX-32: CDN 404 · 500 을 그대로 내보내거나 본문의 코드가 다르거나, 만료가 아닌데 재발급 함수를 부르면 실패
        table {
            for ((name, status) in listOf("PX-32 a" to 404, "PX-32 b" to 500)) {
                row(name) { fx ->
                    fx.cdn.onGet("/track.flac", CdnGetReply(status))
                    val spy = fx.refreshToNewUrl()
                    fx.proxy.streamRefresher = spy.function
                    val response = fx.get(fx.register())
                    eq("CDN $status 일 때 상태", 500, response.status)
                    eq("CDN $status 일 때 본문", "CDN error: $status", response.bodyText)
                    eq("재발급 기록", emptyList<String>(), spy.calls.toList())
                    eq("CDN 기록 건수", 1, fx.cdn.requests().size)
                }
            }
        }
    }

    @Test
    fun `PX-33 CDN 에 연결하지 못하면 500 이고 본문이 Proxy error 로 시작한다`() {
        // PX-33: 연결 실패를 500 으로 답하지 않거나(응답 없음 · 다른 상태) 본문이 Proxy error: 로 시작하지 않으면 실패
        table {
            row("PX-33") { fx ->
                val response = fx.get(fx.register(directUrl = FakeCdnServer.closedPortUrl("/track.flac")))
                eq("상태", 500, response.status)
                truth("본문", response.bodyText.startsWith("Proxy error:"), "Proxy error: 로 시작하지 않음: <${response.bodyText}>")
            }
        }
    }

    // ---------------------------------------------------------------- GET: DASH 중계

    @Test
    fun `PX-34 유효한 매니페스트는 초기화 세그먼트와 세그먼트들을 순서대로 이어 붙여 전달한다`() {
        // PX-34: 세그먼트 순서가 바뀌거나 빠지거나, 타입이 audio/mp4 가 아니거나, Accept-Ranges 를 알리거나, 초기화 세그먼트 없는 매니페스트를 거부하면 실패
        table {
            row("PX-34 a") { fx ->
                val dash = fx.mpd3()
                val response = fx.get(fx.register(directUrl = "", manifestXml = dash.manifest))
                eq("상태", 200, response.status)
                bytes("본문", ascii("INITAAAABBCCCCCC"), response.body)
                eq("Content-Type", "audio/mp4", response.header("Content-Type"))
                eq("Accept-Ranges", null, response.header("Accept-Ranges"))
                for (path in dash.allPaths) eq("CDN GET $path 건수", 1, fx.cdn.count("GET", path))
            }
            row("PX-34 b") { fx ->
                val dash = fx.mpd3NoInit()
                val response = fx.get(fx.register(directUrl = "", manifestXml = dash.manifest))
                eq("상태", 200, response.status)
                bytes("본문", ascii("AAAABBCCCCCC"), response.body)
                eq("Content-Type", "audio/mp4", response.header("Content-Type"))
                val initRequests = fx.cdn.requests().filter { it.path.endsWith("/init.mp4") }
                eq("CDN 의 init.mp4 요청", emptyList<CdnRequest>(), initRequests)
            }
        }
    }

    @Test
    fun `PX-35 모든 세그먼트의 길이를 알면 Content-Length 는 합계다`() {
        // PX-35: 합계(4 + 4 + 2 + 6 = 16)가 아닌 길이를 알리거나 길이를 알리지 않으면 실패
        table {
            row("PX-35") { fx ->
                val dash = fx.mpd3()
                val response = fx.get(fx.register(directUrl = "", manifestXml = dash.manifest))
                eq("상태", 200, response.status)
                eq("Content-Length", "16", response.header("Content-Length"))
                bytes("본문", ascii("INITAAAABBCCCCCC"), response.body)
            }
        }
    }

    @Test
    fun `PX-36 세그먼트 하나라도 길이를 모르면 길이 없이 chunked 로 본문 전체를 전달한다`() {
        // PX-36: 길이를 모르는 세그먼트가 있는데 Content-Length 를 알리거나(오류 상태의 길이를 더하는 것 포함) 본문이 잘리면 실패
        val unknownHeads = listOf("PX-36 a" to CdnHeadReply(200, null), "PX-36 b" to CdnHeadReply(404, 2))
        table {
            for ((name, head) in unknownHeads) {
                row(name) { fx ->
                    val dash = fx.mpd3()
                    fx.cdn.onHead(dash.segmentPath(2), head)
                    val response = fx.get(fx.register(directUrl = "", manifestXml = dash.manifest))
                    eq("상태", 200, response.status)
                    eq("Content-Length", null, response.header("Content-Length"))
                    eq("Transfer-Encoding", "chunked", response.header("Transfer-Encoding"))
                    bytes("본문", ascii("INITAAAABBCCCCCC"), response.body)
                }
            }
        }
    }

    @Test
    fun `PX-37 매니페스트를 해석하지 못하면 500 Invalid DASH manifest 다`() {
        // PX-37: 해석 못 하는 매니페스트에 500 이 아닌 응답을 주거나 본문이 다르거나 CDN 에 요청하면 실패
        val cases = listOf("PX-37 a" to "not xml", "PX-37 b" to "<MPD><Period/></MPD>")
        table {
            for ((name, manifest) in cases) {
                row(name) { fx ->
                    val response = fx.get(fx.register(directUrl = "", manifestXml = manifest))
                    eq("상태", 500, response.status)
                    eq("본문", "Invalid DASH manifest", response.bodyText)
                    eq("CDN 기록 건수", 0, fx.cdn.requests().size)
                }
            }
        }
    }

    @Test
    fun `PX-38 세그먼트 길이 조회는 매니페스트당 한 번만 하고 모르는 결과는 다시 조회한다`() {
        // PX-38: 요청마다 세그먼트 HEAD 를 다시 보내거나, 길이를 모른 결과를 기억해 다음 요청에도 길이를 알리지 못하면 실패
        table {
            row("PX-38 a") { fx ->
                val dash = fx.mpd3()
                val url = fx.register(directUrl = "", manifestXml = dash.manifest)
                eq("HEAD 응답 Content-Length", "16", fx.head(url).header("Content-Length"))
                val response = fx.get(url)
                eq("GET 응답 Content-Length", "16", response.header("Content-Length"))
                bytes("GET 본문", ascii("INITAAAABBCCCCCC"), response.body)
                for (path in dash.allPaths) eq("CDN HEAD $path 건수", 1, fx.cdn.count("HEAD", path))
                eq("CDN HEAD 합계", 4, fx.cdn.count("HEAD"))
            }
            row("PX-38 b") { fx ->
                val dash = fx.mpd3()
                val url = fx.register(directUrl = "", manifestXml = dash.manifest)
                for (attempt in 1..2) {
                    val response = fx.get(url)
                    eq("${attempt}번째 상태", 200, response.status)
                    eq("${attempt}번째 Content-Length", "16", response.header("Content-Length"))
                    bytes("${attempt}번째 본문", ascii("INITAAAABBCCCCCC"), response.body)
                }
                eq("CDN HEAD 합계", 4, fx.cdn.count("HEAD"))
                eq("CDN GET 합계", 8, fx.cdn.count("GET"))
            }
            row("PX-38 c") { fx ->
                val dash = fx.mpd3()
                fx.cdn.onHead(dash.segmentPath(2), CdnHeadReply(200, null), CdnHeadReply(200, 2))
                val url = fx.register(directUrl = "", manifestXml = dash.manifest)
                val first = fx.head(url)
                eq("1번째 상태", 200, first.status)
                eq("1번째 Content-Length", null, first.header("Content-Length"))
                eq("2번째 Content-Length", "16", fx.head(url).header("Content-Length"))
                eq("2번째 뒤 CDN HEAD 2.mp4 건수", 2, fx.cdn.count("HEAD", dash.segmentPath(2)))
                val headsAfterSecond = fx.cdn.count("HEAD")
                eq("3번째 Content-Length", "16", fx.head(url).header("Content-Length"))
                eq("3번째 뒤 CDN HEAD 합계", headsAfterSecond, fx.cdn.count("HEAD"))
            }
        }
    }

    // ---------------------------------------------------------------- 속성 테스트

    /** PX-02 의 판정 순서를 옮긴 참조 표. */
    private fun referenceExtension(mime: String): String = when {
        "flac" in mime -> "flac"
        "mp4" in mime || "m4a" in mime || "aac" in mime -> "m4a"
        "mpeg" in mime -> "mp3"
        else -> "m4a"
    }

    @Test
    fun `P-PX-1 몇 번을 등록하든 주소는 정해진 형식이고 토큰이 서로 다르다`() {
        // P-PX-1: 어떤 등록에서든 주소 형식이 깨지거나 토큰이 겹치면 실패
        ProxyFixture().use { fx ->
            val pattern = Regex("""^http://127\.0\.0\.1:${fx.proxy.listeningPort}/audio/([0-9a-f]{16})\.(flac|m4a|mp3)$""")
            val seenTokens = HashSet<String>()
            property {
                checkAll(pbt(100), ProxyGenerators.registrationMimes) { mimes ->
                    mimes.forEachIndexed { index, mime ->
                        val url = fx.register(
                            trackId = "$index",
                            directUrl = "http://cdn.example.test/track.flac",
                            mimeType = mime,
                        )
                        val match = pattern.matchEntire(url)
                        assertNotNull("주소 형식이 아님: <$url> (MIME <$mime>)", match)
                        assertTrue("토큰이 겹침: <$url>", seenTokens.add(match!!.groupValues[1]))
                    }
                }
            }
        }
    }

    @Test
    fun `P-PX-2 어떤 MIME 문자열이든 확장자가 참조 표와 같다`() {
        // P-PX-2: 어떤 MIME 에서든 확장자가 PX-02 의 순서로 정한 참조 표와 다르면 실패
        ProxyFixture().use { fx ->
            property {
                checkAll(pbt(100), ProxyGenerators.mimeString) { mime ->
                    val url = fx.register(directUrl = "http://cdn.example.test/track.flac", mimeType = mime)
                    assertEquals("MIME <$mime> 의 확장자", referenceExtension(mime), extensionOf(url))
                }
            }
        }
    }

    @Test
    fun `P-PX-3 어떤 등록 순서에서도 최근 3개 모델에 있는 주소만 살아 있다`() {
        // P-PX-3: 등록할 때마다 "최근 3개" 모델과 비교해, 모델에 있는 주소가 404 이거나 밀려난 주소가 404 가 아니면 실패
        property {
            checkAll(pbt(25), ProxyGenerators.registrationCount) { count ->
                ProxyFixture().use { fx ->
                    assertEquals("등록 0회: 미등록 토큰의 상태", 404, fx.get(unregisteredPath).status)
                    val all = mutableListOf<String>()
                    val model = ArrayDeque<String>()
                    for (n in 1..count) {
                        val url = fx.register(trackId = "$n", directUrl = fx.cdn.url("/t$n.flac"), allowedHost = otherHost)
                        all += url
                        model.addLast(url)
                        if (model.size > 3) model.removeFirst()
                        all.forEachIndexed { index, registered ->
                            val expected = if (registered in model) 403 else 404
                            val actual = fx.get(registered).status
                            assertEquals("등록 ${n}회 뒤 ${index + 1}번째 주소의 상태", expected, actual)
                        }
                    }
                    assertEquals("CDN 기록 건수", 0, fx.cdn.requests().size)
                }
            }
        }
    }

    @Test
    fun `P-PX-4 어떤 허용 주소든 빈 값이거나 요청한 쪽의 주소와 같을 때만 통과한다`() {
        // P-PX-4: 빈 값 · 127.0.0.1 이 아닌 허용 주소에서 통과시키거나 CDN 에 요청하거나, 빈 값 · 127.0.0.1 을 막으면 실패
        ProxyFixture().use { fx ->
            fx.cdn.onGet("/track.flac", body10)
            property {
                checkAll(pbt(50), ProxyGenerators.allowedHost) { host ->
                    fx.cdn.takeRequests()
                    val response = fx.get(fx.register(allowedHost = host))
                    if (host == "" || host == "127.0.0.1") {
                        assertEquals("allowedHost <$host> 상태", 200, response.status)
                        assertArrayEquals("allowedHost <$host> 본문", body10, response.body)
                    } else {
                        assertEquals("allowedHost <$host> 상태", 403, response.status)
                        assertEquals("allowedHost <$host> 본문", "Forbidden", response.bodyText)
                        assertEquals("allowedHost <$host> CDN 기록 건수", 0, fx.cdn.requests().size)
                    }
                }
            }
        }
    }

    @Test
    fun `P-PX-5 어떤 Range 값이든 CDN 이 받은 Range 가 요청의 값과 같다`() {
        // P-PX-5: 어떤 Range 값에서든 CDN 이 받은 Range 가 보낸 값과 글자 하나라도 다르거나 빠지면 실패
        ProxyFixture().use { fx ->
            fx.cdn.onGet("/track.flac", body10)
            val url = fx.register()
            property {
                checkAll(pbt(50), ProxyGenerators.rangeValue) { range ->
                    fx.cdn.takeRequests()
                    fx.get(url, range = range)
                    assertEquals("CDN 이 받은 Range", listOf<String?>(range), fx.cdn.requests().map { it.range })
                }
            }
        }
    }

    @Test
    fun `P-PX-6 어떤 바이트 내용이든 GET 으로 받은 본문이 CDN 의 내용과 같다`() {
        // P-PX-6 (단일 파일): 어떤 길이 · 내용에서든 중계한 본문이 CDN 의 내용과 한 바이트라도 다르면 실패
        ProxyFixture().use { fx ->
            val counter = AtomicInteger(0)
            property {
                checkAll(pbt(25), ProxyGenerators.byteContent) { content ->
                    val path = "/content/${counter.incrementAndGet()}.flac"
                    fx.cdn.onGet(path, content)
                    val response = fx.get(fx.register(directUrl = fx.cdn.url(path)))
                    assertArrayEquals("길이 ${content.size} 의 본문", content, response.body)
                }
            }
        }
    }

    @Test
    fun `P-PX-6 어떤 DASH 내용이든 본문이 세그먼트를 순서대로 이은 것과 같고 길이가 합계와 같다`() {
        // P-PX-6 (DASH): 어떤 세그먼트 개수 · 내용에서든 본문이 이어 붙인 것과 다르거나 Content-Length 가 합계와 다르면 실패
        ProxyFixture().use { fx ->
            property {
                checkAll(pbt(25), ProxyGenerators.dashContent) { content ->
                    val dash = fx.prepareDash(content.init, content.segments)
                    val url = fx.register(directUrl = "", manifestXml = dash.manifest, mimeType = "audio/mp4")
                    val response = fx.get(url)
                    val expected = (listOfNotNull(content.init) + content.segments).fold(ByteArray(0)) { acc, part -> acc + part }
                    assertArrayEquals("$content 의 본문", expected, response.body)
                    assertEquals("$content 의 Content-Length", expected.size.toString(), response.header("Content-Length"))
                }
            }
        }
    }
}
