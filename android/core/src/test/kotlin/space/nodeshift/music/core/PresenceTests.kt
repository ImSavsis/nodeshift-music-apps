package space.nodeshift.music.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PresenceBackoffTests {
    @Test
    fun scheduleIsTwoFourEightSixteenThirty() {
        val got = (1..5).map { PresencePolicy.backoffMillis(it) }
        assertEquals(listOf(2_000L, 4_000L, 8_000L, 16_000L, 30_000L), got)
    }

    @Test
    fun scheduleStaysAtThirtySeconds() {
        assertEquals(30_000L, PresencePolicy.backoffMillis(6))
        assertEquals(30_000L, PresencePolicy.backoffMillis(40))
        assertEquals(30_000L, PresencePolicy.backoffMillis(Int.MAX_VALUE))
    }

    @Test
    fun noFailuresMeansNoDelay() {
        assertEquals(0L, PresencePolicy.backoffMillis(0))
        assertEquals(0L, PresencePolicy.backoffMillis(-3))
    }
}

class PresenceOutcomeTests {
    @Test
    fun successIsDelivered() {
        for (code in listOf(200, 201, 204, 299)) {
            assertEquals(PresenceOutcome.Delivered, PresencePolicy.outcomeFor(code), "$code")
        }
    }

    @Test
    fun permanentClientErrorsAreRejected() {
        for (code in listOf(400, 403, 404, 413, 415, 422, 499)) {
            assertEquals(PresenceOutcome.Rejected, PresencePolicy.outcomeFor(code), "$code")
        }
    }

    @Test
    fun transientFailuresAreRetried() {
        for (code in listOf(0, 100, 301, 401, 408, 429, 500, 502, 503, 504, 599)) {
            assertEquals(PresenceOutcome.Retry, PresencePolicy.outcomeFor(code), "$code")
        }
    }
}

class PresenceDecisionTests {
    @Test
    fun nothingToDoWaits() {
        assertEquals(PresenceStep.Wait, PresencePolicy.decide(PresenceFacts(hasTrack = false)))
        assertEquals(PresenceStep.Wait, PresencePolicy.decide(PresenceFacts(enabled = false)))
        assertEquals(PresenceStep.Wait, PresencePolicy.decide(PresenceFacts(hasSession = false)))
    }

    @Test
    fun publishedStateIsRetiredWhenNothingToShow() {
        assertEquals(PresenceStep.Retire, PresencePolicy.decide(PresenceFacts(hasTrack = false, published = true)))
        assertEquals(PresenceStep.Retire, PresencePolicy.decide(PresenceFacts(enabled = false, published = true)))
        assertEquals(PresenceStep.Retire, PresencePolicy.decide(PresenceFacts(hasSession = false, published = true)))
    }

    @Test
    fun failedStopWaitsForBackoff() {
        val early = PresenceFacts(hasTrack = false, published = true, failures = 2, sinceAttemptMs = 3_999L)
        val due = early.copy(sinceAttemptMs = 4_000L)
        assertEquals(PresenceStep.Wait, PresencePolicy.decide(early))
        assertEquals(PresenceStep.Retire, PresencePolicy.decide(due))
    }

    @Test
    fun changedStateIsSent() {
        assertEquals(PresenceStep.Send, PresencePolicy.decide(PresenceFacts(changed = true)))
        assertEquals(PresenceStep.Send, PresencePolicy.decide(PresenceFacts(changed = true, playing = true)))
    }

    @Test
    fun unchangedPausedStateIsNeverResent() {
        val idle = PresenceFacts(playing = false, sinceSendMs = 3_600_000L)
        assertEquals(PresenceStep.Wait, PresencePolicy.decide(idle))
    }

    @Test
    fun playingStateBeatsEveryFifteenSeconds() {
        val early = PresenceFacts(playing = true, sinceSendMs = PresencePolicy.BEAT_MS - 1)
        val due = early.copy(sinceSendMs = PresencePolicy.BEAT_MS)
        assertEquals(PresenceStep.Wait, PresencePolicy.decide(early))
        assertEquals(PresenceStep.Send, PresencePolicy.decide(due))
    }

