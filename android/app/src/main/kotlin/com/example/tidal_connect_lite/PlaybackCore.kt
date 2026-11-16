package com.example.tidal_connect_lite

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import java.lang.ref.WeakReference
import android.content.Context
import android.database.ContentObserver
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * 프로세스 범위의 재생 핵심 객체.
 *
 * 인증 관리자, TIDAL 플레이어, DLNA 프록시 서버를 소유한다. Activity가 파괴되고 다시 만들어져도
 * 재생은 계속되며, 정지와 해제는 Flutter의 정지 명령으로만 일어난다.
 */
@SuppressLint("StaticFieldLeak") // applicationContext만 보관한다
object PlaybackCore {
    private const val CHANNEL = "com.example.tidal_connect_lite/tidal_sdk"
    private const val EVENT_CHANNEL = "com.example.tidal_connect_lite/player_events"
    private const val NOTIFICATION_REQUEST_CODE = 1001

    private lateinit var appContext: Context
    private lateinit var auth: TidalAuthManager
    private var playerManager: TidalPlayerManager? = null
    private var proxyServer: TidalStreamProxyServer? = null
    private var eventSink: EventChannel.EventSink? = null
    private var channel: MethodChannel? = null
    private var attachedMessenger: BinaryMessenger? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private var activityRef: WeakReference<Activity>? = null

