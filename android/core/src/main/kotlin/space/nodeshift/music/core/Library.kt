package space.nodeshift.music.core

import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

data class TrackFingerprint(
    val id: String,
    val artist: String,
    val title: String,
    val durationMs: Int? = null,
    val fileHash: String? = null,
    val format: String = "",
    val bitrateKbps: Int? = null,
)

enum class DuplicateKind { SAME_FILE, SAME_TRACK, SIMILAR }

data class DuplicateMatch(val existingId: String, val kind: DuplicateKind, val candidateIsBetterQuality: Boolean)

object QualityRank {
    private val lossless = setOf("flac", "wav", "aiff", "aif", "alac", "ape", "wv", "dsf")

    fun score(format: String, bitrateKbps: Int?): Int {
        if (lossless.contains(format.lowercase())) return 10_000
        return bitrateKbps ?: 128
    }
}

class DuplicateIndex(tracks: List<TrackFingerprint> = emptyList()) {
    private val byHash = HashMap<String, MutableList<TrackFingerprint>>()
    private val byKey = HashMap<String, MutableList<TrackFingerprint>>()
    private val byArtist = HashMap<String, MutableList<TrackFingerprint>>()

    init {
        tracks.forEach(::add)
    }

    private fun key(track: TrackFingerprint): String =
        TextMatching.artistKey(track.artist) + "|" + TextMatching.titleKey(track.title)

    fun add(track: TrackFingerprint) {
        track.fileHash?.takeIf { it.isNotEmpty() }?.let { byHash.getOrPut(it) { mutableListOf() }.add(track) }
        byKey.getOrPut(key(track)) { mutableListOf() }.add(track)
        byArtist.getOrPut(TextMatching.artistKey(track.artist)) { mutableListOf() }.add(track)
    }

    fun remove(id: String) {
        byHash.values.forEach { list -> list.removeAll { it.id == id } }
        byKey.values.forEach { list -> list.removeAll { it.id == id } }
        byArtist.values.forEach { list -> list.removeAll { it.id == id } }
    }

    fun existingId(hash: String): String? = byHash[hash]?.firstOrNull()?.id

    private fun closeEnough(a: Int?, b: Int?, tolerance: Int): Boolean {
        if (a == null || b == null) return true
        return abs(a - b) <= tolerance
    }

    fun matches(candidate: TrackFingerprint): List<DuplicateMatch> {
        val seen = HashSet<String>()
        val result = mutableListOf<DuplicateMatch>()
        fun better(existing: TrackFingerprint): Boolean =
            QualityRank.score(candidate.format, candidate.bitrateKbps) > QualityRank.score(existing.format, existing.bitrateKbps)

        val hash = candidate.fileHash
        if (hash != null) {
            byHash[hash]?.forEach { hit ->
                if (hit.id != candidate.id && seen.add(hit.id)) {
                    result.add(DuplicateMatch(hit.id, DuplicateKind.SAME_FILE, false))
                }
            }
        }
        byKey[key(candidate)]?.forEach { hit ->
            if (hit.id != candidate.id && closeEnough(hit.durationMs, candidate.durationMs, SAME_TRACK_TOLERANCE_MS) && seen.add(hit.id)) {
                result.add(DuplicateMatch(hit.id, DuplicateKind.SAME_TRACK, better(hit)))
            }
        }
        if (result.isEmpty()) {
            val wantedTitle = TextMatching.titleKey(candidate.title)
            byArtist[TextMatching.artistKey(candidate.artist)]?.forEach { hit ->
                if (hit.id != candidate.id &&
                    closeEnough(hit.durationMs, candidate.durationMs, SIMILAR_TOLERANCE_MS) &&
                    SequenceSimilarity.ratio(TextMatching.titleKey(hit.title), wantedTitle) >= SIMILAR_TITLE_THRESHOLD &&
                    seen.add(hit.id)
                ) {
                    result.add(DuplicateMatch(hit.id, DuplicateKind.SIMILAR, better(hit)))
                }
            }
        }
        return result
    }

    companion object {
        const val SAME_TRACK_TOLERANCE_MS = 2000
        const val SIMILAR_TOLERANCE_MS = 3000
        const val SIMILAR_TITLE_THRESHOLD = 0.92
    }
}

class AppVersion private constructor(val components: List<Int>) : Comparable<AppVersion> {
    private fun padded(other: AppVersion): Pair<List<Int>, List<Int>> {
        val count = max(components.size, other.components.size)
        return components + List(count - components.size) { 0 } to other.components + List(count - other.components.size) { 0 }
    }

    override fun compareTo(other: AppVersion): Int {
        val (a, b) = padded(other)
        for ((x, y) in a.zip(b)) {
            if (x != y) return x.compareTo(y)
        }
        return 0
    }

    override fun equals(other: Any?): Boolean = other is AppVersion && compareTo(other) == 0

    override fun hashCode(): Int {
        val trimmed = components.toMutableList()
        while (trimmed.isNotEmpty() && trimmed.last() == 0) trimmed.removeAt(trimmed.lastIndex)
        return trimmed.hashCode()
    }

    companion object {
        fun parse(text: String): AppVersion? {
            var value = text.trim()
            if (value.startsWith("v") || value.startsWith("V")) value = value.substring(1)
            if (value.isEmpty()) return null
            val parsed = value.split(".").map { it.toIntOrNull()?.takeIf { number -> number >= 0 } ?: return null }
            return AppVersion(parsed)
        }
    }
}

