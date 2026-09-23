import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/usb_controller.dart';
import '../devices/device_profile.dart';
import '../models/recommendation.dart';
import '../models/tone_target.dart';
import '../presets/matribox_transfer_slots.dart';
import '../sounds/sound_labels.dart';
import '../models/guitar_profile.dart';
import '../sounds/sound_session.dart';
import '../ui/preset_slot_picker.dart';
import '../ui/wyrm_components.dart';
import '../ui/wyrm_design.dart';
import 'preset_workspace_page.dart';
import 'sound_detail_page.dart';
import '../presets/device_catalog.dart';
import 'device_prepare_page.dart';

/// Opens "Dein Sound" for the current sound. After an app restart the local sound is rebuilt first;
/// if that is not possible the user gets a clear message instead of a broken screen.
Future<void> openYourSound(
  BuildContext context, {
  required RecommendationController controller,
  required SoundSession session,
  UsbController? usbController,
  VoidCallback? openProfile,
  Future<DevicePresetCatalog> Function()? loadCatalog,
}) async {
  final ok = await session.reopen();
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(session.notice ?? 'Dein Sound konnte nicht geöffnet werden.')));
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => YourSoundPage(controller: controller, session: session, usbController: usbController, openProfile: openProfile, loadCatalog: loadCatalog),
    ),
  );
}

/// The result of the sound flow: the sound for this guitar and tuning, what was adjusted, how it
/// sounds in words and bars, and (separately) what can be done with a device.
class YourSoundPage extends StatefulWidget {
  const YourSoundPage({required this.controller, required this.session, this.usbController, this.openProfile, this.loadCatalog, super.key});
  final RecommendationController controller;
  final SoundSession session;

  /// Shows "Empfangsgerät" connection status inline; null only in tests that do not exercise it.
  final UsbController? usbController;
  final VoidCallback? openProfile;

  /// Loads the device catalog (tests inject a file-based loader).
  final Future<DevicePresetCatalog> Function()? loadCatalog;

  @override
  State<YourSoundPage> createState() => _YourSoundPageState();
}

class _YourSoundPageState extends State<YourSoundPage> {
  RecommendationFeedback? _feedback;

