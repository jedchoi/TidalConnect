package com.example.tidal_connect_lite

import io.kotest.property.Arb
import io.kotest.property.arbitrary.boolean
import io.kotest.property.checkAll
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * [PlaybackCommandRouter] 테스트.
 *
 * 규칙은 `business-rules.md` 1절(CR-01 ~ CR-13), 속성은 `business-logic-model.md` 3절(P-CR-1 ~ P-CR-6)이다.
 * 기대값은 규칙 문서의 값을 그대로 적었다. 결과(`CommandResult`)와 fake가 받은 호출을 함께 본다.
 */
class PlaybackCommandRouterTest {
    private companion object {
        const val PLAYER_MISSING = "TIDAL Player가 초기화되지 않았습니다"
        const val PROXY_URL = "http://192.0.2.1:8765/audio/0123456789abcdef.flac"
    }

    /** fake 4개와 router 한 벌. [currentPlayer]가 null이면 "플레이어가 아직 없음"이다. */
    private class Harness(playerPresent: Boolean = true) {
        val auth = FakeAuthControls()
        val player = FakePlayerControls()
        val device = FakeDeviceControls()
        val proxy = FakeProxyRegistrar()
        var currentPlayer: PlayerControls? = if (playerPresent) player else null
        val router = PlaybackCommandRouter(auth, { currentPlayer }, device, proxy)

        /** fake 4개가 지금까지 받은 호출 전체. */
        fun recorded(): Map<String, List<String>> = mapOf(
            "auth" to auth.calls.toList(),
            "player" to player.calls.toList(),
            "device" to device.calls.toList(),
            "proxy" to proxy.calls.toList(),
        )
    }

    /** 표를 도는 테스트의 한 줄. */
    private class Row(
        val label: String,
        val method: String,
        val args: Map<String, Any?> = emptyMap(),
        val setup: (Harness) -> Unit = {},
        val expectedResult: CommandResult,
        val expectedCalls: Map<String, List<String>>,
    )

    /** 플레이어 동작 하나와, 그때 플레이어 fake에 남아야 하는 호출 문자열. */
    private class PlayerAction(val method: String, val args: Map<String, Any?>, val call: String)

    // CR-05 · CR-07 의 플레이어 동작. 앞의 7개는 플레이어가 없으면 오류가 되는 동작이고 마지막이 stopTrack 이다.
    private val playerActions = listOf(
        PlayerAction("playTrack", mapOf("trackId" to "101"), "playTrack(101)"),
        PlayerAction("pauseTrack", emptyMap(), "pause()"),
        PlayerAction("resumeTrack", emptyMap(), "resume()"),
        PlayerAction("seekTrack", mapOf("positionMs" to 90000), "seekTo(90000)"),
        PlayerAction("skipToNext", emptyMap(), "skipToNext()"),
        PlayerAction("setNextTrack", mapOf("trackId" to "102"), "setNextTrack(102)"),
        PlayerAction("setAudioQuality", mapOf("quality" to "HIGH"), "setAudioQuality(HIGH)"),
        PlayerAction("stopTrack", emptyMap(), "stop()"),
    )

    private val registerArgs = mapOf(
        "trackId" to "101",
        "directUrl" to "https://cdn.example.test/101.flac",
        "manifestXml" to "<MPD/>",
        "allowedHost" to "192.0.2.10",
        "mimeType" to "audio/flac",
    )
    private val registerCall =
        "registerTrackStream(101, https://cdn.example.test/101.flac, <MPD/>, 192.0.2.10, audio/flac)"

    private fun ok(vararg pairs: Pair<String, Any?>): CommandResult = CommandResult.Success(mapOf(*pairs))

    /** 기대하는 호출 기록. 적지 않은 fake는 호출이 없어야 한다. */
    private fun calls(
        auth: List<String> = emptyList(),
        player: List<String> = emptyList(),
        device: List<String> = emptyList(),
        proxy: List<String> = emptyList(),
    ): Map<String, List<String>> = mapOf("auth" to auth, "player" to player, "device" to device, "proxy" to proxy)

    /** 줄마다 새 fake와 새 router로 호출하고 결과와 호출 기록을 비교한다. */
    private fun runRows(rule: String, rows: List<Row>, playerPresent: Boolean = true) {
        for (row in rows) {
            val h = Harness(playerPresent)
            row.setup(h)
            val result = h.router.handle(row.method, row.args)
            assertEquals("$rule ${row.label}: 결과", row.expectedResult, result)
            assertEquals("$rule ${row.label}: 호출 기록", row.expectedCalls, h.recorded())
        }
    }

    /** [block]이 던진 예외를 돌려준다. 예외 없이 결과가 돌아오면 실패다. */
    private fun thrownBy(label: String, block: () -> CommandResult): Throwable {
        val result = try {
            block()
        } catch (e: Throwable) {
            return e
        }
        throw AssertionError("$label: 예외가 그대로 전파되어야 하는데 결과가 돌아왔다 <$result>")
    }

    // ---------------------------------------------------------------- 예시 기반 테스트

