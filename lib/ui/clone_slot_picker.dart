import 'package:flutter/material.dart';

import '../services/matribox_clone_slot_policy.dart';
import 'wyrm_design.dart';

/// Product NAM transfer V1: the Matribox Clone-slot picker -- same shape as
/// [PresetSlotPicker] (`preset_slot_picker.dart`), sized for exactly 5 Clone
/// slots instead of P01..P99. Clone 1 and Clone 5 are hardware-confirmed and
/// selectable; Clone 2-4 are shown (so the picker honestly represents the
/// device's five Clone slots) but disabled and labelled "Noch nicht
/// verifiziert" -- never silently presented as equally certified. Picking
/// never reads, backs up or writes anything by itself.
abstract final class CloneSlotPicker {
  static Future<MatriboxTransferCloneSlot?> pick(BuildContext context, {required int? selectedCloneNumber}) =>
      showModalBottomSheet<MatriboxTransferCloneSlot>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _CloneSlotSheet(selectedCloneNumber: selectedCloneNumber),
      );
}

class _CloneSlotSheet extends StatelessWidget {
  const _CloneSlotSheet({required this.selectedCloneNumber});
  final int? selectedCloneNumber;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(child: Text('Clone-Slot auswählen', style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Schließen',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                MatriboxCloneSlotPolicy.explanation,
                key: const Key('clone-slot-picker-explanation'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final slot in MatriboxTransferCloneSlots.all)
            ListTile(
              key: Key('clone-slot-picker-${slot.cloneNumber}'),
              enabled: slot.approved,
              leading: Icon(
                slot.approved ? Icons.check_circle_outline : Icons.help_outline,
                color: slot.approved ? WyrmTokens.success : WyrmTokens.muted,
                semanticLabel: slot.approved ? 'Verfügbar' : 'Gesperrt',
              ),
              title: Text(slot.label),
              subtitle: Text(slot.capability.userLabel),
              selected: slot.cloneNumber == selectedCloneNumber,
              onTap: slot.approved ? () => Navigator.of(context).pop(slot) : null,
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
