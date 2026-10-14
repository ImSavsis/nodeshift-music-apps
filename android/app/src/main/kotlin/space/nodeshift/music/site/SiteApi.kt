package space.nodeshift.music.site

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encodeToString
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import space.nodeshift.music.data.Prefs
import space.nodeshift.music.net.Net
import space.nodeshift.music.net.NetException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object SecureStore {
    private const val ALIAS = "nsm_tokens"
    private const val PROVIDER = "AndroidKeyStore"

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(PROVIDER).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    fun put(name: String, value: String) {
        try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
            Prefs.putString("sec_$name", Base64.encodeToString(cipher.iv + encrypted, Base64.NO_WRAP))
        } catch (_: Exception) {
            Prefs.putString("sec_$name", null)
        }
    }

    fun get(name: String): String? {
        val raw = Prefs.string("sec_$name") ?: return null
        return try {
            val bytes = Base64.decode(raw, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, 12))
            String(cipher.doFinal(bytes, 12, bytes.size - 12), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    fun remove(name: String) {
        Prefs.putString("sec_$name", null)
    }
}

@Serializable(with = FlexibleIdSerializer::class)
data class FlexibleId(val value: String)

object FlexibleIdSerializer : KSerializer<FlexibleId> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("FlexibleId", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): FlexibleId {
        val element = (decoder as JsonDecoder).decodeJsonElement()
        return FlexibleId((element as JsonPrimitive).content)
    }

    override fun serialize(encoder: Encoder, value: FlexibleId) = encoder.encodeString(value.value)
}

@Serializable
data class SiteUser(
    val id: FlexibleId,
    val email: String? = null,
    val username: String? = null,
    val handle: String? = null,
    val avatarUrl: String? = null,
)

@Serializable
data class SiteTokenPair(val accessToken: String, val refreshToken: String, val user: SiteUser)

@Serializable
data class SiteAccessToken(val accessToken: String)

@Serializable
data class SiteLoginUrl(val url: String)

@Serializable
data class SiteTrack(
    val id: FlexibleId,
    val title: String = "",
    val artist: String = "",
    val album: String? = null,
    val durationSeconds: Double? = null,
    val filename: String = "",
    val coverFilename: String? = null,
    val motionFilename: String? = null,
    val streamFilename: String? = null,
    val format: String? = null,
    val playCount: Int? = null,
    val mediaKind: String? = null,
)

@Serializable
data class SiteLibraryState(val favoriteIds: List<FlexibleId> = emptyList())

@Serializable
data class SitePlaylist(
    val id: FlexibleId,
    val name: String = "",
    val coverFilename: String? = null,
    val trackCount: Int? = null,
)

@Serializable
data class SitePlaylistEntry(val position: Int = 0, val track: SiteTrack)

@Serializable
data class SitePlaylistDetail(
    val id: FlexibleId,
    val name: String = "",
    val coverFilename: String? = null,
    val tracks: List<SitePlaylistEntry> = emptyList(),
)

@Serializable
data class SiteLyrics(val synced: String? = null, val plain: String? = null, val source: String? = null)

@Serializable
data class SiteRoomCreated(val code: String)

class SiteException(val kind: Kind, val code: Int = 0) : Exception(kind.name) {
    enum class Kind { Cancelled, NoToken, BadCallback, Unauthorized, Server }
}

object SiteApi {
    const val BASE = "https://music.nodeshift.space"
    private const val MEDIA = "https://burmalda.savsis.xyz"

    private var access: String? = null
    private var refresh: String? = null

    fun load() {
        access = SecureStore.get("access")
        refresh = SecureStore.get("refresh")
    }

    val hasSession: Boolean
        get() = refresh != null

    fun setTokens(access: String?, refresh: String?) {
        this.access = access
        if (refresh != null) this.refresh = refresh
        if (access != null) SecureStore.put("access", access)
        if (refresh != null) SecureStore.put("refresh", refresh)
    }

    fun clear() {
        access = null
        refresh = null
        SecureStore.remove("access")
        SecureStore.remove("refresh")
    }

    private val json: Json
        get() = Net.snakeJson

    suspend fun loginUrl(): String {
        val payload = json.decodeFromString<SiteLoginUrl>(Net.text("$BASE/api/auth/login-url?client=native"))
        if (payload.url.isEmpty()) throw SiteException(SiteException.Kind.BadCallback)
        return payload.url
    }

    suspend fun ssoLogin(token: String, state: String): SiteTokenPair {
        val body = buildJsonObject {
            put("sso_token", token)
            put("state", state)
        }
        Net.execute(Net.postJson("$BASE/api/auth/sso-login", body.toString())).use { response ->
            if (!response.isSuccessful) throw SiteException(SiteException.Kind.Server, response.code)
            return json.decodeFromString(response.body.string())
        }
    }

    suspend fun refreshAccess(): String {
        val token = refresh ?: throw SiteException(SiteException.Kind.NoToken)
        val body = buildJsonObject { put("refresh_token", token) }
        Net.execute(Net.postJson("$BASE/api/auth/refresh", body.toString())).use { response ->
            if (response.code == 401 || response.code == 400) {
                clear()
                throw SiteException(SiteException.Kind.Unauthorized)
            }
            if (!response.isSuccessful) throw SiteException(SiteException.Kind.Server, response.code)
            val fresh = json.decodeFromString<SiteAccessToken>(response.body.string()).accessToken
            setTokens(fresh, null)
            return fresh
        }
    }

