package space.nodeshift.music.core

import java.text.Normalizer

data class ParsedName(
    val disc: Int? = null,
    val track: Int? = null,
    val artist: String? = null,
    val title: String? = null,
)

object FilenameParser {
    private val extensionPattern = Regex("""\.(mp3|flac|wav|ogg|opus|m4a|aac|aiff?|wma)$""", RegexOption.IGNORE_CASE)
    private val junkPattern = Regex(
        """\s*[\[(](?:flac|mp3|320\s*kbps|320|hq|hd|lossless|official\s*(?:audio|video|music\s*video|lyric\s*video))[\])]\s*""",
        RegexOption.IGNORE_CASE,
    )
    private val sitePattern = Regex(
        """\s*[\[(]?(?:www\.)?[a-z0-9-]+\.(?:com|net|org|ru|me|io|fm)[\])]?\s*$""",
        RegexOption.IGNORE_CASE,
    )
    private val dashPattern = Regex("""(?:\s+[-–—]\s+|\s*[-–—]\s+|\s+[-–—]\s*)""")
    private val discTrackPattern = Regex("""^(\d{1,2})[-.](\d{2,3})(?:\s*(?:[-.)_]|\s[-–—]\s)\s*|\s+)""")
    private val strongPattern = Regex("""^(\d{1,3})(?:\s*[-.)_]\s*|\s[-–—]\s)""")
    private val weakPattern = Regex("""^(\d{1,3})\s+(?=\D)""")
    private val whitespace = Regex("""[\s\p{Z}]+""")

    private data class Lead(val value: Int, val raw: String, val rest: String, val strong: Boolean)

    private fun collapse(text: String): String =
        text.split(whitespace).filter { it.isNotEmpty() }.joinToString(" ")

    internal fun clean(stem: String): String {
        var text = Normalizer.normalize(stem, Normalizer.Form.NFC)
        val trimmed = text.trim()
        if (!trimmed.contains(' ') && text.count { it == '_' } >= 2) {
            text = text.replace('_', ' ')
        }
        text = junkPattern.replace(text, " ")
        text = sitePattern.replace(text, "")
        return collapse(text)
    }

    internal fun stem(name: String): String = clean(extensionPattern.replace(name, ""))

    private fun nonEmptyParts(text: String): List<String> =
        dashPattern.split(text).map { it.trim() }.filter { it.isNotEmpty() }

    private fun lead(text: String): Lead? {
        strongPattern.find(text)?.let { match ->
            val raw = match.groupValues[1]
            val value = raw.toIntOrNull() ?: return@let
            return Lead(value, raw, text.substring(match.range.last + 1), true)
        }
        weakPattern.find(text)?.let { match ->
            val raw = match.groupValues[1]
            val value = raw.toIntOrNull() ?: return@let
            return Lead(value, raw, text.substring(match.range.last + 1), false)
        }
        return null
    }

    fun isNumberedBatch(names: List<String>): Boolean {
        val texts = names.map(::stem)
        val found = mutableListOf<Int?>()
        for (text in texts) {
            if (discTrackPattern.find(text) != null) {
                found.add(null)
                continue
            }
            lead(text)?.let { found.add(it.value) }
        }
        if (found.size < texts.size * 0.8 || texts.size < 3) {
            return false
        }
        val plain = found.filterNotNull()
        return plain.isNotEmpty() && plain.all { it in 1..99 } && plain.toSet().size == plain.size
    }

    fun parse(name: String, numberedBatch: Boolean): ParsedName {
        var text = stem(name)
        var disc: Int? = null
        var track: Int? = null
        val discMatch = discTrackPattern.find(text)
        if (discMatch != null) {
            disc = discMatch.groupValues[1].toIntOrNull()
            track = discMatch.groupValues[2].toIntOrNull()
            text = text.substring(discMatch.range.last + 1)
        } else {
            val info = lead(text)
            if (info != null) {
                val padded = info.raw.length == 2 && info.raw.startsWith("0")
                val threePart = info.strong && nonEmptyParts(info.rest).size >= 2
                if (padded || threePart || numberedBatch) {
                    track = info.value
                    text = info.rest
                }
            }
        }
        val parts = nonEmptyParts(text)
        var artist: String? = null
        var title: String? = null
        if (parts.size >= 2) {
            artist = parts[0]
            title = parts.drop(1).joinToString(" - ")
        } else if (parts.isNotEmpty()) {
            title = parts[0]
        }
        return ParsedName(disc, track, artist, title)
    }

    fun parseBatch(names: List<String>): List<ParsedName> {
        val numbered = isNumberedBatch(names)
        return names.map { parse(it, numbered) }
    }
}
