package com.example.tidal_connect_lite

import io.kotest.property.Arb
import io.kotest.property.arbitrary.bind
import io.kotest.property.arbitrary.boolean
import io.kotest.property.arbitrary.choice
import io.kotest.property.arbitrary.constant
import io.kotest.property.arbitrary.element
import io.kotest.property.arbitrary.filter
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.list
import io.kotest.property.arbitrary.map
import io.kotest.property.arbitrary.orNull

// PlaybackCommandRouter 속성 테스트(P-CR-1 ~ P-CR-6)의 입력 생성기.
// 범위는 `domain-entities.md` 4절을 따른다. 타입이 계약과 다른 인자는 만들지 않는다.
// Kotest의 기본 Arb와 조합 함수만 쓰고 축소 설정은 건드리지 않는다.

/** 채널 호출 하나. [args]에 없는 키는 "인자 없음"이다. */
data class RouterCall(val method: String, val args: Map<String, Any?>)

/** 플레이어가 던질 예외와, 그때 router가 오류 메시지로 돌려줘야 하는 문자열. */
data class RouterThrown(val exception: RuntimeException, val expectedMessage: String)

/** `registerTrackStream`의 다섯 인자. null은 "인자 없음"이다. */
data class RouterRegistration(
    val trackId: String?,
    val directUrl: String?,
    val manifestXml: String?,
    val allowedHost: String?,
    val mimeType: String?,
) {
    fun toArgs(): Map<String, Any?> = routerArgsOf(
        "trackId" to trackId,
        "directUrl" to directUrl,
        "manifestXml" to manifestXml,
        "allowedHost" to allowedHost,
        "mimeType" to mimeType,
    )
}

/** 값이 null인 쌍은 빼고 인자 맵을 만든다("인자 없음"을 키가 없는 것으로 표현). */
private fun routerArgsOf(vararg pairs: Pair<String, Any?>): Map<String, Any?> =
    pairs.filter { it.second != null }.toMap()

object RouterArbs {
    /** 채널 메서드 16개(`business-rules.md` 1절의 표). */
    val knownMethods: List<String> = listOf(
        "initTidalAuth",
        "updateUserCredentials",
        "clearUserCredentials",
        "playTrack",
        "pauseTrack",
        "resumeTrack",
        "seekTrack",
        "stopTrack",
        "skipToNext",
        "setNextTrack",
        "setAudioQuality",
        "getPhoneVolume",
        "setPhoneVolume",
        "requestNotificationPermission",
        "setStreamingLock",
        "registerTrackStream",
    )

    private val playerMethods: List<String> = listOf(
        "playTrack",
        "pauseTrack",
        "resumeTrack",
        "seekTrack",
        "stopTrack",
        "skipToNext",
        "setNextTrack",
        "setAudioQuality",
    )

    private val digits: List<Char> = ('0'..'9').toList()
    private val lowercase: List<Char> = ('a'..'z').toList()
    private val uppercase: List<Char> = ('A'..'Z').toList()
    private val letters: List<Char> = lowercase + uppercase
    private val alphanumeric: List<Char> = letters + digits
    private val hex: List<Char> = digits + ('a'..'f').toList()
    private val messageChars: List<Char> = alphanumeric + " .:-_/재생실패오류가났습니다플레이어".toList()

    private fun text(pool: List<Char>, length: IntRange): Arb<String> =
        Arb.list(Arb.element(pool), length).map { it.joinToString("") }

    private val caseChanges: List<(String) -> String> = listOf(
        { name -> name.uppercase() },
        { name -> name.lowercase() },
        { name -> name.replaceFirstChar { it.uppercaseChar() } },
    )

