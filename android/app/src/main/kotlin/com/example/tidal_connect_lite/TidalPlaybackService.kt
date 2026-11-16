package com.example.tidal_connect_lite

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * 백그라운드 오디오 스트리밍 및 로컬 프록시 유지를 위한 Android Foreground Service
 *
 * 화면이 꺼지거나 다른 앱으로 전환되어도 OS가 프로세스를 종료하거나
 * WiFi/CPU 슬립(Doze Mode)에 빠지는 것을 원천 차단합니다.
 */
class TidalPlaybackService : Service() {

    companion object {
        const val CHANNEL_ID = "tidal_playback_service_channel"
        const val NOTIFICATION_ID = 1001
        private const val TAG = "TidalPlaybackService"

        const val ACTION_START = "ACTION_START"
        const val ACTION_UPDATE = "ACTION_UPDATE"
        const val ACTION_STOP = "ACTION_STOP"

        const val EXTRA_TITLE = "EXTRA_TITLE"
        const val EXTRA_ARTIST = "EXTRA_ARTIST"

        fun startService(context: Context, title: String = "Tidal Connect Lite", artist: String = "재생 중...") {
            val intent = Intent(context, TidalPlaybackService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_ARTIST, artist)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun updateNotification(context: Context, title: String, artist: String) {
            val intent = Intent(context, TidalPlaybackService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_ARTIST, artist)
            }
            context.startService(intent)
        }

        fun stopService(context: Context) {
            val intent = Intent(context, TidalPlaybackService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireLocks()
        Log.i(TAG, "🚀 백그라운드 재생 서비스 및 WakeLock/WifiLock 활성화")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Tidal Connect Lite"
        val artist = intent?.getStringExtra(EXTRA_ARTIST) ?: "오디오 스트리밍 중"

        when (action) {
            ACTION_START, ACTION_UPDATE -> {
                val notification = buildNotification(title, artist)
                startForeground(NOTIFICATION_ID, notification)
            }
            ACTION_STOP -> {
                releaseLocks()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    /**
     * 사용자가 최근 앱(Recents)에서 앱을 스와이프하여 종료했을 때
     * 네이티브 플레이어를 즉시 멈추고 서비스를 완전 정리합니다.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.i(TAG, "📱 앱 태스크 종료 감지 (Task Removed) -> 모든 오디오 재생 완전 중단")
        try {
            TidalPlayerManager.stopAll()
            releaseLocks()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        } catch (e: Exception) {
            Log.e(TAG, "Task Removed 정리 오류: ${e.message}")
        }
    }

    private fun buildNotification(title: String, artist: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(artist)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "TIDAL 재생 서비스",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "백그라운드 음악 재생 및 DLNA 프록시 스트리밍을 유지합니다."
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }
    }

    private fun acquireLocks() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = powerManager?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "TidalConnect:PlaybackWakeLock")
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire(24 * 60 * 60 * 1000L) // 최대 24시간

            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            wifiLock = wifiManager?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "TidalConnect:StreamingWifiLock")
            wifiLock?.setReferenceCounted(false)
            wifiLock?.acquire()
        } catch (e: Exception) {
            Log.w(TAG, "WakeLock / WifiLock 획득 예외: ${e.message}")
        }
    }

    private fun releaseLocks() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "WakeLock / WifiLock 해제 예외: ${e.message}")
        }
    }

    override fun onDestroy() {
        releaseLocks()
        Log.i(TAG, "⏹ 백그라운드 재생 서비스 종료 및 Lock 해제")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
