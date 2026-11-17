package com.example.tidal_connect_lite

import io.kotest.property.Arb
import io.kotest.property.arbitrary.bind
import io.kotest.property.arbitrary.choice
import io.kotest.property.arbitrary.element
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.list
import io.kotest.property.arbitrary.long

// DASH 세그먼트 시각 속성(P-DS-1 · 2, P-PS-1)의 입력 생성기와 참조 모델.
// Kotest의 기본 Arb와 조합 함수만 쓰고 축소 설정은 건드리지 않는다.

/**
 * 세그먼트 시각의 참조 모델. dash-seek `business-rules.md` 1절의 문장을 그대로 옮겼다.
 *
 * - DS-01: 시작 시각 = 앞 세그먼트들의 `d` 합 × 1000 ÷ timescale (정수, 버림)
 * - DS-02 ~ DS-04: 위치가 0 이하면 0번, 아니면 시작 시각이 위치 이하인 세그먼트 가운데 마지막 것
 *
 * [durations]는 세그먼트마다의 `d`(timescale 단위)다.
 */
class DashTiming(val timescale: Int, val durations: List<Long>) {
    /** 세그먼트마다의 시작 시각(밀리초). */
    val startsMs: List<Long> = durations.indices.map { index -> durations.take(index).sum() * 1000 / timescale }

    /** 곡 전체 길이(밀리초, 버림). */
    val totalMs: Long = durations.sum() * 1000 / timescale

    /** [positionMs]가 속한 세그먼트의 번호(0부터). */
    fun indexAt(positionMs: Long): Int = if (positionMs <= 0) 0 else startsMs.indexOfLast { it <= positionMs }

    /** 세그먼트마다 `<S d="..."/>` 하나씩 적은 `SegmentTimeline` 내용. */
    fun timelineXml(): String = durations.joinToString("") { """<S d="$it"/>""" }

    override fun toString(): String = "DashTiming(timescale=$timescale, durations=$durations, startsMs=$startsMs)"
}

/** 매니페스트 속성의 입력: timescale과 `<S d r>` 묶음들. [runs]의 한 쌍은 (`d`, `r`)이다. */
class DashTimelineCase(val timescale: Int, val runs: List<Pair<Long, Int>>) {
    /** `r`을 풀어 쓴 참조 모델. */
    val timing = DashTiming(timescale, runs.flatMap { (d, r) -> List(r + 1) { d } })

    /** 이 타임라인을 담은 최소 MPD. `r`이 0이면 `r` 속성을 적지 않는다. */
    fun manifestXml(): String {
        val timeline = runs.joinToString("") { (d, r) -> if (r > 0) """<S d="$d" r="$r"/>""" else """<S d="$d"/>""" }
        return """<MPD><Period><AdaptationSet><Representation>""" +
            """<SegmentTemplate timescale="$timescale" media="https://cdn.example.test/${'$'}Number${'$'}.mp4" startNumber="1">""" +
            """<SegmentTimeline>$timeline</SegmentTimeline>""" +
            """</SegmentTemplate></Representation></AdaptationSet></Period></MPD>"""
    }

    override fun toString(): String = "DashTimelineCase(timescale=$timescale, runs=$runs, startsMs=${timing.startsMs})"
}

/**
 * 위치를 고르는 방법. 타임라인이 정해진 뒤 [positionIn]으로 실제 위치(밀리초)를 얻는다.
 *
 * - 방식 0: 곡 길이의 [permille]/1000 지점 (1000을 넘으면 곡 길이 밖)
 * - 방식 1: [snap]번째(세그먼트 수로 나눈 나머지) 세그먼트의 시작 시각에 [nudge](-1, 0, 1)를 더한 값
 * - 방식 2: 0 이하의 값(-[permille])
 */
class DashPositionPick(val mode: Int, val permille: Int, val snap: Int, val nudge: Int) {
    fun positionIn(timing: DashTiming): Long = when (mode) {
        0 -> timing.totalMs * permille / 1000
        1 -> timing.startsMs[snap % timing.startsMs.size] + nudge
        else -> -permille.toLong()
    }

    override fun toString(): String = "DashPositionPick(mode=$mode, permille=$permille, snap=$snap, nudge=$nudge)"
}

object DashGenerators {
    /** timescale: 1(속성이 없을 때의 값), 1000, 그리고 흔한 샘플레이트. */
    val timescale: Arb<Int> = Arb.element(1, 1000, 44_100, 48_000, 96_000)

    /** 세그먼트 길이 `d`: 아주 짧은 값(같은 밀리초로 버림되는 경우), 임의의 값, TIDAL 에서 흔한 값. */
    val duration: Arb<Long> = Arb.choice(
        Arb.long(1L..50L),
        Arb.long(1L..500_000L),
        Arb.element(88_200L, 176_400L, 384_000L),
    )

    /** `<S d r>` 묶음 1 ~ 6개, `r`은 0 ~ 3 (세그먼트 1 ~ 24개). */
    val timeline: Arb<DashTimelineCase> = Arb.bind(
        timescale,
        Arb.list(Arb.bind(duration, Arb.int(0..3)) { d, r -> d to r }, 1..6),
    ) { scale, runs -> DashTimelineCase(scale, runs) }

    /** 위치를 고르는 방법 (세 방식이 고르게 나온다). */
    val positionPick: Arb<DashPositionPick> =
        Arb.bind(Arb.int(0..2), Arb.int(0..1200), Arb.int(0..63), Arb.int(-1..1)) { mode, permille, snap, nudge ->
            DashPositionPick(mode, permille, snap, nudge)
        }
}
