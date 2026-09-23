package de.neevel.wyrmtone

/**
 * The one predetermined Full Live plan for User P01: capture-confirmed model
 * selections, parameter writes and two block toggles, exactly the values of
 * the editor big capture. Dart addresses it only by [PLAN_ID]; no operation,
 * byte, slot, algorithm or index ever comes from the caller. No Store, no
 * commit, no metadata, no User IR.
 *
 * Must stay identical to lib/presets/matribox_full_live_plan.dart; both are
 * tested against the same 25 real captured messages.
 */
object MatriboxFullLivePlan {
    const val PLAN_ID = "FULL_LIVE_P01_V1"

    private fun model(slot: ChainSlot, code: Int, name: String) =
        FullLiveOperation.ModelSelect(slot, code, name)

    private fun param(slot: ChainSlot, code: Int, index: Int, value: Float, name: String) =
        FullLiveOperation.Parameter(slot, code, index, value, name)

    val operations: List<FullLiveOperation> = listOf(
        model(ChainSlot.FX1, 0x03000000, "Skreamer"),
        param(ChainSlot.FX1, 0x03000000, 0, 23f, "Gain"),
        model(ChainSlot.FX2, 0x03000009, "Blues OD"),
        param(ChainSlot.FX2, 0x03000009, 1, 61f, "Tone"),
        model(ChainSlot.AMP, 0x07000035, "Brit 800"),
        param(ChainSlot.AMP, 0x07000035, 0, 17f, "Gain"),
        param(ChainSlot.AMP, 0x07000035, 1, 67f, "PRES"),
        model(ChainSlot.NR, 0x0000001d, "Gate 2"),
        param(ChainSlot.NR, 0x0000001d, 0, 31f, "THRE"),
        model(ChainSlot.CAB, 0x0a000022, "BritGN 4x12"),
        param(ChainSlot.CAB, 0x0a000022, 1, 43f, "VOL"),
        model(ChainSlot.EQ, 0x0100003a, "Bass EQ"),
        param(ChainSlot.EQ, 0x0100003a, 0, 17f, "50Hz"),
        param(ChainSlot.EQ, 0x0100003a, 1, -23f, "120Hz"),
        model(ChainSlot.MOD, 0x04000011, "Flanger"),
        param(ChainSlot.MOD, 0x04000011, 1, 3.7f, "Rate"),
        param(ChainSlot.MOD, 0x04000011, 4, 1f, "Sync"),
        model(ChainSlot.DLY, 0x0b000006, "Sweep"),
        param(ChainSlot.DLY, 0x0b000006, 0, 17f, "Mix"),
        param(ChainSlot.DLY, 0x0b000006, 7, 1f, "Trail"),
        model(ChainSlot.RVB, 0x0c000008, "Mod RVB"),
        param(ChainSlot.RVB, 0x0c000008, 0, 23f, "Mix"),
        param(ChainSlot.RVB, 0x0c000008, 5, 1f, "Trail"),
        FullLiveOperation.BlockToggle(ChainSlot.FX1, enabled = false),
        FullLiveOperation.BlockToggle(ChainSlot.FX2, enabled = true),
    )

    /** Pause after each message; longer after a model select so the device can apply defaults. */
    fun pauseAfterMillis(operation: FullLiveOperation): Long =
        if (operation is FullLiveOperation.ModelSelect) 200L else 60L
}