    @Test
    fun `CR-01 표의 16개 메서드는 정해진 협력 객체 호출 1회와 정해진 성공 값을 만든다`() {
        // CR-01: 메서드 표 17줄. 다른 협력 객체를 부르거나, 인자 · 반환 맵의 키나 값이 표와 다르면 실패
        val rows = listOf(
            Row(
                "#1 initTidalAuth",
                "initTidalAuth",
                mapOf("clientId" to "test-client-id", "clientSecret" to "test-client-secret"),
                setup = { it.auth.initializeResult = true },
                expectedResult = ok(
                    "status" to "initialized",
                    "sdk" to "com.tidal.sdk",
                    "clientId" to "test-client-id",
                ),
                expectedCalls = calls(auth = listOf("initialize(test-client-id, test-client-secret)")),
            ),
            Row(
                "#2 updateUserCredentials",
                "updateUserCredentials",
                mapOf("userId" to "user-1", "accessToken" to "test-access-token", "expiresInSeconds" to 7200),
                expectedResult = ok("status" to "updated", "userId" to "user-1"),
                expectedCalls = calls(auth = listOf("updateUserCredentials(user-1, test-access-token, 7200)")),
            ),
            Row(
                "#3 clearUserCredentials",
                "clearUserCredentials",
                expectedResult = ok("status" to "cleared"),
                expectedCalls = calls(auth = listOf("clearUserCredentials()")),
            ),
            Row(
                "#4 playTrack",
                "playTrack",
                mapOf("trackId" to "101"),
                expectedResult = ok("status" to "playing", "trackId" to "101"),
                expectedCalls = calls(player = listOf("playTrack(101)")),
            ),
            Row(
                "#5 pauseTrack",
                "pauseTrack",
                expectedResult = ok("status" to "paused"),
                expectedCalls = calls(player = listOf("pause()")),
            ),
            Row(
                "#6 resumeTrack",
                "resumeTrack",
                expectedResult = ok("status" to "resumed"),
                expectedCalls = calls(player = listOf("resume()")),
            ),
            Row(
                "#7 seekTrack",
                "seekTrack",
                mapOf("positionMs" to 90000),
                expectedResult = ok("status" to "seeked", "positionMs" to 90000),
                expectedCalls = calls(player = listOf("seekTo(90000)")),
            ),
            Row(
                "#8 stopTrack",
                "stopTrack",
                expectedResult = ok("status" to "stopped"),
                expectedCalls = calls(player = listOf("stop()")),
            ),
            Row(
                "#9 skipToNext",
                "skipToNext",
                expectedResult = ok("status" to "skipped_to_next"),
                expectedCalls = calls(player = listOf("skipToNext()")),
            ),
            Row(
                "#10 setNextTrack",
                "setNextTrack",
                mapOf("trackId" to "102"),
                expectedResult = ok("status" to "next_track_set", "trackId" to "102"),
                expectedCalls = calls(player = listOf("setNextTrack(102)")),
            ),
            Row(
                "#11 setAudioQuality",
                "setAudioQuality",
                mapOf("quality" to "HI_RES_LOSSLESS"),
                expectedResult = ok("status" to "quality_set", "quality" to "HI_RES_LOSSLESS"),
                expectedCalls = calls(player = listOf("setAudioQuality(HI_RES_LOSSLESS)")),
            ),
            Row(
                "#12 getPhoneVolume",
                "getPhoneVolume",
                setup = { it.device.volumePercent = 37 },
                expectedResult = CommandResult.Success(37),
                expectedCalls = calls(device = listOf("phoneVolumePercent()")),
            ),
            Row(
                "#13 setPhoneVolume",
                "setPhoneVolume",
                mapOf("percent" to 42),
                expectedResult = CommandResult.Success(null),
                expectedCalls = calls(device = listOf("setPhoneVolumePercent(42)")),
            ),
            Row(
                "#14 requestNotificationPermission (true)",
                "requestNotificationPermission",
                setup = { it.device.notificationPermission = true },
                expectedResult = CommandResult.Success(true),
                expectedCalls = calls(device = listOf("requestNotificationPermission()")),
            ),
            Row(
                "#15 requestNotificationPermission (false)",
                "requestNotificationPermission",
                setup = { it.device.notificationPermission = false },
                expectedResult = CommandResult.Success(false),
                expectedCalls = calls(device = listOf("requestNotificationPermission()")),
            ),
            Row(
                "#16 setStreamingLock",
                "setStreamingLock",
                mapOf("enabled" to true),
                expectedResult = CommandResult.Success(null),
                expectedCalls = calls(device = listOf("setWifiLock(true)")),
            ),
            Row(
                "#17 registerTrackStream",
                "registerTrackStream",
                registerArgs,
                setup = { it.proxy.result = "http://192.0.2.1:8765/audio/0123456789abcdef.flac" },
                expectedResult = ok("proxyUrl" to "http://192.0.2.1:8765/audio/0123456789abcdef.flac"),
                expectedCalls = calls(
                    proxy = listOf(
                        "registerTrackStream(101, https://cdn.example.test/101.flac, <MPD/>, 192.0.2.10, audio/flac)",
                    ),
                ),
            ),
        )

        runRows("CR-01", rows)
    }

