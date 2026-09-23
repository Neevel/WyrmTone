package de.neevel.wyrmtone

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MatriboxFamilyExpansionPlanTest {
    private val hash = "a".repeat(64)
    private val target = CertificationTarget("USER", 1, hash)
    private val operations = MatriboxFamilyExpansionPlan.operations

    private fun hex(bytes: ByteArray) = bytes.joinToString(" ") { "%02x".format(it) }

    private fun slot(op: FullLiveOperation): ChainSlot = when (op) {
        is FullLiveOperation.ModelSelect -> op.slot
        is FullLiveOperation.Parameter -> op.slot
        is FullLiveOperation.BlockToggle -> op.slot
    }

    /** payload of a 34 B parameter write: code(4) index(2) float(4), nibble-paired from byte 13. */
    private fun payload(op: FullLiveOperation): ByteBuffer {
        val m = MatriboxFullLiveCodec.encode(op)
        val raw = ByteArray(10) { i -> ((m[13 + 2 * i].toInt() shl 4) or m[14 + 2 * i].toInt()).toByte() }
        return ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
    }

    private fun param(slot: ChainSlot, name: String) =
        operations.filterIsInstance<FullLiveOperation.Parameter>().single { it.slot == slot && it.name == name }

    private fun eligibility() = ProbeEligibility(
        enabled = true, connection = "usb/box", vendor = 0x84ef, product = 0x0054, uniqueUsb = true,
        uniqueMidi = true, directlyMapped = true, deviceOpen = true, expectedInput = true, monitoring = false,
    )

    private class Recorder(var failAt: Int? = null) : MatriboxFullLiveSendPort {
        val sent = mutableListOf<FullLiveOperation>()
        var opened = 0
        override fun sendOperation(operation: FullLiveOperation) {
            if (failAt == sent.size) throw IllegalStateException("Transport-Fehler.")
            sent.add(operation)
        }
        override fun close() {}
    }

    private fun session(recorder: Recorder, plan: List<FullLiveOperation>?) = MatriboxFullLiveCertificationSession(
        eligibility = { eligibility() },
        openSendPort = { recorder.opened++; recorder },
        pause = {},
        preflight = MatriboxFamilyExpansionValidator::preflightMessage,
        planResolver = { id -> if (id == MatriboxFamilyExpansionPlan.PLAN_ID) plan else null },
    )

    // ---- plan content -------------------------------------------------------------------------

    @Test fun `the plan is the exact semantic list in chain order, 23 operations including Tier B`() {
        assertEquals(23, operations.size)
        assertEquals(9, operations.count { it is FullLiveOperation.ModelSelect })
        assertEquals(11, operations.count { it is FullLiveOperation.Parameter })
        assertEquals(3, operations.count { it is FullLiveOperation.BlockToggle })
        assertEquals(
            listOf(
                "FX1 MODEL Boost",
                "FX2 MODEL Boost", "FX2 PARAM Gain = 23.0", "FX2 PARAM Bright = 1.0",
                "AMP MODEL Sol 100 OD",
                "NR MODEL Gate 2", "NR PARAM THRE = 31.0", "NR BLOCK ON",
                "CAB MODEL Sol 4x12", "CAB PARAM VOL = 43.0",
                "EQ MODEL Guitar EQ", "EQ PARAM 400Hz = -23.0", "EQ BLOCK ON",
                "MOD MODEL Chorus A", "MOD PARAM Rate = 3.7",
                "DLY MODEL Warm", "DLY PARAM Time = 743.0", "DLY PARAM Trail = 1.0",
                "RVB MODEL Room", "RVB PARAM Mix = 23.0", "RVB PARAM Decay = 41.0", "RVB PARAM Trail = 1.0", "RVB BLOCK ON",
            ),
            operations.map { it.label },
        )
        assertEquals("FAMILY_EXPANSION_P01_V1", MatriboxFamilyExpansionPlan.PLAN_ID)
    }

    @Test fun `deterministic order - slots ascend, inside a slot select then parameters then block`() {
        assertEquals(operations.sortedBy { slot(it).ordinal }, operations)
        for (s in ChainSlot.values()) {
            val ranks = operations.filter { slot(it) == s }.map {
                when (it) {
                    is FullLiveOperation.ModelSelect -> 0
                    is FullLiveOperation.Parameter -> 1
                    is FullLiveOperation.BlockToggle -> 2
                }
            }
            assertEquals(ranks.sorted(), ranks)
        }
    }

    @Test fun `Tier B is part of the plan - FX1 Boost and AMP Sol 100 OD select`() {
        assertTrue(operations.contains(FullLiveOperation.ModelSelect(ChainSlot.FX1, 0x1a, "Boost")))
        assertTrue(operations.contains(FullLiveOperation.ModelSelect(ChainSlot.AMP, 0x07000047, "Sol 100 OD")))
    }

    @Test fun `every message equals the golden hex generated from the Dart plan`() {
        assertEquals(MatriboxFamilyExpansionGolden.messages, operations.map { hex(MatriboxFullLiveCodec.encode(it)) })
    }

    @Test fun `no Sync or TimeSync, no ATK Rel, no User IR, nothing outside the tested set`() {
        val names = operations.filterIsInstance<FullLiveOperation.Parameter>().map { it.name }
        assertFalse(names.any { it.contains("Sync") || it == "ATK" || it == "Rel" })
        assertFalse(operations.any { it is FullLiveOperation.ModelSelect && it.name.startsWith("User IR") })
    }

    // ---- encodings ----------------------------------------------------------------------------

    @Test fun `CAB VOL uses wire index 1 (catalog index 0)`() {
        assertEquals(1, payload(param(ChainSlot.CAB, "VOL")).getShort(4).toInt())
        assertEquals(1, param(ChainSlot.CAB, "VOL").index)
        assertEquals(43f, payload(param(ChainSlot.CAB, "VOL")).getFloat(6), 0f)
    }

    @Test fun `the CAB special case is not generalized to other slots`() {
        assertEquals(1, payload(param(ChainSlot.EQ, "400Hz")).getShort(4).toInt()) // EQ catalog index 1 = wire 1
        assertEquals(0, payload(param(ChainSlot.NR, "THRE")).getShort(4).toInt())
        assertEquals(0, payload(param(ChainSlot.FX2, "Gain")).getShort(4).toInt())
        assertEquals(4, payload(param(ChainSlot.DLY, "Trail")).getShort(4).toInt())
    }

    @Test fun `signed -23 decimal 3_7 and Time 743 encode as little-endian float32`() {
        assertEquals(java.lang.Float.floatToIntBits(-23f), payload(param(ChainSlot.EQ, "400Hz")).getInt(6))
        assertEquals(java.lang.Float.floatToIntBits(3.7f), payload(param(ChainSlot.MOD, "Rate")).getInt(6))
        assertEquals(743f, payload(param(ChainSlot.DLY, "Time")).getFloat(6), 0f)
    }

    @Test fun `wire index is the editor ID minus 1 - Boost Bright is wire 2, CAB VOL wire 1`() {
        assertEquals(2, payload(param(ChainSlot.FX2, "Bright")).getShort(4).toInt())
        assertEquals(2, param(ChainSlot.FX2, "Bright").index)
        assertEquals(1, param(ChainSlot.CAB, "VOL").index)
    }

    @Test fun `Bright on the catalog index 1 (the hidden parameter) is rejected before any send`() {
        val wrong = operations.toMutableList()
        wrong[3] = FullLiveOperation.Parameter(ChainSlot.FX2, 0x1a, 1, 1f, "Bright")
        assertZeroSends(wrong, "PARAMETER_INDEX_MISMATCH")
    }

    @Test fun `flags Bright and both Trails are float 1_0`() {
        for ((slot, name) in listOf(ChainSlot.FX2 to "Bright", ChainSlot.DLY to "Trail", ChainSlot.RVB to "Trail")) {
            assertEquals(0x3f800000, payload(param(slot, name)).getInt(6))
        }
    }

    @Test fun `block CC ON is 0xb1 controller value 0x00 for NR EQ RVB`() {
        val cc = operations.filterIsInstance<FullLiveOperation.BlockToggle>().map { hex(MatriboxFullLiveCodec.encode(it)) }
        assertEquals(listOf("b1 33 00", "b1 35 00", "b1 38 00"), cc)
    }

    @Test fun `no store, no 12 11 metadata, no 12 12 commit in any message`() {
        for (op in operations) {
            val bytes = MatriboxFullLiveCodec.encode(op)
            MatriboxFullLiveCodec.validate(bytes)
            if (bytes.size > 3) {
                assertEquals(0x12, bytes[8].toInt())
                assertEquals(0x10, bytes[9].toInt())
            }
        }
    }

    // ---- preflight: whole plan, zero sends ----------------------------------------------------

    @Test fun `the valid plan passes the preflight`() {
        assertNull(MatriboxFamilyExpansionValidator.preflightMessage(MatriboxFamilyExpansionPlan.PLAN_ID, operations, target))
        assertNull(MatriboxFamilyExpansionValidator.preflightMessage("OTHER_PLAN", emptyList(), null)) // not this test's plan
    }

    private fun assertZeroSends(bad: List<FullLiveOperation>, expected: String, t: CertificationTarget? = target) {
        assertNotNull(expected, MatriboxFamilyExpansionValidator.preflightMessage(MatriboxFamilyExpansionPlan.PLAN_ID, bad, t))
        assertTrue(
            MatriboxFamilyExpansionValidator.preflightMessage(MatriboxFamilyExpansionPlan.PLAN_ID, bad, t)!!.startsWith(expected),
        )
        val recorder = Recorder()
        val result = session(recorder, bad).run(MatriboxFamilyExpansionPlan.PLAN_ID, t)
        assertEquals("SAFETY_REJECTED", result["outcome"])
        assertTrue(recorder.sent.isEmpty())
        assertEquals(0, recorder.opened) // the port is not even opened
        assertEquals(0, result["completed"])
    }

    /** An invalid entry at the END of an otherwise valid list still yields ZERO sends. */
    private fun withBadLast(bad: FullLiveOperation) = operations + bad

    @Test fun `an invalid operation at the end rejects the whole plan before the first send`() {
        assertZeroSends(withBadLast(FullLiveOperation.Parameter(ChainSlot.RVB, 0x0c000000, 3, 1f, "Nope")), "ORDER_INVALID")
        // and in the middle (unknown parameter name) - still zero sends
        val mid = operations.toMutableList()
        mid[6] = FullLiveOperation.Parameter(ChainSlot.NR, 0x1d, 0, 31f, "Threshold")
        assertZeroSends(mid, "PARAMETER_UNKNOWN")
    }

    @Test fun `wrong slot, model or category is rejected`() {
        val wrongSlot = operations.toMutableList()
        wrongSlot[4] = FullLiveOperation.ModelSelect(ChainSlot.AMP, 0x1a, "Boost") // Boost is an FX model
        assertZeroSends(wrongSlot, "MODEL_WRONG_SLOT")
        val wrongModel = operations.toMutableList()
        wrongModel[18] = FullLiveOperation.ModelSelect(ChainSlot.RVB, 0x0b00000d, "Warm") // a delay in RVB
        assertZeroSends(wrongModel, "MODEL_WRONG_SLOT")
        val unknownCode = operations.toMutableList()
        unknownCode[5] = FullLiveOperation.ModelSelect(ChainSlot.NR, 0x0000001b, "Gate 1") // catalog-real, but not in this plan's table
        assertZeroSends(unknownCode, "MODEL_UNKNOWN")
        val nameMismatch = operations.toMutableList()
        nameMismatch[5] = FullLiveOperation.ModelSelect(ChainSlot.NR, 0x1d, "Gate 1")
        assertZeroSends(nameMismatch, "MODEL_UNKNOWN")
    }

    @Test fun `unknown parameter, wrong index or wrong model for the parameter is rejected`() {
        val unknown = operations.toMutableList()
        unknown[2] = FullLiveOperation.Parameter(ChainSlot.FX2, 0x1a, 0, 23f, "Drive")
        assertZeroSends(unknown, "PARAMETER_UNKNOWN")
        val wrongIndex = operations.toMutableList()
        wrongIndex[9] = FullLiveOperation.Parameter(ChainSlot.CAB, 0x0a000028, 0, 43f, "VOL") // catalog index instead of wire index
        assertZeroSends(wrongIndex, "PARAMETER_INDEX_MISMATCH")
        val notSelected = operations.toMutableList()
        notSelected[2] = FullLiveOperation.Parameter(ChainSlot.FX2, 0x0b00000d, 0, 23f, "Mix") // Warm never selected in FX2
        assertZeroSends(notSelected, "MODEL_WRONG_SLOT")
    }

    @Test fun `out of range, wrong type and non-finite values are rejected`() {
        for ((value, name, code, slotIndex) in listOf(
            Quad(100f, "Gain", 0x1a, 2), // > 99
            Quad(-1f, "Gain", 0x1a, 2), // negative number parameter
            Quad(2f, "Bright", 0x1a, 3), // flag must be 0/1
            Quad(Float.NaN, "Gain", 0x1a, 2),
            Quad(Float.POSITIVE_INFINITY, "Gain", 0x1a, 2),
        )) {
            val ops = operations.toMutableList()
            val index = if (name == "Bright") 1 else 0
            ops[slotIndex] = FullLiveOperation.Parameter(ChainSlot.FX2, code, index, value, name)
            assertNotNull(MatriboxFamilyExpansionValidator.preflightMessage(MatriboxFamilyExpansionPlan.PLAN_ID, ops, target))
            val recorder = Recorder()
            assertEquals("SAFETY_REJECTED", session(recorder, ops).run(MatriboxFamilyExpansionPlan.PLAN_ID, target)["outcome"])
            assertTrue(recorder.sent.isEmpty())
        }
        val time = operations.toMutableList()
        time[16] = FullLiveOperation.Parameter(ChainSlot.DLY, 0x0b00000d, 1, 5000f, "Time")
        assertZeroSends(time, "VALUE_OUT_OF_RANGE")
        val rate = operations.toMutableList()
        rate[14] = FullLiveOperation.Parameter(ChainSlot.MOD, 0x04000000, 1, 0.05f, "Rate")
        assertZeroSends(rate, "VALUE_OUT_OF_RANGE")
        val eq = operations.toMutableList()
        eq[11] = FullLiveOperation.Parameter(ChainSlot.EQ, 0x01000035, 1, -51f, "400Hz")
        assertZeroSends(eq, "VALUE_OUT_OF_RANGE")
    }

    private data class Quad(val value: Float, val name: String, val code: Int, val slotIndex: Int)

    @Test fun `duplicate, conflicting and misordered operations are rejected`() {
        assertZeroSends(operations + operations.first(), "DUPLICATE_OPERATION")
        val twice = operations.toMutableList()
        twice.add(2, FullLiveOperation.ModelSelect(ChainSlot.FX2, 0x1a, "Boost"))
        assertZeroSends(twice, "DUPLICATE_OPERATION")
        val toggleTwice = operations.toMutableList()
        toggleTwice.add(8, FullLiveOperation.BlockToggle(ChainSlot.NR, enabled = false))
        assertZeroSends(toggleTwice, "CONFLICTING_OPERATIONS")
        val reversed = operations.reversed()
        assertZeroSends(reversed, "ORDER_INVALID")
        val toggleFirst = operations.toMutableList()
        toggleFirst.add(5, toggleFirst.removeAt(7)) // NR ON before NR select/param
        assertZeroSends(toggleFirst, "ORDER_INVALID")
        assertZeroSends(emptyList(), "EMPTY_PLAN")
    }

    @Test fun `target must be User P01 with a SHA-256 backup hash`() {
        assertZeroSends(operations, "TARGET_MISSING", null)
        assertZeroSends(operations, "TARGET_NOT_ALLOWED", CertificationTarget("FACTORY", 1, hash))
        assertZeroSends(operations, "TARGET_NOT_ALLOWED", CertificationTarget("USER", 2, hash))
        assertZeroSends(operations, "BACKUP_HASH_INVALID", CertificationTarget("USER", 1, "abc"))
        assertZeroSends(operations, "BACKUP_HASH_INVALID", CertificationTarget("USER", 1, "A".repeat(64)))
    }

    @Test fun `the planId-only Full Live call cannot run this plan`() {
        val recorder = Recorder()
        val result = session(recorder, operations).run(MatriboxFamilyExpansionPlan.PLAN_ID) // no target
        assertEquals("SAFETY_REJECTED", result["outcome"])
        assertTrue(recorder.sent.isEmpty())
    }

    // ---- run behaviour ------------------------------------------------------------------------

    @Test fun `a valid run sends all 23 in order once, no retry`() {
        val recorder = Recorder()
        val s = session(recorder, operations)
        val ok = s.run(MatriboxFamilyExpansionPlan.PLAN_ID, target)
        assertEquals("SUCCESS", ok["outcome"])
        assertEquals(23, ok["completed"])
        assertEquals(operations, recorder.sent)
        assertEquals(1, recorder.opened)
        // a second run in the same connection is refused and sends nothing more
        assertEquals("SEND_FAILED", s.run(MatriboxFamilyExpansionPlan.PLAN_ID, target)["outcome"])
        assertEquals(23, recorder.sent.size)
    }

    @Test fun `the first send failure stops the run - completed, failed, notSent`() {
        val recorder = Recorder(failAt = 6)
        val result = session(recorder, operations).run(MatriboxFamilyExpansionPlan.PLAN_ID, target)
        assertEquals("SEND_FAILED", result["outcome"])
        assertEquals(6, result["completed"])
        assertEquals(6, result["failedIndex"])
        assertEquals(operations.take(6), recorder.sent)
        @Suppress("UNCHECKED_CAST")
        val statuses = (result["operations"] as List<Map<String, Any?>>).map { it["status"] }
        assertEquals(6, statuses.count { it == "SENT" })
        assertEquals(1, statuses.count { it == "FAILED" })
        assertEquals(16, statuses.count { it == "NOT_SENT" })
    }

    // ---- gates, no productive expansion -------------------------------------------------------

    @Test fun `the plan resolves only through its own gate and exposes only its own operations to the port`() {
        val id = MatriboxFamilyExpansionPlan.PLAN_ID
        assertNull(MatriboxCertificationPlans.operations(id, fullLiveEnabled = true, angelsEnabled = true))
        assertNull(MatriboxCertificationPlans.operations(id, true, true, familyExpansionEnabled = false))
        assertEquals(operations, MatriboxCertificationPlans.operations(id, false, false, familyExpansionEnabled = true))
        assertNull(MatriboxCertificationPlans.operations(MatriboxAngelsPlan.PLAN_ID, false, false, familyExpansionEnabled = true))
        assertNull(MatriboxCertificationPlans.operations(MatriboxFullLivePlan.PLAN_ID, false, false, familyExpansionEnabled = true))
        assertEquals(operations, MatriboxCertificationPlans.permitted(false, false, true))
        assertTrue(MatriboxCertificationPlans.permitted(false, false, false).isEmpty())
    }

    @Test fun `Angels stays exactly 11 operations without any family-expansion operation`() {
        assertEquals(11, MatriboxAngelsPlan.operations.size)
        assertEquals(MatriboxAngelsPlan.operations, MatriboxCertificationPlans.permitted(false, true))
        assertFalse(MatriboxAngelsPlan.operations.any { it is FullLiveOperation.Parameter && it.slot != ChainSlot.AMP })
    }

    @Test fun `the promoted productive table releases the plan operations except the bound Rate and Time`() {
        assertEquals(
            operations.filter { !(it is FullLiveOperation.Parameter && (it.name == "Rate" || it.name == "Time")) },
            operations.filter { MatriboxToneTransferCatalog.isConfirmed(it) },
        )
        // bind/Sync is conservatively blocked productively although the certification run wrote both
        assertFalse(MatriboxToneTransferCatalog.isConfirmed(param(ChainSlot.MOD, "Rate")))
        assertFalse(MatriboxToneTransferCatalog.isConfirmed(param(ChainSlot.DLY, "Time")))
    }

    @Test fun `the certification table agrees with the manufacturer table on every wire index`() {
        for (m in MatriboxFamilyExpansionCatalog.models) {
            for (slot in m.slots) {
                val manufacturer = MatriboxToneTransferCatalog.model(slot, m.name)!!
                assertEquals(m.code, manufacturer.code)
                for (p in m.parameters) assertEquals("${m.name}/${p.name}", p.wireIndex, manufacturer.parameter(p.name)!!.wireIndex)
            }
        }
    }
}
