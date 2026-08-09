package com.example.tidal_connect_lite

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player as ExoPlayerListener
import androidx.media3.exoplayer.ExoPlayer
import com.tidal.sdk.auth.CredentialsProvider
import java.io.File

class TidalPlayerManager(
    private val context: Context,
    private val credentialsProvider: CredentialsProvider?
) {
    private var exoPlayer: ExoPlayer? = null
    private var isCurrentlyPlaying = false

    fun initializePlayer() {
        try {
            if (exoPlayer == null) {
                exoPlayer = ExoPlayer.Builder(context)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                            .setUsage(C.USAGE_MEDIA)
                            .build(),
                        true
                    )
                    .build().apply {
                        addListener(object : ExoPlayerListener.Listener {
                            override fun onIsPlayingChanged(isPlaying: Boolean) {
                                isCurrentlyPlaying = isPlaying
                                Log.i("TidalPlayerManager", "ExoPlayer isPlaying changed: $isPlaying")
                            }

                            override fun onPlaybackStateChanged(playbackState: Int) {
                                when (playbackState) {
                                    ExoPlayerListener.STATE_READY -> {
                                        Log.i("TidalPlayerManager", "ExoPlayer STATE_READY, duration: ${duration}ms")
                                    }
                                    ExoPlayerListener.STATE_ENDED -> {
                                        Log.i("TidalPlayerManager", "ExoPlayer STATE_ENDED (playback completed)")
                                        isCurrentlyPlaying = false
                                    }
                                    ExoPlayerListener.STATE_BUFFERING -> {
                                        Log.d("TidalPlayerManager", "ExoPlayer STATE_BUFFERING...")
                                    }
                                    ExoPlayerListener.STATE_IDLE -> {
                                        Log.d("TidalPlayerManager", "ExoPlayer STATE_IDLE")
                                    }
                                }
                            }

                            override fun onPlayerError(error: PlaybackException) {
                                Log.e("TidalPlayerManager", "ExoPlayer error: ${error.errorCodeName} (${error.errorCode}) - ${error.message}", error)
                                isCurrentlyPlaying = false
                            }
                        })
                    }
                Log.i("TidalPlayerManager", "ExoPlayer audio engine initialized successfully")
            }
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Exception initializing ExoPlayer: ${e.message}", e)
        }
    }

    fun playTrack(trackId: String, streamUrl: String = "", manifest: String = "", mimeType: String = "") {
        try {
            initializePlayer()
            stop()

            val fixedUrl = streamUrl.replace("&amp;", "&")

            // 1. MPEG-DASH MPD Manifest 스트리밍 (TIDAL Full-Track 표준)
            if (manifest.isNotEmpty() && (mimeType.contains("dash") || manifest.contains("<MPD"))) {
                val cleanManifest = manifest.replace("&amp;", "&")
                val mpdFile = File(context.cacheDir, "track_${trackId}.mpd")
                mpdFile.writeText(cleanManifest)
                Log.i("TidalPlayerManager", "Playing MPEG-DASH manifest for track $trackId (${mpdFile.length()} bytes)")

                val mediaItem = MediaItem.Builder()
                    .setUri(Uri.fromFile(mpdFile))
                    .setMimeType(MimeTypes.APPLICATION_MPD)
                    .build()

                exoPlayer?.setMediaItem(mediaItem)
                exoPlayer?.prepare()
                exoPlayer?.play()
                isCurrentlyPlaying = true
                Log.i("TidalPlayerManager", "ExoPlayer started DASH playback for track $trackId")
                return
            }

            // 2. 직접 음원 스트림 URL (FLAC / AAC / Preview)
            if (fixedUrl.isNotEmpty()) {
                Log.i("TidalPlayerManager", "Playing direct audio stream: $fixedUrl")
                val mediaItem = MediaItem.fromUri(Uri.parse(fixedUrl))
                exoPlayer?.setMediaItem(mediaItem)
                exoPlayer?.prepare()
                exoPlayer?.play()
                isCurrentlyPlaying = true
                Log.i("TidalPlayerManager", "ExoPlayer started direct playback for track $trackId")
                return
            }

            Log.w("TidalPlayerManager", "playTrack invoked without streamUrl or manifest for trackId: $trackId")
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Exception starting ExoPlayer playback: ${e.message}", e)
        }
    }

    fun pause() {
        try {
            exoPlayer?.pause()
            isCurrentlyPlaying = false
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun resume() {
        try {
            exoPlayer?.play()
            isCurrentlyPlaying = true
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun seekTo(msec: Int) {
        try {
            exoPlayer?.seekTo(msec.toLong())
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun stop() {
        try {
            exoPlayer?.stop()
            isCurrentlyPlaying = false
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun release() {
        stop()
        exoPlayer?.release()
        exoPlayer = null
    }
}