    @Test
    fun `CR-02 인자 맵이 비어 있으면 표의 기본값을 쓴다`() {
        // CR-02 (a): 인자가 있는 메서드 9개를 빈 맵으로 호출. 기본값이 표와 다르면(예: quality 가 빈 문자열) 실패
        val rows = listOf(
            Row(
                "#1 initTidalAuth",
                "initTidalAuth",
                expectedResult = ok("status" to "initialized", "sdk" to "com.tidal.sdk", "clientId" to ""),
                expectedCalls = calls(auth = listOf("initialize(, )")),
            ),
            Row(
                "#2 updateUserCredentials",
                "updateUserCredentials",
                expectedResult = ok("status" to "updated", "userId" to ""),
                expectedCalls = calls(auth = listOf("updateUserCredentials(, , 3600)")),
            ),
            Row(
                "#3 playTrack",
                "playTrack",
                expectedResult = ok("status" to "playing", "trackId" to ""),
                expectedCalls = calls(player = listOf("playTrack()")),
            ),
            Row(
                "#4 seekTrack",
                "seekTrack",
                expectedResult = ok("status" to "seeked", "positionMs" to 0),
                expectedCalls = calls(player = listOf("seekTo(0)")),
            ),
            Row(
                "#5 setNextTrack",
                "setNextTrack",
                expectedResult = ok("status" to "next_track_set", "trackId" to ""),
                expectedCalls = calls(player = listOf("setNextTrack()")),
            ),
            Row(
                "#6 setAudioQuality",
                "setAudioQuality",
                expectedResult = ok("status" to "quality_set", "quality" to "LOSSLESS"),
                expectedCalls = calls(player = listOf("setAudioQuality(LOSSLESS)")),
            ),
            Row(
                "#7 setPhoneVolume",
                "setPhoneVolume",
                expectedResult = CommandResult.Success(null),
                expectedCalls = calls(device = listOf("setPhoneVolumePercent(0)")),
            ),
            Row(
                "#8 setStreamingLock",
                "setStreamingLock",
                expectedResult = CommandResult.Success(null),
                expectedCalls = calls(device = listOf("setWifiLock(false)")),
            ),
            Row(
                "#9 registerTrackStream",
                "registerTrackStream",
                expectedResult = ok("proxyUrl" to PROXY_URL),
                expectedCalls = calls(proxy = listOf("registerTrackStream(, , , , audio/mp4)")),
            ),
        )

        runRows("CR-02 (a)", rows)
    }

    @Test
    fun `CR-02 일부 키만 있으면 없는 인자에만 기본값을 쓴다`() {
        // CR-02 (b): 있는 인자는 그대로, 없는 인자만 기본값. 있는 인자까지 기본값으로 덮거나 없는 인자에서 실패하면 실패
        val rows = listOf(
            Row(
                "① updateUserCredentials",
                "updateUserCredentials",
                mapOf("userId" to "user-1"),
                expectedResult = ok("status" to "updated", "userId" to "user-1"),
                expectedCalls = calls(auth = listOf("updateUserCredentials(user-1, , 3600)")),
            ),
            Row(
                "② initTidalAuth",
                "initTidalAuth",
                mapOf("clientId" to "test-client-id"),
                expectedResult = ok(
                    "status" to "initialized",
                    "sdk" to "com.tidal.sdk",
                    "clientId" to "test-client-id",
                ),
                expectedCalls = calls(auth = listOf("initialize(test-client-id, )")),
            ),
            Row(
                "③ registerTrackStream",
                "registerTrackStream",
                mapOf("trackId" to "101", "manifestXml" to "<MPD/>"),
                expectedResult = ok("proxyUrl" to PROXY_URL),
                expectedCalls = calls(proxy = listOf("registerTrackStream(101, , <MPD/>, , audio/mp4)")),
            ),
        )

        runRows("CR-02 (b)", rows)
    }

    @Test
    fun `CR-02 키는 있는데 값이 null 이면 없는 인자처럼 기본값을 쓴다`() {
        // CR-02 (c): null 값은 인자가 없는 것과 같다. null 을 그대로 넘기려다 예외가 나거나 "null" 문자열이 되면 실패
        val rows = listOf(
            Row(
                "① playTrack",
                "playTrack",
                mapOf("trackId" to null),
                expectedResult = ok("status" to "playing", "trackId" to ""),
                expectedCalls = calls(player = listOf("playTrack()")),
            ),
            Row(
                "② seekTrack",
                "seekTrack",
                mapOf("positionMs" to null),
                expectedResult = ok("status" to "seeked", "positionMs" to 0),
                expectedCalls = calls(player = listOf("seekTo(0)")),
            ),
            Row(
                "③ setAudioQuality",
                "setAudioQuality",
                mapOf("quality" to null),
                expectedResult = ok("status" to "quality_set", "quality" to "LOSSLESS"),
                expectedCalls = calls(player = listOf("setAudioQuality(LOSSLESS)")),
            ),
            Row(
                "④ setStreamingLock",
                "setStreamingLock",
                mapOf("enabled" to null),
                expectedResult = CommandResult.Success(null),
                expectedCalls = calls(device = listOf("setWifiLock(false)")),
            ),
            Row(
                "⑤ updateUserCredentials",
                "updateUserCredentials",
                mapOf("userId" to "user-1", "accessToken" to null, "expiresInSeconds" to null),
                expectedResult = ok("status" to "updated", "userId" to "user-1"),
                expectedCalls = calls(auth = listOf("updateUserCredentials(user-1, , 3600)")),
            ),
            Row(
                "⑥ registerTrackStream",
                "registerTrackStream",
                mapOf("trackId" to "101", "mimeType" to null),
                expectedResult = ok("proxyUrl" to PROXY_URL),
                expectedCalls = calls(proxy = listOf("registerTrackStream(101, , , , audio/mp4)")),
            ),
        )

        runRows("CR-02 (c)", rows)
    }

