package space.nodeshift.music.net

import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNamingStrategy
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.math.max

class NetException(val status: Int, message: String = "http $status") : IOException(message)

object RateLimiter {
    private val mutex = Mutex()
    private val next = HashMap<String, Long>()

    suspend fun wait(key: String, intervalMillis: Long) {
        val pause = mutex.withLock {
            val now = System.currentTimeMillis()
            val slot = max(now, next[key] ?: now)
            next[key] = slot + intervalMillis
            slot - now
        }
        if (pause > 0) delay(pause)
    }
}

@OptIn(ExperimentalSerializationApi::class)
object Net {
    const val USER_AGENT = "NodeShiftMusic/0.1 (+https://music.nodeshift.space)"
    const val BROWSER_AGENT =
        "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36"

    val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .writeTimeout(25, TimeUnit.SECONDS)
        .callTimeout(10, TimeUnit.MINUTES)
        .followRedirects(true)
        .build()

    val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
    }

    val snakeJson = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
        namingStrategy = JsonNamingStrategy.SnakeCase
    }

    private val jsonMedia = "application/json".toMediaType()

    fun request(url: String, headers: Map<String, String> = emptyMap(), agent: String = USER_AGENT): Request.Builder {
        val builder = Request.Builder().url(url).header("User-Agent", agent)
        headers.forEach { (key, value) -> builder.header(key, value) }
        return builder
    }

    fun postJson(url: String, body: String, headers: Map<String, String> = emptyMap()): Request =
        request(url, headers).header("Content-Type", "application/json").post(body.toRequestBody(jsonMedia)).build()

    private suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation: CancellableContinuation<Response> ->
        continuation.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (continuation.isActive) continuation.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                continuation.resume(response)
            }
        })
    }

    suspend fun execute(request: Request): Response = client.newCall(request).await()

    suspend fun bytes(url: String, headers: Map<String, String> = emptyMap(), agent: String = USER_AGENT): ByteArray {
        execute(request(url, headers, agent).build()).use { response ->
            if (!response.isSuccessful) throw NetException(response.code)
            return withContext(Dispatchers.IO) { response.body.bytes() }
        }
    }

    suspend fun text(url: String, headers: Map<String, String> = emptyMap(), agent: String = USER_AGENT): String =
        String(bytes(url, headers, agent), Charsets.UTF_8)

    suspend fun download(url: String, destination: File, agent: String = USER_AGENT, headers: Map<String, String> = emptyMap()) {
        execute(request(url, headers, agent).build()).use { response ->
            if (!response.isSuccessful) throw NetException(response.code)
            withContext(Dispatchers.IO) {
                destination.parentFile?.mkdirs()
                val temporary = File(destination.parentFile, destination.name + ".part")
                response.body.byteStream().use { input ->
                    temporary.outputStream().use { output -> input.copyTo(output, 64 * 1024) }
                }
                destination.delete()
                if (!temporary.renameTo(destination)) {
                    temporary.copyTo(destination, overwrite = true)
                    temporary.delete()
                }
            }
        }
    }

    fun components(base: String, items: Map<String, String>): String? {
        val parsed: HttpUrl = base.toHttpUrlOrNull() ?: return null
        val builder = parsed.newBuilder()
        items.toSortedMap().forEach { (key, value) -> builder.addQueryParameter(key, value) }
        return builder.build().toString()
    }
}
