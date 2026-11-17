package com.example.tidal_connect_lite

import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import okio.Buffer
import java.io.Closeable
import java.net.InetAddress
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/** 가짜 CDN이 받은 요청 한 건. [range]는 `Range` 헤더 값이고 없으면 null이다. */
data class CdnRequest(val method: String, val path: String, val range: String? = null)

/**
 * 가짜 CDN의 GET 응답.
 *
 * [chunked]가 true면 `Content-Length` 없이 chunked로 본문을 보낸다. false면 본문 길이를 `Content-Length`로 싣는다.
 */
class CdnGetReply(
    val status: Int = 200,
    val body: ByteArray = ByteArray(0),
    val headers: Map<String, String> = emptyMap(),
    val chunked: Boolean = false,
)

/** 가짜 CDN의 HEAD 응답. 본문은 쓰지 않는다. [contentLength]가 null이면 `Content-Length` 헤더를 싣지 않는다. */
class CdnHeadReply(val status: Int = 200, val contentLength: Long? = null)

/**
 * 프록시 테스트용 가짜 CDN. `MockWebServer`를 감싸며, 테스트는 이 클래스만 쓴다.
 *
 * - `127.0.0.1`의 임시 포트로 뜬다(고정 포트 없음).
 * - 경로마다 GET·HEAD 응답을 따로 정한다. 응답을 여러 개 주면 n번째 요청에 n번째 응답을 주고, 다 쓰면 마지막 응답을 반복한다.
 * - HEAD를 따로 정하지 않은 경로는 GET 응답의 상태와 본문 길이를 `Content-Length`로 알린다.
 * - 정하지 않은 경로는 404로 답한다. 받은 요청은 모두 도착 순서대로 기록한다.
 */
class FakeCdnServer : Closeable {
    private val server = MockWebServer()
    private val getReplies = ConcurrentHashMap<String, List<CdnGetReply>>()
    private val headReplies = ConcurrentHashMap<String, List<CdnHeadReply>>()
    private val getCounts = ConcurrentHashMap<String, AtomicInteger>()
    private val headCounts = ConcurrentHashMap<String, AtomicInteger>()
    private val recorded = Collections.synchronizedList(mutableListOf<CdnRequest>())

    init {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val method = request.method ?: ""
                val path = request.path ?: ""
                recorded.add(CdnRequest(method, path, request.getHeader("Range")))
                return if (method == "HEAD") headResponse(path) else getResponse(path)
            }
        }
        server.start(InetAddress.getByName(LOOPBACK), 0)
    }

    /** 이 서버의 [path]를 가리키는 주소. */
    fun url(path: String): String = "http://$LOOPBACK:${server.port}$path"

    /** [path]의 GET 응답을 순서대로 정한다. */
    fun onGet(path: String, vararg replies: CdnGetReply) {
        require(replies.isNotEmpty()) { "응답이 하나 이상 필요하다" }
        getReplies[path] = replies.toList()
        getCounts[path] = AtomicInteger(0)
    }

    /** [path]의 GET 응답을 상태 200과 [body]로 정한다. */
    fun onGet(path: String, body: ByteArray) = onGet(path, CdnGetReply(body = body))

    /** [path]의 HEAD 응답을 순서대로 정한다. */
    fun onHead(path: String, vararg replies: CdnHeadReply) {
        require(replies.isNotEmpty()) { "응답이 하나 이상 필요하다" }
        headReplies[path] = replies.toList()
        headCounts[path] = AtomicInteger(0)
    }

    /** 지금까지 받은 요청(도착 순서). */
    fun requests(): List<CdnRequest> = synchronized(recorded) { recorded.toList() }

    /** 지금까지의 기록을 돌려주고 비운다. */
    fun takeRequests(): List<CdnRequest> = synchronized(recorded) {
        val copy = recorded.toList()
        recorded.clear()
        copy
    }

    /** [method]로 받은 요청 수. [path]를 주면 그 경로만 센다. */
    fun count(method: String, path: String? = null): Int =
        requests().count { it.method == method && (path == null || it.path == path) }

    override fun close() {
        server.shutdown()
    }

    private fun getResponse(path: String): MockResponse {
        val replies = getReplies[path] ?: return MockResponse().setResponseCode(404)
        val index = getCounts.getValue(path).getAndIncrement().coerceAtMost(replies.size - 1)
        val reply = replies[index]
        val response = MockResponse().setResponseCode(reply.status)
        val buffer = Buffer().write(reply.body)
        if (reply.chunked) response.setChunkedBody(buffer, 4) else response.setBody(buffer)
        reply.headers.forEach { (name, value) -> response.setHeader(name, value) }
        return response
    }

    private fun headResponse(path: String): MockResponse {
        val replies = headReplies[path]
        val reply = if (replies != null) {
            replies[headCounts.getValue(path).getAndIncrement().coerceAtMost(replies.size - 1)]
        } else {
            // HEAD를 따로 정하지 않았으면 GET 응답의 상태와 본문 길이를 알린다(순서는 소비하지 않는다).
            val get = getReplies[path]?.first() ?: return MockResponse().setResponseCode(404)
            CdnHeadReply(get.status, get.body.size.toLong())
        }
        // 본문은 쓰지 않는다. MockResponse는 기본으로 Content-Length: 0을 달고 있어 값만 바꾸거나 지운다.
        val response = MockResponse().setResponseCode(reply.status)
        if (reply.contentLength == null) {
            response.removeHeader("Content-Length")
        } else {
            response.setHeader("Content-Length", reply.contentLength.toString())
        }
        return response
    }

    companion object {
        private const val LOOPBACK = "127.0.0.1"

        /**
         * 연결이 바로 거부되는 주소. 서버를 하나 띄워 포트를 받은 뒤 곧바로 닫는다.
         * 기다리지 않고 연결 실패를 만들 때 쓴다.
         */
        fun closedPortUrl(path: String): String {
            val temp = MockWebServer()
            temp.start(InetAddress.getByName(LOOPBACK), 0)
            val port = temp.port
            temp.shutdown()
            return "http://$LOOPBACK:$port$path"
        }
    }
}