    @Test
    fun `CR-03 표에 없는 메서드는 미구현이고 협력 객체를 부르지 않는다`() {
        // CR-03: 대소문자가 다르거나 글자가 붙은 이름도 모르는 메서드다. 비슷한 이름을 알려진 메서드로 처리하면 실패
        for (method in listOf("unknownMethod", "", "PlayTrack", "playtrack", "playTrackX", "xplayTrack")) {
            val h = Harness()

            val result = h.router.handle(method, mapOf("trackId" to "101"))

            assertEquals("CR-03 '$method': 결과", CommandResult.NotImplemented, result)
            assertEquals("CR-03 '$method': 호출 기록", calls(), h.recorded())
        }
    }

    @Test
    fun `CR-04 인증 초기화가 성공하면 status 가 initialized 인 성공 값이다`() {
        // CR-04 (a): auth.initialize 가 true. status 가 다르거나 sdk · clientId 가 빠지면 실패
        val h = Harness()
        h.auth.initializeResult = true

        val result = h.router.handle(
            "initTidalAuth",
            mapOf("clientId" to "test-client-id", "clientSecret" to "test-client-secret"),
        )

        assertEquals(ok("status" to "initialized", "sdk" to "com.tidal.sdk", "clientId" to "test-client-id"), result)
        assertEquals(calls(auth = listOf("initialize(test-client-id, test-client-secret)")), h.recorded())
    }

    @Test
    fun `CR-04 인증 초기화가 실패해도 오류가 아니라 status 가 init_failed 인 성공 값이다`() {
        // CR-04 (b): auth.initialize 가 false. Error 로 돌려주거나 status 를 initialized 로 고정하면 실패
        val h = Harness()
        h.auth.initializeResult = false

        val result = h.router.handle(
            "initTidalAuth",
            mapOf("clientId" to "test-client-id", "clientSecret" to "test-client-secret"),
        )

        assertEquals(ok("status" to "init_failed", "sdk" to "com.tidal.sdk", "clientId" to "test-client-id"), result)
        assertEquals(calls(auth = listOf("initialize(test-client-id, test-client-secret)")), h.recorded())
    }

    @Test
    fun `CR-05 플레이어가 없으면 플레이어 동작 7개는 PLAYER_ERROR 다`() {
        // CR-05: stopTrack 을 뺀 7개. 성공으로 답하거나 코드 · 메시지가 다르거나 다른 협력 객체를 부르면 실패
        for (action in playerActions.filter { it.method != "stopTrack" }) {
            val h = Harness(playerPresent = false)

            val result = h.router.handle(action.method, action.args)

            assertEquals(
                "CR-05 ${action.method}: 결과",
                CommandResult.Error("PLAYER_ERROR", "TIDAL Player가 초기화되지 않았습니다"),
                result,
            )
            assertEquals("CR-05 ${action.method}: 호출 기록", calls(), h.recorded())
        }
    }

    @Test
    fun `CR-06 플레이어가 없어도 stopTrack 은 오류가 아니라 stopped 다`() {
        // CR-06: stopTrack 만 예외다. 나머지 동작처럼 PLAYER_ERROR 로 답하면 실패
        val h = Harness(playerPresent = false)

        val result = h.router.handle("stopTrack", emptyMap())

        assertEquals(ok("status" to "stopped"), result)
        assertEquals(calls(), h.recorded())
    }

    @Test
    fun `CR-07 플레이어가 예외를 던지면 PLAYER_ERROR 이고 메시지는 예외의 메시지다`() {
        // CR-07 (a): 동작 8개(stopTrack 포함). 예외가 밖으로 나오거나 메시지가 예외의 메시지와 다르면 실패
        for (action in playerActions) {
            val h = Harness()
            h.player.failure = IllegalStateException("재생 실패")

            val result = h.router.handle(action.method, action.args)

            assertEquals("CR-07 (a) ${action.method}: 결과", CommandResult.Error("PLAYER_ERROR", "재생 실패"), result)
            assertEquals("CR-07 (a) ${action.method}: 호출 기록", calls(player = listOf(action.call)), h.recorded())
        }
    }

    @Test
    fun `CR-07 예외의 메시지가 null 이면 메시지는 패키지 없는 예외 클래스 이름이다`() {
        // CR-07 (b): 메시지 없는 예외. 메시지가 null · 전체 이름(java.lang 포함) · toString 결과면 실패
        for (action in playerActions) {
            val h = Harness()
            h.player.failure = IllegalStateException()

            val result = h.router.handle(action.method, action.args)

            assertEquals(
                "CR-07 (b) ${action.method}: 결과",
                CommandResult.Error("PLAYER_ERROR", "IllegalStateException"),
                result,
            )
            assertEquals("CR-07 (b) ${action.method}: 호출 기록", calls(player = listOf(action.call)), h.recorded())
        }
    }

