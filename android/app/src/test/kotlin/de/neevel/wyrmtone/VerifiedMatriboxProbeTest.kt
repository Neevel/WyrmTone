package de.neevel.wyrmtone

import org.junit.Assert.*
import org.junit.Test

class VerifiedMatriboxProbeTest {
    private val eligible = ProbeEligibility(true, "usb/box", 0x84ef, 0x0054, true, true, true, true, true, false)
    private class Port : VerifiedProbePort {
        var sends = 0
        var closes = 0
        var fail = false
        override fun sendVerifiedGain41() { ++sends; if (fail) error("send failure") }
        override fun close() { ++closes }
    }
    private fun rejects(block: () -> Unit) {
        try { block(); fail("Must reject") } catch (_: IllegalArgumentException) { }
    }
    @Test fun exactReferenceAcceptedAndCopiesCannotMutateConstant() {
        VerifiedGain41Reference.validate(VerifiedGain41Reference.bytes())
        val copy = VerifiedGain41Reference.bytes(); copy[1] = 0
        assertEquals(0x21, VerifiedGain41Reference.bytes()[1].toInt())
        rejects { VerifiedGain41Reference.validate(copy) }
    }
    @Test fun wrongLengthRejected() = rejects { VerifiedGain41Reference.validate(ByteArray(33)) }
    @Test fun wrongHeaderRejected() = corrupted(4)
    @Test fun wrongAlgorithmRejected() = corrupted(14)
    @Test fun wrongParameterRejected() = corrupted(22)
    @Test fun wrongValueRejected() = corrupted(30)
    @Test fun wrongStartRejected() = corrupted(0)
    @Test fun wrongEndRejected() = corrupted(33)
    private fun corrupted(index: Int) {
        val bytes = VerifiedGain41Reference.bytes(); bytes[index] = (bytes[index].toInt() xor 1).toByte()
        rejects { VerifiedGain41Reference.validate(bytes) }
    }
    private fun blocked(state: ProbeEligibility) {
        var opens = 0
        val probe = VerifiedMatriboxProbe({ state }, { ++opens; Port() })
        assertEquals(false, probe.sendVerifiedSol100OdGain41Probe()["success"])
        assertEquals(0, opens)
    }
    @Test fun flagOffNeverOpens() = blocked(eligible.copy(enabled = false))
    @Test fun wrongVidPidNeverOpens() {
        blocked(eligible.copy(vendor = 0x054c)); blocked(eligible.copy(product = 0x5703))
    }
    @Test fun ambiguousOrUnmappedNeverOpens() {
        blocked(eligible.copy(uniqueUsb = false)); blocked(eligible.copy(uniqueMidi = false))
        blocked(eligible.copy(directlyMapped = false))
    }
    @Test fun closedMissingPortAndMonitorNeverOpen() {
        blocked(eligible.copy(deviceOpen = false)); blocked(eligible.copy(expectedInput = false))
        blocked(eligible.copy(monitoring = true)); blocked(eligible.copy(connection = null))
    }
    @Test fun successExactlyOneCallClosesAndRejectsSecond() {
        val port = Port(); var opens = 0
        val probe = VerifiedMatriboxProbe({ eligible }, { ++opens; port })
        val result = probe.sendVerifiedSol100OdGain41Probe()
        assertEquals(true, result["success"]); assertEquals(1, result["sendCalls"])
        assertEquals(1, port.sends); assertEquals(1, port.closes)
        assertEquals(false, probe.sendVerifiedSol100OdGain41Probe()["success"])
        assertEquals(1, opens); assertEquals(1, port.sends)
        val log = (probe.status()["logs"] as List<*>).joinToString()
        listOf("SEND_ATTEMPT", "SEND_SUCCESS", "PORT_CLOSED", VerifiedGain41Reference.SHA256).forEach { assertTrue(log.contains(it)) }
    }
    @Test fun portOpenFailureZeroCallsAndNoRetry() {
        var opens = 0
        val probe = VerifiedMatriboxProbe({ eligible }, { ++opens; error("open failed") })
        assertEquals(0, probe.sendVerifiedSol100OdGain41Probe()["sendCalls"])
        assertEquals(0, probe.sendVerifiedSol100OdGain41Probe()["sendCalls"])
        assertEquals(1, opens)
    }
    @Test fun sendFailureClosesWithoutRetry() {
        val port = Port().also { it.fail = true }
        val probe = VerifiedMatriboxProbe({ eligible }, { port })
        assertEquals(false, probe.sendVerifiedSol100OdGain41Probe()["success"])
        assertEquals(1, port.sends); assertEquals(1, port.closes)
        probe.sendVerifiedSol100OdGain41Probe(); assertEquals(1, port.sends)
    }
    @Test fun parallelInvocationRejectedBeforeOpening() {
        val port = Port(); lateinit var probe: VerifiedMatriboxProbe
        probe = VerifiedMatriboxProbe({ eligible }, {
            try { probe.sendVerifiedSol100OdGain41Probe(); fail("Parallel call must reject") }
            catch (_: IllegalStateException) { }
            port
        })
        probe.sendVerifiedSol100OdGain41Probe(); assertEquals(1, port.sends)
    }
    @Test fun detachDuringOpenClosesWithoutSending() {
        val port = Port(); lateinit var probe: VerifiedMatriboxProbe
        probe = VerifiedMatriboxProbe({ eligible }, { probe.detached("usb/box"); port })
        assertEquals(false, probe.sendVerifiedSol100OdGain41Probe()["success"])
        assertEquals(0, port.sends); assertEquals(1, port.closes)
    }
    @Test fun pauseOrRemovalDuringOpenClosesWithoutSending() {
        val port = Port(); lateinit var probe: VerifiedMatriboxProbe
        probe = VerifiedMatriboxProbe({ eligible }, { probe.cancel(); port })
        probe.sendVerifiedSol100OdGain41Probe()
        assertEquals(0, port.sends); assertEquals(1, port.closes)
    }
    @Test fun eligibilityRecheckedAfterOpening() {
        var current = eligible
        val port = Port()
        val probe = VerifiedMatriboxProbe({ current }, { current = eligible.copy(vendor = 0); port })
        probe.sendVerifiedSol100OdGain41Probe()
        assertEquals(0, port.sends); assertEquals(1, port.closes)
    }
    @Test fun reopeningDoesNotResetButDetachRequiresNewManualInvocation() {
        val port = Port()
        val probe = VerifiedMatriboxProbe({ eligible }, { port })
        probe.sendVerifiedSol100OdGain41Probe(); probe.cancel()
        probe.sendVerifiedSol100OdGain41Probe(); assertEquals(1, port.sends)
        probe.detached("usb/box"); assertEquals(1, port.sends)
        assertEquals(false, probe.status()["attempted"])
    }
}
