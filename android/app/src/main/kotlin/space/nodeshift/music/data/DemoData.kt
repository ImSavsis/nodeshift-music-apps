package space.nodeshift.music.data

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.min

object DemoData {
    class Album(val name: String, val artist: String, val hueA: Float, val hueB: Float, val cover: String)

    private class Row(val title: String, val album: Int, val format: String, val seconds: Int)

    val albums = listOf(
        Album("Static Bloom", "Aurora Vale", 0.58f, 0.82f, "demo-a.jpg"),
        Album("Harbour Lights", "Kite Runner", 0.05f, 0.62f, "demo-b.jpg"),
        Album("Тишина после", "Низкая орбита", 0.72f, 0.50f, "demo-c.jpg"),
        Album("Glass Season", "Lumen Hall", 0.13f, 0.95f, "demo-d.jpg"),
        Album("Quiet Engines", "North Sea Radio", 0.38f, 0.60f, "demo-e.jpg"),
        Album("Лето в записи", "Мята", 0.30f, 0.12f, "demo-f.jpg"),
    )

    private val rows = listOf(
        Row("Neon Rivers", 0, "flac", 214),
        Row("Paper Boats", 1, "mp3", 242),
        Row("Полночный город", 2, "flac", 228),
        Row("Glass Season", 3, "flac", 312),
        Row("Slow Static", 0, "flac", 177),
        Row("Ferris Wheel", 1, "mp3", 201),
        Row("Холодный свет", 2, "flac", 255),
        Row("Afterglow", 3, "flac", 189),
        Row("Quiet Engines", 4, "mp3", 361),
        Row("Тёплый шум", 5, "mp3", 164),
        Row("Lowlight", 4, "flac", 235),
        Row("Sundial", 0, "flac", 210),
        Row("Берег", 5, "flac", 198),
        Row("Nightbus", 1, "mp3", 284),
    )

    val lrc = """
        [00:04.00]Neon rivers hum beneath the sleeping town
        [00:09.50]Every window holds a quiet constellation
        [00:15.00]We keep walking where the streetlights bend
        [00:20.50]Counting echoes that the night forgot to end
        [00:27.00]Hold the silence like a fragile coin
        [00:32.00]Spin it in the palm of a tired sky
        [00:37.50]Nothing here is ever really lost
        [00:43.00]Only waiting for the morning to arrive
        [00:50.00]Hold the silence like a fragile coin
        [00:55.00]Spin it in the palm of a tired sky
        [01:00.50]Nothing here is ever really lost
        [01:06.00]Only waiting for the morning to arrive
        [01:14.00]Я иду по пустым улицам, где гаснут фонари
        [01:20.00]Город засыпает, а утро ещё далеко
        [01:27.00]Слышишь, как тихо дышит ночная река
        [01:34.00]Мы останемся здесь до первого света
    """.trimIndent()

    private fun hsv(hue: Float, saturation: Float, value: Float): Int = Color.HSVToColor(floatArrayOf(hue * 360f, saturation, value))

    private fun ensureCovers() {
        for (album in albums) {
            val file = AppPaths.coverFile(album.cover)
            if (file.exists()) continue
            val size = 640
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            paint.shader = LinearGradient(
                0f,
                0f,
                size.toFloat(),
                size.toFloat(),
                hsv(album.hueA, 0.55f, 0.62f),
                hsv(album.hueB, 0.62f, 0.22f),
                Shader.TileMode.CLAMP,
            )
            canvas.drawRect(0f, 0f, size.toFloat(), size.toFloat(), paint)
            paint.shader = null
            paint.style = Paint.Style.FILL
            paint.color = Color.argb(26, 255, 255, 255)
            canvas.drawOval(size * 0.18f, size * 0.12f, size * 0.18f + size * 0.64f, size * 0.12f + size * 0.64f, paint)
            paint.color = Color.argb(46, 0, 0, 0)
            canvas.drawOval(size * 0.42f, size * 0.46f, size * 0.42f + size * 0.5f, size * 0.46f + size * 0.5f, paint)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 3f
            paint.color = Color.argb(56, 255, 255, 255)
            canvas.drawOval(size * 0.3f, size * 0.3f, size * 0.3f + size * 0.4f, size * 0.3f + size * 0.4f, paint)
            val output = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, output)
            file.writeBytes(output.toByteArray())
            bitmap.recycle()
        }
    }

    private fun writeSilence(file: File, seconds: Int) {
        if (file.exists()) return
        val rate = 4000
        val total = rate * seconds
        val header = ByteArray(44)
        fun int32(offset: Int, value: Int) {
            header[offset] = value.toByte()
            header[offset + 1] = (value shr 8).toByte()
            header[offset + 2] = (value shr 16).toByte()
            header[offset + 3] = (value shr 24).toByte()
        }
        fun int16(offset: Int, value: Int) {
            header[offset] = value.toByte()
            header[offset + 1] = (value shr 8).toByte()
        }
        "RIFF".toByteArray().copyInto(header, 0)
        int32(4, 36 + total)
        "WAVEfmt ".toByteArray().copyInto(header, 8)
        int32(16, 16)
        int16(20, 1)
        int16(22, 1)
        int32(24, rate)
        int32(28, rate)
        int16(32, 1)
        int16(34, 8)
        "data".toByteArray().copyInto(header, 36)
        int32(40, total)
        val block = ByteArray(rate) { 0x80.toByte() }
        file.outputStream().buffered().use { output ->
            output.write(header)
            var remaining = total
            while (remaining > 0) {
                val chunk = min(remaining, block.size)
                output.write(block, 0, chunk)
                remaining -= chunk
            }
        }
    }

    fun tracks(): List<TrackRecord> {
        ensureCovers()
        val now = System.currentTimeMillis()
        return rows.mapIndexed { index, row ->
            val album = albums[row.album]
            val fileName = "demo-$index.wav"
            writeSilence(AppPaths.trackFile(fileName), row.seconds)
            TrackRecord(
                id = "demo-$index",
                title = row.title,
                artist = album.artist,
                album = album.name,
                trackNumber = index % 5 + 1,
                durationMs = row.seconds * 1000,
                format = row.format,
                bitrateKbps = if (row.format == "mp3") 320 else null,
                fileName = fileName,
                fileSize = row.seconds.toLong() * if (row.format == "mp3") 40_000 else 110_000,
                coverName = album.cover,
                isFavorite = index % 3 == 0,
                playCount = (index * 7) % 23,
                lastPlayedAt = if (index < 6) now - index * 3_600_000L else null,
                addedAt = now - index * 86_400_000L,
            )
        }
    }

    fun seed(database: AppDatabase) {
        if (database.allTracks().any { it.id.startsWith("demo-") }) return
        for (track in tracks()) {
            database.save(track)
            val record = when (track.id) {
                "demo-0", "demo-4" -> LyricsRecord(track.id, "line", "demo", lrc, null)
                "demo-1" -> LyricsRecord(track.id, "plain", "demo", null, lrc.lines().joinToString("\n") { it.substringAfter(']') })
                else -> LyricsRecord(track.id, "none", "none", null, null)
            }
            database.save(record)
        }
    }
}
