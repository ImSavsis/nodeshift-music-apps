package space.nodeshift.music.site

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import space.nodeshift.music.BuildConfig
import space.nodeshift.music.core.UpdateCheck
import space.nodeshift.music.core.UpdateManifest
import space.nodeshift.music.data.AppPaths
import space.nodeshift.music.imports.FileHasher
import space.nodeshift.music.net.Net

@Serializable
private data class ManifestDto(
    val platform: String = "android",
    val version: String = "0",
    val build: Int = 0,
    val commit: String? = null,
    val file: String = "",
    val size: Long = 0,
    val sha256: String = "",
    val minOS: String? = null,
    val notes: String? = null,
    val builtAt: String? = null,
    val url: String? = null,
    val available: Boolean? = null,
)

class UpdateChecker(private val context: Context) {
    var available by mutableStateOf<UpdateManifest?>(null)
        private set
    var checking by mutableStateOf(false)
        private set
    var downloading by mutableStateOf(false)
        private set
    var progress by mutableFloatStateOf(0f)
        private set
    var failure by mutableStateOf<String?>(null)
        private set

    private var lastCheck = 0L

    val currentVersion: String
        get() = BuildConfig.VERSION_NAME

    val currentBuild: Int
        get() = BuildConfig.VERSION_CODE

    suspend fun check(force: Boolean = false) {
        if (!force && System.currentTimeMillis() - lastCheck < 6 * 3600 * 1000L) return
        checking = true
        try {
            val dto = runCatching {
                Net.json.decodeFromString<ManifestDto>(Net.text("${SiteApi.BASE}/app/update/files/android"))
            }.getOrNull() ?: return
            lastCheck = System.currentTimeMillis()
            if (dto.available == false || dto.file.isEmpty()) {
                available = null
                return
            }
            val manifest = UpdateManifest(
                platform = dto.platform,
                version = dto.version,
                build = dto.build,
                commit = dto.commit,
                file = dto.file,
                size = dto.size,
                sha256 = dto.sha256,
                minOS = dto.minOS,
                notes = dto.notes,
                builtAt = dto.builtAt,
                url = dto.url,
            )
            available = if (UpdateCheck.isNewer(manifest, currentVersion, currentBuild) &&
                UpdateCheck.meetsMinimumOs(manifest, Build.VERSION.RELEASE)
            ) {
                manifest
            } else {
                null
            }
        } finally {
            checking = false
        }
    }

    suspend fun downloadAndInstall(): Boolean {
        val manifest = available ?: return false
        if (downloading) return false
        downloading = true
        progress = 0f
        failure = null
        try {
            val target = java.io.File(AppPaths.updatesDir, "NodeShiftMusic.apk")
            withContext(Dispatchers.IO) {
                target.delete()
                download("${SiteApi.BASE}/app/files/android/download", target, manifest.size)
            }
            val hash = withContext(Dispatchers.IO) { FileHasher.hash(target) }
            if (manifest.sha256.isNotEmpty() && !hash.equals(manifest.sha256, ignoreCase = true)) {
                target.delete()
                failure = "Файл повреждён, попробуй ещё раз"
                return false
            }
            install(target)
            return true
        } catch (_: Exception) {
            failure = "Не получилось скачать обновление"
            return false
        } finally {
            downloading = false
        }
    }

    private suspend fun download(url: String, target: java.io.File, expected: Long) {
        Net.execute(Net.request(url).build()).use { response ->
            if (!response.isSuccessful) throw java.io.IOException("http ${response.code}")
            val total = if (expected > 0) expected else response.body.contentLength()
            var done = 0L
            response.body.byteStream().use { input ->
                target.outputStream().use { output ->
                    val buffer = ByteArray(1 shl 16)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        done += read
                        if (total > 0) progress = (done.toDouble() / total).toFloat().coerceIn(0f, 1f)
                    }
                }
            }
        }
    }

    private fun install(file: java.io.File) {
        if (!context.packageManager.canRequestPackageInstalls()) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            return
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    fun openDownloadPage() {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse("${SiteApi.BASE}/app/files/android")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}
