package com.example.tidal_connect_lite

/**
 * [PlaybackCommandRouter]가 돌려주는 채널 명령의 결과.
 *
 * Flutter·Android 타입에 의존하지 않는다. 채널 응답으로 옮기는 일은 `ChannelAdapter.kt`가 맡는다.
 */
sealed interface CommandResult {
    /** 성공. [value]는 채널로 돌려줄 값(맵, 정수, 불리언, null). */
    data class Success(val value: Any?) : CommandResult

    /** 실패. Flutter에는 오류 코드와 메시지로 전달된다. */
    data class Error(val code: String, val message: String?) : CommandResult

    /** 모르는 메서드. */
    data object NotImplemented : CommandResult
}

/** TIDAL 플레이어 제어. 실패하면 예외를 던진다. 운영 구현은 [TidalPlayerManager]. */
interface PlayerControls {
    fun playTrack(trackId: String)
    fun pause()
    fun resume()
    fun seekTo(msec: Int)
    fun stop()
    fun skipToNext()
    fun setNextTrack(trackId: String)
    fun setAudioQuality(name: String)
}

/** 인증 제어. 운영 구현은 [PlaybackCore] 안에 있다. */
interface AuthControls {
    /** 인증을 초기화하고, 성공하면 플레이어를 만들어 초기화한다. 반환값은 인증 초기화의 성공 여부. */
    fun initialize(clientId: String, clientSecret: String): Boolean
    fun updateUserCredentials(userId: String, accessToken: String, expiresInSeconds: Long)
    fun clearUserCredentials()
}

/** 폰 볼륨, 알림 권한, Wi-Fi 잠금. 운영 구현은 [PlaybackCore] 안에 있다. */
interface DeviceControls {
    /** 폰 미디어 볼륨(0~100). */
    fun phoneVolumePercent(): Int
    fun setPhoneVolumePercent(percent: Int)

    /** 알림 권한을 요청한다. 이미 허용되었거나 필요 없으면 true. */
    fun requestNotificationPermission(): Boolean
    fun setWifiLock(enabled: Boolean)
}

/** DLNA 프록시에 곡을 등록한다. 운영 구현은 [PlaybackCore] 안에 있다. */
fun interface ProxyRegistrar {
    /** 스피커가 접근할 프록시 주소를 돌려준다. Wi-Fi가 없어 프록시를 띄울 수 없으면 null. */
    fun registerTrackStream(
        trackId: String,
        directUrl: String,
        manifestXml: String,
        allowedHost: String,
        mimeType: String,
    ): String?
}
