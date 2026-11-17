package com.example.tidal_connect_lite

import io.kotest.property.Arb
import io.kotest.property.arbitrary.bind
import io.kotest.property.arbitrary.boolean
import io.kotest.property.arbitrary.byte
import io.kotest.property.arbitrary.byteArray
import io.kotest.property.arbitrary.choice
import io.kotest.property.arbitrary.constant
import io.kotest.property.arbitrary.element
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.list
import io.kotest.property.arbitrary.map

/** DASH 속성의 입력: 초기화 세그먼트(없을 수 있음)와 세그먼트들의 바이트. */
class ProxyDashContent(val init: ByteArray?, val segments: List<ByteArray>) {
    override fun toString(): String =
        "ProxyDashContent(init=${init?.size ?: "없음"}바이트, segments=${segments.map { it.size }}바이트)"
}

/** DASH 탐색 속성(P-PS-1)의 입력: 내용, 세그먼트마다의 시각, 시작 위치(밀리초). */
class ProxyDashSeek(val content: ProxyDashContent, val timing: DashTiming, val positionMs: Long) {
    override fun toString(): String = "ProxyDashSeek($content, $timing, positionMs=$positionMs)"
}

/**
 * 프록시 속성 테스트의 생성기. 범위는 `domain-entities.md` 4절을 따른다.
 * Kotest의 기본 `Arb`와 조합 함수로만 만들고 축소 설정은 건드리지 않는다.
 */
object ProxyGenerators {
    private val knownMimes = listOf(
        "audio/flac",
        "audio/mp4",
        "audio/m4a",
        "audio/aac",
        "audio/mpeg",
        "application/octet-stream",
        "",
    )

    /** 섞어 쓸 조각. 모두 소문자이고 공백만으로 된 조각은 없다(대문자·공백 MIME은 입력 범위 밖). */
    private val mimeFragments = listOf(
        "flac", "mp4", "m4a", "aac", "mpeg",
        "audio/", "application/", "x-", "; codecs=", "octet-stream", "ogg", "wav", "/", "-", ";", "=",
    )

    /** MIME 문자열: 알려진 MIME 7개(빈 문자열 포함)와, 낱말을 섞은 문자열(예: `audio/x-flac; codecs=mp4`). */
    val mimeString: Arb<String> = Arb.choice(
        Arb.element(knownMimes),
        Arb.list(Arb.element(mimeFragments), 1..5).map { it.joinToString("") },
    )

    /** 등록 횟수 0 ~ 10. */
    val registrationCount: Arb<Int> = Arb.int(0..10)

    /** 등록 0 ~ 10회에 쓸 MIME 목록. 목록의 길이가 등록 횟수다. */
    val registrationMimes: Arb<List<String>> = Arb.list(mimeString, 0..10)

    /** 문서용 예약 대역(192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24)의 IPv4 주소. */
    private val documentationIpv4: Arb<String> =
        Arb.bind(Arb.element("192.0.2", "198.51.100", "203.0.113"), Arb.int(0..255)) { net, host -> "$net.$host" }

    /** 공백이 아닌 인쇄 가능 ASCII 1 ~ 12자. */
    private val shortText: Arb<String> =
        Arb.list(Arb.int(0x21..0x7e), 1..12).map { codes -> codes.map { it.toChar() }.joinToString("") }

    /** 허용 주소: 빈 문자열, `127.0.0.1`, 문서용 예약 대역의 주소, `localhost`, 임의의 짧은 문자열. */
    val allowedHost: Arb<String> = Arb.choice(
        Arb.constant(""),
        Arb.constant("127.0.0.1"),
        documentationIpv4,
        Arb.constant("localhost"),
        shortText,
    )

    /** Range 값: `bytes=a-b`(0 ≤ a ≤ b < 1,000,000)와 `bytes=a-`. */
    val rangeValue: Arb<String> =
        Arb.bind(Arb.int(0..999_999), Arb.int(0..999_999), Arb.boolean()) { x, y, openEnded ->
            val a = minOf(x, y)
            val b = maxOf(x, y)
            if (openEnded) "bytes=$a-" else "bytes=$a-$b"
        }

    /** 바이트 내용: 길이 0 ~ 65,536. 경계 길이(0, 1, 65,536)가 자주 나오게 섞는다. */
    val byteContent: Arb<ByteArray> = Arb.byteArray(
        Arb.choice(Arb.element(0, 1, 65_536), Arb.int(0..65_536)),
        Arb.byte(),
    )

    private val segmentBytes: Arb<ByteArray> = Arb.byteArray(Arb.int(1..4_096), Arb.byte())

    /** DASH 내용: 초기화 세그먼트 있음/없음, 세그먼트 1 ~ 8개, 각 길이 1 ~ 4,096. */
    val dashContent: Arb<ProxyDashContent> =
        Arb.bind(Arb.boolean(), segmentBytes, Arb.list(segmentBytes, 1..8)) { hasInit, init, segments ->
            ProxyDashContent(if (hasInit) init else null, segments)
        }

    /**
     * DASH 탐색 입력: [dashContent]의 세그먼트마다 길이 `d`를 하나씩 붙이고, timescale과 시작 위치를 고른다.
     * 시작 위치는 곡 안 · 세그먼트 경계와 그 앞뒤 1ms · 0 이하 · 곡 길이 밖이 섞여 나온다.
     */
    val dashSeek: Arb<ProxyDashSeek> = Arb.bind(
        dashContent,
        DashGenerators.timescale,
        Arb.list(DashGenerators.duration, 8..8),
        DashGenerators.positionPick,
    ) { content, timescale, durations, pick ->
        val timing = DashTiming(timescale, durations.take(content.segments.size))
        ProxyDashSeek(content, timing, pick.positionIn(timing))
    }
}