    @Test
    fun `CR-07 예외의 메시지가 빈 문자열이면 메시지도 빈 문자열 그대로다`() {
        // CR-07 (c): 빈 문자열은 "메시지 없음" 이 아니다. 클래스 이름으로 바꾸면 실패
        for (action in playerActions) {
            val h = Harness()
            h.player.failure = IllegalStateException("")

            val result = h.router.handle(action.method, action.args)

            assertEquals("CR-07 (c) ${action.method}: 결과", CommandResult.Error("PLAYER_ERROR", ""), result)
            assertEquals("CR-07 (c) ${action.method}: 호출 기록", calls(player = listOf(action.call)), h.recorded())
        }
    }

    @Test
    fun `CR-08 프록시 등록이 null 이면 NO_WIFI 오류다`() {
        // CR-08: Wi-Fi 없음. proxyUrl 이 null 인 성공 값으로 답하거나 코드 · 메시지가 다르면 실패
        val h = Harness()
        h.proxy.result = null

        val result = h.router.handle("registerTrackStream", registerArgs)

        assertEquals(
            CommandResult.Error("NO_WIFI", "Wi-Fi에 연결되어 있지 않아 스피커로 스트리밍할 수 없습니다."),
            result,
        )
        assertEquals(calls(proxy = listOf(registerCall)), h.recorded())
    }

    @Test
    fun `CR-09 enabled 가 true 이면 Wi-Fi 잠금을 건다`() {
        // CR-09 (a): enabled=true 만 setWifiLock(true). 값을 읽지 않고 false 로 넘기면 실패
        val h = Harness()

        val result = h.router.handle("setStreamingLock", mapOf("enabled" to true))

        assertEquals(CommandResult.Success(null), result)
        assertEquals(calls(device = listOf("setWifiLock(true)")), h.recorded())
    }

    @Test
    fun `CR-09 enabled 가 false 이면 Wi-Fi 잠금을 푼다`() {
        // CR-09 (b): enabled=false 는 setWifiLock(false). 키가 있기만 하면 true 로 보면 실패
        val h = Harness()

        val result = h.router.handle("setStreamingLock", mapOf("enabled" to false))

        assertEquals(CommandResult.Success(null), result)
        assertEquals(calls(device = listOf("setWifiLock(false)")), h.recorded())
    }

    @Test
    fun `CR-09 enabled 가 없으면 Wi-Fi 잠금을 푼다`() {
        // CR-09 (c): enabled 없음은 setWifiLock(false). 호출을 건너뛰거나 true 로 넘기면 실패
        val h = Harness()

        val result = h.router.handle("setStreamingLock", emptyMap())

        assertEquals(CommandResult.Success(null), result)
        assertEquals(calls(device = listOf("setWifiLock(false)")), h.recorded())
    }

    @Test
    fun `CR-10 숫자 인자가 Int 로 오면 그 값으로 넘긴다`() {
        // CR-10 (a): positionMs · percent · expiresInSeconds 가 Int. 값이 바뀌거나 기본값(0, 3600)으로 넘어가면 실패
        val rows = listOf(
            Row(
                "① seekTrack",
                "seekTrack",
                mapOf("positionMs" to 90000),
                expectedResult = ok("status" to "seeked", "positionMs" to 90000),
                expectedCalls = calls(player = listOf("seekTo(90000)")),
            ),
            Row(
                "② setPhoneVolume",
                "setPhoneVolume",
                mapOf("percent" to 42),
                expectedResult = CommandResult.Success(null),
                expectedCalls = calls(device = listOf("setPhoneVolumePercent(42)")),
            ),
            Row(
                "③ updateUserCredentials",
                "updateUserCredentials",
                mapOf("userId" to "user-1", "accessToken" to "test-access-token", "expiresInSeconds" to 7200),
                expectedResult = ok("status" to "updated", "userId" to "user-1"),
                expectedCalls = calls(auth = listOf("updateUserCredentials(user-1, test-access-token, 7200)")),
            ),
        )

        runRows("CR-10 (a)", rows)
    }

    @Test
    fun `CR-10 숫자 인자가 Long 으로 와도 같은 값으로 넘기고 positionMs 는 Int 로 돌려준다`() {
        // CR-10 (b): 같은 값이 Long. Int 만 읽어 기본값이 되거나 성공 값의 positionMs 가 Long 그대로면 실패
        val rows = listOf(
            Row(
                "① seekTrack",
                "seekTrack",
                mapOf("positionMs" to 90000L),
                expectedResult = ok("status" to "seeked", "positionMs" to 90000),
                expectedCalls = calls(player = listOf("seekTo(90000)")),
            ),
            Row(
                "② setPhoneVolume",
                "setPhoneVolume",
                mapOf("percent" to 42L),
                expectedResult = CommandResult.Success(null),
                expectedCalls = calls(device = listOf("setPhoneVolumePercent(42)")),
            ),
            Row(
                "③ updateUserCredentials",
                "updateUserCredentials",
                mapOf("userId" to "user-1", "accessToken" to "test-access-token", "expiresInSeconds" to 7200L),
                expectedResult = ok("status" to "updated", "userId" to "user-1"),
                expectedCalls = calls(auth = listOf("updateUserCredentials(user-1, test-access-token, 7200)")),
            ),
        )

        runRows("CR-10 (b)", rows)
    }

