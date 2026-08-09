package com.example.tidal_connect_lite

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.util.Log
import com.tidal.sdk.auth.CredentialsProvider

class TidalPlayerManager(
    private val context: Context,
    private val credentialsProvider: CredentialsProvider?
) {
    private var mediaPlayer: MediaPlayer? = null
    private var isCurrentlyPlaying = false

    fun initializePlayer() {
        Log.d("TidalPlayerManager", "TidalPlayerManager initialized with context")
    }

    fun playTrack(trackId: String, streamUrl: String = "") {
        try {
            stop()
            if (streamUrl.isNotEmpty()) {
                Log.d("TidalPlayerManager", "Playing audio stream on mobile speaker: $streamUrl")
                mediaPlayer = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .build()
                    )
                    setDataSource(context, Uri.parse(streamUrl))
                    setOnPreparedListener { mp ->
                        mp.start()
                        this@TidalPlayerManager.isCurrentlyPlaying = true
                        Log.d("TidalPlayerManager", "MediaPlayer playback started successfully on phone speaker")
                    }
                    setOnCompletionListener {
                        this@TidalPlayerManager.isCurrentlyPlaying = false
                        Log.d("TidalPlayerManager", "MediaPlayer playback completed")
                    }
                    setOnErrorListener { _, what, extra ->
                        Log.e("TidalPlayerManager", "MediaPlayer error: what=$what, extra=$extra")
                        this@TidalPlayerManager.isCurrentlyPlaying = false
                        false
                    }
                    prepareAsync()
                }
            } else {
                Log.d("TidalPlayerManager", "playTrack invoked without streamUrl for trackId: $trackId")
            }
        } catch (e: Exception) {
            Log.e("TidalPlayerManager", "Exception starting MediaPlayer: ${e.message}", e)
        }
    }

    fun pause() {
        try {
            mediaPlayer?.let {
                if (it.isPlaying) {
                    it.pause()
                    isCurrentlyPlaying = false
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun resume() {
        try {
            mediaPlayer?.let {
                it.start()
                isCurrentlyPlaying = true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun seekTo(msec: Int) {
        try {
            mediaPlayer?.seekTo(msec)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun stop() {
        try {
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
    }
}
