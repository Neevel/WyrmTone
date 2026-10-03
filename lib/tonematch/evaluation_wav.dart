import 'dart:typed_data';

import 'evaluation_signal.dart';

/// Decoded DRY channel of an evaluation recording, still at the recording's own sample rate.
class DecodedDryChannel {
  const DecodedDryChannel({required this.samples, required this.sampleRate});
  final Float32List samples;
  final int sampleRate;
}

/// Reads the original evaluation WAV (RIFF, PCM 24-bit, stereo) and returns ONLY the LEFT (= DRY)
/// channel as Float32 in [-1, 1). The RIGHT (= WET) channel is dropped here and never used.
/// Decoding is exact: v / 2^23. The file is never modified or normalised.
abstract final class EvaluationWavReader {
  static DecodedDryChannel readDryLeft(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 12 || _tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') {
      throw const EvaluationSignalException('Keine RIFF/WAVE-Datei.');
    }
    int? format, channels, rate, bits, dataStart, dataLen;
    var pos = 12;
    while (pos + 8 <= bytes.length) {
      final id = _tag(bytes, pos);
      final size = data.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (id == 'fmt ') {
        format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        rate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
        if (format == 0xFFFE && size >= 26) format = data.getUint16(body + 24, Endian.little); // sub-format
      } else if (id == 'data') {
        dataStart = body;
        dataLen = (body + size > bytes.length) ? bytes.length - body : size;
        break;
      }
      pos = body + size + (size & 1);
    }
    if (format == null || dataStart == null || dataLen == null) throw const EvaluationSignalException('WAV ohne fmt-/data-Chunk.');
    if (format != 1) throw const EvaluationSignalException('Nur lineares PCM wird unterstützt.');
    if (bits != 24) throw EvaluationSignalException('Erwartet 24 Bit, gefunden $bits.');
    if (channels != 2) throw EvaluationSignalException('Erwartet Stereo (Links = Dry), gefunden $channels Kanäle.');
    if (rate != evaluationOriginalSampleRate) {
      throw EvaluationSignalException('Erwartet $evaluationOriginalSampleRate Hz, gefunden $rate Hz.');
    }
    const frameBytes = 6;
    final frames = dataLen ~/ frameBytes;
    final out = Float32List(frames);
    for (var i = 0; i < frames; i++) {
      final o = dataStart + i * frameBytes;
      var v = bytes[o] | (bytes[o + 1] << 8) | (bytes[o + 2] << 16);
      if (v >= 0x800000) v -= 0x1000000;
      out[i] = v / 8388608.0;
    }
    return DecodedDryChannel(samples: out, sampleRate: rate!);
  }

  static String _tag(Uint8List b, int o) => String.fromCharCodes(b.sublist(o, o + 4));
}
