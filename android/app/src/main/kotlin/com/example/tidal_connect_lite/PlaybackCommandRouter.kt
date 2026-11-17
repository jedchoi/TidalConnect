package com.example.tidal_connect_lite

/**
 * Flutter가 보낸 채널 명령을 협력 객체 호출로 옮기고 결과를 만든다.
 *
 * Android·Flutter 타입에 의존하지 않아 JVM 단위 테스트로 검증할 수 있다.
 * 상태를 갖지 않는다. 플레이어는 인증 초기화가 끝나야 생기므로 호출할 때마다 [player]로 조회한다.
 *
 * @param player 지금의 플레이어. 아직 없으면 null을 돌려준다.
 */
class PlaybackCommandRouter(
    private val auth: AuthControls,
    private val player: () -> PlayerControls?,
    private val device: DeviceControls,
    private val proxy: ProxyRegistrar,
) {
    /**
     * 채널 명령 하나를 처리한다.
     *
     * 인자가 없거나 null이거나 타입이 다르면 기본값을 쓴다. 플레이어 동작의 실패만 오류 결과로 바꾸고,
     * 인증·기기·프록시 협력 객체의 예외는 그대로 전파한다.
     *
     * @param method 채널 메서드 이름
     * @param args 채널 인자. 없으면 빈 맵
     */
    fun handle(method: String, args: Map<String, Any?>): CommandResult = when (method) {
        "initTidalAuth" -> {
            val clientId = args.string("clientId")
            val clientSecret = args.string("clientSecret")
            val isInitialized = auth.initialize(clientId, clientSecret)
            CommandResult.Success(
                mapOf(
                    "status" to if (isInitialized) "initialized" else "init_failed",
                    "sdk" to "com.tidal.sdk",
                    "clientId" to clientId,
                ),
            )
        }
        "updateUserCredentials" -> {
            val userId = args.string("userId")
            val accessToken = args.string("accessToken")
            val expiresInSeconds = args.number("expiresInSeconds")?.toLong() ?: 3600L
            auth.updateUserCredentials(userId, accessToken, expiresInSeconds)
            CommandResult.Success(mapOf("status" to "updated", "userId" to userId))
        }
        "clearUserCredentials" -> {
            auth.clearUserCredentials()
            CommandResult.Success(mapOf("status" to "cleared"))
        }
        "playTrack" -> runPlayerAction {
            val trackId = args.string("trackId")
            requirePlayer().playTrack(trackId)
            mapOf("status" to "playing", "trackId" to trackId)
        }
        "pauseTrack" -> runPlayerAction {
            requirePlayer().pause()
            mapOf("status" to "paused")
        }
        "resumeTrack" -> runPlayerAction {
            requirePlayer().resume()
            mapOf("status" to "resumed")
        }
        "seekTrack" -> runPlayerAction {
            val positionMs = args.number("positionMs")?.toInt() ?: 0
            requirePlayer().seekTo(positionMs)
            mapOf("status" to "seeked", "positionMs" to positionMs)
        }
        "stopTrack" -> runPlayerAction {
            player()?.stop()
            mapOf("status" to "stopped")
        }
        "skipToNext" -> runPlayerAction {
            requirePlayer().skipToNext()
            mapOf("status" to "skipped_to_next")
        }
        "setNextTrack" -> runPlayerAction {
            val trackId = args.string("trackId")
            requirePlayer().setNextTrack(trackId)
            mapOf("status" to "next_track_set", "trackId" to trackId)
        }
        "setAudioQuality" -> runPlayerAction {
            val quality = args.string("quality", "LOSSLESS")
            requirePlayer().setAudioQuality(quality)
            mapOf("status" to "quality_set", "quality" to quality)
        }
        "getPhoneVolume" -> CommandResult.Success(device.phoneVolumePercent())
        "setPhoneVolume" -> {
            device.setPhoneVolumePercent(args.number("percent")?.toInt() ?: 0)
            CommandResult.Success(null)
        }
        "requestNotificationPermission" -> CommandResult.Success(device.requestNotificationPermission())
        "setStreamingLock" -> {
            device.setWifiLock(args["enabled"] == true)
            CommandResult.Success(null)
        }
        "registerTrackStream" -> {
            val proxyUrl = proxy.registerTrackStream(
                trackId = args.string("trackId"),
                directUrl = args.string("directUrl"),
                manifestXml = args.string("manifestXml"),
                allowedHost = args.string("allowedHost"),
                mimeType = args.string("mimeType", "audio/mp4"),
            )
            if (proxyUrl == null) {
                CommandResult.Error("NO_WIFI", "Wi-Fi에 연결되어 있지 않아 스피커로 스트리밍할 수 없습니다.")
            } else {
                CommandResult.Success(mapOf("proxyUrl" to proxyUrl))
            }
        }
        else -> CommandResult.NotImplemented
    }

    private fun requirePlayer(): PlayerControls =
        player() ?: throw IllegalStateException("TIDAL Player가 초기화되지 않았습니다")

    /** 플레이어 동작을 실행하고, 실패하면 오류(PLAYER_ERROR)로 돌려준다. */
    private inline fun runPlayerAction(action: () -> Map<String, Any?>): CommandResult =
        try {
            CommandResult.Success(action())
        } catch (e: Exception) {
            CommandResult.Error("PLAYER_ERROR", e.message ?: e.javaClass.simpleName)
        }

    /** 문자열 인자. 없거나 문자열이 아니면 [default]. */
    private fun Map<String, Any?>.string(key: String, default: String = ""): String = this[key] as? String ?: default

    /** 정수 인자(Int·Long). 없거나 숫자가 아니면 null. */
    private fun Map<String, Any?>.number(key: String): Number? = this[key] as? Number
}
