package com.example.tidal_connect_lite

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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
}