    @Test
    fun failedSendRetriesOnBackoffSchedule() {
        for (failures in 1..8) {
            val wait = PresencePolicy.backoffMillis(failures)
            val early = PresenceFacts(playing = true, failures = failures, sinceAttemptMs = wait - 1)
            val due = early.copy(sinceAttemptMs = wait)
            assertEquals(PresenceStep.Wait, PresencePolicy.decide(early), "early $failures")
            assertEquals(PresenceStep.Send, PresencePolicy.decide(due), "due $failures")
        }
    }

    @Test
    fun newerStateSupersedesPendingRetry() {
        val stale = PresenceFacts(failures = 4, sinceAttemptMs = 10L, changed = true)
        assertEquals(PresenceStep.Wait, PresencePolicy.decide(stale))
        assertEquals(PresenceStep.Send, PresencePolicy.decide(stale.copy(newerThanAttempt = true)))
    }

    @Test
    fun heartbeatIsHeldBackWhileRetrying() {
        val facts = PresenceFacts(playing = true, failures = 1, sinceSendMs = 600_000L, sinceAttemptMs = 100L)
        assertEquals(PresenceStep.Wait, PresencePolicy.decide(facts))
    }

    @Test
    fun shortBufferingIsNotReportedAsPause() {
        val buffering = PresenceFacts(changed = true, stalledForMs = 0L)
        assertTrue(buffering.settling)
        assertEquals(PresenceStep.Wait, PresencePolicy.decide(buffering))
        assertEquals(PresenceStep.Wait, PresencePolicy.decide(buffering.copy(stalledForMs = PresencePolicy.SETTLE_MS - 1)))
    }

    @Test
    fun longStallIsReportedAsPause() {
        val stalled = PresenceFacts(changed = true, stalledForMs = PresencePolicy.SETTLE_MS)
        assertFalse(stalled.settling)
        assertEquals(PresenceStep.Send, PresencePolicy.decide(stalled))
    }

    @Test
    fun stopIsNotDelayedByBuffering() {
        val facts = PresenceFacts(hasTrack = false, published = true, stalledForMs = 0L)
        assertEquals(PresenceStep.Retire, PresencePolicy.decide(facts))
    }

    @Test
    fun gapIsTheRemainderOfTheMinimumSpacing() {
        assertEquals(PresencePolicy.MIN_GAP_MS - 600L, PresencePolicy.gapMillis(600L))
        assertEquals(PresencePolicy.MIN_GAP_MS, PresencePolicy.gapMillis(0L))
        assertEquals(0L, PresencePolicy.gapMillis(PresencePolicy.MIN_GAP_MS))
        assertEquals(0L, PresencePolicy.gapMillis(PresencePolicy.MIN_GAP_MS + 5_000L))
    }

    @Test
    fun burstOfChangesCollapsesIntoTwoRequests() {
        val changes = listOf(0L, 100L, 250L, 600L, 1_100L)
        val sends = ArrayList<Long>()
        var clock = 0L
        var settled = 0
        var lastAttempt = -100_000L
        fun seen(): Int = changes.count { it <= clock }
        while (settled < changes.size) {
            if (seen() == settled) clock = changes[settled]
            clock += PresencePolicy.gapMillis(clock - lastAttempt)
            if (PresencePolicy.decide(PresenceFacts(changed = seen() != settled)) == PresenceStep.Send) {
                sends.add(clock)
                settled = seen()
                lastAttempt = clock
            }
        }
        assertEquals(listOf(0L, PresencePolicy.MIN_GAP_MS), sends)
    }

    @Test
    fun singleChangeAfterLongIdleIsSentImmediately() {
        assertEquals(0L, PresencePolicy.gapMillis(3_600_000L))
    }
}

