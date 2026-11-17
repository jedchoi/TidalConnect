package com.example.tidal_connect_lite

import android.util.Log
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.io.InputStream

/**
 * DASH 세그먼트를 순서대로 이어 붙여 하나의 fMP4 스트림처럼 읽게 한다.
 *
 * 다음 세그먼트는 앞 세그먼트를 다 읽었을 때만 받는다. 스피커가 연결을 끊어 [close]가 호출되면
 * 지금 받고 있는 응답만 닫고 남은 세그먼트는 요청하지 않는다.
 * 세그먼트 하나라도 받지 못하면 거기서 스트림을 끝낸다.
 *
 * @param startSegment 초기화 세그먼트 다음에 읽기 시작할 세그먼트 번호(0부터)
 */
class DashSegmentInputStream(
    private val client: OkHttpClient,
    private val manifest: DashManifest,
    private val startSegment: Int = 0,
) : InputStream() {

    private var nextIndex = -1 // -1: 초기화 세그먼트 차례
    private var current: Response? = null
    private var currentStream: InputStream? = null
    private var finished = false
    @Volatile private var closed = false

    override fun read(): Int {
        val one = ByteArray(1)
        val n = read(one, 0, 1)
        return if (n <= 0) -1 else one[0].toInt() and 0xff
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        while (true) {
            if (closed || finished) return -1
            val stream = currentStream ?: openNext() ?: return -1
            val n = stream.read(b, off, len)
            if (n >= 0) return n
            closeCurrent() // 이 세그먼트를 다 읽음 -> 다음으로
        }
    }

    /** 다음 세그먼트를 연다. 더 없거나 실패하면 스트림을 끝내고 null. */
    private fun openNext(): InputStream? {
        val url: String = when {
            nextIndex == -1 && manifest.initializationUrl != null -> manifest.initializationUrl
            nextIndex == -1 -> {
                nextIndex = startSegment
                return openNext()
            }
            nextIndex < manifest.segmentCount -> manifest.segmentUrl(nextIndex)
            else -> {
                finished = true
                return null
            }
        }
        val label = if (nextIndex == -1) "init" else "#${manifest.startNumber + nextIndex}"
        nextIndex = if (nextIndex == -1) startSegment else nextIndex + 1
        return try {
            val response = client.newCall(Request.Builder().url(url).build()).execute()
            val body = response.body
            if (!response.isSuccessful || body == null) {
                Log.w(TAG, "DASH 세그먼트 $label 실패: HTTP ${response.code} - 스트림 종료")
                response.close()
                finished = true
                null
            } else {
                current = response
                body.byteStream().also { currentStream = it }
            }
        } catch (e: IOException) {
            Log.w(TAG, "DASH 세그먼트 $label 예외: ${e.message} - 스트림 종료")
            finished = true
            null
        }
    }

    private fun closeCurrent() {
        try {
            current?.close()
        } catch (_: Exception) {
        }
        current = null
        currentStream = null
    }

    override fun close() {
        closed = true
        closeCurrent()
    }

    companion object {
        private const val TAG = "TidalStreamProxy"
    }
}
