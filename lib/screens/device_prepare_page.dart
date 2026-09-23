import 'package:flutter/material.dart';

import '../controllers/usb_controller.dart';
import '../presets/matribox_chain_slot.dart';
import '../presets/matribox_hardware_evidence.dart';
import '../presets/matribox_target_preset.dart';
import '../presets/matribox_tone_transfer_pipeline.dart';
import '../presets/matribox_transfer_slots.dart';
import '../presets/matribox_translation_result.dart';
import '../presets/tone_intent.dart';
import '../ui/preset_slot_picker.dart';
import '../ui/wyrm_components.dart';
import '../ui/wyrm_design.dart';
import 'tone_transfer_page.dart';

/// "Für Gerät vorbereiten": what the created sound becomes on the Matribox 1, before anything
/// happens at the device. Nothing is read or sent here; the next step (a separate, confirmed flow)
/// reads the device, makes a backup and shows the exact changes.
class DevicePreparePage extends StatefulWidget {
  const DevicePreparePage({required this.recommendation, this.targetSlot, this.usbController, this.transferPage, super.key});
  final ToneTransferRecommendation recommendation;

  /// The intended target ("Dein Sound" picks it; it can also be picked or changed here). There is no
  /// default: only a product-writable slot P11..P99 lets "Mit der Matribox fortfahren" continue;
  /// P01..P10 are protected and a missing slot stays blocked.
  final int? targetSlot;

  /// Passed on to [ToneTransferPage] so a disconnect there goes STALE immediately.
  final UsbController? usbController;

  /// Builds the transfer step for the chosen slot (tests substitute a channel-free page).
  final Widget Function(BuildContext context, int targetSlot)? transferPage;

  @override
  State<DevicePreparePage> createState() => _DevicePreparePageState();

  static const _blockNames = {
    MatriboxChainSlot.fx1: 'Pedal 1 (FX1)',
    MatriboxChainSlot.fx2: 'Pedal 2 (FX2)',
    MatriboxChainSlot.amp: 'Amp',
    MatriboxChainSlot.nr: 'Gate (NR)',
    MatriboxChainSlot.cab: 'Box (CAB)',
    MatriboxChainSlot.eq: 'EQ',
    MatriboxChainSlot.mod: 'Modulation',
    MatriboxChainSlot.dly: 'Delay',
    MatriboxChainSlot.rvb: 'Hall (RVB)',
  };

  static String parameterWord(String semantic) => switch (semantic) {
    'gain' => 'Gain',
    'presence' => 'Präsenz',
    'bass' => 'Bass',
    'middle' => 'Mitten',
    'treble' => 'Höhen',
    'mix' => 'Mix',
    'fdbk' => 'Feedback',
    _ => semantic,
  };
}

class _DevicePreparePageState extends State<DevicePreparePage> {
  late int? _targetSlot = widget.targetSlot;

  ToneTransferRecommendation get recommendation => widget.recommendation;

  MatriboxTranslationResult _analyze() => MatriboxTranslationAnalyzer.analyze(
    target: recommendation.target,
    library: recommendation.library,
    ledger: MatriboxHardwareLedger.product(),
  );

