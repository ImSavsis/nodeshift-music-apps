package space.nodeshift.music.data

import android.content.Context
import java.io.File

object AppPaths {
    private lateinit var base: File
    private lateinit var cache: File

    fun init(context: Context) {
        base = File(context.filesDir, "NodeShiftMusic").also { it.mkdirs() }
        cache = context.cacheDir
    }

    private fun directory(name: String, root: File = base): File = File(root, name).also { it.mkdirs() }

    val tracksDir: File get() = directory("tracks")
    val coversDir: File get() = directory("covers")
    val motionDir: File get() = directory("motion")
    val scratchDir: File get() = directory("nsm-scratch", cache)
    val updatesDir: File get() = directory("updates", cache)
    val databaseFile: File get() = File(base, "library.sqlite")

    fun trackFile(name: String): File = File(tracksDir, name)

    fun coverFile(name: String): File = File(coversDir, name)

    fun motionFile(name: String): File = File(motionDir, name)
}
