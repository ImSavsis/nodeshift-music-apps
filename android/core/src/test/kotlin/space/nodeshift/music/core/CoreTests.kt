package space.nodeshift.music.core

import java.io.File
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

object TestData {
    private val root: File = generateSequence(File(System.getProperty("user.dir")).absoluteFile) { it.parentFile }
        .first { File(it, "shared/testdata").isDirectory }

    fun text(name: String): String = File(root, "shared/testdata/$name").readText(Charsets.UTF_8)

    fun json(name: String): JsonElement = Json.parseToJsonElement(text(name))
}

private fun JsonElement.stringOrNull(): String? = if (this is JsonNull) null else jsonPrimitive.content

private fun JsonElement.intOrNullSafe(): Int? = if (this is JsonNull) null else jsonPrimitive.intOrNull

class FilenameParserTests {
    @Test
    fun vectorsMatchSwiftAndPython() {
        val cases = TestData.json("filename-parser.json").jsonArray
        assertTrue(cases.size > 10)
        for (item in cases) {
            val obj = item.jsonObject
            val label = obj["label"]!!.jsonPrimitive.content
            val names = obj["names"]!!.jsonArray.map { it.jsonPrimitive.content }
            assertEquals(obj["numbered"]!!.jsonPrimitive.boolean, FilenameParser.isNumberedBatch(names), label)
            val numbered = FilenameParser.isNumberedBatch(names)
            val expected = obj["expected"]!!.jsonArray
            assertEquals(names.size, expected.size, label)
            for ((name, want) in names.zip(expected)) {
                val got = FilenameParser.parse(name, numbered)
                val w = want.jsonObject
                assertEquals(w["disc"]!!.intOrNullSafe(), got.disc, "$label: $name disc")
                assertEquals(w["track"]!!.intOrNullSafe(), got.track, "$label: $name track")
                assertEquals(w["artist"]!!.stringOrNull(), got.artist, "$label: $name artist")
                assertEquals(w["title"]!!.stringOrNull(), got.title, "$label: $name title")
            }
        }
    }

    @Test
    fun userExample() {
        val parsed = FilenameParser.parse("09 - 2pac - Ratha Be Ya Nigga.flac", false)
        assertEquals(ParsedName(null, 9, "2pac", "Ratha Be Ya Nigga"), parsed)
    }
}

class SimilarityTests {
    @Test
    fun goldenRatiosMatchDifflib() {
        val cases = TestData.json("similarity.json").jsonArray
        assertTrue(cases.size > 20)
        for (item in cases) {
            val obj = item.jsonObject
            val a = obj["a"]!!.jsonPrimitive.content
            val b = obj["b"]!!.jsonPrimitive.content
            val got = if (obj["mode"]!!.jsonPrimitive.content == "words") {
                SequenceSimilarity.ratio(TextMatching.words(a), TextMatching.words(b))
            } else {
                SequenceSimilarity.ratio(a, b)
            }
            assertEquals(obj["ratio"]!!.jsonPrimitive.double, got, 1e-6, obj["name"]!!.jsonPrimitive.content)
        }
    }

    @Test
    fun normalizeFoldsCaseAccentsAndBrackets() {
        assertEquals("beyonce halo", TextMatching.normalize("Beyoncé — Halo (Live)"))
        assertEquals("hit em up", TextMatching.normalize("  Hit 'Em  Up [Dirty] "))
    }

    @Test
    fun featuringIsStripped() {
        assertEquals("Song", TextMatching.stripFeaturing("Song (feat. Someone)"))
        assertEquals("Eminem", TextMatching.stripFeaturing("Eminem feat. Rihanna"))
        assertEquals("Track", TextMatching.stripFeaturing("Track ft. Guest"))
        assertEquals("Defeat Of Me", TextMatching.stripFeaturing("Defeat Of Me"))
    }

    @Test
    fun artistMatching() {
        assertTrue(TextMatching.artistRatio("Eminem feat. Rihanna", "Eminem") > 0.99)
        assertTrue(TextMatching.artistRatio("Eminem & Dr. Dre", "Dr Dre") > 0.9)
        assertTrue(TextMatching.artistRatio("Eminem", "Metallica") < 0.5)
        assertEquals(listOf("a", "b", "c"), TextMatching.artistParts("A & B, C"))
    }
}