    /** 모르는 메서드 이름: 빈 문자열, 임의의 영문자, 알려진 이름의 대소문자를 바꾼 것, 앞뒤에 글자를 붙인 것. */
    fun unknownMethod(): Arb<String> = Arb.choice(
        Arb.constant(""),
        text(letters, 1..20),
        Arb.bind(Arb.element(knownMethods), Arb.element(caseChanges)) { name, change -> change(name) },
        Arb.bind(Arb.element(knownMethods), Arb.element(letters), Arb.boolean()) { name, letter, front ->
            if (front) "$letter$name" else "$name$letter"
        },
    ).filter { it !in knownMethods }

    /** 플레이어 동작 8개 중 하나의 이름. */
    fun playerMethod(): Arb<String> = Arb.element(playerMethods)

    /** 곡 ID: 숫자 1 ~ 12자리, 그리고 빈 문자열. */
    fun trackId(): Arb<String> = Arb.choice(Arb.constant(""), text(digits, 1..12))

    /** 재생 위치(밀리초): 0 ~ 36,000,000. */
    fun position(): Arb<Int> = Arb.int(0..36_000_000)

    /** 볼륨: -1000 ~ 1000 (범위 밖 값 포함). */
    fun volume(): Arb<Int> = Arb.int(-1000..1000)

    /** 음질 이름: 알려진 4개와 임의의 대문자 문자열. */
    fun quality(): Arb<String> = Arb.choice(
        Arb.element(listOf("LOW", "HIGH", "LOSSLESS", "HI_RES_LOSSLESS")),
        text(uppercase, 1..16),
    )

    /** 자격 증명 문자열(`userId`, `accessToken`, `clientId`, `clientSecret`): 임의의 영숫자. 가짜 값이다. */
    fun credential(): Arb<String> = text(alphanumeric, 0..24)

    /** 토큰 유효 시간(초): 1 ~ 86,400. */
    fun expiresInSeconds(): Arb<Int> = Arb.int(1..86_400)

    private val intOrLongValue: (Int, Boolean) -> Any = { value, asLong -> if (asLong) value.toLong() else value }

    /** 같은 정수를 Int 또는 Long 타입으로. 채널은 값의 크기에 따라 두 타입 가운데 하나로 보낸다. */
    private fun intOrLong(values: Arb<Int>): Arb<Any> = Arb.bind(values, Arb.boolean(), intOrLongValue)

    private fun directUrl(): Arb<String> = Arb.choice(
        Arb.constant(""),
        Arb.bind(
            text(lowercase, 1..8),
            text(digits, 1..9),
            Arb.element(listOf("flac", "m4a", "mp3")),
        ) { host, id, ext -> "https://$host.example.test/$id.$ext" },
    )

    private fun manifestXml(): Arb<String> = Arb.choice(
        Arb.constant(""),
        Arb.bind(text(lowercase, 1..8), text(digits, 1..6)) { id, duration ->
            "<MPD><Period id=\"$id\"><S d=\"$duration\"/></Period></MPD>"
        },
    )

    private fun allowedHost(): Arb<String> = Arb.choice(
        Arb.constant(""),
        Arb.constant("127.0.0.1"),
        Arb.int(1..254).map { host -> "192.0.2.$host" },
    )

    private fun mimeType(): Arb<String> = Arb.element(
        listOf("audio/flac", "audio/mp4", "audio/m4a", "audio/aac", "audio/mpeg", "application/octet-stream", ""),
    )

    /** 등록 인자: 다섯 문자열 각각 있음(빈 문자열 포함) 또는 없음(null). */
    fun registration(): Arb<RouterRegistration> = Arb.bind(
        trackId().orNull(0.3),
        directUrl().orNull(0.3),
        manifestXml().orNull(0.3),
        allowedHost().orNull(0.3),
        mimeType().orNull(0.3),
    ) { trackId, directUrl, manifestXml, allowedHost, mimeType ->
        RouterRegistration(trackId, directUrl, manifestXml, allowedHost, mimeType)
    }

