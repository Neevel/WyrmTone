package de.neevel.wyrmtone

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MatriboxToneTransferTest {
    private val hash = "a".repeat(64)

    private fun select(slot: String, model: String) = mapOf("type" to "SELECT_MODEL", "slot" to slot, "model" to model)
    private fun param(slot: String, model: String, name: String, value: Number) =
        mapOf("type" to "SET_PARAMETER", "slot" to slot, "model" to model, "parameter" to name, "value" to value)
    private fun toggle(slot: String, on: Boolean) = mapOf("type" to if (on) "ENABLE_BLOCK" else "DISABLE_BLOCK", "slot" to slot)

    private fun request(
        operations: List<Any?>,
        planId: String = "plan-1",
        bank: Any? = "USER",
        slot: Any? = 11,
        backup: Any? = hash,
    ): Map<String, Any?> = mapOf(
        "planId" to planId,
        "targetBank" to bank,
        "targetSlot" to slot,
        "backupHash" to backup,
        "operations" to operations,
    )

    private val angels: List<Map<String, Any?>> = listOf(
        toggle("FX1", false),
        select("FX2", "Boost"),
        toggle("FX2", true),
        param("AMP", "Sol 100 OD", "Gain", 67),
        param("AMP", "Sol 100 OD", "PRES", 59),
        param("AMP", "Sol 100 OD", "Bass", 41),
        param("AMP", "Sol 100 OD", "Middle", 59),
        param("AMP", "Sol 100 OD", "Treble", 61),
        select("CAB", "Sol 4x12"),
        toggle("CAB", true),
        toggle("EQ", false),
    )

    private fun rejected(request: Any?): String =
        try {
            MatriboxToneTransferPlanValidator.validate(request)
            "ACCEPTED"
        } catch (rejection: ToneTransferRejection) {
            rejection.code
        }

    private class Port(val failAt: Int? = null, val failPresetSelect: Boolean = false) : MatriboxToneTransferSendPort {
        val sent = mutableListOf<FullLiveOperation>()
        val selected = mutableListOf<MatriboxWritableUserPreset>()
        var closes = 0

        /** Every call that would put bytes on the wire, in order. */
        val wire = mutableListOf<String>()
        override fun selectUserPreset(target: MatriboxWritableUserPreset) {
            if (failPresetSelect) throw IllegalStateException("Transport-Fehler beim Preset-Select.")
            selected.add(target)
            wire.add("SELECT ${target.label}")
        }
        override fun sendValidated(operation: FullLiveOperation) {
            if (failAt == sent.size) throw IllegalStateException("Transport-Fehler.")
            sent.add(operation)
            wire.add(operation.label)
        }
        override fun close() { ++closes }
    }

    private fun eligible(enabled: Boolean = true, connection: String? = "usb/box", monitoring: Boolean = false) = ProbeEligibility(
        enabled = enabled, connection = connection, vendor = 0x84ef, product = 0x0054, uniqueUsb = true,
        uniqueMidi = true, directlyMapped = true, deviceOpen = true, expectedInput = true, monitoring = monitoring,
    )

    private fun session(port: Port, opens: IntArray = intArrayOf(0), state: () -> ProbeEligibility = { eligible() }) =
        MatriboxToneTransferSession(state, { opens[0]++; port }, pause = {})

    @Test fun `the certified Angels plan validates and encodes to the same bytes as the certification golden`() {
        val plan = MatriboxToneTransferPlanValidator.validate(request(angels))
        assertEquals(11, plan.operations.size)
        assertEquals(
            MatriboxAngelsGolden.messages,
            plan.operations.map { MatriboxFullLiveCodec.encode(it).joinToString(" ") { b -> "%02x".format(b) } },
        )
        assertEquals(MatriboxAngelsPlan.operations, plan.operations)
    }

    @Test fun `every operation of an accepted plan is natively hardware-confirmed`() {
        val plan = MatriboxToneTransferPlanValidator.validate(request(angels))
        assertTrue(plan.operations.all { MatriboxToneTransferCatalog.isConfirmed(it) })
    }

    @Test fun `unknown or blocked models, parameters and values are refused with a precise code`() {
        assertEquals("MODEL_NOT_CONFIRMED", rejected(request(listOf(select("FX2", "Nope")))))
        assertEquals("MODEL_NOT_CONFIRMED", rejected(request(listOf(select("AMP", "Boost"))))) // an FX model is no AMP
        assertEquals("MODEL_NOT_CONFIRMED", rejected(request(listOf(select("RVB", "Sol 4x12"))))) // a CAB is no reverb
        assertEquals("MODEL_NOT_CONFIRMED", rejected(request(listOf(select("CAB", "User IR 7"))))) // User IR stays BLOCKED
        assertEquals("MODEL_NOT_CONFIRMED", rejected(request(listOf(param("CAB", "Sol 100 OD", "Gain", 20))))) // model of another slot
        assertEquals("PARAMETER_NOT_CONFIRMED", rejected(request(listOf(param("AMP", "Sol 100 OD", "Nope", 50)))))
        assertEquals("PARAMETER_NOT_CONFIRMED", rejected(request(listOf(param("AMP", "Sol 100 OD", "Bright", 1))))) // belongs to Boost
        assertEquals("VALUE_OUT_OF_RANGE", rejected(request(listOf(param("AMP", "Sol 100 OD", "Gain", 120)))))
        assertEquals("VALUE_OUT_OF_RANGE", rejected(request(listOf(param("AMP", "Sol 100 OD", "Gain", -1)))))
        assertEquals("VALUE_OUT_OF_RANGE", rejected(request(listOf(param("AMP", "Sol 100 OD", "Gain", Double.NaN)))))
        assertEquals("VALUE_OUT_OF_RANGE", rejected(request(listOf(param("FX2", "Boost", "Bright", 0.5))))) // flags are 0 or 1
        assertEquals("VALUE_OUT_OF_RANGE", rejected(request(listOf(param("EQ", "Guitar EQ", "400Hz", -51)))))
    }

    @Test fun `bind, Sync, enumerations and unsampled signed values stay BLOCKED natively`() {
        assertEquals("PARAMETER_NOT_CONFIRMED", rejected(request(listOf(param("MOD", "Chorus A", "Rate", 3.7))))) // bound to Sync
        assertEquals("PARAMETER_NOT_CONFIRMED", rejected(request(listOf(param("DLY", "Warm", "Time", 743))))) // bound to Sync
        assertEquals("PARAMETER_NOT_CONFIRMED", rejected(request(listOf(param("DLY", "Warm", "Sync", 1))))) // Sync itself
        assertEquals("PARAMETER_NOT_CONFIRMED", rejected(request(listOf(param("FX2", "AC Sim", "Mode", 1))))) // Combox
        assertEquals("PARAMETER_NOT_CONFIRMED", rejected(request(listOf(param("RVB", "Mod RVB", "Lo End", -10))))) // signed only sampled in EQ
    }

    @Test fun `the promoted families are accepted - any manufacturer model, number, signed EQ and flag writes, all block CC`() {
        val plan = MatriboxToneTransferPlanValidator.validate(
            request(
                listOf(
                    select("FX1", "Skreamer"), param("FX1", "Skreamer", "Gain", 30),
                    select("FX2", "Boost"), param("FX2", "Boost", "Bright", 1), toggle("FX2", true),
                    select("AMP", "Brit 800"), param("AMP", "Brit 800", "Gain", 40),
                    select("NR", "Gate 2"), param("NR", "Gate 2", "THRE", 31), toggle("NR", true),
                    select("CAB", "Brit75 4x12"), param("CAB", "Brit75 4x12", "VOL", 43),
                    select("EQ", "Guitar EQ"), param("EQ", "Guitar EQ", "400Hz", -23), toggle("EQ", true),
                    select("MOD", "Chorus A"), toggle("MOD", false),
                    select("DLY", "Warm"), param("DLY", "Warm", "Trail", 1), toggle("DLY", true),
                    select("RVB", "Room"), param("RVB", "Room", "Mix", 23), toggle("RVB", true),
                ),
            ),
        )
        assertEquals(23, plan.operations.size)
        assertTrue(plan.operations.all { MatriboxToneTransferCatalog.isConfirmed(it) })
        // wire index = manufacturer ID - 1, resolved natively
        val byLabel = plan.operations.filterIsInstance<FullLiveOperation.Parameter>().associateBy { "${it.slot.name} ${it.name}" }
        assertEquals(2, byLabel.getValue("FX2 Bright").index)
        assertEquals(1, byLabel.getValue("CAB VOL").index)
        assertEquals(0, byLabel.getValue("FX1 Gain").index)
        assertEquals(1, byLabel.getValue("EQ 400Hz").index)
    }

    @Test fun `every slot accepts block CC in both directions`() {
        for (slot in ChainSlot.values()) {
            for (on in listOf(true, false)) {
                assertEquals("ACCEPTED", rejected(request(listOf(toggle(slot.name, on)))))
            }
        }
    }

    @Test fun `wrong slot, unknown operation, factory, protected and invalid targets are refused`() {
        assertEquals("UNKNOWN_SLOT", rejected(request(listOf(toggle("FX3", false)))))
        assertEquals("UNKNOWN_SLOT", rejected(request(listOf(toggle("fx1", false)))))
        assertEquals("UNKNOWN_OPERATION", rejected(request(listOf(mapOf("type" to "STORE", "slot" to "FX1")))))
        assertEquals("UNKNOWN_OPERATION", rejected(request(listOf(mapOf("type" to "SET_METADATA", "slot" to "FX1")))))
        assertEquals("TARGET_NOT_ALLOWED", rejected(request(angels, bank = "FACTORY")))
        assertEquals("TARGET_NOT_ALLOWED", rejected(request(angels, bank = null)))
        for (protected in 1..10) assertEquals("P$protected", "TARGET_PROTECTED", rejected(request(angels, slot = protected)))
        for (invalid in listOf<Any?>(0, -1, 100, 128, null, "11", 11.0, 10.5)) {
            assertEquals("$invalid", "TARGET_NOT_ALLOWED", rejected(request(angels, slot = invalid)))
        }
        assertEquals("ARGUMENTS_INVALID", rejected(request(angels) - "targetSlot"))
    }

    // ------------------------------------------------------------ slot policy: P01..P10 protected

    @Test fun `P01, P02, P05 and P10 are rejected natively with ZERO sends - no preset select, no model, no parameter, no block CC`() {
        for (protected in listOf(1, 2, 5, 10)) {
            val port = Port()
            val opens = intArrayOf(0)
            val result = session(port, opens).execute(request(angels, slot = protected))
            assertEquals("P$protected", ToneTransferOutcome.VALIDATION_REJECTED.name, result["outcome"])
            assertEquals("TARGET_PROTECTED", result["errorCode"])
            assertEquals(0, opens[0])
            assertTrue(port.wire.isEmpty())
            assertTrue(port.selected.isEmpty())
            assertTrue(port.sent.isEmpty())
            assertEquals("NOT_SENT", result["presetSelect"])
            assertEquals(null, result["targetSlot"])
            assertEquals(0, result["completed"])
        }
    }

    @Test fun `a protected slot also blocks a plan made only of a block CC, a model select or a parameter`() {
        for (ops in listOf(listOf(toggle("FX1", false)), listOf(select("FX2", "Boost")), listOf(param("AMP", "Sol 100 OD", "Gain", 67)))) {
            val port = Port()
            val result = session(port).execute(request(ops, slot = 1))
            assertEquals(ToneTransferOutcome.VALIDATION_REJECTED.name, result["outcome"])
            assertTrue(port.wire.isEmpty())
        }
    }

    @Test fun `the writer port type cannot even be addressed at a protected or invalid slot`() {
        for (bad in listOf(0, 1, 2, 5, 10, 100)) {
            assertTrue("$bad", runCatching { MatriboxWritableUserPreset.of(bad) }.isFailure)
        }
    }

    // ------------------------------------------------------------ slot policy: P11..P99 writable

    @Test fun `P11, P12, P50 and P99 run through the native pipeline - preset select of exactly that slot first, then the plan`() {
        for ((preset, index) in listOf(11 to 0x0a, 12 to 0x0b, 50 to 0x31, 99 to 0x62)) {
            val port = Port()
            val result = session(port).execute(request(angels, slot = preset, planId = "plan-$preset"))
            assertEquals("P$preset", ToneTransferOutcome.SUCCESS.name, result["outcome"])
            assertEquals(preset, result["targetSlot"])
            assertEquals("SENT", result["presetSelect"])
            assertEquals(listOf(preset, preset), port.selected.map { it.presetNumber })
            assertEquals(List(2) { "SELECT ${MatriboxWritableUserPreset.of(preset).label}" }, port.wire.take(2))
            assertEquals(MatriboxAngelsPlan.operations, port.sent)
            assertEquals(11, result["completed"])
            val message = MatriboxPresetSelectReference.message(MatriboxWritableUserPreset.of(preset))
            assertEquals(index.toByte(), message[MatriboxPresetSelectReference.INDEX_OFFSET])
        }
    }

    @Test fun `the preset select is the confirmed editor message with only the index byte changed`() {
        val reference = VerifiedPresetP01Reference.bytes()
        for ((preset, index) in listOf(11 to 0x0a, 12 to 0x0b, 20 to 0x13, 50 to 0x31, 99 to 0x62)) {
            val target = MatriboxWritableUserPreset.of(preset)
            val message = MatriboxPresetSelectReference.message(target)
            MatriboxPresetSelectReference.validate(message, target)
            assertEquals(22, message.size)
            for (i in reference.indices) {
                if (i == MatriboxPresetSelectReference.INDEX_OFFSET) assertEquals(index.toByte(), message[i]) else assertEquals(reference[i], message[i])
            }
        }
        // it is its own message family (12 00), validated against its own reference: the live-edit
        // codec (12 10 only) would refuse it, so it must never be routed through that check
        val select = MatriboxPresetSelectReference.message(MatriboxWritableUserPreset.of(11))
        assertTrue(runCatching { MatriboxFullLiveCodec.validate(select) }.isFailure)
        // a P11 message is never valid for P12
        val p11 = MatriboxPresetSelectReference.message(MatriboxWritableUserPreset.of(11))
        assertTrue(runCatching { MatriboxPresetSelectReference.validate(p11, MatriboxWritableUserPreset.of(12)) }.isFailure)
    }

    @Test fun `a failing preset select stops before the first operation - nothing of the plan is sent`() {
        val port = Port(failPresetSelect = true)
        val result = session(port).execute(request(angels))
        assertEquals(ToneTransferOutcome.SEND_FAILED.name, result["outcome"])
        assertEquals("FAILED", result["presetSelect"])
        assertTrue(port.sent.isEmpty())
        @Suppress("UNCHECKED_CAST")
        assertTrue((result["operations"] as List<Map<String, Any?>>).all { it["status"] == "NOT_SENT" })
        assertEquals(1, port.closes)
    }

    @Test fun `the same plan id is one-shot per slot - a P11 run never blocks or replays as P12`() {
        val port = Port()
        val s = session(port)
        assertEquals("SUCCESS", s.execute(request(angels, planId = "same", slot = 11))["outcome"])
        assertEquals("SAFETY_REJECTED", s.execute(request(angels, planId = "same", slot = 11))["outcome"])
        val p12 = s.execute(request(angels, planId = "same", slot = 12))
        assertEquals("SUCCESS", p12["outcome"])
        assertEquals(12, p12["targetSlot"])
        assertEquals(listOf(11, 11, 12, 12), port.selected.map { it.presetNumber })
    }

    @Test fun `raw bytes, algorithm ids, indices and extra fields cannot be smuggled in`() {
        assertEquals("ARGUMENTS_INVALID", rejected(request(listOf(mapOf("type" to "SELECT_MODEL", "slot" to "FX2", "model" to "Boost", "code" to 26)))))
        assertEquals("ARGUMENTS_INVALID", rejected(request(listOf(mapOf("type" to "SET_PARAMETER", "slot" to "AMP", "model" to "Sol 100 OD", "parameter" to "Gain", "value" to 1, "index" to 0)))))
        assertEquals("ARGUMENTS_INVALID", rejected(request(listOf(mapOf("type" to "ENABLE_BLOCK", "slot" to "FX2", "bytes" to listOf(1))))))
        assertEquals("ARGUMENTS_INVALID", rejected(request(listOf(listOf(0xf0, 0x21)))))
        assertEquals("ARGUMENTS_INVALID", rejected(request(angels) + mapOf("sysex" to listOf(1))))
        assertEquals("ARGUMENTS_INVALID", rejected(mapOf("planId" to "x", "operations" to angels)))
        assertEquals("ARGUMENTS_INVALID", rejected(null))
        assertEquals("ARGUMENTS_INVALID", rejected(request(angels, backup = "nothex")))
        assertEquals("ARGUMENTS_INVALID", rejected(request(angels, planId = "bad id!")))
        assertEquals("EMPTY_PLAN", rejected(request(emptyList())))
    }

    @Test fun `there is no operation type for store, metadata, name, BPM or volume`() {
        for (type in listOf("STORE", "COMMIT", "SAVE", "SET_NAME", "SET_BPM", "SET_VOLUME", "12 12", "12 11")) {
            assertEquals(type, "UNKNOWN_OPERATION", rejected(request(listOf(mapOf("type" to type, "slot" to "FX1")))))
        }
    }

    @Test fun `operations must follow the chain order, model before its dependants, without duplicates`() {
        assertEquals("ORDER_INVALID", rejected(request(listOf(toggle("FX2", true), select("FX2", "Boost")))))
        assertEquals("ORDER_INVALID", rejected(request(listOf(toggle("CAB", true), toggle("FX1", false)))))
        assertEquals("ORDER_INVALID", rejected(request(listOf(toggle("FX1", false), toggle("FX1", false)))))
    }

    @Test fun `one invalid operation anywhere means ZERO sends, nothing is even opened`() {
        for (bad in listOf(
            listOf<Map<String, Any?>>(select("FX1", "Nope")) + angels.drop(1), // FIRST op unknown
            angels.dropLast(1) + select("DLY", "Nope"), // last op unknown
            listOf(angels.first(), select("FX2", "Nope")) + angels.drop(2), // an early op unknown
            angels.take(3) + param("AMP", "Sol 100 OD", "Nope", 50),
        )) {
            val port = Port()
            val opens = intArrayOf(0)
            val result = session(port, opens).execute(request(bad))
            assertEquals(ToneTransferOutcome.VALIDATION_REJECTED.name, result["outcome"])
            assertTrue(port.sent.isEmpty())
            assertEquals(0, opens[0])
            assertEquals(0, result["completed"])
        }
    }

    @Test fun `a valid plan runs once in order, audit is complete, the port is closed`() {
        val port = Port()
        val result = session(port).execute(request(angels))
        assertEquals(ToneTransferOutcome.SUCCESS.name, result["outcome"])
        assertEquals(MatriboxAngelsPlan.operations, port.sent)
        assertEquals(11, result["completed"])
        assertEquals(1, port.closes)
    }

    @Test fun `the first transport failure stops the run, completed failed notSent, no retry, no rollback`() {
        val port = Port(failAt = 4)
        val s = session(port)
        val result = s.execute(request(angels))
        assertEquals(ToneTransferOutcome.SEND_FAILED.name, result["outcome"])
        assertEquals(4, result["completed"])
        assertEquals(4, result["failedIndex"])
        @Suppress("UNCHECKED_CAST")
        val statuses = (result["operations"] as List<Map<String, Any?>>).map { it["status"] }
        assertEquals(List(4) { "SENT" } + "FAILED" + List(6) { "NOT_SENT" }, statuses)
        assertEquals(MatriboxAngelsPlan.operations.take(4), port.sent)
        // the same plan in the same connection is never executed again
        val again = s.execute(request(angels))
        assertEquals(ToneTransferOutcome.SAFETY_REJECTED.name, again["outcome"])
        assertEquals(4, port.sent.size)
    }

    @Test fun `disabled gate, wrong device and monitoring send nothing`() {
        for ((state, outcome) in listOf(
            eligible(enabled = false) to ToneTransferOutcome.SAFETY_REJECTED,
            eligible(connection = null) to ToneTransferOutcome.DEVICE_NOT_CONNECTED,
            eligible(monitoring = true) to ToneTransferOutcome.MIDI_NOT_AVAILABLE,
        )) {
            val port = Port()
            val opens = intArrayOf(0)
            val result = session(port, opens) { state }.execute(request(angels))
            assertEquals(outcome.name, result["outcome"])
            assertTrue(port.sent.isEmpty())
            assertEquals(0, opens[0])
        }
    }

    @Test fun `a real disconnect resets the one-shot state, a new plan id is a different plan`() {
        val port = Port()
        val s = session(port)
        assertEquals("SUCCESS", s.execute(request(angels, planId = "p1"))["outcome"])
        assertEquals("SAFETY_REJECTED", s.execute(request(angels, planId = "p1"))["outcome"])
        assertEquals("SUCCESS", s.execute(request(angels, planId = "p2"))["outcome"])
        s.detached("usb/box")
        assertEquals("SUCCESS", s.execute(request(angels, planId = "p1"))["outcome"])
    }

    @Test fun `logs contain only run-level events with full hex and never a store event`() {
        val s = session(Port())
        s.execute(request(angels))
        @Suppress("UNCHECKED_CAST")
        val logs = s.status()["logs"] as List<String>
        assertTrue(logs.any { it.contains("EXECUTE") && it.contains("kein Store") && it.contains("User P11 (Index 10)") })
        assertTrue(logs.any { it.contains("SEND_ATTEMPT") && it.contains("f0 21 25 7f 51 4d 45 32 12 10 02 00 01") })
        assertTrue(logs.any { it.contains("PRESET_SELECT_ATTEMPT") && it.contains("f0 21 25 7f 51 4d 45 32 12 00 02 00 00 00 00 00 00 00 0a 00 00 f7") })
        val events = logs.map { it.substringAfter("] ").substringBefore(" ") }.toSet()
        assertEquals(setOf("EXECUTE", "PRESET_SELECT_ATTEMPT", "PRESET_SELECT_SUCCESS", "SEND_ATTEMPT", "SEND_SUCCESS", "PORT_CLOSED"), events)
        assertFalse(logs.any { it.contains("12 12") || it.contains("12 11") })
    }

    @Test fun `the native table is the manufacturer catalog with the productive decisions`() {
        val catalog = MatriboxToneTransferCatalog
        assertEquals(EXPECTED_MODELS, catalog.models.size)
        // every slot has selectable models resolved from the manufacturer data
        for (slot in ChainSlot.values()) assertTrue(slot.name, catalog.models.any { it.slot == slot && it.selectable })
        assertEquals(0x1a, catalog.model(ChainSlot.FX1, "Boost")!!.code)
        assertEquals(0x1a, catalog.model(ChainSlot.FX2, "Boost")!!.code)
        assertEquals(0x0a000028, catalog.model(ChainSlot.CAB, "Sol 4x12")!!.code)
        // wire = ID - 1: Bright (ID 3) -> 2, CAB VOL (ID 2) -> 1, Sol 100 OD Bass (ID 4) -> 3
        assertEquals(2, catalog.model(ChainSlot.FX2, "Boost")!!.parameter("Bright")!!.wireIndex)
        assertEquals(1, catalog.model(ChainSlot.CAB, "Sol 4x12")!!.parameter("VOL")!!.wireIndex)
        assertEquals(3, catalog.model(ChainSlot.AMP, "Sol 100 OD")!!.parameter("Bass")!!.wireIndex)
        for (m in catalog.models) for (p in m.parameters) {
            assertTrue("${m.name}/${p.name}", p.wireIndex == p.manufacturerId - 1 || p.blockedBy != null)
        }
        // User IR is never selectable, bound and Sync parameters are never writable
        assertFalse(catalog.model(ChainSlot.CAB, "User IR 7")!!.selectable)
        assertFalse(catalog.model(ChainSlot.MOD, "Chorus A")!!.parameter("Rate")!!.writable)
        assertFalse(catalog.model(ChainSlot.DLY, "Warm")!!.parameter("Sync")!!.writable)
    }

    @Test fun `value check enforces type, range and the manufacturer step`() {
        val knob = MatriboxToneTransferCatalog.ManufacturerParameter("X", 0, 1, MatriboxToneTransferCatalog.Kind.DECIMAL, 0.1f, 10f, 0.1f, true, null)
        assertEquals(null, MatriboxToneTransferCatalog.valueProblem(knob, 3.7f))
        assertTrue(MatriboxToneTransferCatalog.valueProblem(knob, 3.75f) != null)
        assertTrue(MatriboxToneTransferCatalog.valueProblem(knob, 10.1f) != null)
        val flag = MatriboxToneTransferCatalog.ManufacturerParameter("F", 0, 1, MatriboxToneTransferCatalog.Kind.FLAG, 0f, 1f, null, true, null)
        assertEquals(null, MatriboxToneTransferCatalog.valueProblem(flag, 1f))
        assertTrue(MatriboxToneTransferCatalog.valueProblem(flag, 0.5f) != null)
        assertTrue(MatriboxToneTransferCatalog.valueProblem(flag, Float.NaN) != null)
    }

    private companion object {
        const val EXPECTED_MODELS = 167 // 166 named manufacturer algorithms + the hand-captured (blocked) User IR 7
    }
}
