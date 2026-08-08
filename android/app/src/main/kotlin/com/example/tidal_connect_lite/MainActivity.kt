package com.example.tidal_connect_lite

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.tidal_connect_lite/tidal_sdk"
    private lateinit var authManager: TidalAuthManager
    private var playerManager: TidalPlayerManager? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        authManager = TidalAuthManager(applicationContext)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initTidalAuth" -> {
                    val clientId = call.argument<String>("clientId") ?: ""
                    val clientSecret = call.argument<String>("clientSecret") ?: ""
                    val isInitialized = authManager.initializeAuth(clientId, clientSecret)
                    
                    if (isInitialized && authManager.credentialsProvider != null) {
                        playerManager = TidalPlayerManager(applicationContext, authManager.credentialsProvider)
                        playerManager?.initializePlayer()
                    }

                    result.success(mapOf(
                        "status" to if (isInitialized) "initialized" else "init_failed",
                        "sdk" to "com.tidal.sdk",
                        "clientId" to clientId
                    ))
                }
                "authenticateUser" -> {
                    CoroutineScope(Dispatchers.Main).launch {
                        val success = authManager.authenticateUser()
                        result.success(mapOf("status" to if (success) "authenticated" else "auth_failed"))
                    }
                }
                "playTrack" -> {
                    val trackId = call.argument<String>("trackId") ?: ""
                    if (playerManager != null) {
                        playerManager?.playTrack(trackId)
                        result.success(mapOf("status" to "playing", "trackId" to trackId))
                    } else {
                        result.success(mapOf("status" to "playing_simulated", "trackId" to trackId))
                    }
                }
                "stopTrack" -> {
                    playerManager?.stop()
                    result.success(mapOf("status" to "stopped"))
                }
                "releasePlayer" -> {
                    playerManager?.release()
                    playerManager = null
                    result.success(mapOf("status" to "released"))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