    private suspend fun authorized(path: String, method: String = "GET"): String {
        var token = access ?: refreshAccess()
        for (attempt in 0 until 2) {
            val builder = Net.request("$BASE$path", mapOf("Authorization" to "Bearer $token"))
            when (method) {
                "POST" -> builder.post(ByteArray(0).toRequestBody())
                "DELETE" -> builder.delete()
            }
            Net.execute(builder.build()).use { response ->
                if (response.code == 401 && attempt == 0) {
                    token = refreshAccess()
                    return@use
                }
                if (!response.isSuccessful) {
                    throw SiteException(if (response.code == 401) SiteException.Kind.Unauthorized else SiteException.Kind.Server, response.code)
                }
                return response.body.string()
            }
        }
        throw SiteException(SiteException.Kind.Unauthorized)
    }

    suspend fun me(): SiteUser = json.decodeFromString(authorized("/api/auth/me"))

    suspend fun favorites(): List<SiteTrack> = json.decodeFromString(authorized("/api/music/favorites"))

    suspend fun playlists(): List<SitePlaylist> = json.decodeFromString(authorized("/api/music/playlists"))

    suspend fun playlist(id: String): SitePlaylistDetail = json.decodeFromString(authorized("/api/music/playlists/$id"))

    suspend fun catalog(search: String, sort: String, format: String?, limit: Int, offset: Int): List<SiteTrack> {
        val items = HashMap<String, String>()
        items["sort"] = sort
        items["limit"] = limit.toString()
        items["offset"] = offset.toString()
        if (search.isNotEmpty()) items["search"] = search
        if (format != null) items["format"] = format
        val link = Net.components("$BASE/api/music/tracks", items) ?: throw SiteException(SiteException.Kind.BadCallback)
        return json.decodeFromString(Net.text(link))
    }

    suspend fun wave(limit: Int): List<SiteTrack> {
        val link = Net.components("$BASE/api/music/wave", mapOf("limit" to limit.toString())) ?: throw SiteException(SiteException.Kind.BadCallback)
        return json.decodeFromString(Net.text(link))
    }

    suspend fun registerPlay(trackId: String) {
        runCatching {
            Net.execute(Net.request("$BASE/api/music/tracks/$trackId/play").post(ByteArray(0).toRequestBody()).build()).close()
        }
    }

    suspend fun likedIds(): Set<String> =
        json.decodeFromString<SiteLibraryState>(authorized("/api/music/me/library")).favoriteIds.map { it.value }.toSet()

    suspend fun setLiked(trackId: String, value: Boolean) {
        authorized("/api/music/favorites/$trackId", if (value) "POST" else "DELETE")
    }

    suspend fun lyrics(trackId: String): SiteLyrics? = try {
        json.decodeFromString<SiteLyrics>(Net.text("$BASE/api/music/lyrics/$trackId"))
    } catch (_: Exception) {
        null
    }

    private fun media(folder: String, name: String): String =
        MEDIA.toHttpUrl().newBuilder().addPathSegment(folder).addPathSegment(name).build().toString()

    fun audioUrl(track: SiteTrack, lossless: Boolean): String {
        val stream = track.streamFilename
        if (!lossless && stream != null) return media("stream", stream)
        return media("tracks", track.filename)
    }

    fun coverUrl(name: String): String = media("covers", name)

    fun thumbUrl(name: String): String = media("thumbs", name.substringBeforeLast('.') + ".webp")

    fun motionUrl(name: String): String = media("motion", name)

    suspend fun freshAccessToken(): String? {
        if (!hasSession) return null
        return try {
            refreshAccess()
        } catch (_: Exception) {
            access
        }
    }

    suspend fun createRoom(): String = json.decodeFromString<SiteRoomCreated>(authorized("/api/music/rooms", "POST")).code

    suspend fun roomExists(code: String): Boolean = try {
        Net.text("$BASE/api/music/rooms/$code")
        true
    } catch (error: space.nodeshift.music.net.NetException) {
        if (error.status == 404) false else throw error
    }

    fun roomSocketUrl(code: String): String = "wss://music.nodeshift.space/api/music/rooms/$code/ws"

    fun roomLink(code: String): String = "$BASE/room/$code"

    const val BUMP = "$BASE/app/bump"

    suspend fun publishPresence(body: org.json.JSONObject) {
        if (!hasSession) return
        runCatching {
            var token = access ?: refreshAccess()
            for (attempt in 0 until 2) {
                val request = Net.postJson("$BUMP/presence", body.toString(), mapOf("Authorization" to "Bearer $token"))
                val code = Net.execute(request).use { it.code }
                if (code == 401 && attempt == 0) {
                    token = refreshAccess()
                    continue
                }
                break
            }
        }
    }

    suspend fun uploadPresenceArt(jpeg: ByteArray): String? {
        val token = access ?: return null
        return try {
            val request = Net.request("$BUMP/presence/art", mapOf("Authorization" to "Bearer $token"))
                .post(jpeg.toRequestBody("image/jpeg".toMediaType()))
                .build()
            Net.execute(request).use { response ->
                if (!response.isSuccessful) null else org.json.JSONObject(response.body.string()).optString("url").ifEmpty { null }
            }
        } catch (_: Exception) {
            null
        }
    }
}
