package space.nodeshift.music.core

import kotlin.math.max
import kotlin.math.min

enum class PresenceOutcome {
    Delivered,
    Rejected,
    Retry,
}

enum class PresenceStep {
    Wait,
    Send,
    Retire,
}

data class PresenceFacts(
    val hasTrack: Boolean = true,
    val enabled: Boolean = true,
    val hasSession: Boolean = true,
    val playing: Boolean = false,
    val published: Boolean = false,
    val stalledForMs: Long = -1L,
    val failures: Int = 0,
    val sinceSendMs: Long = 0L,
    val sinceAttemptMs: Long = 0L,
    val changed: Boolean = false,
    val newerThanAttempt: Boolean = false,
) {
    val active: Boolean
        get() = hasTrack && enabled && hasSession

    val settling: Boolean
        get() = stalledForMs >= 0L && stalledForMs < PresencePolicy.SETTLE_MS
}

object PresenceArt {
    const val MAX_BYTES = 600_000
    const val DECODE_PIXELS = 4_000_000L

    fun sampleSize(width: Int, height: Int, side: Int): Int {
        var sample = 1
        while (min(width, height) / (sample * 2) >= side || (width / sample).toLong() * (height / sample) > DECODE_PIXELS) {
            sample *= 2
        }
        return sample
    }
}

class CooldownGate(private val windowMillis: Long) {
    private val until = HashMap<String, Long>()

    fun ready(key: String, now: Long): Boolean {
        val limit = until[key] ?: return true
        return now >= limit
    }

    fun start(key: String, now: Long) {
        until[key] = now + windowMillis
    }
}

object PresencePolicy {
    const val BEAT_MS = 15_000L
    const val IDLE_MS = 60_000L
    const val MIN_GAP_MS = 1_500L
    const val MIN_WAIT_MS = 200L
    const val SETTLE_MS = 2_000L
    const val ART_COOLDOWN_MS = 300_000L

    private val backoff = longArrayOf(2_000L, 4_000L, 8_000L, 16_000L, 30_000L)

    fun backoffMillis(failures: Int): Long {
        if (failures <= 0) return 0L
        return backoff[min(failures, backoff.size) - 1]
    }

    fun outcomeFor(status: Int): PresenceOutcome = when {
        status in 200..299 -> PresenceOutcome.Delivered
        status in 400..499 && status != 401 && status != 408 && status != 429 -> PresenceOutcome.Rejected
        else -> PresenceOutcome.Retry
    }

    fun gapMillis(sinceAttemptMs: Long): Long = max(0L, MIN_GAP_MS - sinceAttemptMs)

    private fun retryDue(facts: PresenceFacts): Boolean =
        facts.failures == 0 || facts.sinceAttemptMs >= backoffMillis(facts.failures)

    fun decide(facts: PresenceFacts): PresenceStep {
        if (!facts.active) {
            if (!facts.published) return PresenceStep.Wait
            return if (retryDue(facts)) PresenceStep.Retire else PresenceStep.Wait
        }
        if (facts.settling) return PresenceStep.Wait
        if (facts.failures > 0) {
            return if (facts.newerThanAttempt || retryDue(facts)) PresenceStep.Send else PresenceStep.Wait
        }
        if (facts.changed) return PresenceStep.Send
        if (facts.playing && facts.sinceSendMs >= BEAT_MS) return PresenceStep.Send
        return PresenceStep.Wait
    }

    fun waitMillis(facts: PresenceFacts): Long {
        if (!facts.active && !facts.published) return IDLE_MS
        var wait = when {
            facts.failures > 0 -> backoffMillis(facts.failures) - facts.sinceAttemptMs
            facts.active && facts.playing -> BEAT_MS - facts.sinceSendMs
            else -> IDLE_MS
        }
        if (facts.active && facts.settling) wait = min(wait, SETTLE_MS - facts.stalledForMs)
        return max(MIN_WAIT_MS, wait)
    }
}
