package com.example.tidal_connect_lite

import android.app.Application
import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
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
    private var mediaPlayer: MediaPlayer? = null
    private var isCurrentlyPlaying = false
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    fun initializePlayer() {
        try {
            if (credentialsProvider != null) {
                val app = context.applicationContext as? Application
                if (app != null) {
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
                    Log.i("TidalPlayerManager", "TIDAL Official Player SDK (ExoPlayer stack) initialized successfully!")
                }
            }
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Failed to initialize TIDAL Official Player SDK: ${e.message}", e)
        }
    }

    fun playTrack(trackId: String, streamUrl: String = "", token: String = "") {
        try {
            stop()

            // 1. 공식 TIDAL SDK Player 우선 사용 (ExoPlayer, DASH 세그먼트, CDN 서명 처리 내장)
            if (tidalPlayer != null && trackId.isNotEmpty()) {
                Log.i("TidalPlayerManager", "Playing track via Official TIDAL SDK Player: $trackId")
                val mediaProduct = MediaProduct(
                    productType = ProductType.TRACK,
                    productId = trackId
                )
                tidalPlayer?.playbackEngine?.load(mediaProduct)
                tidalPlayer?.playbackEngine?.play()
                isCurrentlyPlaying = true
                Log.i("TidalPlayerManager", "TIDAL SDK playbackEngine.play() executed successfully for track $trackId")
                return
            }

            // 2. 폴백: &amp; 치환된 스트림 URL로 MediaPlayer 재생
            val fixedUrl = streamUrl.replace("&amp;", "&")
            if (fixedUrl.isNotEmpty()) {
                Log.i("TidalPlayerManager", "Fallback: Starting audio playback on MediaPlayer: $fixedUrl")
                mediaPlayer = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .build()
                    )
                    setDataSource(fixedUrl)
                    setOnPreparedListener { mp ->
                        mp.start()
                        this@TidalPlayerManager.isCurrentlyPlaying = true
                        Log.i("TidalPlayerManager", "MediaPlayer playback started successfully on phone speaker for track $trackId")
                    }
                    setOnCompletionListener {
                        this@TidalPlayerManager.isCurrentlyPlaying = false
                        Log.i("TidalPlayerManager", "MediaPlayer playback completed for track $trackId")
                    }
                    setOnErrorListener { _, what, extra ->
                        Log.e("TidalPlayerManager", "MediaPlayer error: what=$what, extra=$extra for track $trackId")
                        this@TidalPlayerManager.isCurrentlyPlaying = false
                        false
                    }
                    prepareAsync()
                }
            } else {
                Log.w("TidalPlayerManager", "playTrack invoked without streamUrl or player for trackId: $trackId")
            }
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Exception starting playback: ${e.message}", e)
        }
    }

    fun pause() {
        try {
            tidalPlayer?.playbackEngine?.pause()
            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.pause()
                }
            }
            isCurrentlyPlaying = false
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun resume() {
        try {
            tidalPlayer?.playbackEngine?.play()
            mediaPlayer?.let {
                it.start()
            }
            isCurrentlyPlaying = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun seekTo(msec: Int) {
        try {
            tidalPlayer?.playbackEngine?.seek((msec / 1000).toFloat())
            mediaPlayer?.seekTo(msec)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun stop() {
        try {
            tidalPlayer?.playbackEngine?.reset()
            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.stop()
                }
                it.release()
            }
            mediaPlayer = null
            isCurrentlyPlaying = false
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun release() {
        stop()
        tidalPlayer?.release()
        tidalPlayer = null
    }
}