data class UpdateManifest(
    val platform: String,
    val version: String,
    val build: Int,
    val commit: String? = null,
    val file: String,
    val size: Long,
    val sha256: String,
    val minOS: String? = null,
    val notes: String? = null,
    val builtAt: String? = null,
    val url: String? = null,
)

object UpdateCheck {
    fun isNewer(manifest: UpdateManifest, currentVersion: String, currentBuild: Int): Boolean {
        val remote = AppVersion.parse(manifest.version)
        val local = AppVersion.parse(currentVersion)
        if (remote == null || local == null) return manifest.build > currentBuild
        if (remote != local) return remote > local
        return manifest.build > currentBuild
    }

    fun meetsMinimumOs(manifest: UpdateManifest, current: String): Boolean {
        val required = manifest.minOS ?: return true
        val need = AppVersion.parse(required) ?: return true
        val have = AppVersion.parse(current) ?: return true
        return have >= need
    }
}

data class Rgb8(val r: Int, val g: Int, val b: Int)

object PaletteExtractor {
    val fallback = listOf(Rgb8(72, 76, 94), Rgb8(46, 50, 64), Rgb8(28, 30, 40))

    private class Bucket(var hue: Double, val order: Int) {
        var weight = 0.0
        var red = 0.0
        var green = 0.0
        var blue = 0.0
    }

    internal fun rgbToHsv(red: Double, green: Double, blue: Double): Triple<Double, Double, Double> {
        val maxValue = max(red, max(green, blue))
        val minValue = min(red, min(green, blue))
        val delta = maxValue - minValue
        var hue = 0.0
        if (delta != 0.0) {
            hue = when (maxValue) {
                red -> ((green - blue) / delta) % 6
                green -> (blue - red) / delta + 2
                else -> (red - green) / delta + 4
            }
            hue *= 60
            if (hue < 0) hue += 360
        }
        return Triple(hue, if (maxValue == 0.0) 0.0 else delta / maxValue, maxValue / 255)
    }

    internal fun hsvToRgb(hue: Double, saturation: Double, value: Double): Rgb8 {
        val chroma = value * saturation
        val wrapped = ((hue % 360) + 360) % 360
        val section = wrapped / 60
        val x = chroma * (1 - abs(section % 2 - 1))
        val base = value - chroma
        val table = arrayOf(
            doubleArrayOf(chroma, x, 0.0),
            doubleArrayOf(x, chroma, 0.0),
            doubleArrayOf(0.0, chroma, x),
            doubleArrayOf(0.0, x, chroma),
            doubleArrayOf(x, 0.0, chroma),
            doubleArrayOf(chroma, 0.0, x),
        )
        val pick = table[min(5, floor(section).toInt())]
        fun byte(component: Double): Int = floor((component + base) * 255 + 0.5).toInt()
        return Rgb8(byte(pick[0]), byte(pick[1]), byte(pick[2]))
    }

    private fun hueDistance(a: Double, b: Double): Double {
        val diff = abs(a - b) % 360
        return if (diff > 180) 360 - diff else diff
    }

    fun extract(rgba: ByteArray): List<Rgb8> {
        val buckets = LinkedHashMap<Int, Bucket>()
        var grayTotal = 0.0
        var grayCount = 0.0
        var order = 0
        var index = 0
        while (index + 3 < rgba.size) {
            val red = (rgba[index].toInt() and 0xFF).toDouble()
            val green = (rgba[index + 1].toInt() and 0xFF).toDouble()
            val blue = (rgba[index + 2].toInt() and 0xFF).toDouble()
            index += 4
            val (hue, saturation, value) = rgbToHsv(red, green, blue)
            if (value < 0.1) continue
            if (saturation < 0.18) {
                grayTotal += (red + green + blue) / 3
                grayCount += 1
                continue
            }
            val key = floor(hue / 20).toInt() * 100 + floor(saturation * 3).toInt() * 10 + floor(value * 3).toInt()
            val weight = saturation * (0.4 + value) + 0.05
            val bucket = buckets.getOrPut(key) {
                order += 1
                Bucket(hue, order)
            }
            bucket.weight += weight
            bucket.red += red * weight
            bucket.green += green * weight
            bucket.blue += blue * weight
            bucket.hue = hue
        }
        val ranked = buckets.values.sortedWith(compareBy<Bucket>({ -it.weight }, { it.order }))
        val primary = ranked.firstOrNull()
        if (primary == null) {
            if (grayCount == 0.0) return fallback
            val level = min(0.42, max(0.22, grayTotal / grayCount / 255 / 2.2))
            return listOf(hsvToRgb(230.0, 0.08, level), hsvToRgb(230.0, 0.08, level * 0.62), hsvToRgb(230.0, 0.06, level * 0.38))
        }
        val (primaryHue, primarySaturation, _) = rgbToHsv(primary.red / primary.weight, primary.green / primary.weight, primary.blue / primary.weight)
        val mutedSaturation = min(0.38, max(0.16, primarySaturation * 0.55))
        val second = ranked.firstOrNull { hueDistance(it.hue, primary.hue) >= 35 && it.weight >= primary.weight * 0.45 }
        val secondHue = second?.hue ?: (primaryHue + 14)
        val secondSaturation = if (second != null) min(0.32, mutedSaturation * 0.9) else mutedSaturation * 0.7
        return listOf(
            hsvToRgb(primaryHue, mutedSaturation, 0.46),
            hsvToRgb(secondHue, secondSaturation, if (second != null) 0.36 else 0.3),
            hsvToRgb(primaryHue, min(0.24, mutedSaturation * 0.6), 0.2),
        )
    }
}
