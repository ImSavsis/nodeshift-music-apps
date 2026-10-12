package space.nodeshift.music.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import space.nodeshift.music.core.TextMatching
import java.io.File
import kotlin.math.abs

@Serializable
private data class AppleAlbumResponse(val results: List<AppleAlbum> = emptyList())

@Serializable
private data class AppleAlbum(
    val collectionId: Long? = null,
    val collectionName: String? = null,
    val artistName: String? = null,
    val collectionViewUrl: String? = null,
)

data class MotionFiles(val square: File?, val tall: File?)

data class MotionVariant(val url: String, val width: Int, val bandwidth: Int)

object MotionCoverFinder {
    suspend fun find(artist: String, album: String, directory: File, key: String): MotionFiles? {
        if (album.isEmpty()) return null
        val pages = candidatePages(artist, album)
        for (page in pages.take(6)) {
            val found = motionUrls(page) ?: continue
            var square: File? = null
            var tall: File? = null
            found.first?.let { square = fetchBest(it, File(directory, "$key.mp4")) }
            found.second?.let { tall = fetchBest(it, File(directory, "$key-tall.mp4")) }
            if (square != null || tall != null) return MotionFiles(square, tall)
        }
        return null
    }

    private suspend fun candidatePages(artist: String, album: String): List<String> {
        val pages = mutableListOf<String>()
        for (country in listOf("us", "ru")) {
            RateLimiter.wait("itunes", 3200)
            val url = Net.components(
                "https://itunes.apple.com/search",
                mapOf("term" to "$artist $album", "media" to "music", "entity" to "album", "limit" to "12", "country" to country),
            ) ?: continue
            val response = runCatching { Net.json.decodeFromString<AppleAlbumResponse>(Net.text(url)) }.getOrNull() ?: continue
            for (item in response.results) {
                val name = item.collectionName ?: continue
                val singer = item.artistName ?: continue
                val link = item.collectionViewUrl ?: continue
                if (TextMatching.titleRatio(album, name) >= 0.8 && TextMatching.artistRatio(artist, singer) >= 0.7) {
                    pages.add(link)
                }
            }
            if (pages.isNotEmpty()) break
        }
        return pages
    }

    fun collectVideos(node: JsonElement, found: MutableMap<String, String>) {
        when (node) {
            is JsonObject -> {
                for ((key, value) in node) {
                    val inner = value as? JsonObject
                    val video = (inner?.get("video") as? JsonPrimitive)?.takeIf { it.isString }?.content
                    if ((key == "motionDetailSquare" || key == "motionSquareVideo1x1") && video != null && found["square"] == null) {
                        found["square"] = video
                    } else if ((key == "motionDetailTall" || key == "motionTallVideo3x4") && video != null && found["tall"] == null) {
                        found["tall"] = video
                    } else {
                        collectVideos(value, found)
                    }
                }
            }
            is JsonArray -> node.forEach { collectVideos(it, found) }
            else -> Unit
        }
    }

    private suspend fun motionUrls(page: String): Pair<String?, String?>? {
        RateLimiter.wait("applepage", 1500)
        val html = runCatching { Net.text(page, agent = Net.BROWSER_AGENT) }.getOrNull() ?: return null
        val marker = html.indexOf("id=\"serialized-server-data\"")
        if (marker < 0) return null
        val start = html.indexOf('>', marker)
        if (start < 0) return null
        val end = html.indexOf("</script>", start)
        if (end < 0) return null
        val element = runCatching { Net.json.parseToJsonElement(html.substring(start + 1, end)) }.getOrNull() ?: return null
        val found = HashMap<String, String>()
        withContext(Dispatchers.Default) { collectVideos(element, found) }
        val square = found["square"]
        val tall = found["tall"]
        if (square == null && tall == null) return null
        return square to tall
    }

    fun parseVariants(master: String, base: String): List<MotionVariant> {
        val variants = mutableListOf<MotionVariant>()
        val lines = master.lines()
        val baseUrl = base.toHttpUrlOrNull()
        var index = 0
        while (index < lines.size) {
            val line = lines[index]
            if (line.startsWith("#EXT-X-STREAM-INF:") && line.contains("avc1") && index + 1 < lines.size) {
                val uri = lines[index + 1].trim()
                val width = Regex("RESOLUTION=(\\d+)").find(line)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                val bandwidth = Regex("[,:]BANDWIDTH=(\\d+)").find(line)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                val resolved = baseUrl?.resolve(uri)?.toString()
                if (resolved != null && width > 0) variants.add(MotionVariant(resolved, width, bandwidth))
                index += 2
                continue
            }
            index += 1
        }
        return variants
    }

    fun pickVariant(variants: List<MotionVariant>): MotionVariant? {
        val usable = variants.filter { it.width in 480..1100 }
        val pool = usable.ifEmpty { variants }
        return pool.minWithOrNull(compareBy<MotionVariant>({ abs(it.width - 960) }, { it.bandwidth }))
    }

    fun mapUri(variantPlaylist: String, base: String): String? {
        val baseUrl = base.toHttpUrlOrNull() ?: return null
        for (line in variantPlaylist.lines()) {
            if (!line.startsWith("#EXT-X-MAP:")) continue
            val start = line.indexOf("URI=\"")
            if (start < 0) continue
            val rest = line.substring(start + 5)
            val close = rest.indexOf('"')
            if (close < 0) continue
            return baseUrl.resolve(rest.substring(0, close))?.toString()
        }
        for (line in variantPlaylist.lines()) {
            val trimmed = line.trim()
            if (trimmed.isNotEmpty() && !trimmed.startsWith("#")) return baseUrl.resolve(trimmed)?.toString()
        }
        return null
    }

    private suspend fun fetchBest(master: String, destination: File): File? {
        val masterText = runCatching { Net.text(master, agent = Net.BROWSER_AGENT) }.getOrNull() ?: return null
        val variant = pickVariant(parseVariants(masterText, master)) ?: return null
        val variantText = runCatching { Net.text(variant.url, agent = Net.BROWSER_AGENT) }.getOrNull() ?: return null
        val fileUrl = mapUri(variantText, variant.url) ?: return null
        runCatching { Net.download(fileUrl, destination, agent = Net.BROWSER_AGENT) }.getOrNull() ?: return null
        val valid = withContext(Dispatchers.IO) {
            if (!destination.exists() || destination.length() <= 100_000) return@withContext false
            val head = ByteArray(12)
            val read = destination.inputStream().use { it.read(head) }
            read >= 8 && String(head, 4, 4, Charsets.ISO_8859_1) == "ftyp"
        }
        if (!valid) {
            destination.delete()
            return null
        }
        return destination
    }
}
