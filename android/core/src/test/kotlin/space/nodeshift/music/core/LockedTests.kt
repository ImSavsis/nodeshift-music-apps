package space.nodeshift.music.core

import java.math.BigInteger
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPair
import java.security.MessageDigest
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPrivateKeySpec
import java.util.Base64
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long

class LockedTests {
    private val sample = TestData.json("nlac.json").jsonObject
    private val locked: ByteArray = Base64.getDecoder().decode(sample["locked_b64"]!!.jsonPrimitive.content)
    private val key: ByteArray = hex(sample["key_hex"]!!.jsonPrimitive.content)

    private fun hex(text: String): ByteArray = ByteArray(text.length / 2) { text.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    private fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun read(data: ByteArray, withKey: ByteArray, header: LockedHeader, start: Long, end: Long): ByteArray {
        val span = header.span(start, end)
        val blob = data.copyOfRange(span.offset.toInt(), (span.offset + span.length).toInt())
        return LockedCrypto.decrypt(withKey, header, span, blob, start, end)
    }

    @Test
    fun headerMatchesTheSharedVector() {
        val header = LockedHeader.parse(locked)
        assertEquals(sample["codec"]!!.jsonPrimitive.content, header.codec)
        assertEquals(sample["plain_length"]!!.jsonPrimitive.long, header.plainLength)
        assertEquals(sample["chunk_size"]!!.jsonPrimitive.long, header.chunkSize)
        assertEquals(sample["key_id"]!!.jsonPrimitive.long, header.keyId)
        assertEquals(sample["kind"]!!.jsonPrimitive.long.toInt(), header.kind)
        assertEquals("audio/flac", header.mime)
    }

    @Test
    fun rangesDecryptToTheExpectedBytes() {
        val header = LockedHeader.parse(locked)
        val ranges = sample["ranges"]!!.jsonArray
        val hashes = sample["range_sha256"]!!.jsonArray
        for ((range, expected) in ranges.zip(hashes)) {
            val start = range.jsonArray[0].jsonPrimitive.long
            val end = range.jsonArray[1].jsonPrimitive.long
            val plain = read(locked, key, header, start, end)
            assertEquals(end - start + 1, plain.size.toLong())
            assertEquals(expected.jsonPrimitive.content, digest(plain))
        }
        assertEquals(sample["plain_sha256"]!!.jsonPrimitive.content, digest(read(locked, key, header, 0, header.plainLength - 1)))
    }

    @Test
    fun aWrongKeyOrFlippedByteIsRejected() {
        val header = LockedHeader.parse(locked)
        assertFailsWith<LockedException> { read(locked, ByteArray(32) { 9 }, header, 0, 99) }
        val tampered = locked.copyOf()
        tampered[LockedHeader.SIZE + 10] = (tampered[LockedHeader.SIZE + 10].toInt() xor 1).toByte()
        assertFailsWith<LockedException> { read(tampered, key, header, 0, 99) }
    }

    @Test
    fun foreignFilesAreNotLockedAudio() {
        assertFailsWith<LockedException> { LockedHeader.parse("fLaC".toByteArray()) }
        assertFailsWith<LockedException> { LockedHeader.parse(ByteArray(64)) }
    }

    private fun exchange(sampleJson: kotlinx.serialization.json.JsonObject): LicenseExchange {
        val curve = AlgorithmParameters.getInstance("EC").also { it.init(ECGenParameterSpec("secp256r1")) }.getParameterSpec(ECParameterSpec::class.java)
        val secret = hex(sampleJson["client_private_hex"]!!.jsonPrimitive.content)
        val private = KeyFactory.getInstance("EC").generatePrivate(ECPrivateKeySpec(BigInteger(1, secret), curve))
        val public = LicenseExchange.decodePoint(Base64.getDecoder().decode(sampleJson["client_pub_b64"]!!.jsonPrimitive.content))
        return LicenseExchange(KeyPair(public, private))
    }

    private fun wire(sampleJson: kotlinx.serialization.json.JsonObject, trackId: Long): LicenseWire = LicenseWire(
        sampleJson["server_pub_b64"]!!.jsonPrimitive.content,
        sampleJson["expires_at"]!!.jsonPrimitive.long,
        listOf(
            LicenseWireItem(
                trackId,
                "lossy",
                sampleJson["key_id"]!!.jsonPrimitive.long,
                "x.np3",
                "mp3",
                1,
                sampleJson["nonce_b64"]!!.jsonPrimitive.content,
                sampleJson["wrapped_b64"]!!.jsonPrimitive.content,
            ),
        ),
    )

    @Test
    fun licenseVectorUnwrapsToTheContentKey() {
        val vector = TestData.json("license.json").jsonObject
        val exchange = exchange(vector)
        assertEquals(vector["client_pub_b64"]!!.jsonPrimitive.content, exchange.publicBase64)
        val grants = exchange.open(wire(vector, vector["track_id"]!!.jsonPrimitive.long))
        assertEquals(vector["content_key_hex"]!!.jsonPrimitive.content, grants.first().keyHex)
        assertEquals(vector["kind"]!!.jsonPrimitive.long.toInt(), grants.first().kind)
    }

    @Test
    fun aLicenseForAnotherTrackDoesNotOpen() {
        val vector = TestData.json("license.json").jsonObject
        assertFailsWith<LockedException> { exchange(vector).open(wire(vector, vector["track_id"]!!.jsonPrimitive.long + 1)) }
    }

    @Test
    fun aFreshExchangeHasAnUncompressedKey() {
        val bytes = LicenseExchange().publicBytes
        assertEquals(65, bytes.size)
        assertEquals(4, bytes[0].toInt())
    }

    @Test
    fun byteRanges() {
        assertEquals(99L, ByteRange.parse("bytes=0-99", 1000)?.second)
        assertEquals(900L, ByteRange.parse("bytes=900-", 1000)?.first)
        assertEquals(999L, ByteRange.parse("bytes=900-", 1000)?.second)
        assertEquals(900L, ByteRange.parse("bytes=-100", 1000)?.first)
        assertEquals(999L, ByteRange.parse("bytes=0-5000", 1000)?.second)
        assertNull(ByteRange.parse("bytes=2000-", 1000))
        assertNull(ByteRange.parse("items=0-9", 1000))
        assertNull(ByteRange.parse(null, 1000))
        assertTrue(ByteRange.parse("bytes=5-1", 1000) == null)
    }
}
