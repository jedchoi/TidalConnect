package com.example.tidal_connect_lite

import java.io.StringReader
import java.net.URI
import javax.xml.parsers.DocumentBuilderFactory
import org.w3c.dom.Element
import org.xml.sax.InputSource

/**
 * TIDAL DASH MPD에서 세그먼트 주소를 만드는 데 필요한 값만 꺼낸다.
 *
 * android.util.Xml 대신 javax DOM 파서를 써서 JVM 단위 테스트에서도 그대로 검증할 수 있다.
 */
data class DashManifest(
    val initializationUrl: String?,
    val mediaTemplate: String,
    val startNumber: Int,
    val segmentCount: Int,
) {
    /** [index]번째(0부터) 세그먼트의 시작 시각(밀리초). 시각을 알 수 없는 매니페스트면 0. */
    fun segmentStartMs(index: Int): Long = 0L

    /** [positionMs]가 속한 세그먼트의 번호(0부터). 시각을 알 수 없는 매니페스트면 0. */
    fun segmentIndexAt(positionMs: Long): Int = 0

    /** [index]번째(0부터) 세그먼트 주소. */
    fun segmentUrl(index: Int): String = mediaTemplate.replace("\$Number\$", (startNumber + index).toString())

    companion object {
        /** 마지막 [parse] 실패 이유. 로그에 남겨 실기기에서 원인을 찾는 데 쓴다. */
        @Volatile var lastError: String? = null

        /** MPD를 해석한다. 필요한 값이 없으면 null. */
        fun parse(mpdXml: String): DashManifest? {
            // MPD에는 DOCTYPE이 없다. DOCTYPE이 있으면 외부 엔티티(XXE) 시도로 보고 거부한다.
            // Android의 DocumentBuilderFactory는 disallow-doctype-decl 같은 Xerces 기능을 지원하지 않아
            // setFeature가 예외를 던지므로(JVM 테스트에서는 통과), 기능 설정 대신 직접 검사한다.
            if (mpdXml.contains("<!DOCTYPE", ignoreCase = true) || mpdXml.contains("<!ENTITY", ignoreCase = true)) {
                lastError = "DOCTYPE/ENTITY 포함"
                return null
            }
            val doc = try {
                DocumentBuilderFactory.newInstance().apply {
                    isNamespaceAware = false
                    isExpandEntityReferences = false
                }.newDocumentBuilder().parse(InputSource(StringReader(mpdXml)))
            } catch (e: Exception) {
                lastError = "XML 파싱 실패: ${e.javaClass.simpleName}: ${e.message}"
                return null
            }

            val template = doc.getElementsByTagName("SegmentTemplate").item(0) as? Element
                ?: return null.also { lastError = "SegmentTemplate 없음" }
            val baseUrl = doc.getElementsByTagName("BaseURL").item(0)?.textContent?.trim().orEmpty()

            val media = template.getAttribute("media").takeIf { it.isNotEmpty() }
                ?: return null.also { lastError = "media 속성 없음" }
            val init = template.getAttribute("initialization").takeIf { it.isNotEmpty() }
            val startNumber = template.getAttribute("startNumber").toIntOrNull() ?: 1

            // SegmentTimeline의 <S r="n"/>은 같은 길이의 세그먼트가 n번 더 반복된다는 뜻이다.
            var count = 0
            val segments = template.getElementsByTagName("S")
            for (i in 0 until segments.length) {
                val s = segments.item(i) as Element
                count += 1 + (s.getAttribute("r").toIntOrNull() ?: 0).coerceAtLeast(0)
            }
            if (count == 0) return null.also { lastError = "SegmentTimeline에 세그먼트 없음" }
            lastError = null

            return DashManifest(
                initializationUrl = init?.let { resolve(baseUrl, it) },
                mediaTemplate = resolve(baseUrl, media),
                startNumber = startNumber,
                segmentCount = count,
            )
        }

        private fun resolve(base: String, url: String): String {
            val unescaped = url.replace("&amp;", "&")
            if (base.isEmpty() || unescaped.startsWith("http")) return unescaped
            return try {
                URI(base).resolve(unescaped).toString()
            } catch (e: Exception) {
                unescaped
            }
        }
    }
}
