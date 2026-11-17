package com.example.tidal_connect_lite

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * `ChannelAdapter.kt`의 변환 함수 테스트 (`business-rules.md` 2절의 PC-01, PC-02).
 *
 * PC-01 가운데 "메서드 이름을 router에 넘긴다"는 `PlaybackCore.onMethodCall`에 있어 여기서 보지 않는다.
 */
class ChannelAdapterTest {
    /** 받은 채널 응답을 순서대로 남기는 [MethodChannel.Result]. */
    private class RecordingResult : MethodChannel.Result {
        val responses = mutableListOf<List<Any?>>()

        override fun success(result: Any?) {
            responses += listOf("success", result)
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            responses += listOf("error", errorCode, errorMessage, errorDetails)
        }

        override fun notImplemented() {
            responses += listOf("notImplemented")
        }
    }

    @Test
    fun `PC-01 인자가 맵이면 키와 값과 타입을 그대로 돌려준다`() {
        // PC-01 (a): 인자 맵을 버리거나(빈 맵) 값의 타입을 바꾸면(Long → Int) 실패
        val call = MethodCall("seekTrack", mapOf("trackId" to "101", "positionMs" to 90000L, "enabled" to true))

        val arguments = channelArguments(call)

        assertEquals(mapOf("trackId" to "101", "positionMs" to 90000L, "enabled" to true), arguments)
    }

    @Test
    fun `PC-01 인자가 맵이 아니면 빈 맵을 돌려준다`() {
        // PC-01 (b): null · 문자열 · 목록 · 숫자. 형 변환 예외를 내거나 값을 맵에 담아 돌려주면 실패
        for (arguments in listOf(null, "101", listOf("101"), 42)) {
            val call = MethodCall("playTrack", arguments)

            assertEquals("arguments=$arguments", emptyMap<String, Any?>(), channelArguments(call))
        }
    }

    @Test
    fun `PC-02 성공 결과는 그 값으로 success 를 한 번 보낸다`() {
        // PC-02 (a): 값 4종(맵 · 정수 · 불리언 · null). 응답을 보내지 않거나 두 번 보내거나 값이 바뀌면 실패
        for (value in listOf(mapOf("status" to "paused"), 37, true, null)) {
            val recorder = RecordingResult()

            sendCommandResult(CommandResult.Success(value), recorder)

            assertEquals("value=$value", listOf(listOf("success", value)), recorder.responses)
        }
    }

    @Test
    fun `PC-02 오류 결과는 코드와 메시지와 null 로 error 를 한 번 보낸다`() {
        // PC-02 (b): 메시지가 있는 경우와 null 인 경우. success 로 보내거나 코드 · 메시지가 바뀌거나 details 가 null 이 아니면 실패
        val withMessage = RecordingResult()
        val withoutMessage = RecordingResult()

        sendCommandResult(CommandResult.Error("PLAYER_ERROR", "TIDAL Player가 초기화되지 않았습니다"), withMessage)
        sendCommandResult(CommandResult.Error("PLAYER_ERROR", null), withoutMessage)

        assertEquals(
            "메시지 있음",
            listOf(listOf("error", "PLAYER_ERROR", "TIDAL Player가 초기화되지 않았습니다", null)),
            withMessage.responses,
        )
        assertEquals("메시지 null", listOf(listOf("error", "PLAYER_ERROR", null, null)), withoutMessage.responses)
    }

    @Test
    fun `PC-02 미구현 결과는 notImplemented 를 한 번 보낸다`() {
        // PC-02 (c): 응답을 보내지 않거나 success(null) · error 로 보내면 실패
        val recorder = RecordingResult()

        sendCommandResult(CommandResult.NotImplemented, recorder)

        assertEquals(listOf(listOf("notImplemented")), recorder.responses)
    }
}
