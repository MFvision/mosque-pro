package sa.zood.nearmosque.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * Ayah of the day and Hadith of the day, from shared/daily/daily.json (built by tools/build_daily.py). Everyone sees
 * the same verse and hadith on the same calendar date. Mirrors ios NMCore DailyContent.swift; both are checked against
 * shared/fixtures/daily.json.
 */
@Serializable
data class DailyContent(val epoch: String, val ayat: List<Ayah>, val hadith: List<Hadith>) {
    @Serializable
    data class SurahName(val ar: String, val en: String, val translit: String)

    @Serializable
    data class Ayah(
        /** "2:255" or "94:5-6". */
        val ref: String,
        val surah: Int,
        val first: Int,
        val last: Int,
        val surahName: SurahName,
        /** The Arabic text, with each verse's number in ornate brackets. */
        val ar: String,
        /** Translation by language code (en, es, fr, id, tr, ur). */
        val translations: Map<String, String>,
    ) {
        /** The translation for this language, or English when there is none. */
        fun translation(lang: String): String? = if (lang == "ar") null else translations[lang] ?: translations["en"]
    }

    @Serializable
    data class HadithText(val text: String, val grade: String, val source: String)

    @Serializable
    data class Hadith(
        /** HadeethEnc's item number. */
        val id: Int,
        val ar: HadithText,
        val translations: Map<String, HadithText>,
        val url: String,
    ) {
        /** The hadith in this language (Arabic for ar), or English when there is none. */
        fun text(lang: String): HadithText = if (lang == "ar") ar else translations[lang] ?: translations["en"] ?: ar
    }

    /** The verse for a calendar date (the person's local date). */
    fun ayah(date: LocalDate): Ayah = ayat[index(date, ayat.size)]

    fun hadith(date: LocalDate): Hadith = hadith[index(date, hadith.size)]

    companion object {
        private val EPOCH: LocalDate = LocalDate.of(2026, 1, 1)
        private val json = Json { ignoreUnknownKeys = true }

        fun load(text: String): DailyContent = json.decodeFromString(serializer(), text)

        /** Whole days since 2026-01-01, wrapped to the list (dates before it wrap backwards). */
        fun index(date: LocalDate, count: Int): Int {
            require(count > 0)
            return Math.floorMod(ChronoUnit.DAYS.between(EPOCH, date), count.toLong()).toInt()
        }
    }
}