    @Test
    fun `CR-11 문자열 자리에 숫자가 오면 인자가 없는 것으로 보고 기본값을 쓴다`() {
        // CR-11 (a): 형 변환 예외를 내거나 숫자를 문자열("101")로 바꿔 넘기면 실패
        val rows = listOf(
            Row(
                "① playTrack",
                "playTrack",
                mapOf("trackId" to 101),
                expectedResult = ok("status" to "playing", "trackId" to ""),
                expectedCalls = calls(player = listOf("playTrack()")),
            ),
            Row(
                "② setAudioQuality",
                "setAudioQuality",
                mapOf("quality" to 1),
                expectedResult = ok("status" to "quality_set", "quality" to "LOSSLESS"),
                expectedCalls = calls(player = listOf("setAudioQuality(LOSSLESS)")),
            ),
            Row(
                "③ registerTrackStream",
                "registerTrackStream",
                mapOf("trackId" to "101", "mimeType" to 5),
                expectedResult = ok("proxyUrl" to PROXY_URL),
                expectedCalls = calls(proxy = listOf("registerTrackStream(101, , , , audio/mp4)")),
            ),
        )

        runRows("CR-11 (a)", rows)
    }

    @Test
    fun `CR-11 정수 자리에 문자열이 오면 인자가 없는 것으로 보고 기본값을 쓴다`() {
        // CR-11 (b): 형 변환 예외를 내거나 문자열을 숫자로 해석("5000" → 5000)하면 실패
        val rows = listOf(
            Row(
                "① seekTrack",
                "seekTrack",
                mapOf("positionMs" to "5000"),
                expectedResult = ok("status" to "seeked", "positionMs" to 0),
                expectedCalls = calls(player = listOf("seekTo(0)")),
            ),
            Row(
                "② setPhoneVolume",
                "setPhoneVolume",
                mapOf("percent" to "42"),
                expectedResult = CommandResult.Success(null),
                expectedCalls = calls(device = listOf("setPhoneVolumePercent(0)")),
            ),
            Row(
                "③ updateUserCredentials",
                "updateUserCredentials",
                mapOf("userId" to "user-1", "accessToken" to "test-access-token", "expiresInSeconds" to "60"),
                expectedResult = ok("status" to "updated", "userId" to "user-1"),
                expectedCalls = calls(auth = listOf("updateUserCredentials(user-1, test-access-token, 3600)")),
            ),
        )

        runRows("CR-11 (b)", rows)
    }

    @Test
    fun `CR-11 불리언 자리에 다른 타입이 오면 false 로 본다`() {
        // CR-11 (c): 정확히 true 가 아니면 false. 문자열 "true" 나 숫자 1 을 참으로 보면 실패
        for (enabled in listOf<Any>("true", 1)) {
            val h = Harness()

            val result = h.router.handle("setStreamingLock", mapOf("enabled" to enabled))

            assertEquals("CR-11 (c) enabled=$enabled: 결과", CommandResult.Success(null), result)
            assertEquals(
                "CR-11 (c) enabled=$enabled: 호출 기록",
                calls(device = listOf("setWifiLock(false)")),
                h.recorded(),
            )
        }
    }

    @Test
    fun `CR-12 인증 협력 객체의 예외는 잡지 않고 그대로 전파한다`() {
        // CR-12 (a): 인증 3개. 예외를 오류 결과로 바꾸거나 다른 예외로 감싸면 실패
        val attempts: List<Triple<String, Map<String, Any?>, String>> = listOf(
            Triple(
                "initTidalAuth",
                mapOf("clientId" to "test-client-id", "clientSecret" to "test-client-secret"),
                "initialize(test-client-id, test-client-secret)",
            ),
            Triple(
                "updateUserCredentials",
                mapOf("userId" to "user-1", "accessToken" to "test-access-token", "expiresInSeconds" to 7200),
                "updateUserCredentials(user-1, test-access-token, 7200)",
            ),
            Triple("clearUserCredentials", emptyMap(), "clearUserCredentials()"),
        )
        for ((method, args, call) in attempts) {
            val h = Harness()
            val failure = IllegalStateException("auth 실패")
            h.auth.failure = failure

            val thrown = thrownBy("CR-12 (a) $method") { h.router.handle(method, args) }

            assertSame("CR-12 (a) $method: 전파된 예외", failure, thrown)
            assertEquals("CR-12 (a) $method: 호출 기록", calls(auth = listOf(call)), h.recorded())
        }
    }

