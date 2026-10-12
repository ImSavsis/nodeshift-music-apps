package space.nodeshift.music.core

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

data class LyricWord(val text: String, val start: Double, val end: Double)

data class LyricLine(val time: Double, val text: String, val words: List<LyricWord>? = null) {
    val hasWordTiming: Boolean
        get() = !words.isNullOrEmpty()
}

enum class LyricsKind { WORD_SYNCED, LINE_SYNCED, PLAIN, NONE }

object LrcParser {
    private val lineTag = Regex("""\[(\d{1,3}):(\d{2}(?:[.:]\d{1,3})?)]""")
    private val wordTag = Regex("""<(\d{1,3}):(\d{2}(?:[.:]\d{1,3})?)>""")
    private val offsetTag = Regex("""^\s*\[offset:\s*([+-]?\d+)\s*]\s*$""", RegexOption.IGNORE_CASE)

    private fun seconds(minutes: String, seconds: String): Double? {
        val m = minutes.toDoubleOrNull() ?: return null
        val s = seconds.replace(':', '.').toDoubleOrNull() ?: return null
        return m * 60 + s
    }

    fun parse(lrc: String): List<LyricLine> {
        var offset = 0.0
        val result = mutableListOf<LyricLine>()
        for (raw in lrc.split(Regex("""\r\n|\r|\n"""))) {
            val offsetMatch = offsetTag.find(raw)
            if (offsetMatch != null) {
                offset = (offsetMatch.groupValues[1].toDoubleOrNull() ?: 0.0) / 1000
                continue
            }
            val tags = lineTag.findAll(raw).toList()
            if (tags.isEmpty()) continue
            val body = lineTag.replace(raw, "")
            val times = tags.mapNotNull { seconds(it.groupValues[1], it.groupValues[2]) }
            val words = parseWords(body)
            val plain = wordTag.replace(body, "").trim()
            if (plain.isEmpty()) continue
            for (time in times) {
                result.add(LyricLine(time - offset, plain, words))
            }
        }
        val sorted = result.withIndex().sortedWith(compareBy({ it.value.time }, { it.index })).map { it.value }.toMutableList()
        applyWordEnds(sorted)
        return sorted
    }

    private fun parseWords(body: String): List<LyricWord>? {
        val tags = wordTag.findAll(body).toList()
        if (tags.isEmpty()) return null
        val starts = mutableListOf<Double>()
        val texts = mutableListOf<String>()
        val ends = mutableListOf<Double>()
        for ((index, tag) in tags.withIndex()) {
            val start = seconds(tag.groupValues[1], tag.groupValues[2]) ?: continue
            val nextLower = if (index + 1 < tags.size) tags[index + 1].range.first else body.length
            val segment = body.substring(tag.range.last + 1, nextLower)
            if (segment.isBlank()) {
                if (ends.isNotEmpty()) ends[ends.lastIndex] = start
                continue
            }
            starts.add(start)
            texts.add(segment)
            ends.add(start)
        }
        if (texts.isEmpty()) return null
        for (index in 0 until texts.size - 1) {
            if (ends[index] <= starts[index]) ends[index] = starts[index + 1]
        }
        return texts.indices.map { LyricWord(texts[it], starts[it], ends[it]) }
    }

    private fun applyWordEnds(lines: MutableList<LyricLine>) {
        for (index in lines.indices) {
            val words = lines[index].words ?: continue
            if (words.isEmpty()) continue
            val lineEnd = if (index + 1 < lines.size) lines[index + 1].time else words.last().start + 1.5
            val last = words.last()
            if (last.end <= last.start) {
                val fixed = words.toMutableList()
                fixed[fixed.lastIndex] = last.copy(end = max(lineEnd, last.start + 0.3))
                lines[index] = lines[index].copy(words = fixed)
            }
        }
    }

    fun kind(lines: List<LyricLine>): LyricsKind {
        if (lines.isEmpty()) return LyricsKind.NONE
        val timed = lines.count { it.hasWordTiming }
        return if (timed >= lines.size * 0.6) LyricsKind.WORD_SYNCED else LyricsKind.LINE_SYNCED
    }

    fun plainText(lines: List<LyricLine>): String = lines.joinToString("\n") { it.text }
}

data class SyntheticWord(val text: String, val start: Double, val end: Double)

data class LineStyle(val opacity: Double, val scale: Double, val blur: Double)

object Karaoke {
    const val MAX_LINE_SECONDS = 7.0
    const val MIN_SPAN = 0.6
    const val SPAN_FACTOR = 0.92

    fun syntheticWords(text: String): List<SyntheticWord> {
        val parts = TextMatching.words(text)
        val weights = parts.map { it.length + 1.5 }
        val sum = weights.sum()
        val total = if (sum == 0.0) 1.0 else sum
        var cursor = 0.0
        return parts.mapIndexed { index, part ->
            val start = cursor / total
            cursor += weights[index]
            SyntheticWord(part, start, cursor / total)
        }
    }

    fun span(lineTime: Double, nextTime: Double?): Double {
        val next = nextTime ?: (lineTime + MAX_LINE_SECONDS)
        return max(MIN_SPAN, min(next - lineTime, MAX_LINE_SECONDS) * SPAN_FACTOR)
    }

