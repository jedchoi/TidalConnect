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
    /** [index]번째(0부터) 세그먼트 주소. */
    fun segmentUrl(index: Int): String = mediaTemplate.replace("\$Number\$", (startNumber + index).toString())

    companion object {
        /** MPD를 해석한다. 필요한 값이 없으면 null. */
        fun parse(mpdXml: String): DashManifest? {
            val doc = try {
                DocumentBuilderFactory.newInstance().apply {
                    isNamespaceAware = false
                    // 외부 엔티티를 읽지 않는다(XXE 방지)
                    setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
                }.newDocumentBuilder().parse(InputSource(StringReader(mpdXml)))
            } catch (e: Exception) {
                return null
            }

            val template = doc.getElementsByTagName("SegmentTemplate").item(0) as? Element ?: return null
            val baseUrl = doc.getElementsByTagName("BaseURL").item(0)?.textContent?.trim().orEmpty()

            val media = template.getAttribute("media").takeIf { it.isNotEmpty() } ?: return null
            val init = template.getAttribute("initialization").takeIf { it.isNotEmpty() }
            val startNumber = template.getAttribute("startNumber").toIntOrNull() ?: 1

            // SegmentTimeline의 <S r="n"/>은 같은 길이의 세그먼트가 n번 더 반복된다는 뜻이다.
            var count = 0
            val segments = template.getElementsByTagName("S")
            for (i in 0 until segments.length) {
                val s = segments.item(i) as Element
                count += 1 + (s.getAttribute("r").toIntOrNull() ?: 0).coerceAtLeast(0)
            }
            if (count == 0) return null

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
