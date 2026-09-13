// Offline only: reads explicit files, never imports hardware/network interfaces.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../lib/midi/midi_parser.dart';

class Evidence {
  Evidence(this.raw, this.source, this.position);
  final String raw;
  final String source;
  final int position;
  String get confidence => 'observed';
  String get confirmedMeaning => 'unknown';
  num? get normalized {
    final s = raw.trim();
    if (RegExp(r'^[-+]?0x[0-9a-f]+$', caseSensitive: false).hasMatch(s)) {
      final negative = s.startsWith('-');
      return int.parse(
            s.replaceFirst(RegExp(r'^[-+]?0x', caseSensitive: false), ''),
            radix: 16,
          ) *
          (negative ? -1 : 1);
    }
    return num.tryParse(s);
  }

  String get representation => raw.trim().toLowerCase().contains('0x')
      ? 'hex'
      : normalized == null
      ? 'text/unknown'
      : 'decimal';
}

class ResourceNode {
  ResourceNode(this.name, this.source, this.position);
  final String name;
  final String source;
  final int position;
  final attributes = <String, List<Evidence>>{};
  final children = <ResourceNode>[];
  String? value(String key) =>
      attributes[key]?.length == 1 ? attributes[key]!.single.raw : null;
  Iterable<ResourceNode> all(String tag) sync* {
    if (name == tag) yield this;
    for (final child in children) {
      yield* child.all(tag);
    }
  }
}

class ResourceImport {
  ResourceImport(this.root, this.warnings);
  final ResourceNode root;
  final List<String> warnings;
}