    fun clamp01(value: Double): Double = min(1.0, max(0.0, value))

    fun syntheticFills(text: String, lineTime: Double, nextTime: Double?, at: Double): List<Double> {
        val progress = clamp01((at - lineTime) / span(lineTime, nextTime))
        return syntheticWords(text).map { word ->
            val width = word.end - word.start
            if (width <= 0) 1.0 else clamp01((progress - word.start) / width)
        }
    }

    fun timedFills(words: List<LyricWord>, at: Double): List<Double> =
        words.map { word -> clamp01((at - word.start) / max(word.end - word.start, 0.001)) }

    fun fills(line: LyricLine, nextTime: Double?, at: Double): List<Double> {
        val words = line.words
        if (!words.isNullOrEmpty()) return timedFills(words, at)
        return syntheticFills(line.text, line.time, nextTime, at)
    }

    fun activeIndex(lines: List<LyricLine>, at: Double): Int {
        var low = 0
        var high = lines.size - 1
        var found = -1
        while (low <= high) {
            val mid = (low + high) / 2
            if (lines[mid].time <= at) {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    fun style(index: Int, active: Int): LineStyle {
        if (index == active) return LineStyle(1.0, 1.0, 0.0)
        val distance = abs(index - active).toDouble()
        if (index < active) return LineStyle(0.38, 0.93, min(distance, 5.0) * 0.55)
        return LineStyle(0.30, 0.93, min(distance, 5.0) * 0.7)
    }
}

data class LyricsQuery(val title: String, val artist: String, val duration: Double?)

data class LyricsCandidate(
    val trackName: String,
    val artistName: String,
    val duration: Double?,
    val synced: String? = null,
    val plain: String? = null,
    val instrumental: Boolean = false,
)

sealed class LyricsVerdict {
    data class Accepted(val kind: LyricsKind, val score: Double) : LyricsVerdict()
    data class Rejected(val reason: String) : LyricsVerdict()
}

object LyricsVerifier {
    const val DURATION_TOLERANCE = 2.0
    const val TITLE_THRESHOLD = 0.9
    const val ARTIST_THRESHOLD = 0.88
    const val TIMELINE_SLACK = 3.0

    fun isGarbled(text: String): Boolean {
        if (text.any { it == '�' }) return true
        val visible = text.filter { !it.isWhitespace() }
        if (visible.isEmpty()) return true
        val questions = visible.count { it == '?' }
        return questions.toDouble() / visible.length > 0.12
    }

    fun timelineEnd(lines: List<LyricLine>): Double = lines.maxOfOrNull { it.time } ?: 0.0

    fun verify(candidate: LyricsCandidate, query: LyricsQuery): LyricsVerdict {
        if (candidate.instrumental) return LyricsVerdict.Rejected("instrumental")
        val syncedLines = candidate.synced?.let { LrcParser.parse(it) } ?: emptyList()
        val plain = (candidate.plain ?: "").trim()
        if (syncedLines.isEmpty() && plain.isEmpty()) return LyricsVerdict.Rejected("empty")
        val wanted = query.duration
        val got = candidate.duration
        if (wanted == null || got == null) return LyricsVerdict.Rejected("no-duration")
        if (abs(wanted - got) > DURATION_TOLERANCE) return LyricsVerdict.Rejected("duration")
        val titleScore = TextMatching.titleRatio(candidate.trackName, query.title)
        if (titleScore < TITLE_THRESHOLD) return LyricsVerdict.Rejected("title")
        val artistScore = TextMatching.artistRatio(candidate.artistName, query.artist)
        if (artistScore < ARTIST_THRESHOLD) return LyricsVerdict.Rejected("artist")
        if (syncedLines.isNotEmpty()) {
            if (timelineEnd(syncedLines) > wanted + TIMELINE_SLACK) return LyricsVerdict.Rejected("timeline")
            if (isGarbled(LrcParser.plainText(syncedLines))) return LyricsVerdict.Rejected("garbled")
            val score = (titleScore + artistScore) / 2 - abs(wanted - got) * 0.01
            return LyricsVerdict.Accepted(LrcParser.kind(syncedLines), score)
        }
        if (isGarbled(plain)) return LyricsVerdict.Rejected("garbled")
        val score = (titleScore + artistScore) / 2 - abs(wanted - got) * 0.01 - 0.5
        return LyricsVerdict.Accepted(LyricsKind.PLAIN, score)
    }

    private fun rank(kind: LyricsKind): Double = when (kind) {
        LyricsKind.WORD_SYNCED -> 2.0
        LyricsKind.LINE_SYNCED -> 1.0
        LyricsKind.PLAIN -> 0.0
        LyricsKind.NONE -> -1.0
    }

    fun best(candidates: List<LyricsCandidate>, query: LyricsQuery): Pair<LyricsCandidate, LyricsKind>? {
        var winner: Triple<LyricsCandidate, LyricsKind, Double>? = null
        for (candidate in candidates) {
            val verdict = verify(candidate, query) as? LyricsVerdict.Accepted ?: continue
            val boosted = verdict.score + rank(verdict.kind)
            if (winner == null || boosted > winner.third) {
                winner = Triple(candidate, verdict.kind, boosted)
            }
        }
        return winner?.let { it.first to it.second }
    }
}
