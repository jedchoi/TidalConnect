package com.example.tidal_connect_lite

import android.util.Log
import fi.iki.elonen.NanoHTTPD
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.InputStream
import java.io.SequenceInputStream
import java.net.NetworkInterface
import java.util.Collections
import java.util.Enumeration
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.regex.Pattern

/**
 * 로컬 HTTP 스트림 프록시 서버 (NanoHTTPD 기반)
 *
 * UPnP/DLNA 렌더러(JBL Authentics 300 등)는 긴 URL을 처리하지 못하므로,
 * http://<LAN_IP>:8765/audio/<trackId>.mp4 형태의 표준적인 짧은 URL(40~50자)을 제공합니다.
 *
 * 지연 로딩(Lazy Chunk Stream)을 적용하여 전체 곡(100+ 세그먼트)이 스피커 재생 속도에 맞춰
 * 끊김 없이 자연스럽게 스트리밍되도록 지원합니다.
 */
class TidalStreamProxyServer : NanoHTTPD(PROXY_PORT) {

    companion object {
        const val PROXY_PORT = 8765
        private const val TAG = "TidalStreamProxy"

        fun getLanIpAddress(): String {
            try {
                val interfaces = NetworkInterface.getNetworkInterfaces()
                while (interfaces.hasMoreElements()) {
                    val networkInterface = interfaces.nextElement()
                    if (networkInterface.isLoopback || !networkInterface.isUp) continue

                    val addresses = networkInterface.inetAddresses
                    while (addresses.hasMoreElements()) {
                        val addr = addresses.nextElement()
                        if (addr.isLoopbackAddress) continue
                        val hostAddress = addr.hostAddress ?: continue
                        if (!hostAddress.contains(':')) {
                            Log.i(TAG, "LAN IP: $hostAddress (interface: ${networkInterface.displayName})")
                            return hostAddress
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get LAN IP: ${e.message}")
            }
            return "127.0.0.1"
        }

        /**
         * 50자 이내의 짧고 표준적인 DLNA 전용 미디어 URL을 생성합니다.
         * 예: http://192.168.45.63:8765/audio/189569817.mp4
         */
        fun buildShortAudioUrl(trackId: String): String {
            val lanIp = getLanIpAddress()
            val cleanId = trackId.ifEmpty { "current" }
            return "http://$lanIp:$PROXY_PORT/audio/$cleanId.mp4"
        }
    }

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(20, TimeUnit.SECONDS)
        .build()

    // 트랙별 스트림 정보 캐시 (trackId -> Direct URL or Manifest)
    data class StreamInfo(val directUrl: String = "", val manifestXml: String = "")
    private val streamRegistry = ConcurrentHashMap<String, StreamInfo>()

    @Volatile
    private var lastTrackId: String = "current"

    fun registerTrackStream(trackId: String, directUrl: String, manifestXml: String = "") {
        val id = trackId.ifEmpty { "current" }
        lastTrackId = id
        streamRegistry[id] = StreamInfo(directUrl, manifestXml)
        Log.i(TAG, "🎵 트랙 스트림 등록 완료: ID=$id, directUrl=${directUrl.take(40)}..., manifestLen=${manifestXml.length}")
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
     * 표준 DLNA 엔드포인트: /audio/<trackId>.mp4
     */
    private fun handleAudioRequest(session: IHTTPSession, uri: String): Response {
        val trackId = uri.removePrefix("/audio/").removeSuffix(".mp4").ifEmpty { lastTrackId }
        val info = streamRegistry[trackId] ?: streamRegistry[lastTrackId]

        if (info == null || (info.directUrl.isEmpty() && info.manifestXml.isEmpty())) {
            Log.e(TAG, "등록된 트랙 음원 정보 없음: ID=$trackId")
            return newFixedLengthResponse(Response.Status.NOT_FOUND, "text/plain", "Track media not ready")
        }

        return if (info.directUrl.isNotEmpty()) {
            Log.i(TAG, "🚀 Direct CDN 스트림 중계 시작: TrackID=$trackId")
            proxyDirectCdn(session, info.directUrl)
        } else {
            Log.i(TAG, "🚀 DASH 매니페스트 세그먼트 중계 시작: TrackID=$trackId")
            proxyDashManifest(session, info.manifestXml)
        }
    }

    /**
     * TIDAL Direct CDN URL을 스피커로 투명하게 릴레이 (Range 및 Content-Type 완벽 지원)
     */
    private fun proxyDirectCdn(session: IHTTPSession, cdnUrl: String): Response {
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

            if (responseBody == null || !response.isSuccessful) {
                Log.e(TAG, "TIDAL CDN 오류 응답: ${response.code}")
                return newFixedLengthResponse(Response.Status.INTERNAL_ERROR, "text/plain", "CDN error: ${response.code}")
            }

            val contentType = response.header("Content-Type") ?: "audio/mp4"
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
     */
    private fun proxyDashManifest(session: IHTTPSession, manifestXml: String): Response {
        return try {
            val initPattern = Pattern.compile("initialization=\"([^\"]+)\"", Pattern.CASE_INSENSITIVE)
            val initMatcher = initPattern.matcher(manifestXml)
            val initUrl = if (initMatcher.find()) initMatcher.group(1)?.replace("&amp;", "&") else null

            val mediaPattern = Pattern.compile("media=\"([^\"]+)\"", Pattern.CASE_INSENSITIVE)
            val mediaMatcher = mediaPattern.matcher(manifestXml)
            val mediaTemplate = if (mediaMatcher.find()) mediaMatcher.group(1)?.replace("&amp;", "&") else null

            val startNumPattern = Pattern.compile("startNumber=\"(\\d+)\"", Pattern.CASE_INSENSITIVE)
            val startMatcher = startNumPattern.matcher(manifestXml)
            val startNumber = if (startMatcher.find()) startMatcher.group(1)?.toIntOrNull() ?: 1 else 1

            // SegmentTimeline 내의 모든 r="숫자" 값 합산
            var totalSegments = 0
            val repeatPattern = Pattern.compile("r=\"(\\d+)\"", Pattern.CASE_INSENSITIVE)
            val repeatMatcher = repeatPattern.matcher(manifestXml)
            while (repeatMatcher.find()) {
                val r = repeatMatcher.group(1)?.toIntOrNull() ?: 0
                totalSegments += (r + 1)
            }

            val segmentCount = if (totalSegments > 10) totalSegments + 5 else 120
            val endNumber = startNumber + segmentCount

            Log.i(TAG, "DASH 지연 스트리밍 시작 - init: ${initUrl != null}, 세그먼트: $startNumber..$endNumber (총 $segmentCount 개)")

            // 요청에 맞춰 하나씩 다운로드하여 공급하는 Lazy Enumeration
            val lazyEnumeration = object : Enumeration<InputStream> {
                private var currentStep = if (!initUrl.isNullOrEmpty()) 0 else 1
                private var currentSegNum = startNumber

                override fun hasMoreElements(): Boolean {
                    return currentStep == 0 || (currentStep == 1 && currentSegNum <= endNumber)
                }

                override fun nextElement(): InputStream {
                    if (currentStep == 0) {
                        currentStep = 1
                        try {
                            val initReq = Request.Builder().url(initUrl!!).build()
                            val initResp = httpClient.newCall(initReq).execute()
                            if (initResp.isSuccessful && initResp.body != null) {
                                return initResp.body!!.byteStream()
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "DASH init 세그먼트 다운로드 실패: ${e.message}")
                        }
                    }

                    if (currentStep == 1 && currentSegNum <= endNumber && !mediaTemplate.isNullOrEmpty()) {
                        val num = currentSegNum++
                        val segUrl = mediaTemplate.replace("\$Number\$", num.toString())
                        try {
                            val segReq = Request.Builder().url(segUrl).build()
                            val segResp = httpClient.newCall(segReq).execute()
                            if (segResp.isSuccessful && segResp.body != null) {
                                return segResp.body!!.byteStream()
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "DASH 세그먼트 #$num 다운로드 실패/종료: ${e.message}")
                        }
                    }

                    // 더 이상 없거나 실패 시 빈 스트림 반환
                    return java.io.ByteArrayInputStream(ByteArray(0))
                }
            }

            val combinedStream = SequenceInputStream(lazyEnumeration)

            val proxyResponse = newChunkedResponse(Response.Status.OK, "audio/mp4", combinedStream)
            proxyResponse.addHeader("Accept-Ranges", "bytes")
            proxyResponse.addHeader("Access-Control-Allow-Origin", "*")
            proxyResponse.addHeader("Connection", "keep-alive")
            proxyResponse
        } catch (e: Exception) {
            Log.e(TAG, "DASH 프록시 예외: ${e.message}", e)
            newFixedLengthResponse(Response.Status.INTERNAL_ERROR, "text/plain", "DASH error: ${e.message}")
        }
    }
}