class LyricsTests {
    @Test
    fun lrcMatchesSiteParser() {
        val cases = TestData.json("lrc.json").jsonArray
        assertTrue(cases.size > 4)
        for (item in cases) {
            val obj = item.jsonObject
            val name = obj["name"]!!.jsonPrimitive.content
            val got = LrcParser.parse(obj["lrc"]!!.jsonPrimitive.content)
            val expected = obj["expected"]!!.jsonArray
            assertEquals(expected.size, got.size, name)
            for ((line, want) in got.zip(expected)) {
                val w = want.jsonObject
                assertEquals(w["time"]!!.jsonPrimitive.double, line.time, 1e-9, name)
                assertEquals(w["text"]!!.jsonPrimitive.content, line.text, name)
                assertNull(line.words, name)
            }
        }
    }

    @Test
    fun karaokeFillsMatchSiteFormula() {
        val cases = TestData.json("karaoke.json").jsonArray
        for (item in cases) {
            val obj = item.jsonObject
            val text = obj["text"]!!.jsonPrimitive.content
            val lineTime = obj["lineTime"]!!.jsonPrimitive.double
            val next = obj["nextTime"]!!.let { if (it is JsonNull) null else it.jsonPrimitive.double }
            for (sample in obj["samples"]!!.jsonArray) {
                val s = sample.jsonObject
                val t = s["t"]!!.jsonPrimitive.double
                val got = Karaoke.syntheticFills(text, lineTime, next, t)
                val want = s["fills"]!!.jsonArray.map { it.jsonPrimitive.double }
                assertEquals(want.size, got.size, text)
                for ((a, b) in got.zip(want)) {
                    assertEquals(b, a, 1e-9, "$text @ $t")
                }
            }
        }
    }

    @Test
    fun enhancedLrcWordTiming() {
        val lines = LrcParser.parse("[00:12.00]<00:12.00>Hello <00:12.50>big <00:13.20>world<00:14.00>\n[00:15.00]plain line")
        assertEquals(2, lines.size)
        assertEquals("Hello big world", lines[0].text)
        val words = assertNotNull(lines[0].words)
        assertEquals(3, words.size)
        assertEquals(12.0, words[0].start, 1e-9)
        assertEquals(12.5, words[0].end, 1e-9)
        assertEquals(14.0, words[2].end, 1e-9)
        assertNull(lines[1].words)
        assertEquals(LyricsKind.LINE_SYNCED, LrcParser.kind(lines))
        assertEquals(LyricsKind.WORD_SYNCED, LrcParser.kind(listOf(lines[0])))
    }

    @Test
    fun offsetShiftsTimes() {
        val lines = LrcParser.parse("[offset:+500]\n[00:10.00]line")
        assertEquals(9.5, lines.first().time, 1e-9)
    }

    @Test
    fun activeIndexAndStyle() {
        val lines = (0 until 6).map { LyricLine(it * 10.0, "l$it") }
        assertEquals(-1, Karaoke.activeIndex(lines, -1.0))
        assertEquals(0, Karaoke.activeIndex(lines, 0.0))
        assertEquals(2, Karaoke.activeIndex(lines, 25.0))
        assertEquals(5, Karaoke.activeIndex(lines, 999.0))
        assertEquals(LineStyle(1.0, 1.0, 0.0), Karaoke.style(2, 2))
        assertEquals(LineStyle(0.38, 0.93, 0.55), Karaoke.style(1, 2))
        assertEquals(3.5, Karaoke.style(9, 2).blur, 1e-9)
    }

    private val query = LyricsQuery("Ratha Be Ya Nigga", "2Pac", 250.0)

    private fun candidate(
        title: String = "Ratha Be Ya Nigga",
        artist: String = "2Pac",
        duration: Double? = 250.4,
        synced: String? = "[00:10.00]one\n[03:20.00]two",
        plain: String? = null,
        instrumental: Boolean = false,
    ) = LyricsCandidate(title, artist, duration, synced, plain, instrumental)

    @Test
    fun verifierAcceptsAndRejects() {
        val accepted = LyricsVerifier.verify(candidate(), query)
        assertTrue(accepted is LyricsVerdict.Accepted && accepted.kind == LyricsKind.LINE_SYNCED)
        assertEquals(LyricsVerdict.Rejected("duration"), LyricsVerifier.verify(candidate(duration = 255.0), query))
        assertEquals(LyricsVerdict.Rejected("title"), LyricsVerifier.verify(candidate(title = "Changes"), query))
        assertEquals(LyricsVerdict.Rejected("artist"), LyricsVerifier.verify(candidate(artist = "Metallica"), query))
        assertEquals(LyricsVerdict.Rejected("timeline"), LyricsVerifier.verify(candidate(synced = "[05:30.00]late"), query))
        assertEquals(LyricsVerdict.Rejected("instrumental"), LyricsVerifier.verify(candidate(instrumental = true), query))
        assertEquals(LyricsVerdict.Rejected("empty"), LyricsVerifier.verify(candidate(synced = null, plain = null), query))
        assertEquals(LyricsVerdict.Rejected("no-duration"), LyricsVerifier.verify(candidate(duration = null), query))
        assertEquals(LyricsVerdict.Rejected("garbled"), LyricsVerifier.verify(candidate(synced = null, plain = "??? ??? ???? ???"), query))
    }

