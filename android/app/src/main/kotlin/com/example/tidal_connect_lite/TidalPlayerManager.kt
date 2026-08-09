package com.example.tidal_connect_lite

import android.app.Application
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
                isDebuggable = true
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
            tidalPlayer?.playbackEngine?.seek(msec / 1000f)
            Log.i("TidalPlayerManager", "Seek: ${msec}ms")
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Failed to seek", e)
        }
    }

    fun stop() {
        try {
            tidalPlayer?.playbackEngine?.reset()
            isCurrentlyPlaying = false
            Log.i("TidalPlayerManager", "Playback stopped")
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Failed to stop playback", e)
        }
    }

    fun release() {
        try {
            tidalPlayer?.release()
            tidalPlayer = null
            isCurrentlyPlaying = false
            Log.i("TidalPlayerManager", "TIDAL Player released")
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Failed to release TIDAL Player", e)
        }
    }
}
