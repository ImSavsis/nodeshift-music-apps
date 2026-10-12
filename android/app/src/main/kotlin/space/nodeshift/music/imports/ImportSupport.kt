package space.nodeshift.music.imports

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.documentfile.provider.DocumentFile
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import org.apache.commons.compress.archivers.zip.ZipFile
import java.io.File
import java.io.InputStream
import java.nio.charset.Charset
import java.security.MessageDigest
import java.util.UUID

object FileHasher {
    private fun hex(bytes: ByteArray): String {
        val builder = StringBuilder(bytes.size * 2)
        for (byte in bytes) builder.append("%02x".format(byte.toInt() and 0xFF))
        return builder.toString()
    }

    fun copyAndHash(input: InputStream, destination: File): Pair<String, Long> {
        destination.parentFile?.mkdirs()
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        input.use { source ->
            destination.outputStream().buffered(1 shl 16).use { output ->
                val buffer = ByteArray(1 shl 16)
                while (true) {
                    val read = source.read(buffer)
                    if (read < 0) break
                    digest.update(buffer, 0, read)
                    output.write(buffer, 0, read)
                    total += read
                }
            }
        }
        return hex(digest.digest()) to total
    }

    fun hash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { source ->
            val buffer = ByteArray(1 shl 16)
            while (true) {
                val read = source.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return hex(digest.digest())
    }
}

object ArchiveExtractor {
    val archiveExtensions = setOf("zip", "7z")

    fun sanitize(path: String): String =
        path.replace('\\', '/').split('/').filter { it != ".." && it != "." && it.isNotEmpty() }.joinToString("/")

    private fun target(directory: File, entryName: String): File? {
        val safe = sanitize(entryName)
        if (safe.isEmpty()) return null
        val file = File(directory, safe)
        val root = directory.canonicalPath + File.separator
        if (!file.canonicalPath.startsWith(root)) return null
        return file
    }

    private fun zipNamesBroken(archive: File): Boolean = try {
        ZipFile.builder().setFile(archive).setCharset(Charsets.UTF_8).get().use { zip ->
            zip.entries.asSequence().any { it.name.contains('�') }
        }
    } catch (_: Exception) {
        false
    }

    fun extract(archive: File, into: File) {
        into.mkdirs()
        when (archive.extension.lowercase()) {
            "zip" -> {
                val charset: Charset = if (zipNamesBroken(archive)) Charset.forName("IBM866") else Charsets.UTF_8
                ZipFile.builder().setFile(archive).setCharset(charset).get().use { zip ->
                    for (entry in zip.entries) {
                        if (entry.isDirectory) continue
                        val file = target(into, entry.name) ?: continue
                        file.parentFile?.mkdirs()
                        zip.getInputStream(entry).use { input -> file.outputStream().use { output -> input.copyTo(output) } }
                    }
                }
            }
            "7z" -> {
                SevenZFile.builder().setFile(archive).get().use { sevenZ ->
                    while (true) {
                        val entry = sevenZ.nextEntry ?: break
                        if (entry.isDirectory) continue
                        val file = target(into, entry.name) ?: continue
                        file.parentFile?.mkdirs()
                        sevenZ.getInputStream(entry).use { input -> file.outputStream().use { output -> input.copyTo(output) } }
                    }
                }
            }
        }
    }
}

class ImportCandidate(
    val name: String,
    val group: String,
    val uri: Uri? = null,
    val file: File? = null,
) {
    val extension: String
        get() = name.substringAfterLast('.', "").lowercase()

    fun open(resolver: ContentResolver): InputStream =
        if (file != null) file.inputStream() else resolver.openInputStream(requireNotNull(uri)) ?: throw java.io.IOException("open")
}

data class ImportSource(val uri: Uri, val isTree: Boolean = false)

class ScanResult(val candidates: List<ImportCandidate>, val skipped: Int)

object ImportScanner {
    val audioExtensions = setOf("mp3", "flac", "m4a", "aac", "ogg", "oga", "opus", "wav", "mka")

    fun displayName(resolver: ContentResolver, uri: Uri): String {
        if (uri.scheme == "file") return File(requireNotNull(uri.path)).name
        runCatching {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0 && !cursor.isNull(index)) return cursor.getString(index)
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "file"
    }

    fun scan(context: Context, sources: List<ImportSource>, scratch: File): ScanResult {
        val resolver = context.contentResolver
        val candidates = ArrayList<ImportCandidate>()
        var skipped = 0

        fun visitDirectory(directory: File, group: String) {
            val children = directory.listFiles()?.sortedBy { it.name } ?: return
            for (child in children) {
                if (child.name.startsWith(".")) continue
                if (child.isDirectory) {
                    visitDirectory(child, child.path)
                    continue
                }
                val ext = child.extension.lowercase()
                if (ext in ArchiveExtractor.archiveExtensions) {
                    val target = File(scratch, UUID.randomUUID().toString())
                    try {
                        ArchiveExtractor.extract(child, target)
                        visitDirectory(target, target.path)
                    } catch (_: Exception) {
                        skipped += 1
                    }
                } else if (ext in audioExtensions) {
                    candidates.add(ImportCandidate(child.name, group, file = child))
                } else {
                    skipped += 1
                }
            }
        }

        fun visitDocument(name: String, uri: Uri, group: String) {
            val ext = name.substringAfterLast('.', "").lowercase()
            if (ext in ArchiveExtractor.archiveExtensions) {
                val local = File(scratch, UUID.randomUUID().toString() + "." + ext)
                val target = File(scratch, UUID.randomUUID().toString())
                try {
                    local.parentFile?.mkdirs()
                    resolver.openInputStream(uri)?.use { input -> local.outputStream().use { input.copyTo(it) } }
                    ArchiveExtractor.extract(local, target)
                    visitDirectory(target, target.path)
                } catch (_: Exception) {
                    skipped += 1
                } finally {
                    local.delete()
                }
            } else if (ext in audioExtensions) {
                candidates.add(ImportCandidate(name, group, uri = uri))
            } else {
                skipped += 1
            }
        }

        fun visitTree(document: DocumentFile) {
            val children = document.listFiles().sortedBy { it.name ?: "" }
            for (child in children) {
                val name = child.name ?: continue
                if (name.startsWith(".")) continue
                if (child.isDirectory) visitTree(child) else visitDocument(name, child.uri, document.uri.toString())
            }
        }

        scratch.mkdirs()
        for (source in sources) {
            if (source.isTree) {
                DocumentFile.fromTreeUri(context, source.uri)?.let { visitTree(it) }
            } else {
                visitDocument(displayName(resolver, source.uri), source.uri, "picked")
            }
        }
        return ScanResult(candidates, skipped)
    }
}
