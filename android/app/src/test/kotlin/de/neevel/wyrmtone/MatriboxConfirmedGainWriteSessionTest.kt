package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MatriboxConfirmedGainWriteSessionTest {
    private class SendPort : MatriboxConfirmedGainWriteSendPort {
        var sentValues = mutableListOf<Float>()
        var closes = 0
        var throwOnSend: Exception? = null
        override fun sendGainWrite(value: Float) {
            throwOnSend?.let { throw it }
            sentValues.add(value)
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

    @Test fun `a valid write sends exactly once with the exact target value`() {
        val sendPort = SendPort()
        val session = MatriboxConfirmedGainWriteSession(
            eligibility = { eligible() },
            openSendPort = { sendPort },
        )

        val result = session.writeConfirmedSol100OdGain(18.0)

        assertEquals(MatriboxGainWriteOutcome.SUCCESS.name, result["outcome"])
        assertEquals(listOf(18.0f), sendPort.sentValues)
        assertEquals(1, sendPort.closes)
    }

    @Test fun `an out-of-range value is INVALID_VALUE and never opens a port`() {
        var opens = 0
        val session = MatriboxConfirmedGainWriteSession(
            eligibility = { eligible() },
            openSendPort = { ++opens; SendPort() },
        )
        for (value in listOf(-1.0, 100.0, Double.NaN)) {
            val fresh = MatriboxConfirmedGainWriteSession(
                eligibility = { eligible() },
                openSendPort = { ++opens; SendPort() },
            )
            val result = fresh.writeConfirmedSol100OdGain(value)
            assertEquals(MatriboxGainWriteOutcome.INVALID_VALUE.name, result["outcome"])
        }
        assertEquals(0, opens)
    }

    @Test fun `disabled compile flag is SAFETY_REJECTED, no port opened`() {
        var opens = 0
        val session = MatriboxConfirmedGainWriteSession(
            eligibility = { eligible(enabled = false) },
            openSendPort = { ++opens; SendPort() },
        )
        val result = session.writeConfirmedSol100OdGain(18.0)
        assertEquals(MatriboxGainWriteOutcome.SAFETY_REJECTED.name, result["outcome"])
        assertEquals(0, opens)
    }

    @Test fun `wrong or missing device is DEVICE_NOT_CONNECTED`() {
        for (state in listOf(
            eligible(connection = null),
            eligible(vendor = 0),
            eligible(product = 0),
        )) {
            var opens = 0
            val session = MatriboxConfirmedGainWriteSession(
                eligibility = { state },
                openSendPort = { ++opens; SendPort() },
            )
            val result = session.writeConfirmedSol100OdGain(18.0)
            assertEquals(MatriboxGainWriteOutcome.DEVICE_NOT_CONNECTED.name, result["outcome"])
            assertEquals(0, opens)
        }
    }

    @Test fun `monitoring active or MIDI not uniquely available is MIDI_NOT_AVAILABLE`() {
        for (state in listOf(
            eligible(monitoring = true),
            eligible(open = false),
        )) {
            var opens = 0
            val session = MatriboxConfirmedGainWriteSession(
                eligibility = { state },
                openSendPort = { ++opens; SendPort() },
            )
            val result = session.writeConfirmedSol100OdGain(18.0)
            assertEquals(MatriboxGainWriteOutcome.MIDI_NOT_AVAILABLE.name, result["outcome"])
            assertEquals(0, opens)
        }
    }

    @Test fun `a native send exception is SEND_FAILED and closes the port`() {
        val sendPort = SendPort().apply { throwOnSend = IllegalStateException("Transport-Fehler.") }
        val session = MatriboxConfirmedGainWriteSession(
            eligibility = { eligible() },
            openSendPort = { sendPort },
        )
        val result = session.writeConfirmedSol100OdGain(18.0)
        assertEquals(MatriboxGainWriteOutcome.SEND_FAILED.name, result["outcome"])
        assertEquals(1, sendPort.closes)
    }

    @Test fun `no retry -- a second attempt in the same connection is rejected without sending`() {
        val sendPort = SendPort()
        val session = MatriboxConfirmedGainWriteSession(
            eligibility = { eligible() },
            openSendPort = { sendPort },
        )
        val first = session.writeConfirmedSol100OdGain(18.0)
        assertEquals(MatriboxGainWriteOutcome.SUCCESS.name, first["outcome"])

        val second = session.writeConfirmedSol100OdGain(19.0)
        assertEquals(MatriboxGainWriteOutcome.SEND_FAILED.name, second["outcome"])
        assertEquals(listOf(18.0f), sendPort.sentValues) // no second send at all
    }

    @Test fun `an eligibility failure does not consume the one-shot latch`() {
        var state = eligible(enabled = false)
        val sendPort = SendPort()
        val session = MatriboxConfirmedGainWriteSession(
            eligibility = { state },
            openSendPort = { sendPort },
        )
        assertEquals(
            MatriboxGainWriteOutcome.SAFETY_REJECTED.name,
            session.writeConfirmedSol100OdGain(18.0)["outcome"],
        )
        state = eligible() // now eligible
        val result = session.writeConfirmedSol100OdGain(18.0)
        assertEquals(MatriboxGainWriteOutcome.SUCCESS.name, result["outcome"])
        assertEquals(listOf(18.0f), sendPort.sentValues)
    }

    @Test fun `a real disconnect and reconnect resets the one-shot state`() {
        var currentSend = SendPort()
        val session = MatriboxConfirmedGainWriteSession(
            eligibility = { eligible() },
            openSendPort = { currentSend },
        )
        assertEquals(
            MatriboxGainWriteOutcome.SUCCESS.name,
            session.writeConfirmedSol100OdGain(18.0)["outcome"],
        )
        session.detached("usb/box")
        currentSend = SendPort()
        val afterReconnect = session.writeConfirmedSol100OdGain(19.0)
        assertEquals(MatriboxGainWriteOutcome.SUCCESS.name, afterReconnect["outcome"])
        assertEquals(listOf(19.0f), currentSend.sentValues)
    }

    @Test fun `full raw hex logging includes the manual confirmation and send events`() {
        val sendPort = SendPort()
        val session = MatriboxConfirmedGainWriteSession(
            eligibility = { eligible() },
            openSendPort = { sendPort },
        )
        session.writeConfirmedSol100OdGain(18.0)
        @Suppress("UNCHECKED_CAST")
        val logs = session.status()["logs"] as List<String>
        assertTrue(logs.any { it.contains("MANUAL_CONFIRMATION") && it.contains("Sol 100 OD") })
        assertTrue(logs.any { it.contains("SEND_ATTEMPT") })
        assertTrue(logs.any { it.contains("SEND_SUCCESS") })
        // The log deliberately notes "noch kein Store" for a human reader,
        // but no STORE-related *event* is ever logged -- only exactly the
        // events this session can produce.
        val loggedEvents = logs.map { it.substringAfter("] ").substringBefore(" ") }
        assertEquals(
            setOf("MANUAL_CONFIRMATION", "SEND_ATTEMPT", "SEND_SUCCESS", "PORT_CLOSED"),
            loggedEvents.toSet(),
        )
    }
}
