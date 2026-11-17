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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
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

    // ── 채널 명령 ─────────────────────────────────────────────────
    // 메서드 분배와 응답 값은 PlaybackCommandRouter가 맡는다. 아래는 router가 부르는 운영 구현이다.
    // object의 속성은 적힌 순서대로 초기화되므로, 운영 구현을 router보다 먼저 적는다.

    private val authControls: AuthControls = object : AuthControls {
        override fun initialize(clientId: String, clientSecret: String): Boolean {
            val ch = channel ?: return false
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

            return isInitialized
        }

        override fun updateUserCredentials(userId: String, accessToken: String, expiresInSeconds: Long) {
            auth.updateUserCredentials(userId, accessToken, expiresInSeconds)
            Log.i("TIDAL_NATIVE_SDK", "updateUserCredentials 호출됨 (UserId: $userId)")
        }

        override fun clearUserCredentials() {
            auth.clearUserCredentials()
        }
    }

    // 함수 이름이 PlaybackCore의 private 함수와 같다. `PlaybackCore.`를 빼면 자기 자신을 부른다.
    private val deviceControls: DeviceControls = object : DeviceControls {
        override fun phoneVolumePercent(): Int = PlaybackCore.phoneVolumePercent()

        override fun setPhoneVolumePercent(percent: Int) = PlaybackCore.setPhoneVolumePercent(percent)

        override fun requestNotificationPermission(): Boolean = PlaybackCore.requestNotificationPermission()

        override fun setWifiLock(enabled: Boolean) = PlaybackCore.setWifiLock(enabled)
    }

    private val proxyRegistrar = ProxyRegistrar { trackId, directUrl, manifestXml, allowedHost, mimeType ->
        val server = ensureProxyServer() ?: return@ProxyRegistrar null
        val shortUrl = server.registerTrackStream(trackId, directUrl, manifestXml, allowedHost, mimeType)
        Log.i("PROXY", "registerTrackStream: TrackID=$trackId")
        shortUrl
    }

    private val router = PlaybackCommandRouter(
        auth = authControls,
        player = { playerManager?.let { LoggingPlayerControls(it) } },
        device = deviceControls,
        proxy = proxyRegistrar,
    )

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        sendCommandResult(router.handle(call.method, channelArguments(call)), result)
    }

    /** Flutter에 곡의 새 스트림 정보를 요청한다. 20초 안에 답이 없으면 null. */
    private suspend fun requestStreamFromDart(trackId: String): Map<String, Any?>? {
        val ch = channel ?: return null
        return withTimeoutOrNull(20_000) {
            withContext(Dispatchers.Main) {
                suspendCancellableCoroutine { cont ->
                    ch.invokeMethod("refreshTrackStream", mapOf("trackId" to trackId), object : MethodChannel.Result {
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
                // 프록시 작업 스레드에서 호출되므로 Dart 응답을 기다리는 동안 이 스레드만 막는다.
                it.streamRefresher = { trackId -> runBlocking { requestStreamFromDart(trackId) } }
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

/**
 * 플레이어 동작이 실패하면 스택 트레이스를 로그로 남기고 예외를 그대로 다시 던진다.
 *
 * 예외를 오류 응답(PLAYER_ERROR)으로 바꾸는 일은 [PlaybackCommandRouter]가 한다. router는 Android 타입을
 * 쓰지 않아 로그를 남길 수 없으므로 여기서 남긴다.
 */
private class LoggingPlayerControls(private val inner: PlayerControls) : PlayerControls {
    override fun playTrack(trackId: String) = logFailure { inner.playTrack(trackId) }

    override fun pause() = logFailure { inner.pause() }

    override fun resume() = logFailure { inner.resume() }

    override fun seekTo(msec: Int) = logFailure { inner.seekTo(msec) }

    override fun stop() = logFailure { inner.stop() }

    override fun skipToNext() = logFailure { inner.skipToNext() }

    override fun setNextTrack(trackId: String) = logFailure { inner.setNextTrack(trackId) }

    override fun setAudioQuality(name: String) = logFailure { inner.setAudioQuality(name) }

    private inline fun logFailure(action: () -> Unit) {
        try {
            action()
        } catch (e: Exception) {
            Log.e("TIDAL_NATIVE_SDK", "플레이어 동작 실패: ${e.message}", e)
            throw e
        }
    }
}
