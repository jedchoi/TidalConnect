package com.example.tidal_connect_lite

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.tidal_connect_lite/tidal_sdk"
    private lateinit var authManager: TidalAuthManager
    private var playerManager: TidalPlayerManager? = null
    private var proxyServer: TidalStreamProxyServer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        authManager = TidalAuthManager(applicationContext)

        // 로컬 스트림 프록시 서버 시작 (DLNA relay용)
        startProxyServer()

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initTidalAuth" -> {
                    val clientId = call.argument<String>("clientId") ?: ""
                    val clientSecret = call.argument<String>("clientSecret") ?: ""
                    val isInitialized = authManager.initializeAuth(clientId, clientSecret)
                    authManager.customCredentialsProvider?.tokenRefresher = { requestTokenFromDart(channel) }
                    
                    if (isInitialized && authManager.credentialsProvider != null) {
                        if (playerManager == null) {
                            playerManager = TidalPlayerManager(applicationContext, authManager.credentialsProvider)
                        }
                        Log.i("TIDAL_NATIVE_SDK", "initializePlayer() called")
                        playerManager?.initializePlayer()
                    }

                    result.success(mapOf(
                        "status" to if (isInitialized) "initialized" else "init_failed",
                        "sdk" to "com.tidal.sdk",
                        "clientId" to clientId
                    ))
                }
                "updateUserCredentials" -> {
                    val userId = call.argument<String>("userId") ?: ""
                    val accessToken = call.argument<String>("accessToken") ?: ""
                    val expiresInSeconds = (call.argument<Number>("expiresInSeconds") ?: 3600).toLong()

                    authManager.updateUserCredentials(userId, accessToken, expiresInSeconds)
                    Log.i("TIDAL_NATIVE_SDK", "updateUserCredentials 호출됨 (UserId: $userId, Token length: ${accessToken.length})")
                    result.success(mapOf("status" to "updated", "userId" to userId))
                }
                "clearUserCredentials" -> {
                    authManager.clearUserCredentials()
                    result.success(mapOf("status" to "cleared"))
                }
                "authenticateUser" -> {
                    CoroutineScope(Dispatchers.Main).launch {
                        val success = authManager.authenticateUser()
                        result.success(mapOf("status" to if (success) "authenticated" else "auth_failed"))
                    }
                }
                "playTrack" -> {
                    val trackId = call.argument<String>("trackId") ?: ""
                    playerManager?.playTrack(trackId)
                    TidalPlaybackService.startService(applicationContext, "Tidal Connect Lite", "트랙 ID: $trackId 재생 중")
                    result.success(mapOf("status" to "playing", "trackId" to trackId))
                }
                "pauseTrack" -> {
                    playerManager?.pause()
                    result.success(mapOf("status" to "paused"))
                }
                "resumeTrack" -> {
                    playerManager?.resume()
                    TidalPlaybackService.startService(applicationContext, "Tidal Connect Lite", "재생 중")
                    result.success(mapOf("status" to "resumed"))
                }
                "seekTrack" -> {
                    val positionMs = call.argument<Int>("positionMs") ?: 0
                    playerManager?.seekTo(positionMs)
                    result.success(mapOf("status" to "seeked", "positionMs" to positionMs))
                }
                "stopTrack" -> {
                    playerManager?.stop()
                    TidalPlaybackService.stopService(applicationContext)
                    result.success(mapOf("status" to "stopped"))
                }
                "skipToNext" -> {
                    playerManager?.skipToNext()
                    result.success(mapOf("status" to "skipped_to_next"))
                }
                "setNextTrack" -> {
                    val nextTrackId = call.argument<String>("trackId") ?: ""
                    playerManager?.setNextTrack(nextTrackId)
                    result.success(mapOf("status" to "next_track_set", "trackId" to nextTrackId))
                }
                "getPosition" -> {
                    val positionSec = playerManager?.getCurrentPosition() ?: 0f
                    result.success(mapOf("positionSeconds" to positionSec))
                }
                "releasePlayer" -> {
                    playerManager?.release()
                    playerManager = null
                    TidalPlaybackService.stopService(applicationContext)
                    result.success(mapOf("status" to "released"))
                }
                "startForegroundService" -> {
                    val title = call.argument<String>("title") ?: "Tidal Connect Lite"
                    val artist = call.argument<String>("artist") ?: "오디오 스트리밍 중"
                    TidalPlaybackService.startService(applicationContext, title, artist)
                    result.success(mapOf("status" to "service_started"))
                }
                "stopForegroundService" -> {
                    TidalPlaybackService.stopService(applicationContext)
                    result.success(mapOf("status" to "service_stopped"))
                }
                // ── DLNA 프록시 관련 채널 ──────────────────────────────────────
                "registerTrackStream" -> {
                    val trackId = call.argument<String>("trackId") ?: ""
                    val directUrl = call.argument<String>("directUrl") ?: ""
                    val manifestXml = call.argument<String>("manifestXml") ?: ""

                    proxyServer?.registerTrackStream(trackId, directUrl, manifestXml)
                    val shortUrl = TidalStreamProxyServer.buildShortAudioUrl(trackId)
                    TidalPlaybackService.startService(applicationContext, "DLNA 스트리밍", "Track ID: $trackId")
                    Log.i("PROXY", "✅ registerTrackStream: TrackID=$trackId → Short URL: $shortUrl")
                    result.success(mapOf("proxyUrl" to shortUrl))
                }
                "getProxyServerStatus" -> {
                    val isAlive = proxyServer?.isAlive ?: false
                    val lanIp = TidalStreamProxyServer.getLanIpAddress()
                    result.success(mapOf(
                        "isRunning" to isAlive,
                        "lanIp" to lanIp,
                        "port" to TidalStreamProxyServer.PROXY_PORT
                    ))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    /** Flutter에 사용자 토큰 갱신을 요청하고 결과를 기다린다. 20초 안에 답이 없으면 null. */
    private suspend fun requestTokenFromDart(channel: MethodChannel): Map<String, Any?>? =
        withTimeoutOrNull(20_000) {
            withContext(Dispatchers.Main) {
                suspendCancellableCoroutine { cont ->
                    channel.invokeMethod("refreshUserToken", null, object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            @Suppress("UNCHECKED_CAST")
                            if (cont.isActive) cont.resume(result as? Map<String, Any?>)
                        }

                        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                            if (cont.isActive) cont.resume(null)
                        }

                        override fun notImplemented() {
                            if (cont.isActive) cont.resume(null)
                        }
                    })
                }
            }
        }

    private fun startProxyServer() {
        try {
            if (proxyServer == null) {
                proxyServer = TidalStreamProxyServer()
            }
            if (!proxyServer!!.isAlive) {
                proxyServer!!.start(30_000, false)
                val lanIp = TidalStreamProxyServer.getLanIpAddress()
                Log.i("PROXY", "로컬 스트림 프록시 서버 시작: http://$lanIp:${TidalStreamProxyServer.PROXY_PORT}")
            }
        } catch (e: Exception) {
            Log.e("PROXY", "프록시 서버 시작 실패: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        Log.i("MainActivity", "Activity onDestroy -> 리소스 정리")
        try {
            TidalPlayerManager.stopAll()
            playerManager?.release()
            playerManager = null
            TidalPlaybackService.stopService(applicationContext)
            proxyServer?.stop()
            proxyServer = null
        } catch (e: Exception) {
            Log.w("MainActivity", "onDestroy 정리 오류: ${e.message}")
        }
        super.onDestroy()
    }
}
