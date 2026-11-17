package com.example.tidal_connect_lite

import fi.iki.elonen.NanoHTTPD
import okhttp3.ConnectionPool
import okhttp3.Headers
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.Closeable
import java.util.Collections
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/** 프록시가 돌려준 응답. 본문은 끝까지 읽은 바이트다. */
class ProxyResponse(val status: Int, private val headers: Headers, val body: ByteArray) {
    /** 헤더 값. 없으면 null. 이름은 대소문자를 가리지 않는다. */
    fun header(name: String): String? = headers[name]

    val bodyText: String get() = String(body, Charsets.UTF_8)

    /** 실패 메시지에 넣을 요약: 상태, 모든 헤더, 본문 길이(32바이트 이하면 16진수도). */
    fun describe(): String {
        val headerText = headers.joinToString(", ") { (name, value) -> "$name: $value" }
        val bodyDetail = if (body.size <= 32) " [${proxyHex(body)}]" else ""
        return "$status {$headerText} 본문 ${body.size}바이트$bodyDetail"
    }
}

/** 바이트 열을 `00 01 02` 꼴로 적는다. */
fun proxyHex(bytes: ByteArray): String = bytes.joinToString(" ") { "%02x".format(it) }

/** DASH 준비 결과: 매니페스트 원문과 가짜 CDN에서의 경로. */
class ProxyDash(val manifest: String, val initPath: String?, val segmentPaths: List<String>) {
    /** [number]번 세그먼트(1부터)의 경로. */
    fun segmentPath(number: Int): String = segmentPaths[number - 1]

    /** 초기화 세그먼트(있으면)와 모든 세그먼트의 경로. */
    val allPaths: List<String> get() = listOfNotNull(initPath) + segmentPaths
}

/**
 * `streamRefresher`에 넣을 함수와 그 호출 기록.
 * 받은 `trackId`를 [calls]에 남기고 [answer]의 결과(맵, null, 예외)로 답한다.
 */
class ProxyRefresherSpy(private val answer: (String) -> Map<String, Any?>?) {
    val calls: MutableList<String> = CopyOnWriteArrayList()

    val function: (String) -> Map<String, Any?>? = { trackId ->
        calls.add(trackId)
        answer(trackId)
    }
}

/**
 * 프록시(`TidalStreamProxyServer`)와 가짜 CDN을 함께 띄우고 닫는 묶음.
 *
 * - 둘 다 `127.0.0.1`의 임시 포트를 쓴다. 테스트에 포트 번호를 적지 않는다.
 * - 프록시가 CDN에 쓰는 클라이언트와 테스트가 프록시에 쓰는 클라이언트 모두 타임아웃이 2초다.
 * - 테스트 클라이언트는 `Accept-Encoding: identity`로 보내 압축이 끼지 않게 하고, 연결을 재사용하지 않는다.
 * - 서버 스레드는 데몬으로 띄운다. [close]가 프록시와 가짜 CDN을 모두 닫는다.
 */
class ProxyFixture : Closeable {
    val cdn = FakeCdnServer()

    private val cdnClient: OkHttpClient = shortTimeoutClient().build()
    private val testClient: OkHttpClient = shortTimeoutClient()
        .retryOnConnectionFailure(false)
        .connectionPool(ConnectionPool(0, 1, TimeUnit.MILLISECONDS))
        .build()

    val proxy = TidalStreamProxyServer("127.0.0.1", port = 0, httpClient = cdnClient)

    private val exchangeLog = Collections.synchronizedList(mutableListOf<String>())

    init {
        try {
            proxy.start(NanoHTTPD.SOCKET_READ_TIMEOUT, true)
        } catch (e: Exception) {
            cdn.close()
            throw e
        }
    }

    /** 프록시의 주소(`http://127.0.0.1:<열린 포트>`). */
    val baseUrl: String get() = "http://127.0.0.1:${proxy.listeningPort}"

    /** 지금까지 프록시와 주고받은 요청·응답 요약(실패 메시지용). */
    fun exchanges(): List<String> = synchronized(exchangeLog) { exchangeLog.toList() }

    /**
     * "기본 등록" 값으로 `registerTrackStream`을 부른다. 바꿀 인자만 이름으로 넘긴다.
     * 기본 등록: 곡 `101`, 직접 주소는 가짜 CDN의 `/track.flac`, 매니페스트 없음, 허용 주소 제한 없음, `audio/flac`.
     */
    fun register(
        trackId: String = "101",
        directUrl: String = cdn.url("/track.flac"),
        manifestXml: String = "",
        allowedHost: String = "",
        mimeType: String = "audio/flac",
    ): String = proxy.registerTrackStream(trackId, directUrl, manifestXml, allowedHost, mimeType)