  @override
  Widget build(BuildContext context) {
    final result = _analyze();
    final theme = Theme.of(context);
    final rec = recommendation;
    final slot = MatriboxTransferSlots.slot(_targetSlot);
    final writable = MatriboxSlotPolicy.isProductWritable(_targetSlot);
    return WyrmScaffold(
      title: 'Für Gerät vorbereiten',
      background: true,
      backgroundIntensity: WyrmBackgroundIntensity.dim,
      body: ListView(
        key: const PageStorageKey('device-prepare'),
        padding: WyrmTokens.pagePadding,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: WyrmTokens.contentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Für Matribox 1', style: theme.textTheme.headlineSmall),
                  Text(
                    '${rec.recipe.song} · ${rec.draft.guitar.name} · ${rec.draft.tuning.name == rec.recipe.tuning ? _tuningLabel(rec) : rec.recipe.tuning}',
                    key: const Key('prepare-sound'),
                  ),
                  const SizedBox(height: WyrmTokens.space12),
                  _verdict(context, result),
                  const WyrmSectionHeader('Das wird eingestellt'),
                  WyrmCard(
                    child: Column(
                      key: const Key('prepare-blocks'),
                      children: [for (final b in result.blocks) _blockRow(context, b)],
                    ),
                  ),
                  if (result.unsupportedIntents.isNotEmpty || result.blockedOperations.isNotEmpty) ...[
                    const WyrmSectionHeader('Nicht oder nur teilweise übertragen', subtitle: 'Das lässt WyrmTone bewusst weg oder ändert es nicht'),
                    WyrmCard(
                      child: Column(
                        key: const Key('prepare-limits'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final l in [...result.blockedOperations, ...result.unsupportedIntents])
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: WyrmTokens.space4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('! '),
                                  Expanded(child: Text('${DevicePreparePage._blockNames[l.slot]}: ${l.text}')),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const WyrmSectionHeader('Zielplatz'),
                  WyrmCard(
                    key: const Key('prepare-slot'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(slot == null ? 'Kein Speicherplatz gewählt' : 'Preset ${slot.label}', style: theme.textTheme.titleMedium),
                        const SizedBox(height: WyrmTokens.space4),
                        Text(MatriboxTransferSlots.blockedExplanation(_targetSlot) ?? MatriboxTransferSlots.explanation),
                        const SizedBox(height: WyrmTokens.space8),
                        if (writable)
                          const Text('Dieser Platz wird verändert. Vorher wird er gelesen und gesichert, und du bestätigst jede Übertragung ausdrücklich.'),
                        const SizedBox(height: WyrmTokens.space8),
                        OutlinedButton.icon(
                          key: const Key('prepare-slot-picker'),
                          onPressed: () async {
                            final chosen = await PresetSlotPicker.pick(context, selected: _targetSlot);
                            if (chosen != null && mounted) setState(() => _targetSlot = chosen);
                          },
                          icon: const Icon(Icons.swap_vert),
                          label: Text(slot == null ? 'Speicherplatz wählen' : 'Speicherplatz ändern'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: WyrmTokens.space16),
                  const Text('Bis hierhin wurde nichts an dein Gerät gesendet.', key: Key('prepare-nothing-sent')),
                  const SizedBox(height: WyrmTokens.space8),
                  FilledButton.icon(
                    key: const Key('prepare-continue'),
                    onPressed: result.transferable && writable
                        ? () {
                            // The transfer page is bound to the slot chosen at this moment.
                            final chosen = _targetSlot!;
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) =>
                                    widget.transferPage?.call(context, chosen) ??
                                    ToneTransferPage(recommendation: recommendation, targetSlot: chosen, usbController: widget.usbController),
                              ),
                            );
                          }
                        : null,
                    icon: const Icon(Icons.usb),
                    label: const Text('Mit der Matribox fortfahren'),
                  ),
                  if (!result.transferable || !writable)
                    Padding(
                      padding: const EdgeInsets.only(top: WyrmTokens.space8),
                      child: Text(
                        [
                          if (!result.transferable) ...result.criticalReasons,
                          if (!writable) MatriboxTransferSlots.blockedExplanation(_targetSlot) ?? MatriboxTransferSlots.noSlotExplanation,
                        ].join(' '),
                        key: const Key('prepare-blocked-note'),
                      ),
                    ),
                  ExpansionTile(
                    key: const Key('prepare-details'),
                    title: const Text('Technische Details'),
                    childrenPadding: const EdgeInsets.all(WyrmTokens.space12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final b in result.blocks)
                        if (rec.target[b.slot].report != null) Text('${b.slot.label}: ${rec.target[b.slot].report!.why.join(' ')}\n${rec.target[b.slot].report!.notRepresented.join('\n')}'),
                    ],
                  ),
                  const SizedBox(height: WyrmTokens.space24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _tuningLabel(ToneTransferRecommendation rec) => rec.draft.tuning.name;

  Widget _verdict(BuildContext context, MatriboxTranslationResult result) {
    final (icon, title, text) = switch (result.overallCompatibility) {
      MatriboxCompatibility.full => (Icons.check_circle_outline, 'Gut für die Matribox 1 geeignet', 'Alle wichtigen Bestandteile des Sounds lassen sich auf die Matribox übertragen.'),
      MatriboxCompatibility.partial => (
        Icons.info_outline,
        'Übertragbar mit Einschränkungen',
        'Der Sound lässt sich sinnvoll übertragen. Einzelne Teile werden nur angenähert oder nicht übertragen; sie sind unten aufgeführt.',
      ),
      MatriboxCompatibility.blocked => (Icons.block, 'Aktuell nicht übertragbar', 'Für diesen Sound fehlt etwas Wichtiges, damit er sicher übertragen werden kann.'),
    };
    return WyrmCard(
      key: Key('prepare-verdict-${result.overallCompatibility.name}'),
      accent: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: WyrmTokens.ember),
          const SizedBox(width: WyrmTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: WyrmTokens.space4),
                Text(text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blockRow(BuildContext context, BlockPreview b) {
    final mark = switch (b.state) {
      RecipeBlockState.incomplete => '!',
      RecipeBlockState.unchanged => '·',
      _ => b.quality == ApproximationQuality.limitedApproximation ? '~' : '✓',
    };
    final what = switch (b.state) {
      RecipeBlockState.off => 'aus',
      RecipeBlockState.unchanged => 'bleibt unverändert',
      RecipeBlockState.incomplete => 'kein passendes Modell',
      RecipeBlockState.defined =>
        '${b.model ?? ''}${b.parameters.isEmpty ? '' : ' · ${b.parameters.entries.map((e) => '${DevicePreparePage.parameterWord(e.key)} ${e.value}').join(', ')}'}',
    };
    return Semantics(
      label: '${DevicePreparePage._blockNames[b.slot]}: $what',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WyrmTokens.space4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 24, child: Text(mark)),
            SizedBox(width: 120, child: Text(DevicePreparePage._blockNames[b.slot]!, style: Theme.of(context).textTheme.bodyMedium)),
            Expanded(child: Text(what, key: Key('prepare-block-${b.slot.label}'), style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}
