import 'dart:convert';
import 'dart:io';

import 'package:wyrmtone/presets/matribox_capture_classifier.dart';
import 'package:wyrmtone/presets/raw_preset_backup_format.dart';

/// Offline analyzer for the planned Matribox 1 "big capture".
///
///   dart run tool/matribox_big_capture_analyzer.dart \
///     --report inspector-report.json \
///     [--catalog assets/catalog/matribox_preset_catalog.json] \
///     [--reference tool/reference/matribox_ii_pro_reference.json] \
///     [--before backup.json --after backup.json] [--output report.md]
///
/// --report is the JSON written by tool/matribox_capture_inspector.dart.
/// Reads files only; never talks to a device. II-Pro reference matches are
/// comparison hints, never Matribox 1 confirmations.
void main(List<String> args) {
  String? value(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final reportPath = value('--report');
  if (reportPath == null) {
    stderr.writeln('Missing --report inspector-report.json.');
    exitCode = 2;
    return;
  }
  final report =
      jsonDecode(File(reportPath).readAsStringSync()) as Map<String, Object?>;
  final messages = <CaptureMessage>[
    for (final capture in (report['captures'] as List).cast<Map<String, Object?>>())
      for (final m in (capture['messages'] as List).cast<Map<String, Object?>>())
        CaptureMessage.fromReport(m),
  ];
  final catalogFile = File(
    value('--catalog') ?? 'assets/catalog/matribox_preset_catalog.json',
  );
  final catalog = <CatalogModel>[
    if (catalogFile.existsSync())
      for (final a
          in ((jsonDecode(catalogFile.readAsStringSync()) as Map)['algorithms']
                  as List)
              .cast<Map>())
        CatalogModel(
          category: a['category'] as String,
          name: a['name'] as String,
          code: a['code'] as int,
        ),
  ];
  final referencePath = value('--reference');
  final references = <ReferenceFamily>[
    if (referencePath != null && File(referencePath).existsSync())
      for (final r
          in (jsonDecode(File(referencePath).readAsStringSync()) as List)
              .cast<Map<String, Object?>>())
        ReferenceFamily.fromJson(r),
  ];

  final result = classifyCapture(messages, catalog: catalog);
  final out = StringBuffer()
    ..writeln('# Matribox 1 big capture: offline classification')
    ..writeln()
    ..writeln(
      'Host->device messages: ${result.messageCount}. Labels other than '
      '`parameterWrite` are hypotheses.',
    )
    ..writeln()
    ..writeln('## Clusters (length + command header)')
    ..writeln(
      '| cluster | family | n | ms | variable byte positions | '
      'II-Pro reference (hint only) |',
    )
    ..writeln('|---|---|---:|---|---|---|');
  for (final c in result.clusters) {
    final match = references.isEmpty ? null : crossCorrelate(c, references);
    final hint = match == null
        ? '-'
        : '${match.match.name}'
              '${match.reference == null ? '' : ' (${match.reference!.id})'}';
    out.writeln(
      '| ${c.key} | ${c.family.name} | ${c.messages.length} | '
      '${c.firstMs.toStringAsFixed(0)}-${c.lastMs.toStringAsFixed(0)} | '
      '${c.variablePositions.join(',')} | $hint |',
    );
  }
  out
    ..writeln()
    ..writeln('## Parameter-write runs (slot, algorithm code, index)')
    ..writeln('| slot | block | code | catalog | index | n | first -> last | min..max |')
    ..writeln('|---:|---|---|---|---:|---:|---|---|');
  for (final r in result.runs) {
    final vals = r.values;
    final models = r.models.isEmpty
        ? 'NOT IN CATALOG'
        : r.models.map((m) => '${m.category}/${m.name}').join(' or ');
    out.writeln(
      '| ${r.slot} | ${matriboxSlotBlocks[r.slot] ?? '?'} | '
      '0x${r.algorithmCode.toRadixString(16).padLeft(8, '0')} | $models | '
      '${r.parameterIndex} | ${vals.length} | ${vals.first} -> ${vals.last} | '
      '${vals.reduce((a, b) => a < b ? a : b)}..'
      '${vals.reduce((a, b) => a > b ? a : b)} |',
    );
  }
  out
    ..writeln()
    ..writeln('## Algorithm-code changes per slot (parameter writes)')
    ..writeln('Non-parameter clusters between two writes with different codes:');
  for (final c in result.codeChanges) {
    final between = c.betweenClusters.isEmpty
        ? '(no other message)'
        : c.betweenClusters.toSet().join('; ');
    out.writeln(
      '- slot ${c.slot} ${c.atMs.toStringAsFixed(0)} ms: 0x${c.fromCode.toRadixString(16)} '
      '-> 0x${c.toCode.toRadixString(16)} via $between',
    );
  }
  out
    ..writeln()
    ..writeln('## Model selections (12 10 SS 00 01)')
    ..writeln('| ms | slot | block | code | catalog |')
    ..writeln('|---:|---:|---|---|---|');
  for (final e in result.modelSelections) {
    out.writeln(
      '| ${e.timestampMs.toStringAsFixed(0)} | ${e.slot} | ${matriboxSlotBlocks[e.slot] ?? '?'} | '
      '0x${e.code.toRadixString(16).padLeft(8, '0')} | '
      '${e.models.isEmpty ? 'NOT IN CATALOG' : e.models.map((m) => '${m.category}/${m.name}').join(' or ')} |',
    );
  }
  out
    ..writeln()
    ..writeln('## Preset metadata scalars (12 11 00 00 NN, 18 bytes)');
  for (final e in result.metadata) {
    out.writeln('- ${e.timestampMs.toStringAsFixed(0)} ms selector ${e.selector}: ${e.value}');
  }
  out
    ..writeln()
    ..writeln('## MIDI control changes (3 bytes)');
  for (final e in result.controlChanges) {
    out.writeln(
      '- ${e.timestampMs.toStringAsFixed(0)} ms status 0x${e.status.toRadixString(16)} '
      'controller 0x${e.controller.toRadixString(16)} value 0x${e.value.toRadixString(16)}',
    );
  }
  out
    ..writeln()
    ..writeln('## Timeline (bursts separated by > 2 s idle)')
    ..writeln('| start s | end s | n | content |')
    ..writeln('|---:|---:|---:|---|');
  for (final b in result.bursts) {
    out.writeln(
      '| ${(b.startMs / 1000).toStringAsFixed(1)} | ${(b.endMs / 1000).toStringAsFixed(1)} | ${b.count} | ${b.summary} |',
    );
  }
  out
    ..writeln()
    ..writeln('## Name candidates');
  for (final n in result.nameCandidates) {
    out.writeln('- ${n.timestampMs.toStringAsFixed(0)} ms `${n.text}` in ${n.clusterKey}');
  }

  final beforePath = value('--before');
  final afterPath = value('--after');
  if (beforePath != null && afterPath != null) {
    final before = decodeRawPresetBackupJson(File(beforePath).readAsStringSync());
    final after = decodeRawPresetBackupJson(File(afterPath).readAsStringSync());
    out
      ..writeln()
      ..writeln('## BEFORE/AFTER raw changes (position only)');
    for (final r in rawChangeRanges(before.rawParts, after.rawParts)) {
      out.writeln('- $r (${r.length} bytes)');
    }
  }
  final outputPath = value('--output');
  if (outputPath == null) {
    stdout.write(out);
  } else {
    File(outputPath).writeAsStringSync(out.toString());
  }
}
