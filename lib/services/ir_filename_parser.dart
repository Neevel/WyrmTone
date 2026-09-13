import '../models/ir_metadata.dart';

class IrFilenameParser {
  const IrFilenameParser();

  IrMetadata parse(String fileName, {String? uri}) {
    final normalized = normalizeFileName(fileName);
    final compact = normalized.replaceAll(' ', '');
    final tags = <String>[];

    final manufacturer = _firstMatch(normalized, compact, const {
      'Marshall': ['marshall'],
      'Mesa': ['mesa'],
      'Orange': ['orange'],
      'Peavey': ['peavey'],
      'Engl': ['engl'],
      'Fender': ['fender'],
    }, tags);
    final cabinet = _firstMatch(normalized, compact, const {
      '1960': ['1960'],
      'Rectifier': ['rectifier', 'recto'],
      'Oversized': ['oversized', ' os '],
      '4x12': ['4x12', '412'],
      '2x12': ['2x12', '212'],
      '1x12': ['1x12', '112'],
    }, tags);
    final speaker = _firstMatch(normalized, compact, const {
      'V30': ['v30', 'vintage 30', 'vintage30'],
      'Greenback': ['greenback', 'g12m'],
      'G12T-75': ['g12t 75', 'g12t75'],
      'Creamback': ['creamback'],
    }, tags);
    final microphone = _firstMatch(normalized, compact, const {
      'SM57': ['sm57', ' sm 57 ', ' 57 '],
      'MD421': ['md421', ' 421 '],
      'R121': ['r121', 'royer'],
      'e906': ['e906'],
      'U87': ['u87'],
    }, tags);
    final position = _firstMatch(normalized, compact, const {
      'Cap Edge': ['cap edge', 'capedge'],
      'Off Axis': ['off axis', 'offaxis'],
      'On Axis': ['on axis', 'onaxis'],
      'Center': ['center', 'centre'],
      'Edge': [' edge '],
      'Cone': ['cone'],
      'Cap': [' cap '],
      'Far': [' far '],
      'Room': ['room'],
    }, tags);

    for (final entry in const {
      'CKY': ['cky'],
      '96 Quite Bitter Beings': ['96 quite bitter beings', '96qbb'],
      'Children of Bodom': ['children of bodom', 'cob'],
      'Angels Don’t Kill': ['angels dont kill', 'angels don t kill'],
      'Nirvana': ['nirvana'],
      'Come As You Are': ['come as you are', 'caya'],
    }.entries) {
      if (_containsAny(normalized, compact, entry.value)) tags.add(entry.key);
    }

    final estimates = _estimate(speaker, microphone, position);
    final technicalCount = [
      manufacturer,
      cabinet,
      speaker,
      microphone,
      position,
    ].whereType<String>().length;
    final confidence = switch (technicalCount) {
      0 => 0.0,
      1 => 0.25,
      2 => 0.45,
      3 => 0.65,
      4 => 0.80,
      _ => 0.90,
    };
    return IrMetadata(
      fileName: fileName,
      uri: uri,
      manufacturerOrCollection: manufacturer,
      cabinet: cabinet,
      speaker: speaker,
      microphone: microphone,
      microphonePosition: position,
      brightness: estimates.$1,
      tightness: estimates.$2,
      lowEnd: estimates.$3,
      confidence: confidence,
      detectedTags: tags.toSet().toList(growable: false),
      note: technicalCount == 0
          ? 'Keine technischen Metadaten im Dateinamen erkannt.'
          : null,
    );
  }

  String? _firstMatch(
    String normalized,
    String compact,
    Map<String, List<String>> alternatives,
    List<String> tags,
  ) {
    String? first;
    for (final entry in alternatives.entries) {
      if (_containsAny(normalized, compact, entry.value)) {
        tags.add(entry.key);
        first ??= entry.key;
      }
    }
    return first;
  }

  bool _containsAny(String normalized, String compact, List<String> needles) {
    final padded = ' $normalized ';
    return needles.any((needle) {
      final clean = _normalize(needle);
      if (needle.startsWith(' ') || needle.endsWith(' ')) {
        return padded.contains(' $clean ');
      }
      return normalized.contains(clean) ||
          compact.contains(clean.replaceAll(' ', ''));
    });
  }

  (int?, int?, int?) _estimate(
    String? speaker,
    String? microphone,
    String? position,
  ) {
    final values = <(int, int, int)>[];
    const speakerValues = {
      'V30': (65, 78, 58),
      'Greenback': (50, 52, 55),
      'G12T-75': (68, 68, 62),
      'Creamback': (47, 55, 63),
    };
    const micValues = {
      'SM57': (75, 72, 45),
      'MD421': (55, 70, 68),
      'R121': (35, 45, 72),
      'e906': (66, 68, 52),
      'U87': (52, 50, 66),
    };
    if (speakerValues[speaker] case final value?) values.add(value);
    if (micValues[microphone] case final value?) values.add(value);
    if (values.isEmpty) return (null, null, null);
    var brightness = _average(values.map((value) => value.$1));
    var tightness = _average(values.map((value) => value.$2));
    var lowEnd = _average(values.map((value) => value.$3));
    switch (position) {
      case 'Cap' || 'Center' || 'On Axis':
        brightness += 8;
        tightness += 4;
        lowEnd -= 4;
        break;
      case 'Cap Edge' || 'Edge' || 'Off Axis':
        brightness -= 6;
        lowEnd += 3;
        break;
      case 'Far' || 'Room':
        tightness -= 12;
        lowEnd += 5;
        break;
      case null:
        break;
    }
    return (
      brightness.clamp(0, 100),
      tightness.clamp(0, 100),
      lowEnd.clamp(0, 100),
    );
  }

  int _average(Iterable<int> values) =>
      (values.reduce((left, right) => left + right) / values.length).round();

  String normalizeFileName(String fileName) => _normalize(
    fileName.replaceFirst(RegExp(r'\.wav$', caseSensitive: false), ''),
  );

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll('’', ' ')
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
