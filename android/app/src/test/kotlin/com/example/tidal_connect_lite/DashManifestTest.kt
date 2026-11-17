package com.example.tidal_connect_lite

import io.kotest.property.checkAll
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DashManifestTest {
    private val mpd = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static">
          <Period>
            <AdaptationSet contentType="audio" mimeType="audio/mp4">
              <Representation id="FLAC,96000,24" codecs="flac" bandwidth="4000000" audioSamplingRate="96000">
                <SegmentTemplate timescale="96000"
                    initialization="https://sp.example.test/0.mp4?token=abc&amp;x=1"
                    media="https://sp.example.test/${'$'}Number${'$'}.mp4?token=abc&amp;x=1"
                    startNumber="1">
                  <SegmentTimeline>
                    <S d="384000" r="3"/>
                    <S d="120000"/>
                  </SegmentTimeline>
                </SegmentTemplate>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
    """.trimIndent()

    @Test
    fun parsesTemplateAndCountsRepeatedSegments() {
        val m = DashManifest.parse(mpd)
        assertNotNull(m)
        m!!
        assertEquals("https://sp.example.test/0.mp4?token=abc&x=1", m.initializationUrl)
        assertEquals(1, m.startNumber)
        // r="3"은 4개, 마지막 S 1개 → 5개
        assertEquals(5, m.segmentCount)
        assertEquals("https://sp.example.test/1.mp4?token=abc&x=1", m.segmentUrl(0))
        assertEquals("https://sp.example.test/5.mp4?token=abc&x=1", m.segmentUrl(4))
    }

    @Test
    fun resolvesRelativeUrlsAgainstBaseUrl() {
        val relative = """
            <MPD><Period><BaseURL>https://cdn.example.test/track/</BaseURL>
              <AdaptationSet><Representation>
                <SegmentTemplate initialization="init.mp4" media="seg-${'$'}Number${'$'}.mp4" startNumber="0">
                  <SegmentTimeline><S d="1"/><S d="1"/></SegmentTimeline>
                </SegmentTemplate>
              </Representation></AdaptationSet>
            </Period></MPD>
        """.trimIndent()
        val m = DashManifest.parse(relative)!!
        assertEquals("https://cdn.example.test/track/init.mp4", m.initializationUrl)
        assertEquals("https://cdn.example.test/track/seg-0.mp4", m.segmentUrl(0))
        assertEquals(2, m.segmentCount)
    }

    @Test
    fun returnsNullForMissingTemplateOrMalformedXml() {
        assertNull(DashManifest.parse("<MPD><Period/></MPD>"))
        assertNull(DashManifest.parse("not xml"))
        assertNull(
            DashManifest.parse(
                """<MPD><SegmentTemplate media="a${'$'}Number${'$'}"><SegmentTimeline/></SegmentTemplate></MPD>""",
            ),
        )
    }

    @Test
    fun rejectsDoctypeDeclarations() {
        val xxe = """<?xml version="1.0"?><!DOCTYPE MPD [<!ENTITY x SYSTEM "file:///etc/passwd">]>""" +
            """<MPD><SegmentTemplate media="&x;"><SegmentTimeline><S d="1"/></SegmentTimeline></SegmentTemplate></MPD>"""
        assertNull(DashManifest.parse(xxe))
    }

    // ---------------------------------------------------------------- 세그먼트 시각 (dash-seek 규칙 1절, DS-01 ~ DS-05)
    // 위의 기존 테스트 4개는 DS-06(기존 필드 · segmentUrl 은 바뀌지 않는다)의 보호 테스트라 고치지 않는다.

    /** `SegmentTemplate` 속성([templateAttributes])과 `SegmentTimeline` 내용([timeline])만 다른 최소 MPD. */
    private fun timedMpd(templateAttributes: String, timeline: String): String =
        """<MPD><Period><AdaptationSet><Representation>""" +
            """<SegmentTemplate $templateAttributes initialization="https://cdn.example.test/init.mp4" """ +
            """media="https://cdn.example.test/${'$'}Number${'$'}.mp4" startNumber="1">""" +
            """<SegmentTimeline>$timeline</SegmentTimeline>""" +
            """</SegmentTemplate></Representation></AdaptationSet></Period></MPD>"""

    /** DS-01 의 예: timescale 44100, 4초 세그먼트 3개와 2초 세그먼트 1개. 시작 시각 0, 4000, 8000, 12000. 곡 길이 14000. */
    private val exampleMpd = timedMpd("""timescale="44100"""", """<S d="176400" r="2"/><S d="88200"/>""")

    private fun startsOf(m: DashManifest): List<Long> = (0 until m.segmentCount).map { m.segmentStartMs(it) }

    @Test
    fun `DS-01 세그먼트의 시작 시각은 앞 세그먼트들의 길이 합을 밀리초로 바꿔 버림한 값이다`() {
        // DS-01: r 반복을 세지 않거나, timescale 로 나누지 않거나(없으면 1), 반올림하거나, 세그먼트마다 버림한 값을 더하면 실패
        val cases: List<Triple<String, String, List<Long>>> = listOf(
            // 규칙 문서의 예
            Triple("a 문서의 예", exampleMpd, listOf(0L, 4000L, 8000L, 12000L)),
            // timescale 속성이 없으면 1: d 가 초 단위다
            Triple("b timescale 없음", timedMpd("", """<S d="4" r="2"/><S d="2"/>"""), listOf(0L, 4000L, 8000L, 12000L)),
            // 1000 × 1000 ÷ 44100 = 22.67…, 2000 × 1000 ÷ 44100 = 45.35… (반올림이면 23, 따로 버림해 더하면 44)
            Triple("c 버림", timedMpd("""timescale="44100"""", """<S d="1000" r="2"/>"""), listOf(0L, 22L, 45L)),
            // 이 파일 맨 위의 매니페스트: timescale 96000, 4초 세그먼트 4개와 1.25초 세그먼트 1개
            Triple("d 96000", mpd, listOf(0L, 4000L, 8000L, 12000L, 16000L)),
        )
        for ((label, xml, expected) in cases) {
            val m = DashManifest.parse(xml)!!
            assertEquals("DS-01 $label: 시작 시각", expected, startsOf(m))
        }
    }

    @Test
    fun `DS-02 위치가 속한 세그먼트는 시작 시각이 그 위치 이하인 것 가운데 마지막이다`() {
        // DS-02: 경계(4000, 12000)에서 앞 세그먼트를 고르거나(< 로 비교), 경계 바로 앞(3999, 11999)에서 다음 세그먼트를 고르면 실패
        val m = DashManifest.parse(exampleMpd)!!
        val expected = listOf(
            0L to 0,
            3999L to 0,
            4000L to 1,
            7999L to 1,
            8000L to 2,
            11999L to 2,
            12000L to 3,
        )
        for ((positionMs, index) in expected) {
            assertEquals("DS-02 위치 $positionMs", index, m.segmentIndexAt(positionMs))
        }
    }

    @Test
    fun `DS-03 위치가 0 이하이면 0 번째 세그먼트다`() {
        // DS-03: 음수 위치에서 -1 을 돌려주거나 예외를 내면 실패
        val m = DashManifest.parse(exampleMpd)!!
        for (positionMs in listOf(0L, -1L, -4000L, Long.MIN_VALUE)) {
            assertEquals("DS-03 위치 $positionMs", 0, m.segmentIndexAt(positionMs))
        }
    }

    @Test
    fun `DS-04 위치가 곡 길이 이상이면 마지막 세그먼트다`() {
        // DS-04: 곡 길이(14000) 이상에서 segmentCount(4)를 돌려주거나 예외를 내거나 0 으로 돌아가면 실패
        val m = DashManifest.parse(exampleMpd)!!
        for (positionMs in listOf(14000L, 14001L, 3_600_000L, Long.MAX_VALUE)) {
            assertEquals("DS-04 위치 $positionMs", 3, m.segmentIndexAt(positionMs))
        }
    }

    @Test
    fun `DS-05 길이를 알 수 없는 S 가 있거나 timescale 이 0 이하이면 시각은 모두 0 이고 해석은 그대로 성공한다`() {
        // DS-05: 그런 매니페스트의 해석을 거부하거나(null), 알 수 있는 세그먼트만으로 시각을 계산하거나, 0 으로 나누다 예외를 내면 실패
        val cases: List<Triple<String, String, Int>> = listOf(
            Triple("a d 없음", timedMpd("""timescale="44100"""", """<S d="176400" r="2"/><S/>"""), 4),
            Triple("b d 가 숫자가 아님", timedMpd("""timescale="44100"""", """<S d="abc"/><S d="176400"/>"""), 2),
            Triple("c d 가 0", timedMpd("""timescale="44100"""", """<S d="176400"/><S d="0"/><S d="176400"/>"""), 3),
            Triple("d d 가 음수", timedMpd("""timescale="44100"""", """<S d="176400"/><S d="-5"/>"""), 2),
            Triple("e timescale 이 0", timedMpd("""timescale="0"""", """<S d="176400" r="2"/><S d="88200"/>"""), 4),
            Triple("f timescale 이 음수", timedMpd("""timescale="-1"""", """<S d="176400" r="2"/><S d="88200"/>"""), 4),
        )
        for ((label, xml, count) in cases) {
            val m = DashManifest.parse(xml)
            assertNotNull("DS-05 $label: 해석 결과", m)
            m!!
            assertEquals("DS-05 $label: segmentCount", count, m.segmentCount)
            assertEquals("DS-05 $label: initializationUrl", "https://cdn.example.test/init.mp4", m.initializationUrl)
            assertEquals("DS-05 $label: 0 번째 주소", "https://cdn.example.test/1.mp4", m.segmentUrl(0))
            assertEquals("DS-05 $label: 시작 시각", List(count) { 0L }, startsOf(m))
            for (positionMs in listOf(-1L, 0L, 4000L, 12000L, 3_600_000L)) {
                assertEquals("DS-05 $label: 위치 $positionMs 의 세그먼트", 0, m.segmentIndexAt(positionMs))
            }
        }
    }

    // ---------------------------------------------------------------- 속성 테스트

    @Test
    fun `P-DS-1 어떤 타임라인이든 시작 시각은 줄어들지 않고 시작 시각으로 찾은 세그먼트의 시작 시각은 그 시각이다`() {
        // P-DS-1: 번호가 늘 때 시각이 줄거나, 세그먼트의 시작 시각으로 찾은 세그먼트가 다른 시각에서 시작하면 실패.
        // 모든 시각이 0 인 구현이 그냥 통과하지 않도록, 마지막에 DS-01 의 식을 옮긴 참조 모델과도 비교한다
        property {
            checkAll(pbt(100), DashGenerators.timeline) { case ->
                val m = DashManifest.parse(case.manifestXml())!!
                assertEquals("$case 의 segmentCount", case.timing.startsMs.size, m.segmentCount)
                val starts = startsOf(m)
                for (i in 1 until starts.size) {
                    assertTrue("$case: ${i}번째 시각 ${starts[i]} 이 앞의 ${starts[i - 1]} 보다 작다", starts[i] >= starts[i - 1])
                }
                for (i in starts.indices) {
                    val found = m.segmentIndexAt(starts[i])
                    assertEquals("$case: ${i}번째 시각 ${starts[i]} 으로 찾은 ${found}번째의 시각", starts[i], m.segmentStartMs(found))
                }
                assertEquals("$case 의 시작 시각", case.timing.startsMs, starts)
            }
        }
    }

    @Test
    fun `P-DS-2 어떤 위치든 찾은 세그먼트는 범위 안이고 그 위치를 품는다`() {
        // P-DS-2: 번호가 범위를 벗어나거나, 찾은 세그먼트가 위치보다 뒤에서 시작하거나, 위치가 다음 세그먼트의 시작 시각 이상이면 실패.
        // 위치가 0 이하일 때는 DS-03 에 따라 0 번째인지만 본다 (0 번째와 1 번째가 같은 밀리초로 버림되는 경우 때문, 경계 표의 "정한 것")
        property {
            checkAll(pbt(100), DashGenerators.timeline, DashGenerators.positionPick) { case, pick ->
                val m = DashManifest.parse(case.manifestXml())!!
                val p = pick.positionIn(case.timing)

                val k = m.segmentIndexAt(p)

                assertTrue("$case 위치 $p: 번호 $k 가 0 ~ ${m.segmentCount - 1} 밖", k in 0 until m.segmentCount)
                assertTrue(
                    "$case 위치 $p: ${k}번째의 시각 ${m.segmentStartMs(k)} 이 위치보다 뒤",
                    m.segmentStartMs(k) <= maxOf(p, 0L),
                )
                if (p <= 0L) {
                    assertEquals("$case 위치 $p: 0 이하의 위치", 0, k)
                } else if (k < m.segmentCount - 1) {
                    assertTrue(
                        "$case 위치 $p: ${k}번째를 골랐는데 다음 세그먼트의 시각 ${m.segmentStartMs(k + 1)} 이 위치 이하",
                        p < m.segmentStartMs(k + 1),
                    )
                }
            }
        }
    }
}
