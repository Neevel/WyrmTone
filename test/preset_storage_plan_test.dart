import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/presets/canonical_preset.dart';
import 'package:wyrmtone/presets/device_catalog.dart';
import 'package:wyrmtone/presets/preset_backup.dart';
import 'package:wyrmtone/presets/preset_exchange.dart';
import 'package:wyrmtone/presets/preset_validation.dart';
import 'package:wyrmtone/presets/preset_write_plan.dart';

import 'preset_domain_test.dart' show fixture;

void main() {
  final catalog = DevicePresetCatalog(
    objectMap(
      jsonDecode(
        File('assets/catalog/matribox_preset_catalog.json').readAsStringSync(),
      ),
    ),
  );
  final validator = PresetValidator(catalog);
  final exchange = PresetExportService(validator);
  test('Versioned exchange semantic roundtrip and stable serialization', () {
    final preset = fixture(), at = DateTime.utc(2026);
    final text = exchange.export(preset, exportedAt: at);
    expect(text, exchange.export(preset, exportedAt: at));
    expect(
      canonicalJson(exchange.import(text).toJson()),
      canonicalJson(preset.toJson()),
    );
    final data = objectMap(jsonDecode(text))..['schemaVersion'] = 2;
    expect(() => exchange.import(jsonEncode(data)), throwsFormatException);
    expect(text, isNot(contains('base64')));
    expect(text, isNot(contains('localUri')));
    expect(text, isNot(contains('serialNumber')));
  });
  test('Credentials, private paths and binary fields rejected', () {
    for (final text in [
      'C:\\Users\\private\\test',
      'content://private/file',
      '/storage/emulated/0/private',
      'Bearer secret',
      't3k_secret',
    ]) {
      expect(
        () => exchange.export(
          fixture().copyWith(name: text),
          exportedAt: DateTime.utc(2026),
        ),
        throwsFormatException,
      );
    }
    final data = objectMap(
      jsonDecode(exchange.export(fixture(), exportedAt: DateTime.utc(2026))),
    )..['binary'] = 'hidden';
    expect(() => exchange.import(jsonEncode(data)), throwsFormatException);
  });
  test('Local atomic backups, duplicate, corruption, explicit deletion and restore', () async {
    final directory = await Directory.systemTemp.createTemp(
      'wyrmtone-backup-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = PresetBackupRepository(
      directory,
      clock: () => DateTime.utc(2026),
    );
    final first = await repository.save(fixture(), slotId: 'manual-test');
    final duplicate = await repository.save(fixture(), slotId: 'manual-test');
    expect(first.id, duplicate.id);
    expect((await repository.list()).backups.length, 1);
    expect(
      canonicalJson((await repository.restoreLocally(first.id)).toJson()),
      canonicalJson(fixture().toJson()),
    );
    await expectLater(
      repository.delete(first.id, confirmed: false),
      throwsStateError,
    );
    expect((await repository.list()).backups.length, 1);
    final file = File('${directory.path}/${first.id}.wyrmtone-backup.json');
    await file.writeAsString('{}');
    final listing = await repository.list();
    expect(listing.errors, isNotEmpty);
    expect(await file.exists(), isTrue);
    await expectLater(
      repository.save(fixture(), slotId: 'manual-test'),
      throwsFormatException,
    );
    await repository.delete(first.id, confirmed: true);
    expect(await file.exists(), isFalse);
  });
  test('Every complete write plan is blocked, including known Gain', () {
    final preset = fixture(), planner = PresetWritePlanner(validator);
    final empty = planner.plan(preset);
    expect(empty.transferAllowed, isFalse);
    expect(empty.blockers, contains('Kein ausdrücklich gewählter Zielslot.'));
    const slot = PresetSlot(
      id: 'manual-test',
      bank: 'local',
      position: '1',
      label: 'Local test',
      currentName: 'Local test',
      source: PresetSlotSource.manual,
    );
    expect(
      planner
          .plan(preset, slot: slot, explicitlySelected: true)
          .transferAllowed,
      isFalse,
    );
    final knownSlot = PresetSlot(
      id: 'manual-test',
      bank: 'local',
      position: '1',
      label: 'Local test',
      currentName: preset.name,
      source: PresetSlotSource.manual,
      currentPreset: preset,
      protected: false,
    );
    final backup = PresetBackup(
      id: presetHash(preset),
      at: DateTime.utc(2026),
      preset: preset,
      hash: presetHash(preset),
      origin: BackupOrigin.wyrmToneDraft,
      slotId: knownSlot.id,
    );
    final plan = planner.plan(
      preset,
      slot: knownSlot,
      backup: backup,
      explicitlySelected: true,
      uniqueConnectedTarget: true,
    );
    expect(plan.transferAllowed, isFalse);
    expect(plan.blockers.any((b) => b.contains('preset.transfer')), isTrue);
    expect(plan.confirmationRequired, isTrue);
    expect(
      const OfflineMatriboxPresetAdapter().capabilityFor('transfer').status,
      AdapterResultStatus.notConfirmed,
    );
  });
}
