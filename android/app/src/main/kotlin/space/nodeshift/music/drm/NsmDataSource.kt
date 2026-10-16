package space.nodeshift.music.drm

import android.content.Context
import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSourceException
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.TransferListener
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import kotlinx.coroutines.runBlocking
import space.nodeshift.music.core.LockedCrypto
import space.nodeshift.music.core.LockedException
import space.nodeshift.music.core.LockedGrant
import space.nodeshift.music.core.LockedHeader
import space.nodeshift.music.core.LockedKind
import space.nodeshift.music.data.AppPaths
import space.nodeshift.music.net.Net
import space.nodeshift.music.site.SiteApi

private interface LockedSource {
    fun read(offset: Long, length: Long): ByteArray
}

private class FileSource(private val file: File) : LockedSource {
    override fun read(offset: Long, length: Long): ByteArray =
        RandomAccessFile(file, "r").use {
            it.seek(offset)
            ByteArray(length.toInt()).also { buffer -> it.readFully(buffer) }
        }
}

private class RemoteSource(private val url: String) : LockedSource {
    override fun read(offset: Long, length: Long): ByteArray = runBlocking {
        Net.execute(Net.request(url, mapOf("Range" to "bytes=$offset-${offset + length - 1}")).build()).use { response ->
            if (response.code != 206) throw IOException("the file host refused the range")
            val bytes = response.body.bytes()
            if (bytes.size.toLong() != length) throw IOException("the file host sent a short range")
            bytes
        }
    }
}

private class LockedStream(val header: LockedHeader, val key: ByteArray, val source: LockedSource) {
    fun batch(start: Long, end: Long): ByteArray {
        val span = header.span(start, end)
        return LockedCrypto.decrypt(key, header, span, source.read(span.offset, span.length), start, end)
    }
}

@androidx.annotation.OptIn(UnstableApi::class)
class LockedDataSource : BaseDataSource(true) {
    private var uri: Uri? = null
    private var stream: LockedStream? = null
    private var buffer = ByteArray(0)
    private var bufferPosition = 0
    private var position = 0L
    private var remaining = 0L
    private var opened = false

    private fun resolve(route: Uri): LockedStream = runBlocking {
        val parts = route.pathSegments
        val site = route.host.orEmpty()
        when (site) {
            "site" -> {
                val wantsLossless = parts.getOrNull(1) == "lossless"
                val grant = try {
                    LicenseVault.grant(parts[0], if (wantsLossless) LockedKind.LOSSLESS else LockedKind.LOSSY, false)
                } catch (error: Exception) {
                    if (!wantsLossless) throw error
                    LicenseVault.grant(parts[0], LockedKind.LOSSY, false)
                }
                open(grant, RemoteSource(SiteApi.lockedUrl(grant.name)))
            }
            "file" -> {
                val kind = if (parts.getOrNull(1) == "lossless") LockedKind.LOSSLESS else LockedKind.LOSSY
                val name = parts.getOrNull(2) ?: throw LockedException("no file name")
                if (name.contains('/') || name.contains("..")) throw LockedException("bad file name")
                open(LicenseVault.grantForPlayback(parts[0], kind), FileSource(AppPaths.trackFile(name)))
            }
            else -> throw LockedException("unknown route")
        }
    }

    private fun open(grant: LockedGrant, source: LockedSource): LockedStream {
        val header = LicenseVault.header(grant.name) ?: LockedHeader.parse(source.read(0, LockedHeader.SIZE.toLong())).also { LicenseVault.keepHeader(grant.name, it) }
        if (header.keyId != grant.keyId) throw LockedException("the key does not match the file")
        return LockedStream(header, grant.key(), source)
    }

    override fun open(dataSpec: DataSpec): Long {
        uri = dataSpec.uri
        transferInitializing(dataSpec)
        val resolved = try {
            resolve(dataSpec.uri)
        } catch (error: Exception) {
            throw DataSourceException(IOException(error), PlaybackException.ERROR_CODE_IO_NO_PERMISSION)
        }
        val total = resolved.header.plainLength
        if (dataSpec.position > total) throw DataSourceException(PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE)
        stream = resolved
        position = dataSpec.position
        remaining = if (dataSpec.length == C.LENGTH_UNSET.toLong()) total - position else minOf(dataSpec.length, total - position)
        buffer = ByteArray(0)
        bufferPosition = 0
        opened = true
        transferStarted(dataSpec)
        return remaining
    }

    override fun read(target: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (remaining == 0L) return C.RESULT_END_OF_INPUT
        val current = stream ?: throw IOException("the source is closed")
        if (bufferPosition >= buffer.size) {
            val size = current.header.chunkSize
            val last = minOf(position + remaining - 1, (position / size + BATCH_CHUNKS) * size - 1)
            buffer = try {
                current.batch(position, last)
            } catch (error: LockedException) {
                throw IOException(error)
            }
            bufferPosition = 0
        }
        val count = minOf(length.toLong(), (buffer.size - bufferPosition).toLong(), remaining).toInt()
        System.arraycopy(buffer, bufferPosition, target, offset, count)
        bufferPosition += count
        position += count
        remaining -= count
        bytesTransferred(count)
        return count
    }

    override fun getUri(): Uri? = uri

    override fun close() {
        uri = null
        stream = null
        buffer = ByteArray(0)
        if (opened) {
            opened = false
            transferEnded()
        }
    }

    companion object {
        const val SCHEME = "nsm"
        const val BATCH_CHUNKS = 32L

        fun site(siteId: String, wantsLossless: Boolean): Uri = Uri.parse("$SCHEME://site/$siteId/${if (wantsLossless) "lossless" else "lossy"}")

        fun file(siteId: String, fileName: String): Uri {
            val kind = if (fileName.endsWith(".nlac")) "lossless" else "lossy"
            return Uri.parse("$SCHEME://file/$siteId/$kind/${Uri.encode(fileName)}")
        }
    }
}

@androidx.annotation.OptIn(UnstableApi::class)
private class RoutingDataSource(private val fallback: DataSource, private val locked: DataSource) : DataSource {
    private var active: DataSource? = null

    override fun addTransferListener(transferListener: TransferListener) {
        fallback.addTransferListener(transferListener)
        locked.addTransferListener(transferListener)
    }

    override fun open(dataSpec: DataSpec): Long {
        if (dataSpec.uri.scheme != LockedDataSource.SCHEME) {
            active = fallback
            return fallback.open(dataSpec)
        }
        try {
            active = locked
            return locked.open(dataSpec)
        } catch (error: IOException) {
            locked.close()
            val track = dataSpec.uri.pathSegments.firstOrNull()
            if (dataSpec.uri.host != "site" || track == null) throw error
            active = fallback
            return fallback.open(dataSpec.buildUpon().setUri(Uri.parse(SiteApi.previewUrl(track))).build())
        }
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int = (active ?: throw IOException("the source is closed")).read(buffer, offset, length)

    override fun getUri(): Uri? = active?.uri

    override fun getResponseHeaders(): Map<String, List<String>> = active?.responseHeaders ?: emptyMap()

    override fun close() {
        active?.close()
        active = null
    }
}

@androidx.annotation.OptIn(UnstableApi::class)
class NsmDataSourceFactory(context: Context) : DataSource.Factory {
    private val upstream = DefaultDataSource.Factory(context)

    override fun createDataSource(): DataSource = RoutingDataSource(upstream.createDataSource(), LockedDataSource())
}
