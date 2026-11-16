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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class TidalPlayerManager(
    private val context: Context,
    private val credentialsProvider: CredentialsProvider?
) {
    private var tidalPlayer: Player? = null
    private var isCurrentlyPlaying = false
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

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
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Failed to initialize TIDAL Player: ${e.message}", e)
            tidalPlayer = null
        }
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
