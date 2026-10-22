package sa.zood.nearmosque.core

import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class DailyContentTest {
    private val daily = DailyContent.load(Fixtures.file("shared/daily/daily.json").readText())

    @Test
    fun sharedFixture() {
        val f = Fixtures.read("shared/fixtures/daily.json").jsonObject
        assertEquals(f["ayatCount"]!!.jsonPrimitive.int, daily.ayat.size)
        assertEquals(f["hadithCount"]!!.jsonPrimitive.int, daily.hadith.size)
        for (c in f["cases"]!!.jsonArray.map { it.jsonObject }) {
            val date = LocalDate.parse(c["date"]!!.jsonPrimitive.content)
            assertEquals(c["ayahIndex"]!!.jsonPrimitive.int, DailyContent.index(date, daily.ayat.size))
            assertEquals("$date", c["ayahRef"]!!.jsonPrimitive.content, daily.ayah(date).ref)
            assertEquals("$date", c["hadithId"]!!.jsonPrimitive.int, daily.hadith(date).id)
        }
    }

    @Test
    fun languages() {
        val a = daily.ayat[0]
        val h = daily.hadith[0]
        assertNull(a.translation("ar"))
        assertEquals(a.translations["en"], a.translation("zz"))
        assertEquals(h.ar, h.text("ar"))
        assertEquals(h.translations["en"], h.text("zz"))
        assertTrue(daily.hadith.all { it.ar.grade == "صحيح" || it.ar.grade == "حسن" })
    }
}
