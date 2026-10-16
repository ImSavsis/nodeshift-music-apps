package space.nodeshift.music.drm

import java.util.concurrent.ConcurrentHashMap
import space.nodeshift.music.core.LicenseExchange
import space.nodeshift.music.core.LockedException
import space.nodeshift.music.core.LockedGrant
import space.nodeshift.music.core.LockedHeader
import space.nodeshift.music.core.LockedKind
import space.nodeshift.music.site.SecureStore
import space.nodeshift.music.site.SiteApi

object LicenseVault {
    private const val SPARE_SECONDS = 300L
    private const val OFFLINE_SPARE_SECONDS = 7L * 24 * 3600

    private val memory = ConcurrentHashMap<String, LockedGrant>()
    private val headers = ConcurrentHashMap<String, LockedHeader>()

    private fun slot(trackId: Long, kind: LockedKind): String = "drm_${trackId}_${kind.value}"

    private fun now(): Long = System.currentTimeMillis() / 1000

    private fun encode(grant: LockedGrant): String =
        listOf(grant.trackId, grant.kind, grant.keyId, grant.name, grant.codec, grant.plainLength, grant.keyHex, grant.expiresAt).joinToString("|")

    private fun decode(text: String): LockedGrant? {
        val parts = text.split("|")
        if (parts.size != 8) return null
        return runCatching {
            LockedGrant(parts[0].toLong(), parts[1].toInt(), parts[2].toLong(), parts[3], parts[4], parts[5].toLong(), parts[6], parts[7].toLong())
        }.getOrNull()
    }

    private fun stored(trackId: Long, kind: LockedKind): LockedGrant? {
        val key = slot(trackId, kind)
        memory[key]?.let { return it }
        val found = SecureStore.get(key)?.let(::decode) ?: return null
        memory[key] = found
        return found
    }

    fun lookup(trackId: Long, kind: LockedKind, offline: Boolean): LockedGrant? {
        val found = stored(trackId, kind) ?: return null
        return if (found.expiresAt > now() + (if (offline) OFFLINE_SPARE_SECONDS else SPARE_SECONDS)) found else null
    }

    fun playable(trackId: Long, kind: LockedKind): LockedGrant? {
        val found = stored(trackId, kind) ?: return null
        return if (found.expiresAt > now()) found else null
    }

    fun remember(grant: LockedGrant) {
        val key = slot(grant.trackId, LockedKind.of(grant.kind))
        memory[key] = grant
        SecureStore.put(key, encode(grant))
    }

    fun forget(trackId: Long) {
        for (kind in LockedKind.values()) {
            val key = slot(trackId, kind)
            memory.remove(key)
            SecureStore.remove(key)
        }
    }

    fun header(name: String): LockedHeader? = headers[name]

    fun keepHeader(name: String, header: LockedHeader) {
        headers[name] = header
    }

    suspend fun grant(siteId: String, kind: LockedKind, offline: Boolean): LockedGrant {
        val trackId = siteId.toLongOrNull() ?: throw LockedException("bad track id")
        lookup(trackId, kind, offline)?.let { return it }
        val exchange = LicenseExchange()
        val granted = exchange.open(SiteApi.licenses(exchange, listOf(trackId to kind), offline))
        granted.forEach(::remember)
        return granted.firstOrNull { it.kind == kind.value } ?: throw LockedException("no license for this track")
    }

    suspend fun grantForPlayback(siteId: String, kind: LockedKind): LockedGrant {
        val trackId = siteId.toLongOrNull() ?: throw LockedException("bad track id")
        playable(trackId, kind)?.let { return it }
        return grant(siteId, kind, false)
    }
}
