import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/tone3000_controller.dart';
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

Future<DevicePresetCatalog>? _catalogFuture;
Future<DevicePresetCatalog> loadDevicePresetCatalog() =>
    _catalogFuture ??= rootBundle
        .loadString('assets/catalog/matribox_preset_catalog.json')
        .then((text) => DevicePresetCatalog(objectMap(jsonDecode(text))));

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
          return ListView(
            padding: WyrmTokens.pagePadding,
            children: [
              if (message != null) Text(message!),
              const Text('Presetdaten werden lokal geladen …'),
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
                  '${preset.artist} · ${preset.song}\n${preset.guitarName} · ${preset.tuning} · ${preset.role}',
              child: WyrmCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final block in preset.blocks)
                      ExpansionTile(
                        title: Text(
                          '${block.order + 1}. ${block.type.name} · ${block.model ?? 'manuell'}',
                        ),
                        subtitle: Text(
                          '${block.enabled ? 'an' : 'aus'} · ${block.evidence.name} · ${validation.blocks[block.id]?.name}',
                        ),
                        children: [
                          for (final p in block.parameters)
                            ListTile(
                              title: Text(
                                '${p.name}: ${p.value}${p.unit ?? ''}',
                              ),
                              subtitle: Text(
                                'Index ${p.deviceIndex ?? 'unbekannt'} · ${p.evidence.name} · nur manuell',
                              ),
                            ),
                        ],
                      ),
                    for (final issue in validation.issues)
                      Text('${issue.severity.name}: ${issue.message}'),
                  ],
                ),
              ),
            ),
            WyrmSection(
              title: 'Änderungen zum Ausgangsvorschlag',
              child: WyrmCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: diff
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
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy ? null : () => _run(_save),
                    child: const Text('Entwurf sichern'),
                  ),
                  OutlinedButton(
                    key: const Key('preset-export'),
                    onPressed: busy ? null : () => _run(_export),
                    child: const Text('.wyrmtone.json exportieren'),
                  ),
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
                    ...plan.blockers.take(6).map(Text.new),
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
