package space.nodeshift.music.imports

import android.os.ParcelFileDescriptor
import com.kyant.taglib.AudioPropertiesReadStyle
import com.kyant.taglib.Picture
import com.kyant.taglib.TagLib
import java.io.File

data class ReadTags(
    val title: String? = null,
    val artist: String? = null,
    val album: String? = null,
    val albumArtist: String? = null,
    val genre: String? = null,
    val trackNumber: Int? = null,
    val discNumber: Int? = null,
    val year: Int? = null,
    val duration: Double? = null,
    val sampleRate: Int? = null,
    val bitrateKbps: Int? = null,
    val cover: ByteArray? = null,
    val lyrics: String? = null,
)

data class WriteTags(
    val title: String,
    val artist: String,
    val album: String? = null,
    val albumArtist: String? = null,
    val genre: String? = null,
    val trackNumber: Int? = null,
    val discNumber: Int? = null,
    val year: Int? = null,
    val isrc: String? = null,
    val cover: ByteArray? = null,
)

object TagIO {
    private const val FRONT_COVER = "Front Cover"

    private inline fun <T> withFd(file: File, mode: Int, block: (Int) -> T): T =
        ParcelFileDescriptor.open(file, mode).use { descriptor -> block(descriptor.dup().detachFd()) }

    private fun leadingNumber(text: String?): Int? {
        if (text == null) return null
        val digits = text.trim().takeWhile { it.isDigit() }
        return digits.toIntOrNull()
    }

    fun read(file: File): ReadTags? {
        return try {
            val properties = withFd(file, ParcelFileDescriptor.MODE_READ_ONLY) {
                TagLib.getAudioProperties(it, AudioPropertiesReadStyle.Fast)
            } ?: return null
            val metadata = withFd(file, ParcelFileDescriptor.MODE_READ_ONLY) { TagLib.getMetadata(it, true) }
            fun first(key: String): String? =
                metadata?.propertyMap?.get(key)?.firstOrNull()?.trim()?.takeIf { it.isNotEmpty() }
            val pictures = metadata?.pictures ?: emptyArray()
            val front = pictures.firstOrNull { it.pictureType == FRONT_COVER } ?: pictures.firstOrNull()
            ReadTags(
                title = first("TITLE"),
                artist = first("ARTIST"),
                album = first("ALBUM"),
                albumArtist = first("ALBUMARTIST"),
                genre = first("GENRE"),
                trackNumber = leadingNumber(first("TRACKNUMBER")),
                discNumber = leadingNumber(first("DISCNUMBER")),
                year = first("DATE")?.takeIf { it.length >= 4 }?.take(4)?.toIntOrNull(),
                duration = properties.length / 1000.0,
                sampleRate = properties.sampleRate.takeIf { it > 0 },
                bitrateKbps = properties.bitrate.takeIf { it > 0 },
                cover = front?.data,
                lyrics = first("LYRICS"),
            )
        } catch (_: Throwable) {
            null
        }
    }

    fun write(file: File, tags: WriteTags): Boolean {
        return try {
            val current = withFd(file, ParcelFileDescriptor.MODE_READ_ONLY) { TagLib.getMetadata(it, false) }
            val map = HashMap<String, Array<String>>(current?.propertyMap ?: HashMap())
            map["TITLE"] = arrayOf(tags.title)
            map["ARTIST"] = arrayOf(tags.artist)
            tags.album?.let { map["ALBUM"] = arrayOf(it) }
            tags.albumArtist?.let { map["ALBUMARTIST"] = arrayOf(it) }
            tags.genre?.let { map["GENRE"] = arrayOf(it) }
            tags.trackNumber?.let { map["TRACKNUMBER"] = arrayOf(it.toString()) }
            tags.discNumber?.let { map["DISCNUMBER"] = arrayOf(it.toString()) }
            tags.year?.let { map["DATE"] = arrayOf(it.toString()) }
            tags.isrc?.let { map["ISRC"] = arrayOf(it) }
            var ok = withFd(file, ParcelFileDescriptor.MODE_READ_WRITE) { TagLib.savePropertyMap(it, map) }
            val cover = tags.cover
            if (cover != null) {
                val existing = withFd(file, ParcelFileDescriptor.MODE_READ_ONLY) { TagLib.getPictures(it) }
                val kept = existing.filter { it.pictureType != FRONT_COVER }
                val fresh = Picture(cover, FRONT_COVER, FRONT_COVER, "image/jpeg")
                ok = withFd(file, ParcelFileDescriptor.MODE_READ_WRITE) {
                    TagLib.savePictures(it, (listOf(fresh) + kept).toTypedArray())
                } && ok
            }
            ok
        } catch (_: Throwable) {
            false
        }
    }
}
