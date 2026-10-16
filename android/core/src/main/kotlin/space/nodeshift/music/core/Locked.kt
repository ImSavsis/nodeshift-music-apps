package space.nodeshift.music.core

import java.io.ByteArrayOutputStream
import java.math.BigInteger
import java.security.AlgorithmParameters
import java.security.GeneralSecurityException
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PublicKey
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPoint
import java.security.spec.ECPublicKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class LockedException(message: String) : Exception(message)

enum class LockedKind(val value: Int, val label: String) {
    LOSSLESS(1, "lossless"),
    LOSSY(2, "lossy"),
    ;

    companion object {
        fun of(value: Int): LockedKind = if (value == 1) LOSSLESS else LOSSY
    }
}

class LockedSpan(val firstChunk: Long, val lastChunk: Long, val offset: Long, val length: Long)

class LockedHeader private constructor(
    val kind: Int,
    val codec: String,
    val keyId: Long,
    val chunkSize: Long,
    val plainLength: Long,
    val noncePrefix: ByteArray,
    val raw: ByteArray,
) {
    val stride: Long
        get() = chunkSize + TAG_SIZE

    val chunkCount: Long
        get() = (plainLength + chunkSize - 1) / chunkSize

    val mime: String
        get() = when (codec) {
            "flac" -> "audio/flac"
            "aac", "m4a", "alac" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            "ogg", "opus" -> "audio/ogg"
            "aiff", "aif" -> "audio/aiff"
            else -> "application/octet-stream"
        }

    fun span(start: Long, end: Long): LockedSpan {
        val first = start / chunkSize
        val last = end / chunkSize
        val from = SIZE + first * stride
        val total = SIZE + plainLength + chunkCount * TAG_SIZE
        val until = minOf(SIZE + (last + 1) * stride, total)
        return LockedSpan(first, last, from, until - from)
    }

    fun nonce(index: Long): ByteArray = noncePrefix + unsignedInt(index)

    fun associatedData(index: Long): ByteArray = raw + unsignedInt(index)

    companion object {
        const val SIZE = 64
        const val TAG_SIZE = 16
        private val MAGIC = byteArrayOf('N'.code.toByte(), 'S'.code.toByte(), 'M'.code.toByte(), 'L'.code.toByte())

        fun unsignedInt(value: Long): ByteArray =
            byteArrayOf((value shr 24).toByte(), (value shr 16).toByte(), (value shr 8).toByte(), value.toByte())

        fun unsignedLong(value: Long): ByteArray = ByteArray(8) { (value shr ((7 - it) * 8)).toByte() }

        private fun readInt(data: ByteArray, at: Int): Long =
            (0 until 4).fold(0L) { total, index -> (total shl 8) or (data[at + index].toLong() and 0xff) }

        private fun readLong(data: ByteArray, at: Int): Long =
            (0 until 8).fold(0L) { total, index -> (total shl 8) or (data[at + index].toLong() and 0xff) }

        fun parse(input: ByteArray): LockedHeader {
            if (input.size < SIZE) throw LockedException("header is too short")
            if (!input.copyOfRange(0, 4).contentEquals(MAGIC) || input[4].toInt() != 1 || input[5].toInt() !in 1..2) {
                throw LockedException("not a locked audio file")
            }
            val chunk = readInt(input, 20)
            if (chunk == 0L) throw LockedException("bad chunk size")
            val codecBytes = input.copyOfRange(8, 16).takeWhile { it.toInt() != 0 }.toByteArray()
            return LockedHeader(
                kind = input[5].toInt(),
                codec = String(codecBytes, Charsets.US_ASCII),
                keyId = readInt(input, 16),
                chunkSize = chunk,
                plainLength = readLong(input, 24),
                noncePrefix = input.copyOfRange(32, 40),
                raw = input.copyOfRange(0, SIZE),
            )
        }
    }
}

object LockedCrypto {
    fun decrypt(key: ByteArray, header: LockedHeader, span: LockedSpan, blob: ByteArray, start: Long, end: Long): ByteArray {
        val keySpec = SecretKeySpec(key, "AES")
        val stride = header.stride.toInt()
        val plain = ByteArrayOutputStream()
        var position = 0
        var index = span.firstChunk
        while (position < blob.size) {
            val length = minOf(stride, blob.size - position)
            if (length <= LockedHeader.TAG_SIZE) throw LockedException("short data")
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, keySpec, GCMParameterSpec(128, header.nonce(index)))
            cipher.updateAAD(header.associatedData(index))
            try {
                plain.write(cipher.doFinal(blob, position, length))
            } catch (error: GeneralSecurityException) {
                throw LockedException("chunk failed authentication")
            }
            position += length
            index += 1
        }
        val bytes = plain.toByteArray()
        val skip = (start - span.firstChunk * header.chunkSize).toInt()
        val take = (end - start + 1).toInt()
        if (bytes.size < skip + take) throw LockedException("short data")
        return bytes.copyOfRange(skip, skip + take)
    }
}