    /** 프록시에 GET을 보낸다. [urlOrPath]는 등록이 돌려준 주소 전체이거나 `/`로 시작하는 경로다. */
    fun get(urlOrPath: String, range: String? = null): ProxyResponse = send("GET", urlOrPath, range)

    /** 프록시에 HEAD를 보낸다. */
    fun head(urlOrPath: String): ProxyResponse = send("HEAD", urlOrPath, null)

    /** 등록이 돌려준 주소에서 토큰(`/audio/` 뒤, 첫 `.` 앞)을 꺼낸다. */
    fun tokenOf(url: String): String =
        Regex("/audio/([^./]+)").find(url)?.groupValues?.get(1) ?: error("토큰을 찾을 수 없는 주소: $url")

    /** `/audio/<토큰><접미사>` 경로. */
    fun audioPath(token: String, suffix: String = ""): String = "/audio/$token$suffix"

    /**
     * DASH 매니페스트만 만든다(가짜 CDN에 내용은 등록하지 않는다).
     * 주소는 [base] 아래의 고유 경로를 가리킨다. 세그먼트 번호는 1부터다.
     */
    fun newDash(hasInit: Boolean, segmentCount: Int, base: String = cdn.url("")): ProxyDash {
        val prefix = "/dash/${dashCounter.incrementAndGet()}"
        val initPath = if (hasInit) "$prefix/init.mp4" else null
        val segmentPaths = (1..segmentCount).map { "$prefix/$it.mp4" }
        val initAttribute = if (initPath != null) """ initialization="$base$initPath"""" else ""
        val timeline = (1..segmentCount).joinToString("") { """<S d="1"/>""" }
        val manifest = """<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static">
  <Period>
    <AdaptationSet contentType="audio" mimeType="audio/mp4">
      <Representation id="FLAC,44100,16" codecs="flac" bandwidth="1000000" audioSamplingRate="44100">
        <SegmentTemplate timescale="44100"$initAttribute media="$base$prefix/${'$'}Number${'$'}.mp4" startNumber="1">
          <SegmentTimeline>$timeline</SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>"""
        return ProxyDash(manifest, initPath, segmentPaths)
    }

    /**
     * DASH 매니페스트를 만들고 가짜 CDN에 그 내용을 등록한다.
     * [init]이 null이면 초기화 세그먼트가 없는 매니페스트다.
     */
    fun prepareDash(init: ByteArray?, segments: List<ByteArray>): ProxyDash {
        val dash = newDash(hasInit = init != null, segmentCount = segments.size)
        if (init != null) cdn.onGet(dash.initPath!!, init)
        segments.forEachIndexed { index, bytes -> cdn.onGet(dash.segmentPaths[index], bytes) }
        return dash
    }

    override fun close() {
        try {
            proxy.stop()
        } finally {
            cdn.close()
            cdnClient.connectionPool.evictAll()
            cdnClient.dispatcher.executorService.shutdown()
            testClient.connectionPool.evictAll()
            testClient.dispatcher.executorService.shutdown()
        }
    }

    private fun send(method: String, urlOrPath: String, range: String?): ProxyResponse {
        val url = if (urlOrPath.startsWith("http://")) urlOrPath else baseUrl + urlOrPath
        val builder = Request.Builder().url(url).method(method, null).header("Accept-Encoding", "identity")
        if (range != null) builder.header("Range", range)
        val label = "$method ${url.substringAfter(baseUrl)}" + (range?.let { " (Range: $it)" } ?: "")
        try {
            testClient.newCall(builder.build()).execute().use { response ->
                val result = ProxyResponse(response.code, response.headers, response.body?.bytes() ?: ByteArray(0))
                exchangeLog.add("$label → ${result.describe()}")
                return result
            }
        } catch (e: Exception) {
            exchangeLog.add("$label → 예외 ${e.javaClass.simpleName}: ${e.message}")
            throw e
        }
    }

    private fun shortTimeoutClient(): OkHttpClient.Builder = OkHttpClient.Builder()
        .connectTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .writeTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)

    companion object {
        private const val TIMEOUT_SECONDS = 2L

        /** 매니페스트 경로에 넣는 고유 값. 같은 서버를 반복에 재사용해도 매니페스트 원문이 겹치지 않게 한다. */
        private val dashCounter = AtomicInteger(0)
    }
}