  /// The intended target slot ("Speicherplatz"). Picking one never reads, backs up or writes
  /// anything by itself -- see [MatriboxTransferSlots]. There is deliberately no default: the user
  /// chooses a P11..P99 slot consciously.
  int? _selectedSlot;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.session]),
      builder: (context, _) {
        final c = widget.controller;
        final session = widget.session;
        final draft = c.offlineDraft;
        final selection = session.current;
        final definition = selection == null ? null : session.definitionOf(selection);
        if (draft == null || selection == null || definition == null) {
          return WyrmScaffold(
            title: 'Dein Sound',
            background: true,
            backgroundIntensity: WyrmBackgroundIntensity.medium,
            body: Padding(
              padding: WyrmTokens.pagePadding,
              child: WyrmEmptyState(
                title: 'Gerade ist kein Sound aktiv',
                message: 'Suche einen Sound und tippe auf „Sound verwenden“.',
                icon: Icons.graphic_eq,
                action: TextButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('Sound finden')),
              ),
            ),
          );
        }
        final theme = Theme.of(context);
        final metrics = soundMetricsOf({for (final e in draft.tone.values.entries) e.key: e.value}, definition.resolved);
        return WyrmScaffold(
          title: 'Dein Sound',
          background: true,
          backgroundIntensity: WyrmBackgroundIntensity.medium,
          body: ListView(
            key: const PageStorageKey('your-sound'),
            padding: WyrmTokens.pagePadding,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: WyrmTokens.contentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WyrmCard(
                        accent: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entryDisplayTitle(definition.entry), key: const Key('your-sound-title'), style: theme.textTheme.headlineSmall),
                            Text(entrySubtitle(definition.entry, session.vault!.taxonomy), style: theme.textTheme.bodyMedium),
                            const SizedBox(height: WyrmTokens.space12),
                            Wrap(
                              spacing: WyrmTokens.space8,
                              runSpacing: WyrmTokens.space4,
                              children: [
                                WyrmChip(c.selectedProfile?.name ?? draft.guitar.name, icon: Icons.graphic_eq),
                                WyrmChip(draft.tuning.label, icon: Icons.tune),
                                WyrmChip(selection.variant == null ? roleLabel(draft.role) : variantLabel(selection.variant!), icon: Icons.music_note),
                              ],
                            ),
                            const SizedBox(height: WyrmTokens.space12),
                            const Text('Dieser Sound ist auf deinem Gerät nur vorbereitet und noch nicht übertragen.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: WyrmTokens.space8),
                      Row(
                        children: [
                          Expanded(
                            child: WyrmSecondaryButton(
                              label: 'Anpassen',
                              icon: Icons.tune,
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => SoundDetailPage(
                                    controller: c,
                                    session: session,
                                    entryId: selection.entryId,
                                    seed: SoundSeed(variant: selection.variant, modifiers: selection.modifiers, effects: selection.effects, tuning: selection.tuning),
                                    openProfile: widget.openProfile,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: WyrmTokens.space8),
                          Expanded(
                            child: WyrmSecondaryButton(
                              label: 'Anderen Sound finden',
                              icon: Icons.search,
                              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                            ),
                          ),
                        ],
                      ),
                      const WyrmSectionHeader('So klingt er'),
                      WyrmCard(
                        child: Column(
                          key: const Key('your-sound-metrics'),
                          children: [for (final m in metrics) WyrmToneMetric(label: m.label, value: m.value)],
                        ),
                      ),
                      if (selection.modifiers.isNotEmpty || selection.effects.isNotEmpty) ...[
                        const WyrmSectionHeader('Deine Anpassungen'),
                        Wrap(
                          key: const Key('your-adjustments'),
                          spacing: WyrmTokens.space8,
                          runSpacing: WyrmTokens.space4,
                          children: [
                            for (final m in selection.modifiers) WyrmChip(modifierLabel(m)),
                            for (final e in selection.effects) WyrmChip(effectLabel(e)),
                          ],
                        ),
                      ],
                      const WyrmSectionHeader('Gerät', subtitle: 'Sound erstellen ist nicht dasselbe wie senden'),
                      WyrmCard(child: _device(context, draft)),
                      const WyrmSectionHeader('Mehr Optionen'),
                      _fineTune(context),
                      _sources(context, draft),
                      _chain(context, draft),
                      _origin(context, draft),
                      const SizedBox(height: WyrmTokens.space24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------------- device

  Future<void> _prepareForDevice(BuildContext context) async {
    final catalog = await (widget.loadCatalog ?? loadDevicePresetCatalog)();
    final recommendation = await widget.session.prepareForMatribox(catalog);
    if (!context.mounted) return;
    if (recommendation == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.session.notice ?? 'Der Sound konnte nicht vorbereitet werden.')));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DevicePreparePage(recommendation: recommendation, targetSlot: _selectedSlot, usbController: widget.usbController),
      ),
    );
  }

  Widget _device(BuildContext context, PresetDraft draft) {
    final c = widget.controller;
    final session = widget.session;
    final usb = widget.usbController;
    final isMatribox = draft.device == TargetDeviceId.matriboxOne;
    final slot = MatriboxTransferSlots.slot(_selectedSlot);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<TargetDeviceId>(
          key: ValueKey('device-${c.selectedTargetDevice.name}'),
          isExpanded: true,
          initialValue: c.selectedTargetDevice,
          decoration: const InputDecoration(labelText: 'Gerät'),
          items: [
            for (final d in toneDeviceAdapters) DropdownMenuItem(value: d.id, child: Text(d.displayName, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: c.offlineBusy
              ? null
              : (v) async {
                  if (v == null || v == c.selectedTargetDevice) return;
                  c.selectTargetDevice(v);
                  final sel = session.current;
                  if (sel != null) await session.use(sel, remember: false, selectedNamId: draft.selectedNamId);
                },
        ),
        if (isMatribox) ...[
          const SizedBox(height: WyrmTokens.space16),
          Text('Empfangsgerät', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: WyrmTokens.space4),
          Row(
            children: [
              Icon(
                Icons.graphic_eq,
                size: 18,
                color: usb?.connectionState == DeviceConnectionState.connected ? WyrmTokens.success : WyrmTokens.muted,
              ),
              const SizedBox(width: WyrmTokens.space8),
              Expanded(child: Text(usb?.primaryDeviceStatusLabel ?? 'Matribox 1', key: const Key('your-sound-device-status'))),
            ],
          ),
          const SizedBox(height: WyrmTokens.space12),
          Text('Speicherplatz', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: WyrmTokens.space4),
          OutlinedButton(
            key: const Key('your-sound-slot-picker'),
            onPressed: () async {
              final chosen = await PresetSlotPicker.pick(context, selected: _selectedSlot);
              if (chosen != null) setState(() => _selectedSlot = chosen);
            },
            child: Row(
              children: [
                Icon(slot?.approved == true ? Icons.check_circle_outline : Icons.lock_outline, size: 18),
                const SizedBox(width: WyrmTokens.space8),
                Expanded(child: Text(slot?.label ?? 'Speicherplatz wählen', textAlign: TextAlign.left)),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
          const SizedBox(height: WyrmTokens.space4),
          Text(
            MatriboxTransferSlots.blockedExplanation(_selectedSlot) ?? MatriboxTransferSlots.explanation,
            key: const Key('your-sound-slot-note'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: WyrmTokens.space12),
        FilledButton.icon(
          key: const Key('open-tone-transfer'),
          onPressed: c.offlineBusy ? null : () => _prepareForDevice(context),
          icon: const Icon(Icons.swap_horiz),
          label: Text(isMatribox ? 'Auf Matribox übertragen' : 'Für Gerät vorbereiten'),
        ),
        const SizedBox(height: WyrmTokens.space4),
        const Text('Zeigt dir zuerst, was auf der Matribox 1 daraus wird. Dabei wird noch nichts gesendet.', style: TextStyle(fontSize: 12)),
        if (!isMatribox)
          const Text('Für dieses Gerät gibt es nur eine Vorschau mit manuellen Einstellungen. Übertragen kannst du auf die Matribox 1.'),
        const SizedBox(height: WyrmTokens.space8),
        WyrmSecondaryButton(
          key: const Key('open-preset-workspace'),
          label: 'Speichern, vergleichen & planen',
          icon: Icons.rule_folder_outlined,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => PresetWorkspacePage(controller: c, library: session.tone3000)),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------------- more options

  Widget _fineTune(BuildContext context) {
    final c = widget.controller;
    final preview = c.offlinePreview;
    return ExpansionTile(
      key: const Key('fine-tune'),
      title: const Text('Klang nachschärfen'),
      subtitle: const Text('Zum Beispiel „zu schrill“ oder „Gate schneidet Noten ab“'),
      childrenPadding: const EdgeInsets.all(WyrmTokens.space12),
      children: [
        const Text('Wähle, was dich stört. Erst „Anwenden“ ändert deinen Sound.'),
        const SizedBox(height: WyrmTokens.space8),
        Wrap(
          spacing: WyrmTokens.space8,
          runSpacing: WyrmTokens.space4,
          children: [
            for (final f in RecommendationFeedback.values)
              WyrmChip(
                f.label,
                selected: _feedback == f && preview != null,
                onTap: () {
                  setState(() => _feedback = f);
                  c.previewCorrection(f);
                },
              ),
          ],
        ),
        if (preview != null && c.offlineDraft != null)
          Padding(
            padding: const EdgeInsets.only(top: WyrmTokens.space12),
            child: WyrmCard(
              accent: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Änderungsvorschau: ${_feedback?.label ?? 'Korrektur'}', style: Theme.of(context).textTheme.titleMedium),
                  for (final line in _differences(c.offlineDraft!, preview)) Text(line, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: WyrmTokens.space8),
                  Wrap(
                    spacing: WyrmTokens.space8,
                    children: [
                      FilledButton(key: const Key('offline-apply'), onPressed: c.applyCorrection, child: const Text('Anwenden')),
                      TextButton(onPressed: c.cancelCorrection, child: const Text('Abbrechen')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: WyrmTokens.space8),
        Wrap(
          spacing: WyrmTokens.space8,
          children: [
            OutlinedButton(key: const Key('offline-undo'), onPressed: c.canUndoCorrection ? c.undoCorrection : null, child: const Text('Rückgängig')),
            TextButton(key: const Key('offline-reset'), onPressed: c.resetCorrections, child: const Text('Ausgangsklang wiederherstellen')),
          ],
        ),
      ],
    );
  }

  Widget _sources(BuildContext context, PresetDraft draft) {
    final c = widget.controller;
    final session = widget.session;
    final nams = draft.candidates['NAM']!.where((n) => n.eligible);
    return ExpansionTile(
      key: const Key('sound-sources'),
      title: const Text('Klangquellen (Amp, NAM, IR)'),
      subtitle: const Text('Aus deiner lokalen Bibliothek, ohne automatische Downloads'),
      childrenPadding: const EdgeInsets.all(WyrmTokens.space12),
      children: [
        if (nams.isNotEmpty)
          DropdownButtonFormField<String?>(
            key: ValueKey('nam-${draft.selectedNamId}'),
            isExpanded: true,
            initialValue: draft.selectedNamId,
            decoration: const InputDecoration(labelText: 'Klangquelle vormerken'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Interner Amp')),
              for (final n in nams) DropdownMenuItem<String?>(value: n.id, child: Text(n.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: c.offlineBusy
                ? null
                : (v) async {
                    final sel = session.current;
                    if (sel != null) await session.use(sel, remember: false, selectedNamId: v);
                  },
          ),
        for (final category in ['AMP', 'NAM', 'IR'])
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: WyrmTokens.space12),
                child: Text('${category == 'AMP' ? 'Amp' : category}-Vorschläge', style: Theme.of(context).textTheme.titleMedium),
              ),
              if (draft.candidates[category]!.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: WyrmTokens.space8), child: Text('Nichts Passendes in deiner Bibliothek. Der Sound funktioniert auch mit dem internen Amp.'))
              else
                for (final candidate in draft.candidates[category]!)
                  ExpansionTile(
                    key: PageStorageKey('candidate-$category-${candidate.id}'),
                    tilePadding: EdgeInsets.zero,
                    title: Text('${candidate.name} · ${candidate.score}/100'),
                    subtitle: Text(candidate.eligible ? 'Verfügbar' : 'Nicht geeignet'),
                    children: [Text([...candidate.reasons, ...candidate.exclusions, ...candidate.uncertainties].join('\n'))],
                  ),
            ],
          ),
        for (final requirement in draft.searchRequirements) Padding(padding: const EdgeInsets.only(top: WyrmTokens.space8), child: Text(requirement)),
      ],
    );
  }

  String _blockLabel(String slot) => switch (slot) {
    'AMP' => 'Amp',
    'CAB' => 'Box / IR',
    'DLY' => 'Delay',
    'RVB' => 'Hall',
    _ => slot,
  };

  Widget _chain(BuildContext context, PresetDraft draft) => ExpansionTile(
    key: const Key('sound-chain'),
    title: const Text('Signalkette'),
    subtitle: const Text('Was in der Vorschau an- oder ausgeschaltet ist'),
    childrenPadding: const EdgeInsets.all(WyrmTokens.space12),
    children: [
      Wrap(
        spacing: WyrmTokens.space8,
        runSpacing: WyrmTokens.space4,
        children: [for (final b in draft.blocks) WyrmChip('${_blockLabel(b.slot)} ${b.enabled ? 'an' : 'aus'}', icon: b.enabled ? Icons.power_settings_new : Icons.power_off)],
      ),
      for (final block in draft.blocks)
        ExpansionTile(
          key: PageStorageKey('block-${block.slot}'),
          tilePadding: EdgeInsets.zero,
          title: Text('${_blockLabel(block.slot)} · ${block.model ?? 'Manuelle Empfehlung'}'),
          subtitle: Text(
            block.parameters.isEmpty ? 'Manuell einzustellen' : block.parameters.entries.take(2).map((e) => '${e.key} ${e.value}').join(' · '),
          ),
          children: [
            Text(block.note),
            for (final p in block.parameters.entries) ListTile(dense: true, title: Text('${p.key}: ${p.value}'), subtitle: Text(block.provenance[p.key] ?? '')),
          ],
        ),
      if (draft.selectedNamId != null) const Text('NAM vorgemerkt: der interne Amp ist deaktiviert.'),
    ],
  );

  Widget _origin(BuildContext context, PresetDraft draft) => ExpansionTile(
    key: const Key('sound-origin'),
    title: const Text('Herkunft & Details'),
    subtitle: const Text('Quelle, Begründungen und Verlauf'),
    childrenPadding: const EdgeInsets.all(WyrmTokens.space12),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Quelle: ${draft.tone.source}\nProfil v${draft.tone.version}'),
      const SizedBox(height: WyrmTokens.space8),
      Text([...draft.reasons, ...draft.warnings].join('\n')),
      for (var i = 0; i < draft.history.length; i++) Text('${i + 1}. ${draft.history[i]}'),
      const SizedBox(height: WyrmTokens.space8),
      Text('Klangziel (0 = wenig, 100 = viel)', style: Theme.of(context).textTheme.titleMedium),
      for (final e in draft.tone.values.entries) ListTile(dense: true, title: Text(toneLabel(e.key)), trailing: Text('${e.value}')),
    ],
  );

  List<String> _differences(PresetDraft before, PresetDraft after) {
    final result = <String>[];
    for (final dim in ToneDimension.values) {
      if (before.tone[dim] != after.tone[dim]) {
        result.add('${toneLabel(dim)}: ${before.tone[dim]} → ${after.tone[dim]}');
      }
    }
    for (var i = 0; i < before.blocks.length; i++) {
      final old = before.blocks[i], next = after.blocks[i];
      for (final p in old.parameters.entries) {
        if (p.value != next.parameters[p.key]) {
          result.add('${_blockLabel(old.slot)} ${p.key}: ${p.value} → ${next.parameters[p.key]}');
        }
      }
    }
    return result;
  }
}