object ByteRange {
    fun parse(header: String?, total: Long): Pair<Long, Long>? {
        if (header == null || total <= 0) return null
        val text = header.trim()
        if (!text.startsWith("bytes=")) return null
        val parts = text.removePrefix("bytes=").split("-", limit = 2)
        if (parts.size != 2) return null
        if (parts[0].isEmpty()) {
            val suffix = parts[1].toLongOrNull() ?: return null
            return Pair(maxOf(0L, total - suffix), total - 1)
        }
        val start = parts[0].toLongOrNull() ?: return null
        val end = if (parts[1].isEmpty()) total - 1 else minOf(parts[1].toLongOrNull() ?: return null, total - 1)
        return if (start <= end && start < total) Pair(start, end) else null
    }
}

data class LockedGrant(
    val trackId: Long,
    val kind: Int,
    val keyId: Long,
    val name: String,
    val codec: String,
    val plainLength: Long,
    val keyHex: String,
    val expiresAt: Long,
) {
    fun key(): ByteArray {
        if (keyHex.length != 64) throw LockedException("bad key")
        return ByteArray(32) { keyHex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    }
}

class LicenseWireItem(
    val trackId: Long,
    val kind: String,
    val keyId: Long,
    val name: String,
    val codec: String,
    val plainLength: Long,
    val nonce: String,
    val wrapped: String,
)

class LicenseWire(val serverPub: String, val expiresAt: Long, val items: List<LicenseWireItem>)

class LicenseExchange(private val pair: KeyPair) {
    constructor() : this(generate())

    val publicBytes: ByteArray = uncompressed(pair.public as ECPublicKey)

    val publicBase64: String
        get() = Base64.getEncoder().encodeToString(publicBytes)

    fun open(license: LicenseWire): List<LockedGrant> {
        val serverBytes = Base64.getDecoder().decode(license.serverPub)
        val agreement = try {
            KeyAgreement.getInstance("ECDH").also {
                it.init(pair.private)
                it.doPhase(decodePoint(serverBytes), true)
            }.generateSecret()
        } catch (error: GeneralSecurityException) {
            throw LockedException("bad server key")
        }
        val wrapKey = hkdf(agreement, publicBytes + serverBytes, "NSM-LICENSE-1".toByteArray(Charsets.US_ASCII))
        val grants = ArrayList<LockedGrant>()
        for (item in license.items) {
            val kind = if (item.kind == "lossless") LockedKind.LOSSLESS else LockedKind.LOSSY
            val context = "NSM-L1".toByteArray(Charsets.US_ASCII) +
                LockedHeader.unsignedInt(item.trackId) + byteArrayOf(kind.value.toByte()) +
                LockedHeader.unsignedInt(item.keyId) + LockedHeader.unsignedLong(license.expiresAt)
            val nonce = Base64.getDecoder().decode(item.nonce)
            val wrapped = Base64.getDecoder().decode(item.wrapped)
            if (nonce.size != 12) throw LockedException("bad nonce")
            val content = try {
                Cipher.getInstance("AES/GCM/NoPadding").also {
                    it.init(Cipher.DECRYPT_MODE, SecretKeySpec(wrapKey, "AES"), GCMParameterSpec(128, nonce))
                    it.updateAAD(context)
                }.doFinal(wrapped)
            } catch (error: GeneralSecurityException) {
                throw LockedException("license failed authentication")
            }
            grants.add(
                LockedGrant(
                    trackId = item.trackId,
                    kind = kind.value,
                    keyId = item.keyId,
                    name = item.name,
                    codec = item.codec,
                    plainLength = item.plainLength,
                    keyHex = content.joinToString("") { "%02x".format(it) },
                    expiresAt = license.expiresAt,
                ),
            )
        }
        return grants
    }

    companion object {
        private val curve: ECParameterSpec by lazy {
            AlgorithmParameters.getInstance("EC").also { it.init(ECGenParameterSpec("secp256r1")) }.getParameterSpec(ECParameterSpec::class.java)
        }

        private fun generate(): KeyPair =
            KeyPairGenerator.getInstance("EC").also { it.initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()

        private fun fixed(value: BigInteger): ByteArray {
            val raw = value.toByteArray().dropWhile { it.toInt() == 0 }.toByteArray()
            return ByteArray(32 - raw.size) + raw
        }

        fun uncompressed(key: ECPublicKey): ByteArray = byteArrayOf(4) + fixed(key.w.affineX) + fixed(key.w.affineY)

        fun decodePoint(bytes: ByteArray): PublicKey {
            if (bytes.size != 65 || bytes[0].toInt() != 4) throw LockedException("bad server key")
            val point = ECPoint(BigInteger(1, bytes.copyOfRange(1, 33)), BigInteger(1, bytes.copyOfRange(33, 65)))
            return KeyFactory.getInstance("EC").generatePublic(ECPublicKeySpec(point, curve))
        }

        fun hkdf(secret: ByteArray, salt: ByteArray, info: ByteArray): ByteArray {
            val extract = Mac.getInstance("HmacSHA256").also { it.init(SecretKeySpec(salt, "HmacSHA256")) }.doFinal(secret)
            return Mac.getInstance("HmacSHA256").also { it.init(SecretKeySpec(extract, "HmacSHA256")) }.doFinal(info + byteArrayOf(1))
        }
    }
}
