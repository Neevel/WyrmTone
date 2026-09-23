package de.neevel.wyrmtone

/**
 * The fixed "Angels Don't Kill - Product Unlock" certification plan for User
 * P01: exactly the current Sound Engine V2 write plan against the known
 * certification source preset. Runs through the existing Full Live session,
 * port and codec (no second transport). Dart addresses it only by [PLAN_ID];
 * no operation, byte, slot, algorithm or index ever comes from the caller.
 * No Store, no `12 11`, no name/BPM/VOL, no NR/RVB parameter write.
 *
 * Models come from the editor catalog (Boost 0x1a in the FX slots, Sol 4x12
 * 0x0a000028 in CAB); the AMP parameters use the Sol 100 OD indices of the
 * original store capture. Must stay identical to
 * lib/presets/matribox_angels_product_plan.dart (golden test).
 */
object MatriboxAngelsPlan {
    const val PLAN_ID = "ANGELS_DONT_KILL_P01_V1"

    private const val SOL_100_OD = 0x07000047

    val operations: List<FullLiveOperation> = listOf(
        FullLiveOperation.BlockToggle(ChainSlot.FX1, enabled = false),
        FullLiveOperation.ModelSelect(ChainSlot.FX2, 0x0000001a, "Boost"),
        FullLiveOperation.BlockToggle(ChainSlot.FX2, enabled = true),
        FullLiveOperation.Parameter(ChainSlot.AMP, SOL_100_OD, 0, 67f, "Gain"),
        FullLiveOperation.Parameter(ChainSlot.AMP, SOL_100_OD, 1, 59f, "PRES"),
        FullLiveOperation.Parameter(ChainSlot.AMP, SOL_100_OD, 3, 41f, "Bass"),
        FullLiveOperation.Parameter(ChainSlot.AMP, SOL_100_OD, 4, 59f, "Middle"),
        FullLiveOperation.Parameter(ChainSlot.AMP, SOL_100_OD, 5, 61f, "Treble"),
        FullLiveOperation.ModelSelect(ChainSlot.CAB, 0x0a000028, "Sol 4x12"),
        FullLiveOperation.BlockToggle(ChainSlot.CAB, enabled = true),
        FullLiveOperation.BlockToggle(ChainSlot.EQ, enabled = false),
    )
}

/**
 * Which fixed certification plan a build may run. Each plan has its own
 * compile gate; the gates are mutually exclusive (build.gradle.kts), so at
 * most one plan is ever resolvable.
 */
object MatriboxCertificationPlans {
    fun operations(
        planId: String,
        fullLiveEnabled: Boolean,
        angelsEnabled: Boolean,
        familyExpansionEnabled: Boolean = false,
    ): List<FullLiveOperation>? =
        when {
            planId == MatriboxFullLivePlan.PLAN_ID && fullLiveEnabled -> MatriboxFullLivePlan.operations
            planId == MatriboxAngelsPlan.PLAN_ID && angelsEnabled -> MatriboxAngelsPlan.operations
            planId == MatriboxFamilyExpansionPlan.PLAN_ID && familyExpansionEnabled -> MatriboxFamilyExpansionPlan.operations
            else -> null
        }

    /** Operations the port may send in this build. */
    fun permitted(
        fullLiveEnabled: Boolean,
        angelsEnabled: Boolean,
        familyExpansionEnabled: Boolean = false,
    ): List<FullLiveOperation> =
        (if (fullLiveEnabled) MatriboxFullLivePlan.operations else emptyList()) +
            (if (angelsEnabled) MatriboxAngelsPlan.operations else emptyList()) +
            (if (familyExpansionEnabled) MatriboxFamilyExpansionPlan.operations else emptyList())
}
