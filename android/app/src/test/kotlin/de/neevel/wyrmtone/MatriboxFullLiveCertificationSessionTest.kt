package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MatriboxFullLiveCertificationSessionTest {
    private class SendPort(var failAt: Int? = null) : MatriboxFullLiveSendPort {
        val sent = mutableListOf<FullLiveOperation>()
        var closes = 0
        override fun sendOperation(operation: FullLiveOperation) {
            check(operation in MatriboxFullLivePlan.operations) { "not in plan" }
            if (failAt == sent.size) throw IllegalStateException("Transport-Fehler.")
            sent.add(operation)
        }
        override fun close() { ++closes }
    }

    private fun eligible(
        enabled: Boolean = true,
        connection: String? = "usb/box",
        vendor: Int? = 0x84ef,
        product: Int? = 0x0054,
        open: Boolean = true,
        monitoring: Boolean = false,
    ) = ProbeEligibility(
        enabled = enabled,
        connection = connection,
        vendor = vendor,
        product = product,
        uniqueUsb = true,
        uniqueMidi = true,
        directlyMapped = true,
        deviceOpen = open,
        expectedInput = true,
        monitoring = monitoring,
    )

    private val planId = MatriboxFullLivePlan.PLAN_ID
    private val total = MatriboxFullLivePlan.operations.size

    @Suppress("UNCHECKED_CAST")
    private fun statuses(result: Map<String, Any?>): List<String> =
        (result["operations"] as List<Map<String, Any?>>).map { it["status"] as String }

    @Test fun `a valid run sends the fixed plan once, in order, with pauses`() {
        val port = SendPort()
        val pauses = mutableListOf<Long>()
        val session = MatriboxFullLiveCertificationSession(
            eligibility = { eligible() },
            openSendPort = { port },
            pause = { pauses.add(it) },
        )
        val result = session.run(planId)
        assertEquals(MatriboxFullLiveOutcome.SUCCESS.name, result["outcome"])
        assertEquals(MatriboxFullLivePlan.operations, port.sent)
        assertEquals(total, result["completed"])
        assertEquals(List(total) { "SENT" }, statuses(result))
        assertEquals(1, port.closes)
        assertEquals(total, pauses.size)
        assertEquals(9, pauses.count { it == 200L })
    }

    @Test fun `an unknown plan id is rejected before anything is opened or sent`() {
        var opens = 0
        val session = MatriboxFullLiveCertificationSession(
            eligibility = { eligible() },
            openSendPort = { ++opens; SendPort() },
            pause = {},
        )
        for (id in listOf("", "FULL_LIVE_P01_V2", "full_live_p01_v1", "AMP", "P02")) {
            val result = session.run(id)
            assertEquals(id, MatriboxFullLiveOutcome.SAFETY_REJECTED.name, result["outcome"])
            assertEquals(0, result["completed"])
        }
        assertEquals(0, opens)
    }

    @Test fun `disabled gate, wrong device and monitoring never send`() {
        for ((state, expected) in listOf(
            eligible(enabled = false) to MatriboxFullLiveOutcome.SAFETY_REJECTED,
            eligible(connection = null) to MatriboxFullLiveOutcome.DEVICE_NOT_CONNECTED,
            eligible(vendor = 0) to MatriboxFullLiveOutcome.DEVICE_NOT_CONNECTED,
            eligible(monitoring = true) to MatriboxFullLiveOutcome.MIDI_NOT_AVAILABLE,
            eligible(open = false) to MatriboxFullLiveOutcome.MIDI_NOT_AVAILABLE,
        )) {
            var opens = 0
            val session = MatriboxFullLiveCertificationSession(
                eligibility = { state },
                openSendPort = { ++opens; SendPort() },
                pause = {},
            )
            val result = session.run(planId)
            assertEquals(expected.name, result["outcome"])
            assertEquals(0, opens)
            assertEquals(List(total) { "NOT_SENT" }, statuses(result))
        }
    }

    @Test fun `the first failure stops the run, the rest is not sent, no retry, no rollback`() {
        val port = SendPort(failAt = 7)
        val session = MatriboxFullLiveCertificationSession(
            eligibility = { eligible() },
            openSendPort = { port },
            pause = {},
        )
        val result = session.run(planId)
        assertEquals(MatriboxFullLiveOutcome.SEND_FAILED.name, result["outcome"])
        assertEquals(7, result["completed"])
        assertEquals(7, result["failedIndex"])
        val s = statuses(result)
        assertEquals(List(7) { "SENT" } + "FAILED" + List(total - 8) { "NOT_SENT" }, s)
        assertEquals(MatriboxFullLivePlan.operations.take(7), port.sent)
        assertEquals(1, port.closes)
    }

    @Test fun `a second run in the same connection sends nothing more`() {
        val port = SendPort()
        val session = MatriboxFullLiveCertificationSession(
            eligibility = { eligible() },
            openSendPort = { port },
            pause = {},
        )
        assertEquals(MatriboxFullLiveOutcome.SUCCESS.name, session.run(planId)["outcome"])
        val second = session.run(planId)
        assertEquals(MatriboxFullLiveOutcome.SEND_FAILED.name, second["outcome"])
        assertEquals(total, port.sent.size) // still exactly one plan worth
    }

    @Test fun `an eligibility failure does not consume the one-shot latch`() {
        var state = eligible(enabled = false)
        val port = SendPort()
        val session = MatriboxFullLiveCertificationSession(
            eligibility = { state },
            openSendPort = { port },
            pause = {},
        )
        assertEquals(MatriboxFullLiveOutcome.SAFETY_REJECTED.name, session.run(planId)["outcome"])
        state = eligible()
        assertEquals(MatriboxFullLiveOutcome.SUCCESS.name, session.run(planId)["outcome"])
    }

    @Test fun `a real disconnect resets the one-shot state`() {
        var current = SendPort()
        val session = MatriboxFullLiveCertificationSession(
            eligibility = { eligible() },
            openSendPort = { current },
            pause = {},
        )
        assertEquals(MatriboxFullLiveOutcome.SUCCESS.name, session.run(planId)["outcome"])
        session.detached("usb/box")
        current = SendPort()
        assertEquals(MatriboxFullLiveOutcome.SUCCESS.name, session.run(planId)["outcome"])
        assertEquals(total, current.sent.size)
    }

    @Test fun `full raw hex logging and only run-level events, never a store event`() {
        val session = MatriboxFullLiveCertificationSession(
            eligibility = { eligible() },
            openSendPort = { SendPort() },
            pause = {},
        )
        session.run(planId)
        @Suppress("UNCHECKED_CAST")
        val logs = session.status()["logs"] as List<String>
        assertTrue(logs.any { it.contains("MANUAL_CONFIRMATION") && it.contains("kein Store") })
        assertTrue(logs.any { it.contains("SEND_ATTEMPT") && it.contains("f0 21 25 7f 51 4d 45 32 12 10 01 00 01") })
        val events = logs.map { it.substringAfter("] ").substringBefore(" ") }.toSet()
        assertEquals(setOf("MANUAL_CONFIRMATION", "SEND_ATTEMPT", "SEND_SUCCESS", "PORT_CLOSED"), events)
    }
}
