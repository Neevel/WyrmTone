import 'dart:typed_data';

/// Container of the bundled Tone Match runtime signals: a plain RIFF/WAVE file with IEEE-float
/// (format tag 3), mono, 32 bit, 48 kHz. The data chunk is the exact Float32 PCM that is fed to the
/// NAM engine, so decoding is a byte copy (no codec, no rounding). Not meant for playback.
abstract final class RuntimeSignalWav {
  static const headerBytes = 44;

  static Uint8List encode(Float32List samples, {int sampleRate = 48000}) {
    final dataBytes = samples.length * 4;
    final out = ByteData(headerBytes + dataBytes);
    void tag(int o, String s) {
      for (var i = 0; i < 4; i++) {
        out.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    out.setUint32(4, 36 + dataBytes, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 3, Endian.little); // IEEE float
    out.setUint16(22, 1, Endian.little); // mono
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, sampleRate * 4, Endian.little);
    out.setUint16(32, 4, Endian.little);
    out.setUint16(34, 32, Endian.little);
    tag(36, 'data');
    out.setUint32(40, dataBytes, Endian.little);
    final bytes = out.buffer.asUint8List();
    bytes.setRange(
      headerBytes,
      headerBytes + dataBytes,
      samples.buffer.asUint8List(samples.offsetInBytes, dataBytes),
    );
    return bytes;
  }

  /// The PCM bytes (little-endian Float32) of a file written by [encode], or null if the container is
  /// not exactly that format. Callers verify the content hash separately.
  static Float32List? decode(Uint8List bytes, {int sampleRate = 48000}) {
    if (bytes.length < headerBytes) return null;
    final d = ByteData.sublistView(bytes);
    String tag(int o) => String.fromCharCodes(bytes.sublist(o, o + 4));
    if (tag(0) != 'RIFF' ||
        tag(8) != 'WAVE' ||
        tag(12) != 'fmt ' ||
        tag(36) != 'data') {
      return null;
    }
    if (d.getUint32(16, Endian.little) != 16 ||
        d.getUint16(20, Endian.little) != 3) {
      return null;
    }
    if (d.getUint16(22, Endian.little) != 1 ||
        d.getUint32(24, Endian.little) != sampleRate ||
        d.getUint16(34, Endian.little) != 32) {
      return null;
    }
    final dataBytes = d.getUint32(40, Endian.little);
    if (dataBytes == 0 ||
        dataBytes % 4 != 0 ||
        headerBytes + dataBytes != bytes.length) {
      return null;
    }
    return Float32List.fromList(
      Float32List.view(Uint8List.fromList(bytes.sublist(headerBytes)).buffer),
    );
  }
}