    @Test
    fun bestPrefersWordThenLineThenPlain() {
        val plain = candidate(synced = null, plain = "words words")
        val line = candidate()
        val word = candidate(synced = "[00:10.00]<00:10.00>one <00:11.00>two\n[03:20.00]<03:20.00>x <03:21.00>y")
        assertEquals(LyricsKind.WORD_SYNCED, LyricsVerifier.best(listOf(plain, line, word), query)?.second)
        assertEquals(LyricsKind.LINE_SYNCED, LyricsVerifier.best(listOf(plain, line), query)?.second)
        assertEquals(LyricsKind.PLAIN, LyricsVerifier.best(listOf(plain), query)?.second)
        assertNull(LyricsVerifier.best(listOf(candidate(title = "Other")), query))
    }

    @Test
    fun garbledDetection() {
        assertTrue(LyricsVerifier.isGarbled("abc � def"))
        assertTrue(LyricsVerifier.isGarbled("   "))
        assertFalse(LyricsVerifier.isGarbled("Is it really you? I can't tell"))
    }
}

class LibraryTests {
    @Test
    fun paletteMatchesSiteAlgorithm() {
        val cases = TestData.json("palette.json").jsonArray
        assertTrue(cases.size > 5)
        for (item in cases) {
            val obj = item.jsonObject
            val name = obj["name"]!!.jsonPrimitive.content
            val data = Base64.getDecoder().decode(obj["rgbaBase64"]!!.jsonPrimitive.content)
            val got = PaletteExtractor.extract(data).map { listOf(it.r, it.g, it.b) }
            val want = obj["expected"]!!.jsonArray.map { row -> row.jsonArray.map { it.jsonPrimitive.int } }
            assertEquals(want, got, name)
        }
    }

    @Test
    fun paletteFallbackOnEmptyInput() {
        assertEquals(PaletteExtractor.fallback, PaletteExtractor.extract(ByteArray(0)))
    }

    @Test
    fun duplicateSameFile() {
        val index = DuplicateIndex(listOf(TrackFingerprint("a", "X", "Y", fileHash = "abc", format = "flac")))
        val hits = index.matches(TrackFingerprint("new", "Other", "Other", fileHash = "abc", format = "mp3"))
        assertEquals(listOf(DuplicateKind.SAME_FILE), hits.map { it.kind })
        assertEquals("a", index.existingId("abc"))
        assertNull(index.existingId("zzz"))
    }

    @Test
    fun duplicateSameTrackDifferentFormat() {
        val existing = TrackFingerprint("a", "2Pac", "Ratha Be Ya Nigga", 250_000, null, "mp3", 128)
        val index = DuplicateIndex(listOf(existing))
        val hits = index.matches(TrackFingerprint("n", "2pac", "Ratha Be Ya Nigga (Remastered)", 250_800, null, "flac"))
        assertEquals(1, hits.size)
        assertEquals(DuplicateKind.SAME_TRACK, hits[0].kind)
        assertTrue(hits[0].candidateIsBetterQuality)
    }

    @Test
    fun duplicateIgnoresFeaturingAndRespectsDuration() {
        val index = DuplicateIndex(listOf(TrackFingerprint("a", "Eminem", "Stan", 404_000, null, "flac")))
        val featuring = TrackFingerprint("n", "Eminem feat. Dido", "Stan (feat. Dido)", 404_500, null, "flac")
        assertEquals(DuplicateKind.SAME_TRACK, index.matches(featuring).first().kind)
        val different = TrackFingerprint("n2", "Eminem", "Stan", 480_000, null, "flac")
        assertTrue(index.matches(different).isEmpty())
    }

    @Test
    fun duplicateSimilarTitleAndRemove() {
        val index = DuplicateIndex(listOf(TrackFingerprint("a", "Artist", "Midnight Rain Falling", 200_000, "h", "mp3", 320)))
        val hits = index.matches(TrackFingerprint("n", "Artist", "Midnight Rain Fallin", 201_000, null, "mp3", 320))
        assertEquals(DuplicateKind.SIMILAR, hits.first().kind)
        index.remove("a")
        assertTrue(index.matches(TrackFingerprint("n", "Artist", "Midnight Rain Fallin", 201_000, "h", "mp3", 320)).isEmpty())
    }

