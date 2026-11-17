package com.example.tidal_connect_lite

import android.util.Log
import fi.iki.elonen.NanoHTTPD
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.io.PrintWriter
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import java.net.Inet4Address
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * 로컬 HTTP 스트림 프록시 서버 (NanoHTTPD 기반)
 *
 * UPnP/DLNA 렌더러(JBL Authentics 300 등)는 긴 URL을 처리하지 못하므로,
 * http://<LAN_IP>:8765/audio/<trackId>.mp4 형태의 표준적인 짧은 URL(40~50자)을 제공합니다.
 *
 * 지연 로딩(Lazy Chunk Stream)을 적용하여 전체 곡(100+ 세그먼트)이 스피커 재생 속도에 맞춰
 * 끊김 없이 자연스럽게 스트리밍되도록 지원합니다.
 */
/**
 * @param boundHost 서버가 바인딩할 Wi-Fi 주소. 다른 인터페이스에서는 접근할 수 없다.
 * @param port 바인딩할 포트. 운영은 기본값([PROXY_PORT])을 쓴다. 테스트는 0을 넘겨 빈 포트를 쓴다.
 * @param httpClient TIDAL CDN에 요청을 보내는 클라이언트. 테스트는 타임아웃이 짧은 것을 넘긴다.
 */