// Narrow XML-like scanner for installed editor resources, not a general XML parser.
// Keeps each duplicate occurrence and reports syntax it cannot safely consume.
ResourceImport readResource(String text, String source) {
  final root = ResourceNode('#document', source, 0);
  final stack = [root];
  final warnings = <String>[];
  String location(int offset) {
    final prefix = text.substring(0, offset);
    return '$source:${'\n'.allMatches(prefix).length + 1}:${offset - prefix.lastIndexOf('\n')}';
  }

  final tokens = RegExp(
    r'''<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!(?:[^>]*?)>|<(?:"[^"]*"|'[^']*'|[^'">])*>''',
  );
  final attrs = RegExp(r'''([\w:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
  var end = 0;
  for (final token in tokens.allMatches(text)) {
    if (text.substring(end, token.start).contains('<'))
      warnings.add('${location(end)}: unparsed markup');
    end = token.end;
    final body = token.group(0)!;
    if (body.startsWith('<?') || body.startsWith('<!')) continue;
    if (body.startsWith('</')) {
      final closing = body.substring(2, body.length - 1).trim();
      if (stack.length > 1 && stack.last.name == closing) {
        stack.removeLast();
      } else {
        warnings.add('${location(token.start)}: mismatched closing $closing');
      }
      continue;
    }
    final name = RegExp(r'^<([\w:.-]+)').firstMatch(body);
    if (name == null) {
      warnings.add('${location(token.start)}: invalid element');
      continue;
    }
    final node = ResourceNode(name.group(1)!, source, token.start);
    stack.last.children.add(node);
    final contentEnd = body.length - (body.endsWith('/>') ? 2 : 1);
    var consumed = name.end;
    for (final attr in attrs.allMatches(body.substring(name.end, contentEnd))) {
      final start = name.end + attr.start;
      if (body.substring(consumed, start).trim().isNotEmpty)
        warnings.add(
          '${location(token.start + consumed)}: unparsed attribute text',
        );
      consumed = name.end + attr.end;
      final key = attr.group(1)!;
      final raw = (attr.group(2) ?? attr.group(3)!)
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&apos;', "'");
      final list = node.attributes.putIfAbsent(key, () => []);
      list.add(Evidence(raw, source, token.start + start));
      if (list.length > 1)
        warnings.add(
          '${location(token.start + start)}: duplicate $key; values ${list.map((e) => e.raw).join(', ')} retained; meaning conflicting if unequal',
        );
    }
    if (body.substring(consumed, contentEnd).trim().isNotEmpty)
      warnings.add(
        '${location(token.start + consumed)}: unparsed attribute text',
      );
    if (!body.endsWith('/>')) stack.add(node);
  }
  if (stack.length > 1)
    warnings.add(
      '$source: unclosed ${stack.skip(1).map((e) => e.name).join(', ')}',
    );
  if (text.substring(end).contains('<')) {
    warnings.add('${location(end)}: trailing unparsed markup');
  }
  return ResourceImport(root, warnings);
}

class CaptureImport {
  CaptureImport(
    this.source,
    this.messages,
    this.markers,
    this.warnings,
    this.session,
  );
  final String source;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> markers;
  final List<String> warnings;
  final Map<String, dynamic> session;
}

List<int> hexBytes(String hex) {
  if (hex.trim().isEmpty) return [];
  return hex.trim().split(RegExp(r'\s+')).map((s) {
    if (!RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(s))
      throw FormatException('Invalid hex byte');
    return int.parse(s, radix: 16);
  }).toList();
}

CaptureImport readCapture(String text, String source) {
  final doc = jsonDecode(text);
  if (doc is! Map || doc['schemaVersion'] != 1 || doc['session'] is! Map)
    throw FormatException('$source: invalid capture schema');
  final session = Map<String, dynamic>.from(doc['session'] as Map);
  if (session['receiveOnly'] != true)
    throw FormatException('$source: receiveOnly must be true');
  if (session['startedAt'] is! String ||
      DateTime.tryParse(session['startedAt'] as String) == null ||
      session['messages'] is! List)
    throw FormatException('$source: invalid session timestamp/messages');
  final messages = <Map<String, dynamic>>[];
  final markers = <Map<String, dynamic>>[];
  final warnings = <String>[];
  for (final key in ['droppedEntries', 'droppedChunks', 'incompleteCount']) {
    final value = session[key];
    if (value is! int || value < 0)
      warnings.add('$source: $key missing/invalid');
    else if (value > 0)
      warnings.add('$source: $key=$value; chronology incomplete');
  }
  final parser = MidiParser();
  final reconstructed = <String>[];
  var previous = -1;
  for (final item in session['messages'] as List) {
    if (item is! Map) throw FormatException('$source: invalid entry');
    final e = Map<String, dynamic>.from(item);
    if (e['sequence'] is! int || e['sequence'] <= previous)
      throw FormatException('$source: invalid sequence');
    previous = e['sequence'] as int;
    if (e['localTimestamp'] is! String ||
        DateTime.tryParse(e['localTimestamp'] as String) == null)
      throw FormatException('$source: invalid entry timestamp');
    if (e['marker'] != null && e['marker'] is! String)
      throw FormatException('$source: invalid marker');
    if (e['androidTimestampNanos'] != null &&
        e['androidTimestampNanos'] is! int)
      throw FormatException('$source: invalid Android timestamp');
    final bytes = hexBytes(
      e['hex'] is String
          ? e['hex'] as String
          : throw FormatException('$source: missing hex'),
    );
    if (e['length'] != bytes.length)
      throw FormatException('$source: length mismatch #$previous');
    if (e['truncated'] == true) warnings.add('$source: truncated #$previous');
    if (e['kind'] == 'marker') {
      markers.add(e);
      continue;
    }
    if (e['kind'] == 'loss') {
      parser.finish();
      warnings.add('$source: reception gap #$previous');
      continue;
    }
    if (e['kind'] == 'chunk') {
      final at = DateTime.parse(e['localTimestamp'] as String)
          .millisecondsSinceEpoch;
      for (final m in parser.feed(bytes, at)) {
        if (m.type == 'SysEx' && m.status == 'vollständig')
          reconstructed.add(jsonEncode(m.bytes));
      }
    } else if (e['kind'] == 'message' && e['type'] == 'SysEx') {
      if (e['status'] != 'vollständig') {
        warnings.add('$source: incomplete SysEx #$previous');
        continue;
      }
      if (bytes.length < 2 ||
          bytes.first != 0xF0 ||
          bytes.last != 0xF7 ||
          bytes.sublist(1, bytes.length - 1).any((b) => b >= 0x80))
        throw FormatException('$source: invalid complete SysEx #$previous');
      messages.add({...e, 'bytes': bytes});
    }
  }
  if (session['droppedEntries'] == 0 &&
      reconstructed.join('|') !=
          messages.map((e) => jsonEncode(e['bytes'])).join('|'))
    warnings.add(
      '$source: chunks and assembled messages differ; no silent reconstruction substitution',
    );
  return CaptureImport(source, messages, markers, warnings, session);
}

List<Map<String, dynamic>> differences(List<List<int>> messages) {
  if (messages.isEmpty) return [];
  final length = messages.first.length;
  if (messages.any((m) => m.length != length))
    throw ArgumentError('Compare equal lengths only');
  return List.generate(length, (offset) {
    final values = messages.map((m) => m[offset]).toSet().toList()..sort();
    return {
      'offset': offset,
      'hex': values
          .map((v) => v.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' '),
      'decimal': values,
      'ascii': values.length == 1 && values.single >= 32 && values.single <= 126
          ? String.fromCharCode(values.single)
          : null,
      'constant': values.length == 1,
      'meaning': 'unknown',
      'confidence': 'observed',
    };
  });
}

double? nibbleFloat(List<int> bytes, int start) {
  if (bytes.length < start + 8 ||
      bytes.sublist(start, start + 8).any((b) => b > 15))
    return null;
  final data = ByteData(4);
  for (var i = 0; i < 4; i++) {
    data.setUint8(i, bytes[start + 2 * i] * 16 + bytes[start + 2 * i + 1]);
  }
  final value = data.getFloat32(0, Endian.little);
  return value.isFinite ? value : null;
}

String report(
  ResourceImport algorithms,
  ResourceImport presets,
  List<CaptureImport> captures,
  List<String> missing,
) {
  final out = StringBuffer('# Matribox: lokale Offline-Analyse\n\n');
  out.writeln('## Zweck und Aufruf\n');
  out.writeln(
    'Entwicklerwerkzeug außerhalb der App; keine Build-Abhängigkeit auf Editor-Ressourcen. `dart run tool/matribox_analyzer.dart --algorithm "<algorithm.xml>" --preset "<preset.xml>" --capture "<capture.json>" [--capture "<weiterer.json>"] --output "<bericht.md>"`. Fehlende Capture-Pfade werden ausgewiesen; ungültige Captures abgelehnt. Ausgabe enthält nur abgeleitete kompakte Erkenntnisse, keine Originalressourcen. Originaldateien bleiben unverändert.\n',
  );
  out.writeln('## Quellen und Warnungen\n');
  out.writeln(
    'Lokal installierte Editor-Ressourcen: ${algorithms.root.source}, ${presets.root.source}.',
  );
  out.writeln(
    'Captures: ${captures.map((c) => c.source).join(', ')}. Mehrere Exporte können überlappen; Gesamtzahlen sind Export-Beobachtungen, keine unabhängigen Geräteereignisse.',
  );
  final seen = <String, String>{};
  for (final capture in captures) {
    final signature = jsonEncode(
      capture.messages
          .map((e) => [e['sequence'], e['localTimestamp'], e['bytes']])
          .toList(),
    );
    if (signature.isNotEmpty && seen.containsKey(signature)) {
      out.writeln(
        '- ${capture.source}: identische erhaltene Nachrichten wie ${seen[signature]}; keine unabhängige Gegenprobe.',
      );
    } else {
      seen[signature] = capture.source;
    }
  }
  for (final warning in [
    ...missing,
    ...algorithms.warnings,
    ...presets.warnings,
    ...captures.expand((c) => c.warnings),
  ]) {
    out.writeln('- $warning');
  }
  out.writeln('\n## Algorithmus- und Presetstruktur\n');
  out.writeln(
    '| Kategorie | Algorithmen | direkte Parameter |\n|---|---:|---:|',
  );
  for (final category in algorithms.root.all('Catalog')) {
    final algs = category.children.where((n) => n.name == 'Alg').toList();
    out.writeln(
      '| ${category.value('Name')} | ${algs.length} | ${algs.expand((a) => a.children).where((n) => ['Knob', 'Switch', 'Combox'].contains(n.name)).length} |',
    );
  }
  out.writeln(
    '\nObserved: Alg(Name, Module, Code, Index); Parameter(Knob/Switch/Combox) mit Name, ID, idx, default, Dmin/Dmax, Step/step, Suffix, Type/valueType, bind und Menu(Name, ID), soweit vorhanden. Fehlende Werte bleiben unbekannt; unbekannte Attribute und Elemente bleiben im Importmodell erhalten. Numerische Rohdarstellung, Basis und normalisierter Wert bleiben getrennt. Doppelte Attribute werden als Liste mit Position erhalten, nicht überschrieben. Dies sind Editor-Felder, keine bestätigten Wire-IDs.',
  );
  for (final preset in presets.root.all('Preset')) {
    out.writeln(
      '\nBeispiel-Preset: Name=${preset.value('Name')}, ID=${preset.value('ID')}, volume=${preset.value('volume')}; Reihenfolge ${preset.children.map((b) => b.value('Module')).join(' → ')}. Blöcke enthalten Name/code/switch und Parameterattribute; switch als Aktivzustand ist eine Hypothese. Die Vorlage ist kein live gelesener Preset-Dump.',
    );
  }
  final groups = <int, List<Map<String, dynamic>>>{};
  for (final capture in captures) {
    for (final m in capture.messages) {
      groups.putIfAbsent((m['bytes'] as List<int>).length, () => []).add({
        ...m,
        'source': capture.source,
      });
    }
  }
  out.writeln('\n## Nachrichtenfamilien und Differenzen\n');
  final lengths = groups.keys.toList()..sort();
  for (final length in lengths) {
    final entries = groups[length]!;
    final bytes = entries.map((m) => m['bytes'] as List<int>).toList();
    final diff = differences(bytes);
    final variable = diff
        .where((d) => d['constant'] == false)
        .map((d) => d['offset'])
        .toList();
    var prefix = 0;
    while (prefix < length && diff[prefix]['constant'] == true) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < length - prefix &&
        diff[length - 1 - suffix]['constant'] == true) {
      suffix++;
    }
    out.writeln('### $length Byte\n');
    out.writeln(
      '${entries.length} Nachrichten; konstantes Präfix $prefix Byte, Suffix $suffix Byte; variable Offsets (nullbasiert): $variable. Markierungen: ${entries.map((m) => m['marker'] ?? '(keine; Dateiname ist kein Marker)').toSet().join(', ')}.',
    );
    if (length >= 8 &&
        bytes.every(
          (b) => ascii.decode(b.sublist(4, 8), allowInvalid: true) == 'QME2',
        ))
      out.writeln(
        'Observed: Offsets 4–7 = ASCII QME2; Kennzeichner, Semantik unknown.',
      );
    final actions = <String, List<List<int>>>{};
    for (final e in entries) {
      actions
          .putIfAbsent(e['marker'] as String? ?? '(unmarkiert)', () => [])
          .add(e['bytes'] as List<int>);
    }
    for (final action in actions.entries) {
      final positions = differences(action.value)
          .where((d) => d['constant'] == false)
          .map((d) => d['offset'])
          .join(', ');
      out.writeln(
        '- Aktion ${action.key}: ${action.value.length} Nachrichten, variable Offsets [$positions]; alle übrigen Offsets konstant innerhalb dieser Gruppe.',
      );
    }
    out.writeln(
      '\n| Offset | Hexwerte | Dezimalwerte | ASCII | Zustand |\n|---:|---|---|---|---|',
    );
    for (final d in diff) {
      out.writeln(
        '| ${d['offset']} | ${d['hex']} | ${(d['decimal'] as List).join(',')} | ${d['ascii'] ?? ''} | ${d['constant'] == true ? 'konstant' : 'variabel'} |',
      );
    }
    final checksumMethods = <String, bool Function(List<int>)>{
      'sum7': (b) =>
          (b.sublist(1, b.length - 2).fold(0, (a, v) => a + v) & 127) ==
          b[b.length - 2],
      'xor7': (b) =>
          b.sublist(1, b.length - 2).fold(0, (a, v) => a ^ v) ==
          b[b.length - 2],
      'complement7': (b) =>
          ((-b.sublist(1, b.length - 2).fold(0, (a, v) => a + v)) & 127) ==
          b[b.length - 2],
    };
    out.writeln(
      '\nOffline-Prüfsummenkandidaten (Payload 1..L-3 gegen L-2, F7 ausgeschlossen): ${checksumMethods.entries.map((e) => '${e.key}: ${bytes.where(e.value).length}/${bytes.length} passend').join('; ')}. Teiltreffer bestätigen nichts; andere Prüfsummen/Positionen bleiben offen.',
    );
  }
  out.writeln('\n## Korrelationsmatrix und Wertkandidaten\n');
  out.writeln(
    '| Capture/Markierung | Muster | XML-Zuordnung | Wertkandidat | Vertrauen |\n|---|---|---|---|---|',
  );
  for (final capture in captures) {
    final pedal = capture.messages
        .where((m) => (m['bytes'] as List<int>).length == 34)
        .toList();
    final values = pedal
        .map((m) => nibbleFloat(m['bytes'] as List<int>, 25))
        .whereType<double>()
        .toList();
    out.writeln(
      '| ${capture.source} / ${capture.markers.map((m) => m['marker']).join('; ')} | ${capture.messages.length} SysEx | unknown | ${values.isEmpty ? 'unknown' : 'Offsets 25–32, Nibble-Paare → Float32 LE: ${values.first.toStringAsFixed(4)} → ${values.last.toStringAsFixed(4)}'} | ${values.isEmpty ? 'unknown' : 'hypothesis; wiederkehrende Endpunkte correlated'} |',
    );
  }
  final codes = algorithms.root
      .all('Alg')
      .expand((a) => a.attributes['Code'] ?? <Evidence>[])
      .map((e) => e.normalized)
      .whereType<int>()
      .toSet();
  final ids = algorithms.root
      .all('Alg')
      .expand((a) => a.children)
      .expand((p) => p.attributes['ID'] ?? <Evidence>[])
      .map((e) => e.normalized)
      .whereType<int>()
      .toSet();
  final allMessages = captures
      .expand((c) => c.messages)
      .map((m) => m['bytes'] as List<int>)
      .toList();
  final exact =
      allMessages
          .expand((b) => b.sublist(1, b.length - 1))
          .where(codes.contains)
          .toSet()
          .toList()
        ..sort();
  final idHits =
      allMessages
          .expand((b) => b.sublist(1, b.length - 1))
          .where(ids.contains)
          .toSet()
          .toList()
        ..sort();
  final transformed = <String>{};
  for (final b in allMessages) {
    for (var offset = 8; offset + 4 < b.length; offset++) {
      final part = b.sublist(offset, offset + 4);
      final le = part[0] + (part[1] << 8) + (part[2] << 16) + (part[3] << 24);
      final be = part[3] + (part[2] << 8) + (part[1] << 16) + (part[0] << 24);
      if (codes.contains(le)) transformed.add('LE32@$offset=$le');
      if (codes.contains(be)) transformed.add('BE32@$offset=$be');
    }
  }
  final transformList = transformed.toList()..sort();
  out.writeln(
    '\nVierbyte-Codekandidaten, Offsets ab 8: ${transformList.take(24).join('; ')}${transformList.length > 24 ? '; weitere Zufallstreffer unterdrückt' : ''}. Padding und kleine Codes erzeugen Mehrfachtreffer; kein eindeutiges Codefeld. Andere Bitpackungen, Offsets oder invertierte IDs bleiben unbewiesen.',
  );
  out.writeln(
    '\nObserved numerische Byte-Treffer: Algorithmus-Codes $exact; Parameter-IDs $idHits. Kleine Zahlen treffen Header, Padding und Werte zufällig; keine Zuordnung daraus. XML-default 50 bzw. Bereiche 0–99 sind mit dem Float-Kandidaten plausibel vereinbar, aber keinem konkreten Parameter zugeordnet. Direkte/offset/invertierte/skalierte 7-Bit- oder Mehrbyte-ID-Darstellungen sind ohne kontrollierten Algorithmuswechsel nicht unterscheidbar.',
  );
  out.writeln(
    '\nHypothesis: acht Bytes 25–32 sind High-/Low-Nibbles von vier Little-Endian-Bytes, interpretiert als IEEE754 Float32. Wiederkehrende Endpunkte 0 und 99 sind correlated mit den vom Nutzer beschriebenen Pedalanschlägen, nicht confirmed als allgemeine Protokollsemantik. Keine belegte invertierte Skalierung. Keine XML-Algorithmus-/Parameter-Zuordnung confirmed. Marker können Aktionen zeitlich versetzt zuordnen; Dateinamen sind nur Nutzerkontext. Sequenznummern sind App-Lognummern, kein Wire-Zähler. Konstante/schwankende Bytes allein belegen weder Nachrichtentyp noch Länge oder Prüfsumme. 18/22/34-Byte-Gruppen sind observed unterschiedliche Strukturen; ihre proprietären Nachrichtentypen bleiben unknown.',
  );
  out.writeln(
    '\n## Kleinste offene Gegenproben\n\n- Sichtbaren Parameter in bekanntem Algorithmus aufnehmen: Gain 40 → 41 → 42 → 41, Block/Algorithmus und Bildschirmwerte markieren. Dient Parameterwert/ID, nicht Geräteausgabe.\n- Zweiten Parameter desselben Algorithmus mit denselben Werten aufnehmen; trennt Parameter-ID von Wert.\n- Erst danach derselbe Parameter in anderem Algorithmus; trennt Algorithmus-/Block-ID.\n- Pedalzuweisung und sichtbare Werte fehlen; Float-Kandidat darf ohne diese Gegenprobe nicht als bestätigte Pedal-Prozentanzeige verwendet werden.\n- Button-Drücken und Regler-Drehen getrennt markieren; aktuelle 0/1-Paare unterscheiden Schaltzustand, UI-Aktion und Parameterwert nicht eindeutig.',
  );
  out.writeln(
    '\n## Sicherheitsstatus\n\nNur explizit angegebene lokale Dateien gelesen; kein MIDI-Port geöffnet, keine Matribox angesprochen, nichts gesendet oder wiederholt, keine USB-Transfers, kein Editor gestartet. Herstellerdateien und Captures unverändert; keine Originalressourcen/Binärdateien kopiert. Umfangreiche Herstellerlisten verbleiben nur im Arbeitsspeicher. Keine rechtliche Freigabe zur Veröffentlichung solcher Listen abgeleitet; dauerhafte Übernahme würde eine gesonderte Bewertung erfordern.',
  );
  return out.toString();
}

Future<void> main(List<String> args) async {
  try {
    final options = <String, List<String>>{};
    for (var i = 0; i < args.length; i += 2) {
      if (i + 1 >= args.length ||
          ![
            '--algorithm',
            '--preset',
            '--capture',
            '--output',
          ].contains(args[i]))
        throw FormatException(
          'Usage: --algorithm PATH --preset PATH --capture PATH [--capture PATH] --output PATH',
        );
      options.putIfAbsent(args[i], () => []).add(args[i + 1]);
    }
    for (final key in ['--algorithm', '--preset', '--output']) {
      if (options[key]?.length != 1)
        throw FormatException('$key required exactly once');
    }
    if (options['--capture']?.isNotEmpty != true)
      throw FormatException('--capture required');
    final inputs = [
      ...options['--algorithm']!,
      ...options['--preset']!,
      ...options['--capture']!,
    ];
    final output = File(options['--output']!.single);
    if (inputs.any(
          (p) =>
              File(p).absolute.path.toLowerCase() ==
              output.absolute.path.toLowerCase(),
        ) ||
        output.existsSync())
      throw FormatException('Output must be a new file distinct from inputs');
    String label(String p) => p.replaceAll('\\', '/').split('/').last;
    final algorithm = readResource(
      await File(options['--algorithm']!.single).readAsString(),
      label(options['--algorithm']!.single),
    );
    final preset = readResource(
      await File(options['--preset']!.single).readAsString(),
      label(options['--preset']!.single),
    );
    final captures = <CaptureImport>[];
    final missing = <String>[];
    for (final path in options['--capture']!) {
      if (!File(path).existsSync()) {
        missing.add('${label(path)}: not found');
        continue;
      }
      captures.add(readCapture(await File(path).readAsString(), label(path)));
    }
    await output.writeAsString(report(algorithm, preset, captures, missing));
    stdout.writeln(
      'Offline report written; ${captures.length} capture files, ${missing.length} missing.',
    );
  } on Object catch (e) {
    stderr.writeln('Offline analysis failed: $e');
    exitCode = 1;
  }
}