class PresenceWaitTests {
    @Test
    fun idleWaitsAMinute() {
        assertEquals(PresencePolicy.IDLE_MS, PresencePolicy.waitMillis(PresenceFacts(hasTrack = false)))
        assertEquals(PresencePolicy.IDLE_MS, PresencePolicy.waitMillis(PresenceFacts(playing = false)))
    }

    @Test
    fun playingWaitsForNextBeat() {
        val facts = PresenceFacts(playing = true, sinceSendMs = 4_000L)
        assertEquals(PresencePolicy.BEAT_MS - 4_000L, PresencePolicy.waitMillis(facts))
    }

    @Test
    fun overdueBeatNeverSpins() {
        val facts = PresenceFacts(playing = true, sinceSendMs = 90_000L)
        assertEquals(PresencePolicy.MIN_WAIT_MS, PresencePolicy.waitMillis(facts))
    }

    @Test
    fun retryWaitsRemainingBackoff() {
        val facts = PresenceFacts(playing = true, failures = 3, sinceAttemptMs = 1_000L, sinceSendMs = 500_000L)
        assertEquals(7_000L, PresencePolicy.waitMillis(facts))
    }

    @Test
    fun retryWithNothingPendingDoesNotSpin() {
        val facts = PresenceFacts(hasTrack = false, published = false, failures = 3, sinceAttemptMs = 900_000L)
        assertEquals(PresencePolicy.IDLE_MS, PresencePolicy.waitMillis(facts))
    }

    @Test
    fun settlingWakesWhenWindowEnds() {
        val facts = PresenceFacts(stalledForMs = 500L)
        assertEquals(PresencePolicy.SETTLE_MS - 500L, PresencePolicy.waitMillis(facts))
    }
}

class PresenceArtTests {
    @Test
    fun smallCoverIsDecodedAsIs() {
        assertEquals(1, PresenceArt.sampleSize(500, 500, 600))
        assertEquals(1, PresenceArt.sampleSize(1100, 1100, 600))
    }

    @Test
    fun largeCoverIsHalvedUntilShortSideFitsTheTarget() {
        assertEquals(2, PresenceArt.sampleSize(1400, 1400, 600))
        assertEquals(4, PresenceArt.sampleSize(3000, 3000, 600))
        assertEquals(8, PresenceArt.sampleSize(3000, 3000, 360))
    }

    @Test
    fun hugePixelCountIsCappedEvenWhenShortSideIsSmall() {
        val sample = PresenceArt.sampleSize(800, 20_000, 600)
        assertEquals(2, sample)
        assertTrue((800 / sample).toLong() * (20_000 / sample) <= PresenceArt.DECODE_PIXELS)
    }

    @Test
    fun degenerateSizesTerminate() {
        assertTrue(PresenceArt.sampleSize(1, 100_000, 600) >= 1)
        assertTrue(PresenceArt.sampleSize(100_000, 100_000, 600) >= 1)
        assertEquals(1, PresenceArt.sampleSize(0, 0, 600))
    }
}

class CooldownGateTests {
    @Test
    fun unknownKeyIsReady() {
        assertTrue(CooldownGate(PresencePolicy.ART_COOLDOWN_MS).ready("cover.jpg", 0L))
    }

    @Test
    fun failedCoverWaitsFiveMinutes() {
        val gate = CooldownGate(PresencePolicy.ART_COOLDOWN_MS)
        gate.start("cover.jpg", 1_000L)
        assertFalse(gate.ready("cover.jpg", 1_000L))
        assertFalse(gate.ready("cover.jpg", 1_000L + 299_999L))
        assertTrue(gate.ready("cover.jpg", 1_000L + 300_000L))
    }

    @Test
    fun coversAreIndependent() {
        val gate = CooldownGate(PresencePolicy.ART_COOLDOWN_MS)
        gate.start("a.jpg", 0L)
        assertFalse(gate.ready("a.jpg", 10L))
        assertTrue(gate.ready("b.jpg", 10L))
    }
}