    @Test
    fun `CR-12 기기 협력 객체의 예외는 잡지 않고 그대로 전파한다`() {
        // CR-12 (b): 기기 4개. 예외를 오류 결과로 바꾸거나 다른 예외로 감싸면 실패
        val attempts: List<Triple<String, Map<String, Any?>, String>> = listOf(
            Triple("getPhoneVolume", emptyMap(), "phoneVolumePercent()"),
            Triple("setPhoneVolume", mapOf("percent" to 42), "setPhoneVolumePercent(42)"),
            Triple("requestNotificationPermission", emptyMap(), "requestNotificationPermission()"),
            Triple("setStreamingLock", mapOf("enabled" to true), "setWifiLock(true)"),
        )
        for ((method, args, call) in attempts) {
            val h = Harness()
            val failure = IllegalStateException("device 실패")
            h.device.failure = failure

            val thrown = thrownBy("CR-12 (b) $method") { h.router.handle(method, args) }

            assertSame("CR-12 (b) $method: 전파된 예외", failure, thrown)
            assertEquals("CR-12 (b) $method: 호출 기록", calls(device = listOf(call)), h.recorded())
        }
    }

    @Test
    fun `CR-12 프록시 협력 객체의 예외는 잡지 않고 그대로 전파한다`() {
        // CR-12 (c): 프록시 등록. 예외를 NO_WIFI 같은 오류 결과로 바꾸면 실패
        val h = Harness()
        val failure = IllegalStateException("proxy 실패")
        h.proxy.failure = failure

        val thrown = thrownBy("CR-12 (c) registerTrackStream") { h.router.handle("registerTrackStream", registerArgs) }

        assertSame(failure, thrown)
        assertEquals(calls(proxy = listOf(registerCall)), h.recorded())
    }

    @Test
    fun `CR-13 같은 호출을 두 번 하면 두 번 모두 같은 결과다`() {
        // CR-13 (a): router 는 상태를 갖지 않는다. 두 번째 호출을 건너뛰거나 결과가 달라지면 실패
        val h = Harness()
        h.device.volumePercent = 37

        val firstPlay = h.router.handle("playTrack", mapOf("trackId" to "101"))
        val secondPlay = h.router.handle("playTrack", mapOf("trackId" to "101"))
        val firstVolume = h.router.handle("getPhoneVolume", emptyMap())
        val secondVolume = h.router.handle("getPhoneVolume", emptyMap())

        assertEquals("playTrack 1회째", ok("status" to "playing", "trackId" to "101"), firstPlay)
        assertEquals("playTrack 2회째", ok("status" to "playing", "trackId" to "101"), secondPlay)
        assertEquals("getPhoneVolume 1회째", CommandResult.Success(37), firstVolume)
        assertEquals("getPhoneVolume 2회째", CommandResult.Success(37), secondVolume)
        assertEquals(
            calls(
                player = listOf("playTrack(101)", "playTrack(101)"),
                device = listOf("phoneVolumePercent()", "phoneVolumePercent()"),
            ),
            h.recorded(),
        )
    }

    @Test
    fun `CR-13 플레이어는 호출할 때마다 조회한다`() {
        // CR-13 (b): 처음 조회한 "플레이어 없음" 을 기억해 두면, 플레이어가 생긴 뒤에도 오류가 나와 실패
        val h = Harness(playerPresent = false)

        val before = h.router.handle("playTrack", mapOf("trackId" to "101"))
        h.currentPlayer = h.player
        val after = h.router.handle("playTrack", mapOf("trackId" to "101"))

        assertEquals(
            "플레이어가 없을 때",
            CommandResult.Error("PLAYER_ERROR", "TIDAL Player가 초기화되지 않았습니다"),
            before,
        )
        assertEquals("플레이어가 생긴 뒤", ok("status" to "playing", "trackId" to "101"), after)
        assertEquals(calls(player = listOf("playTrack(101)")), h.recorded())
    }

    // ---------------------------------------------------------------- 속성 테스트

    @Test
    fun `P-CR-1 표에 없는 어떤 이름도 미구현이고 협력 객체 호출이 0회다`() {
        // P-CR-1: 16개 이름이 아닌 문자열. 대소문자를 무시하거나 앞부분만 비교해 알려진 메서드로 처리하면 실패
        property {
            checkAll(pbt(100), RouterArbs.unknownMethod()) { method ->
                val h = Harness()

                val result = h.router.handle(method, emptyMap())

                assertEquals(CommandResult.NotImplemented, result)
                assertEquals(calls(), h.recorded())
            }
        }
    }

    @Test
    fun `P-CR-2 플레이어가 없으면 어떤 인자여도 7개 동작은 PLAYER_ERROR 이고 stopTrack 은 성공이다`() {
        // P-CR-2: 인자에 따라 결과가 달라지거나 플레이어 없이 다른 협력 객체를 부르면 실패
        property {
            checkAll(pbt(100), RouterArbs.playerCall()) { call ->
                val h = Harness(playerPresent = false)

                val result = h.router.handle(call.method, call.args)

                if (call.method == "stopTrack") {
                    assertEquals(ok("status" to "stopped"), result)
                } else {
                    assertEquals(CommandResult.Error("PLAYER_ERROR", PLAYER_MISSING), result)
                }
                assertEquals(calls(), h.recorded())
            }
        }
    }

