package com.example.tidal_connect_lite

import android.app.Application
import android.content.pm.ApplicationInfo
import android.content.Context
import android.util.Log
import com.tidal.sdk.auth.CredentialsProvider
import com.tidal.sdk.eventproducer.EventProducer
import com.tidal.sdk.eventproducer.model.EventsConfig
import com.tidal.sdk.player.Player
import com.tidal.sdk.player.common.model.MediaProduct
import com.tidal.sdk.player.common.model.ProductType
import com.tidal.sdk.player.common.model.AssetPresentation
import com.tidal.sdk.player.playbackengine.model.Event
import com.tidal.sdk.player.playbackengine.model.PlaybackContext
import com.tidal.sdk.player.playbackengine.model.PlaybackState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class TidalPlayerManager(
    private val context: Context,
    private val credentialsProvider: CredentialsProvider?
) {
    private var tidalPlayer: Player? = null
    private var isCurrentlyPlaying = false
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    /**
     * 재생 이벤트를 Flutter로 내보내는 콜백. 메인 스레드에서 호출된다.
     * 형식: {type: state|position|transition|ended|error, ...}
     */
    var onEvent: ((Map<String, Any?>) -> Unit)? = null

    private var eventsJob: Job? = null
    private var positionJob: Job? = null

    /**
     * TIDAL Player는 앱 전체에서 하나만 생성한다.
     */
    fun initializePlayer() {
        // 이미 생성되어 있으면 절대 다시 생성하지 않는다.
        if (tidalPlayer != null) {
            Log.i("TidalPlayerManager", "TIDAL Player already initialized. Skip initialization.")
            return
        }

        if (credentialsProvider == null) {
            Log.e("TidalPlayerManager", "Cannot initialize TIDAL Player: credentialsProvider is null")
            return
        }

        try {
            val app = context.applicationContext as? Application
            if (app == null) {
                Log.e("TidalPlayerManager", "Application context is not available")
                return
            }

            val eventsConfig = EventsConfig(
                maxDiskUsageBytes = 10 * 1024 * 1024,
                blockedConsentCategories = emptySet(),
                appVersion = "1.0.0"
            )

            val eventProducer = EventProducer.getInstance(
                credentialsProvider = credentialsProvider,
                config = eventsConfig,
                context = app,
                coroutineScope = scope
            )

            tidalPlayer = Player(
                application = app,
                credentialsProvider = credentialsProvider,
                eventSender = eventProducer.eventSender,
                isDebuggable = (app.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            )

            Log.i("TidalPlayerManager", "TIDAL Official Player SDK initialized successfully")
            collectEvents()
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Failed to initialize TIDAL Player: ${e.message}", e)
            tidalPlayer = null
        }
    }

    /** SDK 이벤트를 Flutter용 맵으로 바꿔 내보낸다. */
    private fun collectEvents() {
        val player = tidalPlayer ?: return
        eventsJob?.cancel()
        eventsJob = scope.launch {
            player.playbackEngine.events.collect { event ->
                when (event) {
                    is Event.PlaybackStateChange -> {
                        emit(mapOf("type" to "state", "state" to event.playbackState.name))
                        if (event.playbackState == PlaybackState.PLAYING) startPositionTicker() else stopPositionTicker()
                    }
                    is Event.MediaProductTransition -> emit(transitionMap(event.playbackContext))
                    is Event.MediaProductEnded -> emit(
                        mapOf("type" to "ended", "trackId" to event.playbackContext.productId)
                    )
                    is Event.StreamingPrivilegesRevoked -> emit(
                        mapOf(
                            "type" to "error",
                            "code" to "PRIVILEGES_REVOKED",
                            "message" to "다른 기기(${event.privilegedClientDisplayName ?: "알 수 없음"})에서 재생을 시작해 이 기기의 재생이 중단되었습니다."
                        )
                    )
                    is Event.Error -> emit(
                        mapOf("type" to "error", "code" to event.errorCode, "message" to (event::class.simpleName ?: "Error"))
                    )
                    else -> Unit
                }
            }
        }
    }

    private fun transitionMap(context: PlaybackContext): Map<String, Any?> {
        val track = context as? PlaybackContext.Track
        return mapOf(
            "type" to "transition",
            "trackId" to context.productId,
            "durationMs" to (context.duration * 1000).toLong(),
            "preview" to (context.assetPresentation == AssetPresentation.PREVIEW),
            "audioQuality" to track?.audioQuality?.name,
            "bitDepth" to track?.audioBitDepth,
            "sampleRate" to track?.audioSampleRate,
            "codec" to track?.audioCodec,
        )
    }

    /** 재생 중에는 500ms마다 위치를 보낸다. */
    private fun startPositionTicker() {
        if (positionJob?.isActive == true) return
        positionJob = scope.launch {
            while (isActive) {
                val seconds = try { tidalPlayer?.playbackEngine?.assetPosition ?: 0f } catch (e: Exception) { 0f }
                emit(mapOf("type" to "position", "positionMs" to (seconds * 1000).toLong()))
                delay(POSITION_INTERVAL_MS)
            }
        }
    }

    private fun stopPositionTicker() {
        positionJob?.cancel()
        positionJob = null
    }

    private fun emit(event: Map<String, Any?>) {
        onEvent?.invoke(event)
    }

    /**
     * TIDAL 공식 Player SDK로 Track 재생
     */
    fun playTrack(trackId: String) {
        if (trackId.isEmpty()) {
            Log.e("TidalPlayerManager", "playTrack: trackId is empty")
            return
        }

        val player = tidalPlayer
        if (player == null) {
            Log.e("TidalPlayerManager", "playTrack: TIDAL Player is not initialized")
            return
        }

        try {
            Log.i("TidalPlayerManager", "Loading TIDAL track: $trackId")

            val mediaProduct = MediaProduct(
                productType = ProductType.TRACK,
                productId = trackId
            )

            player.playbackEngine.load(mediaProduct)
            Log.i("TidalPlayerManager", "MediaProduct loaded: $trackId")

            player.playbackEngine.play()
            isCurrentlyPlaying = true
            Log.i("TidalPlayerManager", "TIDAL playback started: $trackId")
        } catch (e: Exception) {
            isCurrentlyPlaying = false
            Log.e("TidalPlayerManager", "Failed to play TIDAL track $trackId: ${e.message}", e)
        }
    }

    /**
     * 다음 트랙을 큐에 미리 등록 (TIDAL SDK setNext API)
     * skipToNext() 호출 시 이 트랙으로 넘어감.
     */
    fun setNextTrack(trackId: String) {
        val player = tidalPlayer ?: return
        try {
            if (trackId.isEmpty()) {
                player.playbackEngine.setNext(null)
                Log.i("TidalPlayerManager", "setNext(null) - 다음 트랙 초기화")
            } else {
                val mediaProduct = MediaProduct(
                    productType = ProductType.TRACK,
                    productId = trackId
                )
                player.playbackEngine.setNext(mediaProduct)
                Log.i("TidalPlayerManager", "setNext: $trackId")
            }
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "setNextTrack 실패: ${e.message}")
        }
    }

    /**
     * 다음 트랙으로 즉시 이동 (setNextTrack으로 등록된 트랙으로 전환)
     */
    fun skipToNext() {
        val player = tidalPlayer ?: run {
            Log.e("TidalPlayerManager", "skipToNext: Player not initialized")
            return
        }
        try {
            player.playbackEngine.skipToNext()
            isCurrentlyPlaying = true
            Log.i("TidalPlayerManager", "skipToNext() called")
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "skipToNext 실패: ${e.message}")
        }
    }

    /**
     * 현재 재생 위치 반환 (초 단위)
     */
    fun getCurrentPosition(): Float {
        return try {
            tidalPlayer?.playbackEngine?.assetPosition ?: 0f
        } catch (e: Exception) {
            0f
        }
    }

    fun pause() {
        try {
            tidalPlayer?.playbackEngine?.pause()
            isCurrentlyPlaying = false
            Log.i("TidalPlayerManager", "Playback paused")
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Failed to pause playback", e)
        }
    }

    fun resume() {
        try {
            val player = tidalPlayer
            if (player == null) {
                Log.e("TidalPlayerManager", "resume: Player is not initialized")
                return
            }

            player.playbackEngine.play()
            isCurrentlyPlaying = true
            Log.i("TidalPlayerManager", "Playback resumed")
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Failed to resume playback", e)
        }
    }

    fun seekTo(msec: Int) {
        try {
            // TIDAL SDK PlaybackEngine.seek(time: Float) 내부 구현:
            // extendedExoPlayer.seekTo(time.toLong()) -> 즉 밀리초(ms) 단위 Long을 요구함!
            tidalPlayer?.playbackEngine?.seek(msec.toFloat())
            Log.i("TidalPlayerManager", "Seek: ${msec}ms (passed ${msec.toFloat()} to SDK seek)")
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Failed to seek", e)
        }
    }

    companion object {
        private const val POSITION_INTERVAL_MS = 500L

        @Volatile
        var activeInstance: TidalPlayerManager? = null

        fun stopAll() {
            try {
                activeInstance?.stop()
                activeInstance?.release()
                activeInstance = null
            } catch (e: Exception) {
                Log.w("TidalPlayerManager", "stopAll 예외: ${e.message}")
            }
        }
    }

    init {
        activeInstance?.release()
        activeInstance = this
    }

    fun stop() {
        try {
            tidalPlayer?.playbackEngine?.pause()
            tidalPlayer?.playbackEngine?.reset()
            isCurrentlyPlaying = false
            Log.i("TidalPlayerManager", "Playback fully stopped & reset")
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Failed to stop playback", e)
        }
    }

    fun release() {
        try {
            tidalPlayer?.playbackEngine?.pause()
            tidalPlayer?.playbackEngine?.reset()
            stopPositionTicker()
            eventsJob?.cancel()
            tidalPlayer?.release()
            tidalPlayer = null
            isCurrentlyPlaying = false
            if (activeInstance == this) activeInstance = null
            Log.i("TidalPlayerManager", "TIDAL Player fully released")
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Failed to release TIDAL Player", e)
        }
    }
}
