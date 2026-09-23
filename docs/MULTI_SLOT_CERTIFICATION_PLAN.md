# Multi-Slot Hardware Certification Plan (P11–P99) – NOT executed

Product rule (`lib/presets/matribox_transfer_slots.dart`, natively `MatriboxSlotPolicy.kt`):
P01–P10 are protected play presets and never a transfer target; P11–P99 are product writable
(`SlotCapability.productWritable`). The full productive path is slot-bound in software: read and
backup of the chosen slot, plan, native preflight (`targetSlot` 11..99 only), preset select
(index = preset number − 1), live write, manual save, readback of the same slot, verification.

Status of P11–P99: **PRODUCT_WRITABLE / SOFTWARE_VALIDATED**. `SlotCapability.hardwareCertified`
stays `false` for every slot until the hardware steps below have been run.

## What is still unproven on hardware

The addressing comes from protocol evidence (read Bank/Slot bytes seen for all 199 slots of the
editor enumeration; preset select index confirmed for 0x00/0x09/0x0A, `index = number − 1` via
Program Change for P01/P02/P10/P50/P99). Not yet observed with WyrmTone itself:

* the isolated Phase-D announce/ack + ten-part read for a slot other than P01,
* that the device has finished loading the selected preset after the preset select before the
  first live edit (native settle pause 500 ms),
* that live edits after the select land in the selected slot and survive the manual save,
* the saved-state readback/verification of a slot other than P01.

## Hardware steps (first P11, later a spread such as P12, P50, P99)

1. **Read** – fresh read + backup of the slot; decoded Bank/Slot must name the slot.
2. **Select** – preset select; the display must show the slot.
3. **Live write** – a small plan (e.g. the certified Angels operations).
4. **Manual save** – on the device, while the display shows the slot; no Store from WyrmTone.
5. **Readback** – fresh read of the same slot, compared against the target.
6. **Verify** – `ToneReadbackOutcome.certified`.

P01–P10 are never touched by these steps. Only after they pass for a slot range may its
`hardwareCertified` flag change. No hardware communication has happened for this plan yet.
