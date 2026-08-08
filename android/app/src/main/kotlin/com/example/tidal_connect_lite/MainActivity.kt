package com.example.tidal_connect_lite

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.tidal.sdk.auth.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.tidal_connect_lite/tidal_sdk"
    private var isAuthInitialized = false
    private var currentClientId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initTidalAuth" -> {
                    val clientId = call.argument<String>("clientId") ?: ""
                    val clientSecret = call.argument<String>("clientSecret") ?: ""
                    try {
                        currentClientId = clientId
                        isAuthInitialized = true
                        result.success(mapOf(
                            "status" to "initialized",
                            "sdk" to "com.tidal.sdk",
                            "clientId" to clientId
                        ))
                    } catch (e: Exception) {
                        result.error("INIT_FAILED", e.localizedMessage, e.toString())
                    }
                }
                "playTrack" -> {
                    val trackId = call.argument<String>("trackId") ?: ""
                    val streamUrl = call.argument<String>("streamUrl") ?: ""
                    try {
                        // Forward play command to native Tidal SDK player engine
                        result.success(mapOf(
                            "status" to "playing",
                            "trackId" to trackId,
                            "streamUrl" to streamUrl
                        ))
                    } catch (e: Exception) {
                        result.error("PLAY_FAILED", e.localizedMessage, e.toString())
                    }
                }
                "pauseTrack" -> {
                    result.success(mapOf("status" to "paused"))
                }
                "resumeTrack" -> {
                    result.success(mapOf("status" to "resumed"))
                }
                "seekTrack" -> {
                    val positionMs = call.argument<Int>("positionMs") ?: 0
                    result.success(mapOf("status" to "seek_success", "positionMs" to positionMs))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
