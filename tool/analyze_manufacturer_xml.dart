// Read-only analysis of the manufacturer's algorithm.xml (Sonicake Matribox 1 /
// QME-50 editor resource). Everything in the report is derived directly from
// the XML; nothing is guessed. Never writes the XML.
//
//   dart run tool/analyze_manufacturer_xml.dart <algorithm.xml> <report.md> [<report.json>]
import 'dart:convert';
import 'dart:io';

import 'matribox_analyzer.dart';

class P {
  P(this.tag, this.attrs, this.menus);
  final String tag;
  final Map<String, String> attrs;
  final List<Map<String, String>> menus;
  String? get name => attrs['Name']?.trim();
  int? get idx => int.tryParse(attrs['idx'] ?? '');
  int? get id => int.tryParse(attrs['ID'] ?? '');
}

class A {
  A(this.module, this.attrs, this.params);
  final String module;
  final Map<String, String> attrs;
  final List<P> params;
  String get name => (attrs['Name'] ?? '').trim();
  String get code => attrs['Code'] ?? '';
}

Map<String, String> firstAttrs(ResourceNode n) => {
  for (final e in n.attributes.entries) e.key: e.value.first.raw,
};

Map<String, int> count(Iterable<String> values) {
  final m = <String, int>{};
  for (final v in values) {
    m[v] = (m[v] ?? 0) + 1;
  }
  return Map.fromEntries(m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Usage: dart run tool/analyze_manufacturer_xml.dart <algorithm.xml> <report.md> [<report.json>]');
    exitCode = 64;
    return;
  }
  final xml = File(args[0]).readAsStringSync();
  final resource = readResource(xml, 'manufacturer/algorithm.xml');
  final algorithms = <A>[];
  for (final catalog in resource.root.all('Catalog')) {
    final module = catalog.value('Name')?.trim() ?? '?';
    for (final alg in catalog.children.where((n) => n.name == 'Alg')) {
      final params = <P>[];
      for (final p in alg.children.where((n) => const ['Knob', 'Switch', 'Combox'].contains(n.name))) {
        params.add(P(p.name, firstAttrs(p), [for (final m in p.children.where((c) => c.name == 'Menu')) firstAttrs(m)]));
      }
      algorithms.add(A(module, firstAttrs(alg), params));
    }
  }

  final all = [for (final a in algorithms) for (final p in a.params) (a, p)];
  final buf = StringBuffer();
  final json = <String, Object?>{};
  void h(String t) => buf.writeln('\n## $t\n');
  String tag(A a, P p) => '${a.module} ${a.name.isEmpty ? '(blank name, code ${a.code})' : a.name}/${p.name}';

  buf.writeln('# algorithm.xml – Herstelleranalyse (generiert, read-only)\n');
  buf.writeln('Quelle: `algorithm.xml` des Sonicake-Editors, ausschließlich gelesen. Erzeugt mit `tool/analyze_manufacturer_xml.dart`.');

  h('Umfang');
  final modules = count(algorithms.map((a) => a.module));
  buf.writeln('- Algorithmen: **${algorithms.length}** (${modules.entries.map((e) => '${e.key} ${e.value}').join(', ')})');
  buf.writeln('- Parameter: **${all.length}**');
  json['algorithms'] = algorithms.length;
  json['parameters'] = all.length;
  json['modules'] = modules;

  h('idx vs. ID − 1');
  final equal = all.where((e) => e.$2.idx != null && e.$2.id != null && e.$2.idx == e.$2.id! - 1).length;
  final differ = all.where((e) => e.$2.idx != null && e.$2.id != null && e.$2.idx != e.$2.id! - 1).toList();
  buf.writeln('- idx == ID − 1: **$equal**');
  buf.writeln('- idx != ID − 1: **${differ.length}**');
  json['idxEqualsIdMinus1'] = equal;
  json['idxDiffersFromIdMinus1'] = differ.length;
  final gapAlgorithms = algorithms.where((a) => a.params.any((p) => p.idx != null && p.id != null && p.idx != p.id! - 1)).toList();
  buf.writeln('- Algorithmen mit ID-Lücken (Einträge): **${gapAlgorithms.length}**');
  final gapByModule = count(gapAlgorithms.map((a) => a.module));
  buf.writeln('  - je Modul: ${gapByModule.entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  final blankGap = gapAlgorithms.where((a) => a.name.isEmpty).length;
  buf.writeln('  - davon mit leerem Namen (User IR): $blankGap');
  json['gapAlgorithms'] = gapAlgorithms.length;
  json['gapAlgorithmsByModule'] = gapByModule;
  buf.writeln('\nAlle Parameter mit idx != ID − 1 (Modul Name/Parameter: idx → ID → Wire):');
  final namedDiffer = differ.where((e) => e.$1.name.isNotEmpty).toList();
  for (final e in namedDiffer) {
    buf.writeln('- ${tag(e.$1, e.$2)}: idx ${e.$2.idx} → ID ${e.$2.id} → Wire ${e.$2.id! - 1}');
  }
  buf.writeln('- (+ ${differ.length - namedDiffer.length} Einträge ohne Namen, User IR)');

  h('Strukturprüfung der IDs');
  final dupId = <String>[], dupIdx = <String>[], idLe0 = <String>[], missingId = <String>[], nonNumeric = <String>[], missingIdx = <String>[];
  final gapsInside = <String>[];
  final maxIds = <int>[];
  for (final a in algorithms) {
    final ids = <int>[];
    for (final p in a.params) {
      final raw = p.attrs['ID'];
      if (raw == null) {
        missingId.add('${a.module} ${a.name}/${p.name}');
      } else if (p.id == null) {
        nonNumeric.add('${a.module} ${a.name}/${p.name}: "$raw"');
      } else {
        ids.add(p.id!);
        if (p.id! <= 0) idLe0.add('${a.module} ${a.name}/${p.name}: ${p.id}');
      }
      if (p.attrs['idx'] == null || p.idx == null) missingIdx.add('${a.module} ${a.name}/${p.name}');
    }
    if (ids.toSet().length != ids.length) dupId.add('${a.module} ${a.name}');
    final idxs = [for (final p in a.params) if (p.idx != null) p.idx!];
    if (idxs.toSet().length != idxs.length) dupIdx.add('${a.module} ${a.name}');
    if (ids.isNotEmpty) {
      final maxId = ids.reduce((x, y) => x > y ? x : y);
      maxIds.add(maxId);
      final missing = [for (var i = 1; i <= maxId; i++) if (!ids.contains(i)) i];
      if (missing.isNotEmpty) gapsInside.add('${a.module} ${a.name.isEmpty ? '(blank ${a.code})' : a.name}: fehlende IDs $missing');
    }
  }
  buf.writeln('- doppelte IDs innerhalb eines Algorithmus: ${dupId.length}${dupId.isEmpty ? '' : ' → ${dupId.join(', ')}'}');
  buf.writeln('- doppelte idx innerhalb eines Algorithmus: ${dupIdx.length}${dupIdx.isEmpty ? '' : ' → ${dupIdx.join(', ')}'}');
  buf.writeln('- ID <= 0: ${idLe0.length}${idLe0.isEmpty ? '' : ' → ${idLe0.join(', ')}'}');
  buf.writeln('- Parameter ohne ID: ${missingId.length}${missingId.isEmpty ? '' : ' → ${missingId.take(20).join(', ')}'}');
  buf.writeln('- Parameter ohne/mit nichtnumerischem idx: ${missingIdx.length}');
  buf.writeln('- nichtnumerische IDs: ${nonNumeric.length}${nonNumeric.isEmpty ? '' : ' → ${nonNumeric.take(20).join(', ')}'}');
  buf.writeln('- Algorithmen mit fehlenden IDs im Bereich 1..maxID: **${gapsInside.length}**');
  buf.writeln('- maximale ID: ${maxIds.isEmpty ? '-' : maxIds.reduce((x, y) => x > y ? x : y)} (Verteilung maxID → Algorithmen: ${count(maxIds.map((e) => '$e')).entries.map((e) => '${e.key}:${e.value}').join(', ')})');
  json['duplicateIds'] = dupId.length;
  json['idLe0'] = idLe0.length;
  json['missingId'] = missingId.length;
  json['nonNumericId'] = nonNumeric.length;
  json['gapsInsideAlgorithms'] = gapsInside.length;
  json['maxId'] = maxIds.isEmpty ? null : maxIds.reduce((x, y) => x > y ? x : y);
  buf.writeln('\nFehlende IDs je Algorithmus (nicht User IR):');
  for (final g in gapsInside.where((g) => !g.contains('(blank'))) {
    buf.writeln('- $g');
  }

  h('Parameter-Typen');
  buf.writeln('- Tag: ${count(all.map((e) => e.$2.tag)).entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  buf.writeln('- Type: ${count(all.map((e) => '${e.$2.tag}/Type=${e.$2.attrs['Type']}')).entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  buf.writeln('- valueType: ${count(all.map((e) => e.$2.attrs['valueType'] ?? '(fehlt)')).entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  buf.writeln('- SubType: ${count(all.map((e) => e.$2.attrs['SubType'] ?? '(fehlt)')).entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  buf.writeln('- Suffix: ${count(all.map((e) => e.$2.attrs['Suffix'] ?? '(fehlt)')).entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  buf.writeln('- Step: ${count(all.map((e) => e.$2.attrs['Step'] ?? e.$2.attrs['step'] ?? '(fehlt)')).entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  final attrKeys = <String>{for (final e in all) ...e.$2.attrs.keys};
  buf.writeln('- Attribute an Parametern: ${(attrKeys.toList()..sort()).join(', ')}');
  final algKeys = <String>{for (final a in algorithms) ...a.attrs.keys};
  buf.writeln('- Attribute an Algorithmen: ${(algKeys.toList()..sort()).join(', ')}');
  json['tags'] = count(all.map((e) => e.$2.tag));
  json['valueType'] = count(all.map((e) => e.$2.attrs['valueType'] ?? '(fehlt)'));
  json['bind'] = count(all.map((e) => e.$2.attrs['bind'] ?? '(fehlt)'));

  h('bind');
  final bound = all.where((e) => e.$2.attrs['bind'] != null).toList();
  buf.writeln('- bind-Verteilung: ${count(all.map((e) => e.$2.attrs['bind'] ?? '(fehlt)')).entries.map((e) => '${e.key} ${e.value}').join(', ')}');
  buf.writeln('- gebundene Parameter: **${bound.length}** in ${bound.map((e) => e.$1).toSet().length} Algorithmen');
  for (final e in bound) {
    final targetExists = e.$1.params.any((p) => p.name == e.$2.attrs['bind']);
    buf.writeln('- ${tag(e.$1, e.$2)} → bind="${e.$2.attrs['bind']}" (Ziel im selben Algorithmus: ${targetExists ? 'ja' : 'NEIN'}), valueType=${e.$2.attrs['valueType'] ?? '-'}');
  }
  final syncSwitches = all.where((e) => e.$2.name == 'Sync' || e.$2.attrs['SubType'] == 'Power').toList();
  buf.writeln('\nSync-/Power-Schalter (Ziel der Bindung): ${syncSwitches.length}');
  for (final e in syncSwitches) {
    buf.writeln('- ${tag(e.$1, e.$2)} idx ${e.$2.idx} ID ${e.$2.id} SubType=${e.$2.attrs['SubType'] ?? '-'}');
  }
  json['boundParameters'] = bound.length;
  json['syncSwitches'] = syncSwitches.length;

  h('Wertebereiche (Dmin/Dmax)');
  final noMin = all.where((e) => e.$2.tag == 'Knob' && e.$2.attrs['Dmin'] == null).length;
  final noMax = all.where((e) => e.$2.tag == 'Knob' && e.$2.attrs['Dmax'] == null).length;
  buf.writeln('- Knobs ohne Dmin: $noMin, ohne Dmax: $noMax');
  final range = count(all.where((e) => e.$2.tag == 'Knob').map((e) => '${e.$2.attrs['Dmin']}..${e.$2.attrs['Dmax']}'));
  buf.writeln('- Bereiche (Knob): ${range.entries.map((e) => '${e.key} ×${e.value}').join(', ')}');
  buf.writeln('- Knobs mit Default außerhalb des Bereichs:');
  for (final e in all.where((e) => e.$2.tag == 'Knob')) {
    final d = double.tryParse(e.$2.attrs['default'] ?? '');
    final lo = double.tryParse(e.$2.attrs['Dmin'] ?? '');
    final hi = double.tryParse(e.$2.attrs['Dmax'] ?? '');
    if (d != null && lo != null && hi != null && (d < lo || d > hi)) buf.writeln('  - ${tag(e.$1, e.$2)}: default $d ∉ $lo..$hi');
  }

  h('Switch / Combox / Menu');
  for (final t in const ['Switch', 'Combox']) {
    final ps = all.where((e) => e.$2.tag == t).toList();
    buf.writeln('- $t: ${ps.length} Parameter; Menü-Größen: ${count(ps.map((e) => '${e.$2.menus.length}')).entries.map((e) => '${e.key} Einträge ×${e.value}').join(', ')}');
    final idSets = count(ps.map((e) => '{${(e.$2.menus.map((m) => m['ID']).toList()..sort()).join(',')}}'));
    buf.writeln('  - Menü-ID-Mengen: ${idSets.entries.map((e) => '${e.key} ×${e.value}').join(', ')}');
  }
  final switchOn = all.where((e) => e.$2.tag == 'Switch' && !e.$2.menus.any((m) => m['ID'] == '0') ).toList();
  buf.writeln('- Switches ohne Menü-ID 0: ${switchOn.length}');
  final comboxes = all.where((e) => e.$2.tag == 'Combox').toList();
  buf.writeln('- Combox-Parameter (Auszug der ersten 15):');
  for (final e in comboxes.take(15)) {
    buf.writeln('  - ${tag(e.$1, e.$2)}: ${e.$2.menus.map((m) => '${m['ID']}=${m['Name']}').join(', ')}');
  }
  json['switchParameters'] = all.where((e) => e.$2.tag == 'Switch').length;
  json['comboxParameters'] = comboxes.length;

  h('Algorithmen: Namen, Codes, Index');
  final blank = algorithms.where((a) => a.name.isEmpty).toList();
  buf.writeln('- Algorithmen mit leerem Namen: ${blank.length} (Modul ${count(blank.map((a) => a.module))})');
  final dupNames = <String>[];
  for (final m in modules.keys) {
    final names = algorithms.where((a) => a.module == m && a.name.isNotEmpty).map((a) => a.name).toList();
    dupNames.addAll(count(names).entries.where((e) => e.value > 1).map((e) => '$m ${e.key} ×${e.value}'));
  }
  buf.writeln('- doppelte Namen innerhalb eines Moduls: ${dupNames.length}${dupNames.isEmpty ? '' : ' → ${dupNames.join(', ')}'}');
  final dupCodes = <String>[];
  for (final m in modules.keys) {
    dupCodes.addAll(count(algorithms.where((a) => a.module == m).map((a) => a.code)).entries.where((e) => e.value > 1).map((e) => '$m code ${e.key} ×${e.value}'));
  }
  buf.writeln('- doppelte Codes innerhalb eines Moduls: ${dupCodes.length}${dupCodes.isEmpty ? '' : ' → ${dupCodes.join(', ')}'}');
  buf.writeln('- nichtnumerische Codes: ${algorithms.where((a) => int.tryParse(a.code) == null).length}');
  buf.writeln('- Parameter je Algorithmus (Verteilung): ${count(algorithms.map((a) => '${a.params.length}')).entries.map((e) => '${e.key}:${e.value}').join(', ')}');
  buf.writeln('- Zeichen `|` `~` `;` `\\t` in Namen: ${all.where((e) => RegExp(r'[|~;\t]').hasMatch(e.$2.name ?? '')).length + algorithms.where((a) => RegExp(r'[|~;\t]').hasMatch(a.name)).length}');
  json['blankNames'] = blank.length;
  json['duplicateNamesInModule'] = dupNames.length;
  json['duplicateCodesInModule'] = dupCodes.length;

  h('Weitere Fälle, in denen idx-Adressierung falsch wäre');
  buf.writeln('Jeder Parameter mit idx != ID − 1 (siehe oben) sowie jeder Parameter hinter einer fehlenden ID im selben Algorithmus. '
      'Die Regel Wire = ID − 1 ist für alle 46 Capture-Gruppen und für Boost Bright (Wire 2) und CAB VOL (Wire 1) hardwarebestätigt.');

  File(args[1]).writeAsStringSync(buf.toString());
  if (args.length > 2) File(args[2]).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  stdout.writeln('algorithms=${algorithms.length} parameters=${all.length} idx==ID-1: $equal differ: ${differ.length} gapAlgorithms: ${gapAlgorithms.length}');
}