    /** 등록 함수가 돌려줄 URL 모양의 문자열. */
    fun proxyUrl(): Arb<String> = Arb.bind(
        Arb.int(1..254),
        Arb.int(1024..65535),
        text(hex, 16..16),
        Arb.element(listOf("flac", "m4a", "mp3")),
    ) { host, port, token, ext -> "http://192.0.2.$host:$port/audio/$token.$ext" }

    private class ExceptionKind(
        val simpleName: String,
        val withMessage: (String) -> RuntimeException,
        val withoutMessage: () -> RuntimeException,
    )

    // 메시지가 없을 때 기대하는 이름은 규칙 문서(CR-07)의 "패키지 없는 단순 이름"을 리터럴로 적는다.
    private val exceptionKinds: List<ExceptionKind> = listOf(
        ExceptionKind("IllegalStateException", { IllegalStateException(it) }, { IllegalStateException() }),
        ExceptionKind("IllegalArgumentException", { IllegalArgumentException(it) }, { IllegalArgumentException() }),
        ExceptionKind("RuntimeException", { RuntimeException(it) }, { RuntimeException() }),
    )

    /** 예외: 메시지가 있는 것(한글 포함, 빈 문자열 포함)과 없는 것. 클래스는 세 가지. */
    fun thrown(): Arb<RouterThrown> = Arb.choice(
        Arb.bind(Arb.element(exceptionKinds), text(messageChars, 0..30)) { kind, message ->
            RouterThrown(kind.withMessage(message), expectedMessage = message)
        },
        Arb.element(exceptionKinds).map { kind ->
            RouterThrown(kind.withoutMessage(), expectedMessage = kind.simpleName)
        },
    )

    private fun noArgCall(method: String): Arb<RouterCall> = Arb.constant(RouterCall(method, emptyMap()))

    private fun trackCall(method: String): Arb<RouterCall> =
        trackId().orNull(0.3).map { RouterCall(method, routerArgsOf("trackId" to it)) }

    private fun seekCall(): Arb<RouterCall> =
        intOrLong(position()).orNull(0.3).map { RouterCall("seekTrack", routerArgsOf("positionMs" to it)) }

    private fun qualityCall(): Arb<RouterCall> =
        quality().orNull(0.3).map { RouterCall("setAudioQuality", routerArgsOf("quality" to it)) }

    /** 플레이어 동작 8개 중 하나와 그 인자(각각 있거나 없음). */
    fun playerCall(): Arb<RouterCall> = Arb.choice(
        trackCall("playTrack"),
        noArgCall("pauseTrack"),
        noArgCall("resumeTrack"),
        seekCall(),
        noArgCall("stopTrack"),
        noArgCall("skipToNext"),
        trackCall("setNextTrack"),
        qualityCall(),
    )

    /** 임의의 채널 호출: 16개 메서드 중 하나와 그 인자(각각 있거나 없음). */
    fun call(): Arb<RouterCall> = Arb.choice(
        playerCall(),
        Arb.bind(credential().orNull(0.3), credential().orNull(0.3)) { clientId, clientSecret ->
            RouterCall("initTidalAuth", routerArgsOf("clientId" to clientId, "clientSecret" to clientSecret))
        },
        Arb.bind(
            credential().orNull(0.3),
            credential().orNull(0.3),
            intOrLong(expiresInSeconds()).orNull(0.3),
        ) { userId, accessToken, expires ->
            RouterCall(
                "updateUserCredentials",
                routerArgsOf("userId" to userId, "accessToken" to accessToken, "expiresInSeconds" to expires),
            )
        },
        noArgCall("clearUserCredentials"),
        noArgCall("getPhoneVolume"),
        volume().orNull(0.3).map { RouterCall("setPhoneVolume", routerArgsOf("percent" to it)) },
        noArgCall("requestNotificationPermission"),
        Arb.boolean().orNull(0.3).map { RouterCall("setStreamingLock", routerArgsOf("enabled" to it)) },
        registration().map { RouterCall("registerTrackStream", it.toArgs()) },
    )
}