    @Test
    fun `P-CR-3 플레이어가 어떤 예외를 던져도 PLAYER_ERROR 이고 메시지는 예외의 메시지 또는 클래스 이름이다`() {
        // P-CR-3: 특정 예외 클래스만 잡거나, 메시지가 null 일 때 단순 클래스 이름이 아니면 실패
        property {
            checkAll(pbt(100), RouterArbs.playerMethod(), RouterArbs.thrown()) { method, thrown ->
                val h = Harness()
                h.player.failure = thrown.exception

                val result = h.router.handle(method, emptyMap())

                assertEquals(CommandResult.Error("PLAYER_ERROR", thrown.expectedMessage), result)
                assertEquals(1, h.player.calls.size)
            }
        }
    }

    @Test
    fun `P-CR-4 인자는 어떤 값이든 협력 객체와 성공 값에 그대로 전달된다`() {
        // P-CR-4: 값을 자르거나 범위를 제한하거나 고정값을 돌려주면 실패. positionMs 는 Int · Long 어느 쪽으로 와도 Int 로 실린다
        property {
            checkAll(pbt(100), RouterArbs.trackId()) { trackId ->
                val h = Harness()
                val result = h.router.handle("playTrack", mapOf("trackId" to trackId))
                assertEquals(ok("status" to "playing", "trackId" to trackId), result)
                assertEquals(calls(player = listOf("playTrack($trackId)")), h.recorded())
            }
            checkAll(pbt(100), RouterArbs.trackId()) { trackId ->
                val h = Harness()
                val result = h.router.handle("setNextTrack", mapOf("trackId" to trackId))
                assertEquals(ok("status" to "next_track_set", "trackId" to trackId), result)
                assertEquals(calls(player = listOf("setNextTrack($trackId)")), h.recorded())
            }
            checkAll(pbt(100), RouterArbs.position(), Arb.boolean()) { position, asLong ->
                val h = Harness()
                val argument: Any = if (asLong) position.toLong() else position
                val result = h.router.handle("seekTrack", mapOf("positionMs" to argument))
                assertEquals(ok("status" to "seeked", "positionMs" to position), result)
                assertEquals(calls(player = listOf("seekTo($position)")), h.recorded())
            }
            checkAll(pbt(100), RouterArbs.quality()) { quality ->
                val h = Harness()
                val result = h.router.handle("setAudioQuality", mapOf("quality" to quality))
                assertEquals(ok("status" to "quality_set", "quality" to quality), result)
                assertEquals(calls(player = listOf("setAudioQuality($quality)")), h.recorded())
            }
            checkAll(
                pbt(100),
                RouterArbs.credential(),
                RouterArbs.credential(),
                RouterArbs.expiresInSeconds(),
                Arb.boolean(),
            ) { userId, accessToken, seconds, asLong ->
                val h = Harness()
                val argument: Any = if (asLong) seconds.toLong() else seconds
                val result = h.router.handle(
                    "updateUserCredentials",
                    mapOf("userId" to userId, "accessToken" to accessToken, "expiresInSeconds" to argument),
                )
                assertEquals(ok("status" to "updated", "userId" to userId), result)
                assertEquals(
                    calls(auth = listOf("updateUserCredentials($userId, $accessToken, $seconds)")),
                    h.recorded(),
                )
            }
            checkAll(pbt(100), RouterArbs.volume()) { percent ->
                val h = Harness()
                val result = h.router.handle("setPhoneVolume", mapOf("percent" to percent))
                assertEquals(CommandResult.Success(null), result)
                assertEquals(calls(device = listOf("setPhoneVolumePercent($percent)")), h.recorded())
            }
        }
    }

    @Test
    fun `P-CR-5 등록 인자는 그대로 전달되고 빠진 인자에는 기본값이 들어가며 돌려받은 URL 이 proxyUrl 이다`() {
        // P-CR-5: 인자 순서가 바뀌거나, 빠진 인자의 기본값이 다르거나, proxyUrl 이 등록 함수의 반환값이 아니면 실패
        property {
            checkAll(pbt(100), RouterArbs.registration(), RouterArbs.proxyUrl()) { registration, proxyUrl ->
                val h = Harness()
                h.proxy.result = proxyUrl

                val result = h.router.handle("registerTrackStream", registration.toArgs())

                val trackId = registration.trackId ?: ""
                val directUrl = registration.directUrl ?: ""
                val manifestXml = registration.manifestXml ?: ""
                val allowedHost = registration.allowedHost ?: ""
                val mimeType = registration.mimeType ?: "audio/mp4"
                val expectedCall = "registerTrackStream($trackId, $directUrl, $manifestXml, $allowedHost, $mimeType)"
                assertEquals(ok("proxyUrl" to proxyUrl), result)
                assertEquals(calls(proxy = listOf(expectedCall)), h.recorded())
            }
        }
    }

    @Test
    fun `P-CR-6 어떤 호출이든 두 번 하면 결과가 같다`() {
        // P-CR-6: router 가 이전 호출을 기억해 두 번째 결과나 협력 객체 호출이 달라지면 실패
        property {
            checkAll(pbt(100), RouterArbs.call()) { call ->
                val h = Harness()

                val first = h.router.handle(call.method, call.args)
                val afterFirst = h.recorded()
                val second = h.router.handle(call.method, call.args)

                assertEquals(first, second)
                assertEquals(afterFirst.mapValues { (_, recorded) -> recorded + recorded }, h.recorded())
            }
        }
    }
}
