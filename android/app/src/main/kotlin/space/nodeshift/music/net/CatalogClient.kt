package space.nodeshift.music.net

import kotlinx.serialization.Serializable
import space.nodeshift.music.core.TextMatching
import kotlin.math.abs

data class CatalogMatch(
    val title: String,
    val artist: String,
    val album: String? = null,
    val albumArtist: String? = null,
    val trackNumber: Int? = null,
    val discNumber: Int? = null,
    val year: Int? = null,
    val genre: String? = null,
    val isrc: String? = null,
    val coverUrl: String? = null,
    val durationSeconds: Double? = null,
    val source: String = "",
)

data class CatalogQuery(
    val title: String,
    val artist: String,
    val album: String? = null,
    val duration: Double? = null,
)

@Serializable
private data class ITunesResponse(val results: List<ITunesItem> = emptyList())

@Serializable
private data class ITunesItem(
    val wrapperType: String? = null,
    val trackName: String? = null,
    val artistName: String? = null,
    val collectionName: String? = null,
    val trackTimeMillis: Int? = null,
    val trackNumber: Int? = null,
    val discNumber: Int? = null,
    val releaseDate: String? = null,
    val primaryGenreName: String? = null,
    val artworkUrl100: String? = null,
)

@Serializable
private data class DeezerSearch(val data: List<DeezerTrack> = emptyList())

@Serializable
private data class DeezerArtist(val name: String = "")

@Serializable
private data class DeezerAlbumRef(val id: Long? = null, val title: String? = null, val coverXl: String? = null)

@Serializable
private data class DeezerTrack(
    val id: Long = 0,
    val title: String = "",
    val duration: Int? = null,
    val artist: DeezerArtist = DeezerArtist(),
    val album: DeezerAlbumRef? = null,
    val trackPosition: Int? = null,
    val diskNumber: Int? = null,
    val releaseDate: String? = null,
    val isrc: String? = null,
)

@Serializable
private data class DeezerGenre(val name: String = "")

@Serializable
private data class DeezerGenres(val data: List<DeezerGenre> = emptyList())

@Serializable
private data class DeezerAlbumFull(val releaseDate: String? = null, val genres: DeezerGenres? = null)

object CatalogClient {
    suspend fun lookup(query: CatalogQuery): CatalogMatch? {
        val apple = iTunes(query)
        if (apple != null && apple.album != null) return apple
        val deezer = deezer(query)
        if (deezer != null) return deezer
        return apple
    }

    fun score(query: CatalogQuery, title: String, artist: String, duration: Double?): Double? {
        val titleScore = TextMatching.titleRatio(query.title, title)
        val artistKnown = query.artist.isNotEmpty()
        if (titleScore < (if (artistKnown) 0.85 else 0.95)) return null
        var artistScore = 1.0
        if (artistKnown) {
            artistScore = TextMatching.artistRatio(query.artist, artist)
            if (artistScore < 0.8) return null
        }
        var penalty = 0.0
        val wanted = query.duration
        if (wanted != null && duration != null) {
            val diff = abs(wanted - duration)
            if (diff > (if (artistKnown) 4 else 2)) return null
            penalty = diff * 0.02
        }
        return titleScore + artistScore - penalty
    }

    fun year(text: String?): Int? {
        if (text == null || text.length < 4) return null
        return text.take(4).toIntOrNull()
    }

    fun artworkUrl(small: String?): String? = small?.replace("100x100bb", "1400x1400bb")

    fun searchTerm(query: CatalogQuery): String {
        val artist = TextMatching.stripFeaturing(query.artist)
        val title = TextMatching.stripFeaturing(query.title)
        return listOf(artist, title).filter { it.isNotEmpty() }.joinToString(" ")
    }

    suspend fun iTunes(query: CatalogQuery): CatalogMatch? {
        for (country in listOf("us", "ru")) {
            RateLimiter.wait("itunes", 3200)
            val url = Net.components(
                "https://itunes.apple.com/search",
                mapOf("term" to searchTerm(query), "media" to "music", "entity" to "song", "limit" to "10", "country" to country),
            ) ?: continue
            val response = runCatching { Net.json.decodeFromString<ITunesResponse>(Net.text(url)) }.getOrNull() ?: continue
            var best: Pair<ITunesItem, Double>? = null
            for (item in response.results) {
                if (item.wrapperType != "track") continue
                val title = item.trackName ?: continue
                val artist = item.artistName ?: continue
                val value = score(query, title, artist, item.trackTimeMillis?.let { it / 1000.0 }) ?: continue
                val current = best
                if (current == null || value > current.second) best = item to value
            }
            val winner = best?.first ?: continue
            return CatalogMatch(
                title = winner.trackName ?: query.title,
                artist = winner.artistName ?: query.artist,
                album = winner.collectionName,
                trackNumber = winner.trackNumber,
                discNumber = winner.discNumber,
                year = year(winner.releaseDate),
                genre = winner.primaryGenreName,
                coverUrl = artworkUrl(winner.artworkUrl100),
                durationSeconds = winner.trackTimeMillis?.let { it / 1000.0 },
                source = "itunes",
            )
        }
        return null
    }

    suspend fun deezer(query: CatalogQuery): CatalogMatch? {
        RateLimiter.wait("deezer", 250)
        val artist = TextMatching.stripFeaturing(query.artist)
        val title = TextMatching.stripFeaturing(query.title)
        val term = if (artist.isEmpty()) title else "artist:\"$artist\" track:\"$title\""
        val url = Net.components("https://api.deezer.com/search", mapOf("q" to term, "limit" to "10")) ?: return null
        val response = runCatching { Net.snakeJson.decodeFromString<DeezerSearch>(Net.text(url)) }.getOrNull() ?: return null
        var best: Pair<DeezerTrack, Double>? = null
        for (item in response.data) {
            val value = score(query, item.title, item.artist.name, item.duration?.toDouble()) ?: continue
            val current = best
            if (current == null || value > current.second) best = item to value
        }
        val candidate = best?.first ?: return null
        RateLimiter.wait("deezer", 250)
        val full = runCatching {
            Net.snakeJson.decodeFromString<DeezerTrack>(Net.text("https://api.deezer.com/track/${candidate.id}"))
        }.getOrNull() ?: candidate
        var genre: String? = null
        var releaseDate = full.releaseDate
        val albumId = full.album?.id ?: candidate.album?.id
        if (albumId != null) {
            RateLimiter.wait("deezer", 250)
            val album = runCatching {
                Net.snakeJson.decodeFromString<DeezerAlbumFull>(Net.text("https://api.deezer.com/album/$albumId"))
            }.getOrNull()
            if (album != null) {
                genre = album.genres?.data?.firstOrNull()?.name
                releaseDate = releaseDate ?: album.releaseDate
            }
        }
        return CatalogMatch(
            title = full.title,
            artist = full.artist.name,
            album = full.album?.title ?: candidate.album?.title,
            trackNumber = full.trackPosition,
            discNumber = full.diskNumber,
            year = year(releaseDate),
            genre = genre,
            isrc = full.isrc,
            coverUrl = full.album?.coverXl ?: candidate.album?.coverXl,
            durationSeconds = full.duration?.toDouble(),
            source = "deezer",
        )
    }
}