    /** Flutter 엔진에 채널을 연결한다. 같은 엔진에 다시 붙으면 아무것도 하지 않는다. */
    fun attach(engine: FlutterEngine, context: Context) {
        activityRef = WeakReference(context as? Activity)
        val messenger = engine.dartExecutor.binaryMessenger
        if (attachedMessenger === messenger) return
        attachedMessenger = messenger
        appContext = context.applicationContext
        if (!::auth.isInitialized) auth = TidalAuthManager(appContext)

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
        channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(::onMethodCall) }
        registerPhoneVolumeObserver()
    }

    // ── 폰 미디어 볼륨 ─────────────────────────────────────────────

    private var volumeObserverRegistered = false
    private var lastPhoneVolume = -1

    private fun audioManager(): AudioManager = appContext.getSystemService(AudioManager::class.java)

    private fun phoneVolumePercent(): Int {
        val am = audioManager()
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        return am.getStreamVolume(AudioManager.STREAM_MUSIC) * 100 / max
    }

    private fun setPhoneVolumePercent(percent: Int) {
        val am = audioManager()
        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val index = Math.round(percent.coerceIn(0, 100) * max / 100f)
        am.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
    }

    /** 폰 미디어 볼륨이 바뀌면(볼륨 키 포함) {type: phoneVolume, percent}를 보낸다. */
    private fun registerPhoneVolumeObserver() {
        if (volumeObserverRegistered) return
        volumeObserverRegistered = true
        lastPhoneVolume = phoneVolumePercent()
        appContext.contentResolver.registerContentObserver(
            Settings.System.CONTENT_URI,
            true,
            object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean) {
                    val percent = phoneVolumePercent()
                    if (percent != lastPhoneVolume) {
                        lastPhoneVolume = percent
                        emit(mapOf("type" to "phoneVolume", "percent" to percent))
                    }
                }
            }
        )
    }

    /** Flutter로 이벤트를 보낸다. 메인 스레드에서 호출해야 한다. */
    fun emit(event: Map<String, Any?>) {
        eventSink?.success(event)
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initTidalAuth" -> {
                val ch = channel ?: return
                val clientId = call.argument<String>("clientId") ?: ""
                val clientSecret = call.argument<String>("clientSecret") ?: ""
                val isInitialized = auth.initializeAuth(clientId, clientSecret)
                auth.customCredentialsProvider?.tokenRefresher = { requestTokenFromDart(ch) }
                
                if (isInitialized && auth.credentialsProvider != null) {
                    if (playerManager == null) {
                        playerManager = TidalPlayerManager(appContext, auth.credentialsProvider).also {
                            it.onEvent = { event -> emit(event) }
                        }
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

                auth.updateUserCredentials(userId, accessToken, expiresInSeconds)
                Log.i("TIDAL_NATIVE_SDK", "updateUserCredentials 호출됨 (UserId: $userId)")
                result.success(mapOf("status" to "updated", "userId" to userId))
            }
            "clearUserCredentials" -> {
                auth.clearUserCredentials()
                result.success(mapOf("status" to "cleared"))
            }
            "authenticateUser" -> {
                CoroutineScope(Dispatchers.Main).launch {
                    val success = auth.authenticateUser()
                    result.success(mapOf("status" to if (success) "authenticated" else "auth_failed"))
                }
            }
            "playTrack" -> runPlayerAction(result) {
                val trackId = call.argument<String>("trackId") ?: ""
                requirePlayerManager().playTrack(trackId)
                mapOf("status" to "playing", "trackId" to trackId)
            }
            "pauseTrack" -> runPlayerAction(result) {
                requirePlayerManager().pause()
                mapOf("status" to "paused")
            }
            "resumeTrack" -> runPlayerAction(result) {
                requirePlayerManager().resume()
                mapOf("status" to "resumed")
            }
            "seekTrack" -> runPlayerAction(result) {
                val positionMs = call.argument<Int>("positionMs") ?: 0
                requirePlayerManager().seekTo(positionMs)
                mapOf("status" to "seeked", "positionMs" to positionMs)
            }
            "stopTrack" -> runPlayerAction(result) {
                playerManager?.stop()
                mapOf("status" to "stopped")
            }
            "skipToNext" -> runPlayerAction(result) {
                requirePlayerManager().skipToNext()
                mapOf("status" to "skipped_to_next")
            }
            "setNextTrack" -> runPlayerAction(result) {
                val nextTrackId = call.argument<String>("trackId") ?: ""
                requirePlayerManager().setNextTrack(nextTrackId)
                mapOf("status" to "next_track_set", "trackId" to nextTrackId)
            }
            "getPosition" -> {
                val positionSec = playerManager?.getCurrentPosition() ?: 0f
                result.success(mapOf("positionSeconds" to positionSec))
            }
            "releasePlayer" -> {
                playerManager?.release()
                playerManager = null
                result.success(mapOf("status" to "released"))
            }
            "getPhoneVolume" -> result.success(phoneVolumePercent())
            "setPhoneVolume" -> {
                setPhoneVolumePercent(call.argument<Int>("percent") ?: 0)
                result.success(null)
            }
            "requestNotificationPermission" -> {
                result.success(requestNotificationPermission())
            }
            "setStreamingLock" -> {
                setWifiLock(call.argument<Boolean>("enabled") == true)
                result.success(null)
            }
            // ── DLNA 프록시 관련 채널 ──────────────────────────────────────
            "registerTrackStream" -> {
                val trackId = call.argument<String>("trackId") ?: ""
                val directUrl = call.argument<String>("directUrl") ?: ""
                val manifestXml = call.argument<String>("manifestXml") ?: ""
                val allowedHost = call.argument<String>("allowedHost") ?: ""

                val server = ensureProxyServer()
                if (server == null) {
                    result.error("NO_WIFI", "Wi-Fi에 연결되어 있지 않아 스피커로 스트리밍할 수 없습니다.", null)
                    return
                }
                val shortUrl = server.registerTrackStream(trackId, directUrl, manifestXml, allowedHost)
                Log.i("PROXY", "registerTrackStream: TrackID=$trackId")
                result.success(mapOf("proxyUrl" to shortUrl))
            }
            "getProxyServerStatus" -> {
                val isAlive = proxyServer?.isAlive ?: false
                val lanIp = proxyServer?.boundHost ?: ""
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

    private fun requirePlayerManager(): TidalPlayerManager =
        playerManager ?: throw IllegalStateException("TIDAL Player가 초기화되지 않았습니다")

    /** 플레이어 동작을 실행하고, 실패하면 Flutter에 오류(PLAYER_ERROR)로 돌려준다. */
    private inline fun runPlayerAction(result: MethodChannel.Result, action: () -> Map<String, Any?>) {
        try {
            result.success(action())
        } catch (e: Exception) {
            Log.e("TIDAL_NATIVE_SDK", "플레이어 동작 실패: ${e.message}", e)
            result.error("PLAYER_ERROR", e.message ?: e.javaClass.simpleName, null)
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

    /**
     * Android 13 이상에서 재생 알림 권한을 요청한다. 이미 허용되었거나 필요 없으면 true.
     * 거부해도 재생은 계속되며 알림만 보이지 않는다.
     */
    private fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        val granted = ContextCompat.checkSelfPermission(appContext, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) return true
        val activity = activityRef?.get() ?: return false
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST_CODE)
        return false
    }

    /**
     * DLNA 재생 중에만 WifiLock을 잡아 화면이 꺼져도 Wi-Fi가 절전으로 끊기지 않게 한다.
     * CPU 유지는 audio_service의 서비스가 재생 중 WakeLock으로 처리한다.
     */
    private fun setWifiLock(enabled: Boolean) {
        try {
            if (enabled) {
                val lock = wifiLock ?: appContext.getSystemService(WifiManager::class.java)
                    ?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "WaveConnect:DlnaStreaming")
                    ?.also { it.setReferenceCounted(false); wifiLock = it }
                if (lock != null && !lock.isHeld) lock.acquire()
            } else {
                wifiLock?.takeIf { it.isHeld }?.release()
            }
        } catch (e: Exception) {
            Log.w("PlaybackCore", "WifiLock 처리 실패: ${e.message}")
        }
    }

    /**
     * 현재 Wi-Fi 주소에 바인딩된 프록시 서버를 돌려준다. 주소가 바뀌었으면 새로 띄운다.
     * Wi-Fi가 없으면 null.
     */
    private fun ensureProxyServer(): TidalStreamProxyServer? {
        val wifiIp = TidalStreamProxyServer.getWifiIpv4Address(appContext)
        if (wifiIp == null) {
            Log.w("PROXY", "Wi-Fi 주소 없음 - 프록시를 시작하지 않음")
            return null
        }
        val current = proxyServer
        if (current != null && current.boundHost == wifiIp && current.isAlive) return current
        return try {
            current?.stop()
            TidalStreamProxyServer(wifiIp).also {
                it.start(30_000, false)
                proxyServer = it
                Log.i("PROXY", "로컬 스트림 프록시 시작: $wifiIp:${TidalStreamProxyServer.PROXY_PORT}")
            }
        } catch (e: Exception) {
            Log.e("PROXY", "프록시 서버 시작 실패: ${e.message}", e)
            null
        }
    }
}