class TidalStreamProxyServer(
    val boundHost: String,
    private val port: Int = PROXY_PORT,
    private val httpClient: OkHttpClient = defaultHttpClient(),
) : NanoHTTPD(boundHost, port) {

    companion object {
        const val PROXY_PORT = 8765
        private const val MAX_REGISTERED = 3
        private const val TAG = "TidalStreamProxy"

        /** [dashSegmentLengths]에서 초기화 세그먼트를 가리키는 번호. */
        private const val INIT_SEGMENT = -1

        /**
         * Wi-Fi(또는 유선 LAN) 네트워크의 IPv4 주소. 없으면 null.
         * 모바일 데이터나 VPN 인터페이스의 주소는 스피커가 접근할 수 없으므로 고르지 않는다.
         */
        fun getWifiIpv4Address(context: Context): String? {
            val cm = context.getSystemService(ConnectivityManager::class.java) ?: return null
            @Suppress("DEPRECATION")
            for (network in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(network) ?: continue
                val isLan = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
                if (!isLan || caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                val address = cm.getLinkProperties(network)?.linkAddresses
                    ?.map { it.address }
                    ?.firstOrNull { it is Inet4Address && !it.isLoopbackAddress }
                if (address != null) return address.hostAddress
            }
            return null
        }

        /** 운영에서 쓰는 CDN 클라이언트 설정. */
        fun defaultHttpClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .build()
    }

    /** 등록된 곡 하나. 토큰은 곡마다 새로 만드는 추측 불가능한 경로 조각이다. */
    data class StreamInfo(
        val trackId: String,
        val directUrl: String = "",
        val manifestXml: String = "",
        /** 이 주소에 접근할 수 있는 스피커 IP. 비어 있으면 제한하지 않는다. */
        val allowedHost: String = "",
        /** 실제 오디오 MIME. DASH는 fMP4이므로 audio/mp4. */
        val mimeType: String = "audio/mp4",
        /** DASH 곡에서 초기화 세그먼트 다음에 보낼 첫 세그먼트 번호(0부터). */
        val startSegment: Int = 0,
    )

    // 토큰 -> 곡 정보. 최근 MAX_REGISTERED곡만 남긴다(삽입 순서 유지).
    private val streamRegistry = object : LinkedHashMap<String, StreamInfo>() {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, StreamInfo>?): Boolean =
            size > MAX_REGISTERED
    }
    private val secureRandom = SecureRandom()

    /**
     * 곡을 등록하고 스피커가 접근할 주소를 돌려준다.
     * 예: http://192.168.0.10:8765/audio/3f9c0a1b2d4e5f60.mp4
     */
    fun registerTrackStream(
        trackId: String,
        directUrl: String,
        manifestXml: String,
        allowedHost: String,
        mimeType: String,
    ): String = registerTrackStreamAt(trackId, directUrl, manifestXml, allowedHost, mimeType, 0L).url

    /**
     * 곡을 등록하고 주소와 시작 오프셋을 돌려준다.
     *
     * DASH 곡은 [startPositionMs]가 속한 세그먼트부터 보내고, 그 세그먼트의 시작 시각이 시작 오프셋이다.
     * 단일 파일 곡은 [startPositionMs]를 쓰지 않는다(시작 오프셋 0).
     */
    fun registerTrackStreamAt(
        trackId: String,
        directUrl: String,
        manifestXml: String,
        allowedHost: String,
        mimeType: String,
        startPositionMs: Long,
    ): RegisteredStream {
        val token = newToken()
        val isDash = manifestXml.isNotEmpty() && directUrl.isEmpty()
        val mime = if (isDash) "audio/mp4" else mimeType.ifEmpty { "audio/mp4" }
        // 위치가 0 이하이면 항상 처음부터이므로 매니페스트를 해석하지 않는다.
        val manifest = if (isDash && startPositionMs > 0) DashManifest.parse(manifestXml) else null
        val startSegment = manifest?.segmentIndexAt(startPositionMs) ?: 0
        val startOffsetMs = manifest?.segmentStartMs(startSegment) ?: 0L
        synchronized(streamRegistry) {
            streamRegistry[token] = StreamInfo(trackId, directUrl, manifestXml, allowedHost, mime, startSegment)
        }
        Log.i(
            TAG,
            "트랙 스트림 등록: TrackID=$trackId, mime=$mime, direct=${directUrl.isNotEmpty()}, " +
                "시작 세그먼트=$startSegment, 시작 오프셋=${startOffsetMs}ms",
        )
        return RegisteredStream("http://$boundHost:$servingPort/audio/$token.${extensionFor(mime)}", startOffsetMs)
    }

    /** 스피커에 알려줄 포트. 서버가 떠 있으면 실제로 열린 포트이고, 아니면 생성할 때 받은 포트다. */
    private val servingPort: Int
        get() = listeningPort.takeIf { it > 0 } ?: port

    /** 렌더러가 확장자로 형식을 추측하는 경우가 있어 MIME에 맞는 확장자를 붙인다. */
    private fun extensionFor(mime: String): String = when {
        mime.contains("flac") -> "flac"
        mime.contains("mp4") || mime.contains("m4a") || mime.contains("aac") -> "m4a"
        mime.contains("mpeg") -> "mp3"
        else -> "m4a"
    }

    /**
     * CDN 서명 주소가 만료(401·403)되었을 때 같은 곡의 새 스트림 정보를 받아오는 함수.
     * 결과는 directUrl, manifestXml, mimeType을 담은 맵이며, 실패하면 null.
     */
    @Volatile
    var streamRefresher: ((trackId: String) -> Map<String, Any?>?)? = null

    /** 만료된 주소를 새 주소로 바꿔 등록부를 갱신한다. */
    private fun refreshStream(token: String, info: StreamInfo): StreamInfo? {
        val fresh = try {
            streamRefresher?.invoke(info.trackId)
        } catch (e: Exception) {
            Log.w(TAG, "스트림 재요청 실패: ${e.message}")
            null
        } ?: return null
        val updated = info.copy(
            directUrl = fresh["directUrl"] as? String ?: "",
            manifestXml = fresh["manifestXml"] as? String ?: "",
            mimeType = (fresh["mimeType"] as? String)?.ifEmpty { null } ?: info.mimeType,
        )
        if (updated.directUrl.isEmpty() && updated.manifestXml.isEmpty()) return null
        synchronized(streamRegistry) { streamRegistry[token] = updated }
        Log.i(TAG, "만료된 스트림 주소를 갱신: TrackID=${info.trackId}")
        return updated
    }

    private fun newToken(): String {
        val bytes = ByteArray(8)
        secureRandom.nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    override fun serve(session: IHTTPSession): Response {
        val uri = session.uri
        val method = session.method

        Log.i(TAG, "📥 스피커 프록시 요청 수신: $method $uri from ${session.remoteIpAddress}")

        return when {
            uri.startsWith("/audio/") -> handleAudioRequest(session, uri)
            uri == "/ping"             -> newFixedLengthResponse(Response.Status.OK, "text/plain", "pong")
            else                       -> newFixedLengthResponse(Response.Status.NOT_FOUND, "text/plain", "Not Found")
        }
    }

    /**
     * DLNA 엔드포인트: /audio/<토큰>.<확장자>
     */
    private fun handleAudioRequest(session: IHTTPSession, uri: String): Response {
        val token = uri.removePrefix("/audio/").substringBefore('.')
        val info = synchronized(streamRegistry) { streamRegistry[token] }

        if (info == null || (info.directUrl.isEmpty() && info.manifestXml.isEmpty())) {
            Log.w(TAG, "등록되지 않은 경로 요청 거부")
            return newFixedLengthResponse(Response.Status.NOT_FOUND, "text/plain", "Not Found")
        }
        if (info.allowedHost.isNotEmpty() && info.allowedHost != session.remoteIpAddress) {
            Log.w(TAG, "허용되지 않은 기기의 요청 거부: ${session.remoteIpAddress}")
            return newFixedLengthResponse(Response.Status.FORBIDDEN, "text/plain", "Forbidden")
        }
        val trackId = info.trackId

        if (session.method == Method.HEAD) return headResponse(info)

        return if (info.directUrl.isNotEmpty()) {
            Log.i(TAG, "🚀 Direct CDN 스트림 중계 시작: TrackID=$trackId")
            proxyDirectCdn(session, token, info, allowRefresh = true)
        } else {
            Log.i(TAG, "🚀 DASH 매니페스트 세그먼트 중계 시작: TrackID=$trackId")
            proxyDashManifest(session, info.manifestXml, info.startSegment)
        }
    }

    /**
     * TIDAL Direct CDN URL을 스피커로 투명하게 릴레이 (Range 및 Content-Type 완벽 지원)
     */
    /** HEAD 요청에는 본문 없이 형식과 길이만 알려준다. */
    private fun headResponse(info: StreamInfo): Response {
        var length = -1L
        if (info.directUrl.isEmpty() && info.manifestXml.isNotEmpty()) {
            DashManifest.parse(info.manifestXml)?.let {
                length = dashLength(info.manifestXml, it, info.startSegment) ?: -1L
            }
        }
        if (info.directUrl.isNotEmpty()) {
            try {
                httpClient.newCall(Request.Builder().url(info.directUrl).head().build()).execute().use {
                    length = it.header("Content-Length")?.toLongOrNull() ?: -1L
                }
            } catch (e: Exception) {
                Log.w(TAG, "HEAD 길이 조회 실패: ${e.message}")
            }
        }
        // 본문은 보내지 않지만 Content-Length는 실제 파일 길이로 알린다. 길이를 모르면 알리지 않는다(0으로 알리면
        // 렌더러가 빈 파일로 여긴다).
        val response = if (length >= 0) {
            newFixedLengthResponse(Response.Status.OK, info.mimeType, ByteArrayInputStream(ByteArray(0)), length)
        } else {
            // NanoHTTPD는 HEAD 응답이면 길이를 모르는(chunked) 응답에도 Content-Length를 써서 "-1"이 나간다.
            // 그 헤더를 쓰는 메서드만 막아 헤더 없이 보낸다. 본문 스트림이 비어 있어 본문은 그대로 0바이트다.
            object : Response(Response.Status.OK, info.mimeType, ByteArrayInputStream(ByteArray(0)), -1L) {
                override fun sendContentLengthHeaderIfNotAlreadyPresent(pw: PrintWriter, size: Long) = size
            }
        }
        if (info.directUrl.isNotEmpty()) response.addHeader("Accept-Ranges", "bytes")
        return response
    }

    private fun proxyDirectCdn(session: IHTTPSession, token: String, info: StreamInfo, allowRefresh: Boolean): Response {
        val cdnUrl = info.directUrl
        val mimeType = info.mimeType
        if (cdnUrl.isEmpty()) {
            return newFixedLengthResponse(Response.Status.BAD_REQUEST, "text/plain", "CDN URL required")
        }

        return try {
            val requestBuilder = Request.Builder().url(cdnUrl).get()

            val rangeHeader = session.headers["range"]
            if (!rangeHeader.isNullOrEmpty()) {
                requestBuilder.header("Range", rangeHeader)
                Log.i(TAG, "스피커 Range 요청: $rangeHeader")
            }

            val response = httpClient.newCall(requestBuilder.build()).execute()
            val responseBody = response.body

            if ((response.code == 401 || response.code == 403) && allowRefresh) {
                // 오래 일시정지한 뒤처럼 서명 주소가 만료된 경우: 새 주소를 받아 한 번만 재시도
                response.close()
                val refreshed = refreshStream(token, info)
                    ?: return newFixedLengthResponse(Response.Status.FORBIDDEN, "text/plain", "Stream expired")
                return if (refreshed.directUrl.isNotEmpty()) {
                    proxyDirectCdn(session, token, refreshed, allowRefresh = false)
                } else {
                    proxyDashManifest(session, refreshed.manifestXml)
                }
            }

            if (responseBody == null || !response.isSuccessful) {
                Log.e(TAG, "TIDAL CDN 오류 응답: ${response.code}")
                return newFixedLengthResponse(Response.Status.INTERNAL_ERROR, "text/plain", "CDN error: ${response.code}")
            }

            // CDN이 octet-stream으로 보내는 경우가 있어 등록된 MIME을 우선한다.
            val contentType = mimeType.ifEmpty { response.header("Content-Type") ?: "audio/mp4" }
            val contentLength = response.header("Content-Length")?.toLongOrNull() ?: -1L
            val contentRange = response.header("Content-Range")

            Log.i(TAG, "✅ CDN 연결 성공: HTTP ${response.code}, MIME=$contentType, Size=$contentLength")

            val inputStream: InputStream = responseBody.byteStream()
            val status = if (response.code == 206 || !rangeHeader.isNullOrEmpty()) {
                Response.Status.PARTIAL_CONTENT
            } else {
                Response.Status.OK
            }

            val proxyResponse = if (contentLength > 0) {
                newFixedLengthResponse(status, contentType, inputStream, contentLength)
            } else {
                newChunkedResponse(status, contentType, inputStream)
            }

            if (!contentRange.isNullOrEmpty()) {
                proxyResponse.addHeader("Content-Range", contentRange)
            }
            proxyResponse.addHeader("Accept-Ranges", "bytes")
            proxyResponse.addHeader("Access-Control-Allow-Origin", "*")
            proxyResponse.addHeader("Connection", "keep-alive")
            proxyResponse
        } catch (e: Exception) {
            Log.e(TAG, "Direct CDN 프록시 예외: ${e.message}", e)
            newFixedLengthResponse(Response.Status.INTERNAL_ERROR, "text/plain", "Proxy error: ${e.message}")
        }
    }

    /**
     * DASH 매니페스트 세그먼트를 Lazy Enumeration으로 연결하여
     * 전체 세그먼트를 스피커 재생 흐름에 맞춰 실시간 스트리밍합니다.
     *
     * 초기화 세그먼트 다음에 [startSegment]번째(0부터) 세그먼트부터 보낸다.
     */
    private fun proxyDashManifest(session: IHTTPSession, manifestXml: String, startSegment: Int = 0): Response {
        return try {
            val manifest = DashManifest.parse(manifestXml)
            if (manifest == null) {
                Log.e(TAG, "DASH 매니페스트 해석 실패: ${DashManifest.lastError}")
                return newFixedLengthResponse(Response.Status.INTERNAL_ERROR, "text/plain", "Invalid DASH manifest")
            }
            val length = dashLength(manifestXml, manifest, startSegment)
            Log.i(
                TAG,
                "DASH 중계 시작 - init: ${manifest.initializationUrl != null}, 세그먼트 ${manifest.segmentCount}개, " +
                    "시작 세그먼트 $startSegment, 길이 $length",
            )
            // 이어 붙인 스트림은 바이트 위치로 탐색할 수 없으므로 Accept-Ranges를 알리지 않는다.
            // 길이를 알면 Content-Length를 보낸다. 많은 렌더러가 길이 없는 chunked 응답을 재생하지 않는다.
            val stream = DashSegmentInputStream(httpClient, manifest, startSegment)
            val proxyResponse = if (length != null) {
                newFixedLengthResponse(Response.Status.OK, "audio/mp4", stream, length)
            } else {
                newChunkedResponse(Response.Status.OK, "audio/mp4", stream)
            }
            proxyResponse.addHeader("Access-Control-Allow-Origin", "*")
            proxyResponse.addHeader("Connection", "keep-alive")
            proxyResponse
        } catch (e: Exception) {
            Log.e(TAG, "DASH 프록시 예외: ${e.message}", e)
            newFixedLengthResponse(Response.Status.INTERNAL_ERROR, "text/plain", "DASH error: ${e.message}")
        }
    }

    /**
     * 매니페스트별로 알아낸 세그먼트 길이. 안쪽 키는 세그먼트 번호(0부터)이고 초기화 세그먼트는 [INIT_SEGMENT]다.
     * 길이를 모르는 세그먼트는 저장하지 않아 다음 요청에서 다시 조회한다.
     */
    private val dashSegmentLengths =
        ConcurrentHashMap<String, ConcurrentHashMap<Int, Long>>()

    /**
     * 초기화 세그먼트와 [startSegment]번째부터의 세그먼트 바이트 수를 더한다. 그 범위에 길이를 모르는 것이 있으면 null.
     * 길이는 세그먼트마다 HEAD 요청으로 구하며, 한 번 알아낸 길이는 같은 매니페스트의 다른 요청에도 다시 쓴다.
     */
    private fun dashLength(manifestXml: String, manifest: DashManifest, startSegment: Int): Long? {
        val known = dashSegmentLengths.getOrPut(manifestXml) { ConcurrentHashMap() }
        val wanted = buildList {
            if (manifest.initializationUrl != null) add(INIT_SEGMENT)
            for (i in startSegment until manifest.segmentCount) add(i)
        }
        val missing = wanted.filter { !known.containsKey(it) }
        if (missing.isNotEmpty()) {
            val pool = Executors.newFixedThreadPool(8)
            try {
                val futures = missing.map { index ->
                    val url = if (index == INIT_SEGMENT) manifest.initializationUrl!! else manifest.segmentUrl(index)
                    index to pool.submit<Long?> {
                        try {
                            httpClient.newCall(Request.Builder().url(url).head().build()).execute().use {
                                if (it.isSuccessful) it.header("Content-Length")?.toLongOrNull() else null
                            }
                        } catch (e: Exception) {
                            null
                        }
                    }
                }
                for ((index, future) in futures) {
                    future.get(10, TimeUnit.SECONDS)?.let { known[index] = it }
                }
            } catch (e: Exception) {
                Log.w(TAG, "DASH 길이 계산 실패: ${e.message}")
                return null
            } finally {
                pool.shutdownNow()
            }
        }
        var total = 0L
        for (index in wanted) {
            total += known[index] ?: return null.also {
                Log.w(TAG, "DASH 세그먼트 길이를 알 수 없어 chunked로 보냄")
            }
        }
        return total
    }
}
