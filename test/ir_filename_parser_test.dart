import 'package:wyrmtone/services/ir_filename_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = IrFilenameParser();

  test('parses Marshall V30 SM57 Cap Edge case-insensitively', () {
    final ir = parser.parse('Marshall_1960_V30_SM57_CapEdge.wav');

    expect(ir.manufacturerOrCollection, 'Marshall');
    expect(ir.cabinet, '1960');
    expect(ir.speaker, 'V30');
    expect(ir.microphone, 'SM57');
    expect(ir.microphonePosition, 'Cap Edge');
    expect(ir.confidence, 0.9);
    expect(
      ir.detectedTags,
      containsAll(['Marshall', '1960', 'V30', 'SM57', 'Cap Edge']),
    );
  });

  test('parses abbreviations and separators for Mesa OS MD421 Off Axis', () {
    final ir = parser.parse('Mesa-OS_Vintage 30_421-OffAxis.WAV');

    expect(ir.manufacturerOrCollection, 'Mesa');
    expect(ir.cabinet, 'Oversized');
    expect(ir.speaker, 'V30');
    expect(ir.microphone, 'MD421');
    expect(ir.microphonePosition, 'Off Axis');
  });

  test('keeps multiple microphone terms while exposing primary match', () {
    final ir = parser.parse('Orange_4x12_SM57_MD421_Edge.wav');
    expect(ir.microphone, 'SM57');
    expect(ir.detectedTags, containsAll(['SM57', 'MD421']));
  });

  test('unknown filename remains unknown instead of inventing metadata', () {
    final ir = parser.parse('take_final_master.wav');

    expect(ir.manufacturerOrCollection, isNull);
    expect(ir.cabinet, isNull);
    expect(ir.speaker, isNull);
    expect(ir.microphone, isNull);
    expect(ir.brightness, isNull);
    expect(ir.confidence, 0);
    expect(ir.note, contains('Keine technischen Metadaten'));
  });

  test('artist tags do not fabricate technical details', () {
    final ir = parser.parse('Children_of_Bodom_Angels_Dont_Kill.wav');
    expect(ir.detectedTags, contains('Children of Bodom'));
    expect(ir.speaker, isNull);
    expect(ir.microphone, isNull);
    expect(ir.confidence, 0);
  });
}
