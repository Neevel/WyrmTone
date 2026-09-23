import 'dart:io';

import 'package:wyrmtone/presets/canonical_preset.dart';

import 'matribox_analyzer.dart';

/// Retains every occurrence of allowed factual attributes, including conflicts.
Map<String, Object?> normalizePresetCatalog(String xml) {
  final resource = readResource(xml, 'local-editor/algorithm.xml');
  Object? unique(ResourceNode node, String key, {bool numeric = false}) {
    final observations = node.attributes[key];
    if (observations == null) return null;
    final values = observations
        .map((e) => numeric ? e.normalized : e.raw.trim())
        .toSet();
    return values.length == 1 ? values.single : null;
  }

  Map<String, Object?> observations(ResourceNode node, List<String> keys) => {
    for (final key in keys)
      if (node.attributes.containsKey(key))
        key: [
          for (final e in node.attributes[key]!)
            {'raw': e.raw, 'position': e.position, 'normalized': e.normalized},
        ],
  };
  bool conflicts(ResourceNode node, List<String> keys) => keys.any(
    (key) =>
        (node.attributes[key]?.map((e) => e.raw.trim()).toSet().length ?? 0) >
        1,
  );
  const algorithmKeys = ['Name', 'Module', 'Code', 'Index'];
  const parameterKeys = [
    'Name',
    'idx',
    'ID',
    'Dmin',
    'Dmax',
    'default',
    'Step',
    'step',
    'Suffix',
    'Type',
    'valueType',
    'SubType',
    'bind',
  ];
  return {
    'schemaVersion': 1, 'targetDevice': 'matriboxOne',
    'sourceAttribution': 'Locally installed Sonicake editor algorithm.xml; factual metadata only; no resource redistribution.',
    'evidenceLevel': 'observed',
    'algorithms': [
      for (final category in resource.root.all('Catalog'))
        for (final algorithm in category.children.where((n) => n.name == 'Alg'))
          {
            'category': unique(category, 'Name'),
            'name': unique(algorithm, 'Name'),
            'code': unique(algorithm, 'Code', numeric: true),
            'xmlIndex': unique(algorithm, 'Index', numeric: true),
            'evidenceLevel': 'observed',
            'deviceCompatibility': 'localEditorReference',
            'conflict': conflicts(algorithm, algorithmKeys),
            if (conflicts(algorithm, algorithmKeys))
              'conflictingObservations': observations(algorithm, algorithmKeys),
            'parameters': [
              for (final parameter in algorithm.children.where(
                (n) => ['Knob', 'Switch', 'Combox'].contains(n.name),
              ))
                {
                  'name': unique(parameter, 'Name'),
                  'index': unique(parameter, 'idx', numeric: true),
                  'xmlId': unique(parameter, 'ID', numeric: true),
                  'minimum': unique(parameter, 'Dmin', numeric: true),
                  'maximum': unique(parameter, 'Dmax', numeric: true),
                  'default': unique(parameter, 'default', numeric: true),
                  'step':
                      unique(parameter, 'Step', numeric: true) ??
                      unique(parameter, 'step', numeric: true),
                  'unit': unique(parameter, 'Suffix'),
                  'xmlControlType': parameter.name,
                  'xmlType': unique(parameter, 'Type'),
                  'valueType': unique(parameter, 'valueType'),
                  'subType': unique(parameter, 'SubType'),
                  'bind': unique(parameter, 'bind'),
                  'menus': [
                    for (final menu in parameter.children.where((n) => n.name == 'Menu'))
                      {'id': unique(menu, 'ID', numeric: true), 'name': unique(menu, 'Name')},
                  ],
                  'evidenceLevel': 'observed',
                  'conflict': conflicts(parameter, parameterKeys),
                  if (conflicts(parameter, parameterKeys))
                    'conflictingObservations': observations(parameter, parameterKeys),
                },
            ],
          },
    ],
    // Full scanner diagnostics contain only the supplied symbolic source.
    'scannerWarnings': resource.warnings,
  };
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/generate_preset_catalog.dart <local algorithm.xml> <output.json>',
    );
    exitCode = 64;
    return;
  }
  final catalog = normalizePresetCatalog(File(args[0]).readAsStringSync());
  File(args[1]).writeAsStringSync('${canonicalJson(catalog, pretty: true)}\n');
  stdout.writeln(
    'Normalized ${(catalog['algorithms'] as List).length} algorithms; originals untouched.',
  );
}
