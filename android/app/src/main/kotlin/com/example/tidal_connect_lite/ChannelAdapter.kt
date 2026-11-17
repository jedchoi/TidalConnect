package com.example.tidal_connect_lite

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

// Flutter 채널 타입과 PlaybackCommandRouter 사이의 변환.
// router는 Flutter 타입을 모르므로, 채널에 닿는 코드는 이 파일에만 둔다.

/** 채널 호출의 인자를 router가 읽는 맵으로 바꾼다. 인자가 맵이 아니면 빈 맵을 돌려준다. */
fun channelArguments(call: MethodCall): Map<String, Any?> {
    @Suppress("UNCHECKED_CAST")
    return call.arguments as? Map<String, Any?> ?: emptyMap()
}

/** router의 결과를 채널 응답으로 보낸다. */
fun sendCommandResult(commandResult: CommandResult, result: MethodChannel.Result) {
    when (commandResult) {
        is CommandResult.Success -> result.success(commandResult.value)
        is CommandResult.Error -> result.error(commandResult.code, commandResult.message, null)
        CommandResult.NotImplemented -> result.notImplemented()
    }
}
