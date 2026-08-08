package com.example.tidal_connect_lite

import android.content.Context
import com.tidal.sdk.auth.CredentialsProvider
import com.tidal.sdk.player.Player
import com.tidal.sdk.player.common.model.AudioQuality

class TidalPlayerManager(
    private val context: Context,
    private val credentialsProvider: CredentialsProvider?
) {
    private var tidalPlayer: Player? = null

    fun initializePlayer() {
        if (credentialsProvider == null) return
        try {
            tidalPlayer = Player.Builder(context)
                .setCredentialsProvider(credentialsProvider)
                .build()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun playTrack(trackId: String, quality: AudioQuality = AudioQuality.HIGH) {
        try {
            tidalPlayer?.load(
                trackId = trackId,
                audioQuality = quality,
                playWhenReady = true
            )
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun stop() {
        try {
            tidalPlayer?.stop()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun release() {
        try {
            tidalPlayer?.release()
            tidalPlayer = null
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