    @Test
    fun versionsAndUpdates() {
        assertTrue(AppVersion.parse("1.10.0")!! > AppVersion.parse("1.9.9")!!)
        assertEquals(AppVersion.parse("1.0"), AppVersion.parse("1.0.0"))
        assertNull(AppVersion.parse("1.x"))
        assertNull(AppVersion.parse(""))
        val manifest = UpdateManifest("android", "0.2.0", 5, null, "x.apk", 1, "s", "8")
        assertTrue(UpdateCheck.isNewer(manifest, "0.1.0", 99))
        assertTrue(UpdateCheck.isNewer(manifest, "0.2.0", 4))
        assertFalse(UpdateCheck.isNewer(manifest, "0.2.0", 5))
        assertFalse(UpdateCheck.isNewer(manifest, "0.3.0", 1))
        assertTrue(UpdateCheck.meetsMinimumOs(manifest, "14"))
        assertFalse(UpdateCheck.meetsMinimumOs(manifest, "7"))
    }
}

class MotionTests {
    @Test
    fun coverSeedsMatchSiteHash() {
        val cases = TestData.json("cover-seeds.json").jsonArray
        assertTrue(cases.size > 8)
        for (item in cases) {
            val obj = item.jsonObject
            val seed = obj["seed"]!!.jsonPrimitive.content
            assertEquals(obj["hash"]!!.jsonPrimitive.long, CoverMotion.hash(seed), seed)
            val drift = CoverMotion.drift(seed)
            assertEquals(obj["duration"]!!.jsonPrimitive.double, drift.duration, 1e-9, seed)
            assertEquals(obj["delay"]!!.jsonPrimitive.double, drift.delay, 1e-9, seed)
            assertEquals(obj["shiftX"]!!.jsonPrimitive.double, drift.shiftX, 1e-9, seed)
            assertEquals(obj["shiftY"]!!.jsonPrimitive.double, drift.shiftY, 1e-9, seed)
            assertEquals(obj["originX"]!!.jsonPrimitive.double, drift.originX, 1e-9, seed)
            assertEquals(obj["originY"]!!.jsonPrimitive.double, drift.originY, 1e-9, seed)
            assertEquals(obj["sheenDelay"]!!.jsonPrimitive.double, drift.sheenDelay, 1e-9, seed)
        }
    }

    @Test
    fun easingMatchesReference() {
        val cases = TestData.json("easing.json").jsonArray
        assertEquals(4, cases.size)
        for (item in cases) {
            val obj = item.jsonObject
            val c = obj["curve"]!!.jsonArray.map { it.jsonPrimitive.double }
            val curve = CubicBezier(c[0], c[1], c[2], c[3])
            for (sample in obj["samples"]!!.jsonArray) {
                val s = sample.jsonObject
                assertEquals(s["y"]!!.jsonPrimitive.double, curve.valueAt(s["x"]!!.jsonPrimitive.double), 1e-7, "$c")
            }
        }
    }

    @Test
    fun driftAndSheen() {
        val drift = CoverDrift(20.0, -5.0, 2.0, 1.0, 50.0, 50.0, 0.0)
        assertEquals(CubicBezier.EASE_IN_OUT.valueAt(0.25), CoverMotion.driftProgress(0.0, drift), 1e-9)
        assertEquals(1.0, CoverMotion.driftProgress(15.0, drift), 1e-9)
        assertEquals(CubicBezier.EASE_IN_OUT.valueAt(0.75), CoverMotion.driftProgress(20.0, drift), 1e-9)
        assertEquals(0.0, CoverMotion.driftProgress(35.0, drift), 1e-9)
        assertEquals(-1.3, CoverMotion.sheenOffset(0.0, drift), 1e-12)
        assertEquals(0.0, CoverMotion.sheenOffset(9 * 0.81, drift), 1e-9)
    }

    @Test
    fun ambientKeyframesAndRate() {
        for (blob in AmbientMotion.blobs) {
            assertEquals(blob.start, AmbientMotion.state(blob, 0.0))
            assertEquals(blob.middle.x, AmbientMotion.state(blob, blob.duration / 2).x, 1e-9)
            assertEquals(blob.end.x, AmbientMotion.state(blob, blob.duration).x, 1e-9)
            assertEquals(blob.start.y, AmbientMotion.state(blob, blob.duration * 2).y, 1e-9)
        }
        assertEquals(0.92, AmbientMotion.rate(92.0, true), 1e-9)
        assertEquals(1.6, AmbientMotion.rate(200.0, true), 1e-9)
        assertEquals(0.12, AmbientMotion.rate(120.0, false), 1e-9)
    }
}
