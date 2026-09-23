// Regenerates the native manufacturer table and prints the reach statistics:
//   dart run tool/generate_native_manufacturer_catalog.dart
import 'dart:convert';
import 'dart:io';

import 'package:wyrmtone/presets/canonical_preset.dart';
import 'package:wyrmtone/presets/tone_intent.dart';
import 'package:wyrmtone/presets/device_catalog.dart';
import 'package:wyrmtone/presets/matribox_chain_slot.dart';
import 'package:wyrmtone/presets/matribox_tone_translator.dart';

import 'native_manufacturer_catalog.dart';

DevicePresetCatalog loadManufacturerCatalog() => DevicePresetCatalog(
  objectMap(jsonDecode(File('assets/catalog/matribox_preset_catalog.json').readAsStringSync())),
);

/// Per chain slot, the catalog parameter names for which the Tone translator has an explicit,
/// NON-heuristic mapping rule of that slot's block role (the role -> slot table mirrors the translator).
Map<MatriboxChainSlot, Set<String>> semanticallyMapped() {
  const roleSlot = {
    ToneBlockRole.fx1: MatriboxChainSlot.fx1,
    ToneBlockRole.fx2: MatriboxChainSlot.fx2,
    ToneBlockRole.gate: MatriboxChainSlot.nr,
    ToneBlockRole.amp: MatriboxChainSlot.amp,
    ToneBlockRole.cab: MatriboxChainSlot.cab,
    ToneBlockRole.eq: MatriboxChainSlot.eq,
    ToneBlockRole.modulation: MatriboxChainSlot.mod,
    ToneBlockRole.delay: MatriboxChainSlot.dly,
    ToneBlockRole.reverb: MatriboxChainSlot.rvb,
  };
  final result = <MatriboxChainSlot, Set<String>>{};
  for (final entry in matriboxMappingRules.entries) {
    final slot = roleSlot[entry.key];
    if (slot == null) continue;
    for (final rule in entry.value.values) {
      if (rule.heuristic) continue;
      result.putIfAbsent(slot, () => {}).addAll([rule.catalogName, if (rule.alternative != null) rule.alternative!]);
    }
  }
  return result;
}

void main(List<String> args) {
  final catalog = loadManufacturerCatalog();
  File(nativeCatalogPath).writeAsStringSync(renderNativeManufacturerCatalog(catalog));
  stdout.writeln('written $nativeCatalogPath');
  for (final line in computeReach(catalog, semanticallyMapped()).lines) {
    stdout.writeln(line);
  }
}
