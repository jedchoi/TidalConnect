package com.example.tidal_connect_lite

// PlaybackCommandRouter 테스트용 fake 4개.
// 받은 호출을 `함수이름(인자1, 인자2)` 문자열로 순서대로 남긴다. 문자열 인자에 따옴표를 붙이지 않으므로
// 빈 문자열은 빈 자리로 보인다(예: `playTrack()`, `initialize(, )`).
// `failure`가 있으면 호출을 기록한 뒤 그 예외를 던진다. 값 범위 제한이나 상태 변화 같은 판단은 하지 않는다.

/** [PlayerControls] fake. */
class FakePlayerControls : PlayerControls {
    val calls = mutableListOf<String>()
    var failure: RuntimeException? = null

    private fun record(call: String) {
        calls += call
        failure?.let { throw it }
    }

    override fun playTrack(trackId: String) = record("playTrack($trackId)")

    override fun pause() = record("pause()")

    override fun resume() = record("resume()")

    override fun seekTo(msec: Int) = record("seekTo($msec)")

    override fun stop() = record("stop()")

    override fun skipToNext() = record("skipToNext()")

    override fun setNextTrack(trackId: String) = record("setNextTrack($trackId)")

    override fun setAudioQuality(name: String) = record("setAudioQuality($name)")
}

/** [AuthControls] fake. [initializeResult]가 `initialize`의 반환값이다. */
class FakeAuthControls : AuthControls {
    val calls = mutableListOf<String>()
    var initializeResult: Boolean = true
    var failure: RuntimeException? = null

    private fun record(call: String) {
        calls += call
        failure?.let { throw it }
    }

    override fun initialize(clientId: String, clientSecret: String): Boolean {
        record("initialize($clientId, $clientSecret)")
        return initializeResult
    }

    override fun updateUserCredentials(userId: String, accessToken: String, expiresInSeconds: Long) =
        record("updateUserCredentials($userId, $accessToken, $expiresInSeconds)")

    override fun clearUserCredentials() = record("clearUserCredentials()")
}

/** [DeviceControls] fake. 볼륨과 알림 권한의 반환값을 지정할 수 있다. */
class FakeDeviceControls : DeviceControls {
    val calls = mutableListOf<String>()
    var volumePercent: Int = 37
    var notificationPermission: Boolean = true
    var failure: RuntimeException? = null

    private fun record(call: String) {
        calls += call
        failure?.let { throw it }
    }

    override fun phoneVolumePercent(): Int {
        record("phoneVolumePercent()")
        return volumePercent
    }

    override fun setPhoneVolumePercent(percent: Int) = record("setPhoneVolumePercent($percent)")

    override fun requestNotificationPermission(): Boolean {
        record("requestNotificationPermission()")
        return notificationPermission
    }

    override fun setWifiLock(enabled: Boolean) = record("setWifiLock($enabled)")
}

/**
 * [ProxyRegistrar] fake. [result]가 null이면 Wi-Fi가 없는 경우다.
 * 기본 결과는 시작 오프셋 0(처음부터)인 등록이다.
 */
class FakeProxyRegistrar : ProxyRegistrar {
    val calls = mutableListOf<String>()
    var result: RegisteredStream? = RegisteredStream("http://192.0.2.1:8765/audio/0123456789abcdef.flac", 0L)
    var failure: RuntimeException? = null

    override fun registerTrackStream(
        trackId: String,
        directUrl: String,
        manifestXml: String,
        allowedHost: String,
        mimeType: String,
        startPositionMs: Long,
    ): RegisteredStream? {
        calls += "registerTrackStream($trackId, $directUrl, $manifestXml, $allowedHost, $mimeType, $startPositionMs)"
        failure?.let { throw it }
        return result
    }
}
