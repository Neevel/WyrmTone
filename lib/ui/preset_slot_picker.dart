import 'package:flutter/material.dart';

import '../presets/matribox_transfer_slots.dart';
import 'wyrm_design.dart';

/// The mobile-friendly P01..P99 picker: a searchable bottom sheet instead of a 99-button grid. Every
/// slot is shown. P01..P10 are protected play presets: visible, marked as protected and not
/// selectable. Only P11..P99 can be picked as a transfer target. Picking never reads, backs up or
/// writes anything by itself.
abstract final class PresetSlotPicker {
  static Future<int?> pick(BuildContext context, {required int? selected}) => showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PresetSlotSheet(selected: selected),
  );
}

class _PresetSlotSheet extends StatefulWidget {
  const _PresetSlotSheet({required this.selected});
  final int? selected;

  @override
  State<_PresetSlotSheet> createState() => _PresetSlotSheetState();
}

class _PresetSlotSheetState extends State<_PresetSlotSheet> {
  final _query = TextEditingController();
  late String _filter = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needle = _filter.trim().toUpperCase().replaceAll('P', '');
    final slots = [
      for (final slot in MatriboxTransferSlots.userSlots)
        if (needle.isEmpty || slot.label.contains(needle) || slot.number.toString() == needle) slot,
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Expanded(child: Text('Speicherplatz wählen', style: Theme.of(context).textTheme.titleLarge)),
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(MatriboxTransferSlots.explanation, key: const Key('slot-picker-explanation'), style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  key: const Key('slot-picker-search'),
                  controller: _query,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'P11 … P99', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  key: const Key('slot-picker-list'),
                  itemCount: slots.length,
                  itemBuilder: (context, index) {
                    final slot = slots[index];
                    return ListTile(
                      key: Key('slot-picker-${slot.label}'),
                      enabled: slot.approved,
                      leading: Icon(slot.approved ? Icons.check_circle_outline : Icons.lock_outline, color: slot.approved ? WyrmTokens.success : WyrmTokens.muted),
                      title: Text(slot.label),
                      subtitle: Text(slot.approved ? 'Für Übertragungen verfügbar' : 'Geschützt – wird nicht überschrieben'),
                      selected: slot.number == widget.selected,
                      onTap: slot.approved ? () => Navigator.of(context).pop(slot.number) : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
