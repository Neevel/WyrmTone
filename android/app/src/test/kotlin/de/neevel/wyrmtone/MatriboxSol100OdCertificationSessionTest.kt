package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MatriboxSol100OdCertificationSessionTest {
    private class SendPort : MatriboxSol100OdCertificationSendPort {
        var sentValues = mutableListOf<Pair<Sol100OdAmpField, Float>>()
        var closes = 0
        var throwOnSend: Exception? = null
        override fun sendCertificationWrite(field: Sol100OdAmpField, value: Float) {
            throwOnSend?.let { throw it }
            sentValues.add(field to value)
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
        val session = MatriboxSol100OdCertificationSession(
            eligibility = { eligible() },
            openSendPort = { sendPort },
        )

        val result = session.writeCertificationAmpField("presence", 18.0)

        assertEquals(MatriboxCertificationWriteOutcome.SUCCESS.name, result["outcome"])
        assertEquals(listOf(Sol100OdAmpField.PRESENCE to 18.0f), sendPort.sentValues)
        assertEquals(1, sendPort.closes)
    }

    @Test fun `an out-of-range value is INVALID_VALUE and never opens a port`() {
        var opens = 0
        val session = MatriboxSol100OdCertificationSession(
            eligibility = { eligible() },
            openSendPort = { ++opens; SendPort() },
        )
        for (value in listOf(-1.0, 100.0, Double.NaN)) {
            val fresh = MatriboxSol100OdCertificationSession(
                eligibility = { eligible() },
                openSendPort = { ++opens; SendPort() },
            )
            val result = fresh.writeCertificationAmpField("presence", value)
            assertEquals(MatriboxCertificationWriteOutcome.INVALID_VALUE.name, result["outcome"])
        }
        assertEquals(0, opens)
    }

    @Test fun `disabled compile flag is SAFETY_REJECTED, no port opened`() {
        var opens = 0
        val session = MatriboxSol100OdCertificationSession(
            eligibility = { eligible(enabled = false) },
            openSendPort = { ++opens; SendPort() },
        )
        val result = session.writeCertificationAmpField("presence", 18.0)
        assertEquals(MatriboxCertificationWriteOutcome.SAFETY_REJECTED.name, result["outcome"])
        assertEquals(0, opens)
    }

    @Test fun `wrong or missing device is DEVICE_NOT_CONNECTED`() {
        for (state in listOf(
            eligible(connection = null),
            eligible(vendor = 0),
            eligible(product = 0),
        )) {
            var opens = 0
            val session = MatriboxSol100OdCertificationSession(
                eligibility = { state },
                openSendPort = { ++opens; SendPort() },
            )
            val result = session.writeCertificationAmpField("presence", 18.0)
            assertEquals(MatriboxCertificationWriteOutcome.DEVICE_NOT_CONNECTED.name, result["outcome"])
            assertEquals(0, opens)
        }
    }

    @Test fun `monitoring active or MIDI not uniquely available is MIDI_NOT_AVAILABLE`() {
        for (state in listOf(
            eligible(monitoring = true),
            eligible(open = false),
        )) {
            var opens = 0
            val session = MatriboxSol100OdCertificationSession(
                eligibility = { state },
                openSendPort = { ++opens; SendPort() },
            )
            val result = session.writeCertificationAmpField("presence", 18.0)
            assertEquals(MatriboxCertificationWriteOutcome.MIDI_NOT_AVAILABLE.name, result["outcome"])
            assertEquals(0, opens)
        }
    }

    @Test fun `a native send exception is SEND_FAILED and closes the port`() {
        val sendPort = SendPort().apply { throwOnSend = IllegalStateException("Transport-Fehler.") }
        val session = MatriboxSol100OdCertificationSession(
            eligibility = { eligible() },
            openSendPort = { sendPort },
        )
        val result = session.writeCertificationAmpField("presence", 18.0)
        assertEquals(MatriboxCertificationWriteOutcome.SEND_FAILED.name, result["outcome"])
        assertEquals(1, sendPort.closes)
    }

    @Test fun `no retry -- a second attempt in the same connection is rejected without sending`() {
        val sendPort = SendPort()
        val session = MatriboxSol100OdCertificationSession(
            eligibility = { eligible() },
            openSendPort = { sendPort },
        )
        val first = session.writeCertificationAmpField("presence", 18.0)
        assertEquals(MatriboxCertificationWriteOutcome.SUCCESS.name, first["outcome"])

        val second = session.writeCertificationAmpField("presence", 19.0)
        assertEquals(MatriboxCertificationWriteOutcome.SEND_FAILED.name, second["outcome"])
        assertEquals(listOf(Sol100OdAmpField.PRESENCE to 18.0f), sendPort.sentValues) // no second send at all
    }

    @Test fun `an eligibility failure does not consume the one-shot latch`() {
        var state = eligible(enabled = false)
        val sendPort = SendPort()
        val session = MatriboxSol100OdCertificationSession(
            eligibility = { state },
            openSendPort = { sendPort },
        )
        assertEquals(
            MatriboxCertificationWriteOutcome.SAFETY_REJECTED.name,
            session.writeCertificationAmpField("presence", 18.0)["outcome"],
        )
        state = eligible() // now eligible
        val result = session.writeCertificationAmpField("presence", 18.0)
        assertEquals(MatriboxCertificationWriteOutcome.SUCCESS.name, result["outcome"])
        assertEquals(listOf(Sol100OdAmpField.PRESENCE to 18.0f), sendPort.sentValues)
    }

    @Test fun `a real disconnect and reconnect resets the one-shot state`() {
        var currentSend = SendPort()
        val session = MatriboxSol100OdCertificationSession(
            eligibility = { eligible() },
            openSendPort = { currentSend },
        )
        assertEquals(
            MatriboxCertificationWriteOutcome.SUCCESS.name,
            session.writeCertificationAmpField("presence", 18.0)["outcome"],
        )
        session.detached("usb/box")
        currentSend = SendPort()
        val afterReconnect = session.writeCertificationAmpField("presence", 19.0)
        assertEquals(MatriboxCertificationWriteOutcome.SUCCESS.name, afterReconnect["outcome"])
        assertEquals(listOf(Sol100OdAmpField.PRESENCE to 19.0f), currentSend.sentValues)
    }

    @Test fun `full raw hex logging includes the manual confirmation and send events`() {
        val sendPort = SendPort()
        val session = MatriboxSol100OdCertificationSession(
            eligibility = { eligible() },
            openSendPort = { sendPort },
        )
        session.writeCertificationAmpField("presence", 18.0)
        @Suppress("UNCHECKED_CAST")
        val logs = session.status()["logs"] as List<String>
        assertTrue(logs.any { it.contains("MANUAL_CONFIRMATION") && it.contains("Sol 100 OD") && it.contains("presence") })
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

    @Test fun `gain and unknown fields are rejected, never sent, one-shot not consumed`() {
        var opens = 0
        val session = MatriboxSol100OdCertificationSession(
            eligibility = { eligible() },
            openSendPort = { ++opens; SendPort() },
        )
        for (name in listOf("gain", "reverb", "", "PRESENCE", "1", "presence ")) {
            val result = session.writeCertificationAmpField(name, 74.0)
            assertEquals(name, MatriboxCertificationWriteOutcome.SAFETY_REJECTED.name, result["outcome"])
        }
        assertEquals(0, opens)
        // the latch is untouched: a valid field still works afterwards
        val ok = session.writeCertificationAmpField("treble", 32.0)
        assertEquals(MatriboxCertificationWriteOutcome.SUCCESS.name, ok["outcome"])
    }

    @Test fun `every certification field is sent with its own field, exactly once per connection`() {
        for (field in Sol100OdAmpField.CERTIFICATION_FIELDS) {
            val port = SendPort()
            val session = MatriboxSol100OdCertificationSession(
                eligibility = { eligible() },
                openSendPort = { port },
            )
            val first = session.writeCertificationAmpField(field.wireName, 40.0)
            val second = session.writeCertificationAmpField(field.wireName, 41.0)
            assertEquals(MatriboxCertificationWriteOutcome.SUCCESS.name, first["outcome"])
            assertEquals(MatriboxCertificationWriteOutcome.SEND_FAILED.name, second["outcome"])
            assertEquals(listOf(field to 40.0f), port.sentValues)
        }
    }
}
