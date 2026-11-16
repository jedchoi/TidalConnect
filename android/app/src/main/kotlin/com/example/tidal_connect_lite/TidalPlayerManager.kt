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

    private fun requirePlayer(): Player =
        tidalPlayer ?: throw IllegalStateException("TIDAL Player가 초기화되지 않았습니다")

    // 아래 동작들은 실패하면 예외를 던진다. 호출하는 쪽(MainActivity)이 Flutter에 오류로 돌려준다.

    /** TIDAL 공식 Player SDK로 트랙을 재생한다. */
    fun playTrack(trackId: String) {
        require(trackId.isNotEmpty()) { "trackId가 비어 있습니다" }
        val player = requirePlayer()
        Log.i(TAG, "Loading TIDAL track: $trackId")
        player.playbackEngine.load(MediaProduct(productType = ProductType.TRACK, productId = trackId))
        player.playbackEngine.play()
    }

    /** 다음 트랙을 미리 등록한다(SDK setNext). 빈 값이면 등록을 지운다. */
    fun setNextTrack(trackId: String) {
        val player = requirePlayer()
        player.playbackEngine.setNext(
            if (trackId.isEmpty()) null else MediaProduct(productType = ProductType.TRACK, productId = trackId)
        )
    }

    fun skipToNext() {
        requirePlayer().playbackEngine.skipToNext()
    }

    /** 현재 재생 위치(초). */
    fun getCurrentPosition(): Float = tidalPlayer?.playbackEngine?.assetPosition ?: 0f

    fun pause() {
        requirePlayer().playbackEngine.pause()
    }

    fun resume() {
        requirePlayer().playbackEngine.play()
    }

    /** SDK의 seek(time)은 내부에서 ExoPlayer.seekTo(time.toLong())을 호출하므로 밀리초 단위다. */
    fun seekTo(msec: Int) {
        requirePlayer().playbackEngine.seek(msec.toFloat())
    }

    fun stop() {
        val player = tidalPlayer ?: return
        stopPositionTicker()
        player.playbackEngine.pause()
        player.playbackEngine.reset()
    }

    fun release() {
        try {
            stopPositionTicker()
            eventsJob?.cancel()
            tidalPlayer?.playbackEngine?.reset()
            tidalPlayer?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release TIDAL Player", e)
        } finally {
            tidalPlayer = null
            if (activeInstance == this) activeInstance = null
        }
    }

    companion object {
        private const val TAG = "TidalPlayerManager"
        private const val POSITION_INTERVAL_MS = 500L

        @Volatile
        var activeInstance: TidalPlayerManager? = null

        fun stopAll() {
            try {
                activeInstance?.stop()
                activeInstance?.release()
                activeInstance = null
            } catch (e: Exception) {
                Log.w(TAG, "stopAll 예외: ${e.message}")
            }
        }
    }

    init {
        activeInstance?.release()
        activeInstance = this
    }
}
