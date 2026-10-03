import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/tone3000_controller.dart';
import '../models/tone_target.dart';
import '../presets/canonical_preset.dart';
import '../presets/device_catalog.dart';
import '../presets/draft_preset_adapter.dart';
import '../presets/preset_backup.dart';
import '../presets/preset_diff.dart';
import '../presets/preset_exchange.dart';
import '../presets/preset_exchange_channel.dart';
import '../presets/preset_validation.dart';
import '../presets/preset_write_plan.dart';
import '../ui/wyrm_design.dart';

String _blockTypeLabel(PresetBlockType type) => switch (type) {
  PresetBlockType.gate => 'Noise Gate',
  PresetBlockType.compressor => 'Kompressor',
  PresetBlockType.drive => 'Drive',
  PresetBlockType.amp => 'Verstärker',
  PresetBlockType.nam => 'NAM',
  PresetBlockType.cab => 'Boxensimulation',
  PresetBlockType.eq => 'Equalizer',
  PresetBlockType.modulation => 'Modulation',
  PresetBlockType.delay => 'Delay',
  PresetBlockType.reverb => 'Hall',
};

/// "dStandard" -> "D Standard", "dropC" -> "Drop C".
String _humanize(String raw) {
  final spaced = raw.replaceAllMapped(RegExp(r'(?<=[a-z])(?=[A-Z])'), (_) => ' ');
  return spaced.isEmpty ? spaced : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

/// `preset.role` is the serialized enum name; the label comes from the one shared source.
String _roleLabel(String raw) => SoundRole.values.asNameMap()[raw]?.label ?? _humanize(raw);

/// The same hint repeated for twelve parameters reads as noise: one line with a count.
List<String> _groupedIssues(List<PresetIssue> issues) {
  final counts = <String, int>{};
  for (final issue in issues) {
    final line = '${_severityLabel(issue.severity)}: ${issue.message}';
    counts[line] = (counts[line] ?? 0) + 1;
  }
  return [for (final e in counts.entries) e.value > 1 ? '${e.key} (${e.value}×)' : e.key];
}

String _severityLabel(IssueSeverity severity) => switch (severity) {
  IssueSeverity.error => 'Fehler',
  IssueSeverity.warning => 'Hinweis',
  IssueSeverity.information => 'Info',
};

class PresetWorkspacePage extends StatefulWidget {
  const PresetWorkspacePage({
    required this.controller,
    this.library,
    this.documents = const AndroidPresetDocumentService(),
    super.key,
  });
  final RecommendationController controller;
  final Tone3000Controller? library;
  final PresetDocumentService documents;
  @override
  State<PresetWorkspacePage> createState() => _PresetWorkspacePageState();
}

class _PresetWorkspacePageState extends State<PresetWorkspacePage> {
  late final DateTime createdAt = DateTime.now().toUtc();
  DateTime modifiedAt = DateTime.now().toUtc();
  Object? _lastDraft;
  DevicePresetCatalog? catalog;
  CanonicalPreset? imported;
  PresetBackup? backup;
  String? selectedSlot, message;
  bool slotConfirmed = false, busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await loadDevicePresetCatalog();
      if (mounted) setState(() => catalog = loaded);
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Gerätekatalog konnte nicht geladen werden.');
      }
    }
  }

  CanonicalPreset? _current() {
    if (imported != null) return imported;
    final draft = widget.controller.offlineDraft;
    if (draft == null || catalog == null) return null;
    if (!identical(_lastDraft, draft)) {
      _lastDraft = draft;
      modifiedAt = DateTime.now().toUtc();
    }
    return DraftPresetAdapter(catalog!).convert(
      draft,
      createdAt: createdAt,
      modifiedAt: modifiedAt,
      nams: widget.library?.namCaptures ?? const [],
    );
  }

  CanonicalPreset? _baseline() {
    final draft = widget.controller.offlineOriginalDraft;
    if (draft == null || catalog == null) return null;
    return DraftPresetAdapter(catalog!).convert(
      draft,
      createdAt: createdAt,
      modifiedAt: createdAt,
      nams: widget.library?.namCaptures ?? const [],
    );
  }

  Future<void> _run(Future<String> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await action();
      if (mounted) setState(() => message = result);
    } on FormatException catch (e) {
      if (mounted) setState(() => message = e.message);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => message = e.message ?? 'Dateizugriff fehlgeschlagen.');
      }
    } catch (_) {
      if (mounted) setState(() => message = 'Lokale Aktion fehlgeschlagen.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<PresetExportService> _exchange() async =>
      PresetExportService(PresetValidator(catalog!));
  Future<String> _save() async {
    final preset = _current()!;
    final root = await getApplicationDocumentsDirectory();
    final repo = PresetBackupRepository(
      Directory('${root.path}/preset_backups'),
    );
    backup = await repo.save(preset);
    return 'Lokaler WyrmTone-Entwurf gesichert. Kein Geräte-Backup.';
  }

  Future<String> _export() async {
    final preset = _current()!, service = await _exchange();
    final text = service.export(preset, exportedAt: DateTime.now().toUtc());
    final ok = await widget.documents.export(
      text,
      '${preset.id}.wyrmtone.json',
    );
    return ok ? 'Presetdatei gespeichert.' : 'Export abgebrochen.';
  }

  Future<String> _import() async {
    final text = await widget.documents.import();
    if (text == null) return 'Import abgebrochen.';
    final service = await _exchange();
    imported = service.import(text);
    return 'Presetdatei geprüft und als lokaler Entwurf geöffnet.';
  }

  @override
  Widget build(BuildContext context) => WyrmScaffold(
    title: 'Preset planen',
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final preset = _current(), baseline = _baseline();
        if (catalog == null || preset == null) {
          // "Loading" only while the catalog is really loading; with no active sound there is
          // nothing to plan, and saying so beats waiting forever.
          final noSound = catalog != null && imported == null && widget.controller.offlineDraft == null;
          return ListView(
            padding: WyrmTokens.pagePadding,
            children: [
              if (message != null) Text(message!),
              Text(
                noSound
                    ? 'Gerade ist kein Sound aktiv. Wähle zuerst einen Sound und tippe auf „Sound verwenden“.'
                    : 'Presetdaten werden lokal geladen …',
                key: Key(noSound ? 'preset-workshop-no-sound' : 'preset-workshop-loading'),
              ),
            ],
          );
        }
        final validator = PresetValidator(catalog!);
        final validation = validator.validate(preset);
        final diff = baseline == null
            ? const <PresetChange>[]
            : const PresetDiffEngine().compare(baseline, preset);
        final slots = [
          const PresetSlot(
            id: 'local-test-a',
            bank: 'lokal',
            position: 'A',
            label: 'Lokaler Testslot A',
            currentName: 'Unbekannt',
            source: PresetSlotSource.manual,
          ),
          const PresetSlot(
            id: 'local-test-b',
            bank: 'lokal',
            position: 'B',
            label: 'Lokaler Testslot B',
            currentName: 'Unbekannt',
            source: PresetSlotSource.manual,
          ),
        ];
        final selected = slots.where((s) => s.id == selectedSlot).firstOrNull;
        final plan = PresetWritePlanner(validator).plan(
          preset,
          slot: selected == null
              ? null
              : PresetSlot(
                  id: selected.id,
                  bank: selected.bank,
                  position: selected.position,
                  label: selected.label,
                  currentName: selected.currentName,
                  source: selected.source,
                  protected: !slotConfirmed,
                ),
          backup: backup,
          explicitlySelected: selected != null && slotConfirmed,
        );
        return ListView(
          padding: WyrmTokens.pagePadding,
          children: [
            WyrmStatusBadge(
              validation.status,
              warning: !validation.exportAllowed,
            ),
            const SizedBox(height: 8),
            const WyrmStatusBadge(
              'Nicht für Geräteübertragung freigegeben',
              warning: true,
            ),
            WyrmSection(
              title: preset.name,
              subtitle:
                  '${preset.artist} · ${preset.song}\n${preset.guitarName} · ${_humanize(preset.tuning)} · ${_roleLabel(preset.role)}',
              child: WyrmCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final block in preset.blocks)
                      ExpansionTile(
                        title: Text(
                          '${block.order + 1}. ${_blockTypeLabel(block.type)} · ${block.model ?? 'manuell einstellen'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(block.enabled ? 'an' : 'aus'),
                        children: [
                          for (final p in block.parameters)
                            ListTile(
                              title: Text(
                                '${p.name}: ${p.value}${p.unit ?? ''}',
                              ),
                            ),
                          // Evidence level, device index and readiness are internal bookkeeping,
                          // not something a guitarist needs while planning a preset.
                          ExpansionTile(
                            key: Key('preset-block-technical-${block.id}'),
                            title: const Text('Technische Details'),
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Nachweisstufe: ${block.evidence.name} · Bereitschaft: ${validation.blocks[block.id]?.name}'),
                                    for (final p in block.parameters)
                                      Text('${p.name}: Index ${p.deviceIndex ?? 'unbekannt'} · ${p.evidence.name} · nur manuell'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    if (validation.issues.isNotEmpty)
                      ExpansionTile(
                        key: const Key('preset-issues'),
                        tilePadding: EdgeInsets.zero,
                        title: Text('Prüfhinweise (${validation.issues.length})'),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final line in _groupedIssues(validation.issues)) Text(line),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            WyrmSection(
              title: 'Änderungen zum Ausgangsvorschlag',
              child: WyrmCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: diff.where((d) => d.before != d.after).isEmpty
                      ? const [Text('Keine Änderungen gegenüber dem Vorschlag.')]
                      : diff
                            .where((d) => d.before != d.after)
                            .map(
                              (d) => Text(
                                '${d.path}: ${d.before ?? '—'} → ${d.after ?? '—'}',
                              ),
                            )
                            .toList(),
                ),
              ),
            ),
            WyrmSection(
              title: 'Lokaler Austausch & Sicherung',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: busy ? null : () => _run(_save),
                    child: const Text('Entwurf sichern'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('preset-export'),
                    onPressed: busy ? null : () => _run(_export),
                    child: const Text('.wyrmtone.json exportieren'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('preset-import'),
                    onPressed: busy ? null : () => _run(_import),
                    child: const Text('.wyrmtone.json importieren'),
                  ),
                ],
              ),
            ),
            WyrmSection(
              title: 'Zielslot planen',
              subtitle: 'Presetplätze konnten noch nicht sicher vom Gerät gelesen werden. Explizite lokale Testliste.',
              child: WyrmCard(
                child: Column(
                  children: [
                    for (final slot in slots)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(slot.label),
                            const Text(
                              'Manuell angelegt · Inhalt unbekannt · kein Gerätezugriff',
                            ),
                            const SizedBox(height: 6),
                            OutlinedButton(
                              onPressed: () => setState(() {
                                selectedSlot = slot.id;
                                slotConfirmed = false;
                                backup = null;
                              }),
                              child: Text(
                                selectedSlot == slot.id
                                    ? 'Ausgewählt'
                                    : 'Wählen',
                              ),
                            ),
                          ],
                        ),
                      ),
                    CheckboxListTile(
                      value: slotConfirmed,
                      title: const Text(
                        'Lokalen Testslot ausdrücklich für die Planung auswählen',
                      ),
                      subtitle: const Text(
                        'Nur Planung – noch keine Übertragung',
                      ),
                      onChanged: selected == null
                          ? null
                          : (v) => setState(() => slotConfirmed = v == true),
                    ),
                    if (plan.blockers.isNotEmpty)
                      ExpansionTile(
                        key: const Key('preset-blockers'),
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Technische Details'),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [for (final blocker in plan.blockers.take(6)) Text(blocker)],
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    FilledButton(
                      key: const Key('preset-transfer-disabled'),
                      onPressed: null,
                      child: const Text('Übertragung nicht verfügbar'),
                    ),
                    const Text(
                      'Die vollständige Matribox-Presetübertragung ist noch nicht protokollseitig bestätigt.',
                    ),
                  ],
                ),
              ),
            ),
            if (message != null) Text(message!),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zum Entwurf zurück'),
            ),
          ],
        );
      },
    ),
  );
}
