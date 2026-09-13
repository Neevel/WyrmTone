import 'dart:convert';
import 'dart:typed_data';

class ValidatedWav {
  const ValidatedWav({
    required this.channels,
    required this.sampleRateHz,
    required this.bitsPerSample,
    required this.durationMs,
  });

  final int channels;
  final int sampleRateHz;
  final int bitsPerSample;
  final int durationMs;
  bool get isStereo => channels == 2;
}

class WavValidationException implements Exception {
  const WavValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WavValidator {
  const WavValidator();

  ValidatedWav validate(Uint8List bytes) {
    if (bytes.length < 44 ||
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
      throw const WavValidationException(
        'Die Datei ist kein RIFF/WAVE-Container.',
      );
    }
    final data = ByteData.sublistView(bytes);
    int? encoding;
    int? channels;
    int? sampleRate;
    int? byteRate;
    int? bits;
    int? audioLength;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = ascii.decode(
        bytes.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final length = data.getUint32(offset + 4, Endian.little);
      final content = offset + 8;
      if (content + length > bytes.length) {
        throw const WavValidationException('Die WAV-Datei ist unvollständig.');
      }
      if (id == 'fmt ' && length >= 16) {
        encoding = data.getUint16(content, Endian.little);
        channels = data.getUint16(content + 2, Endian.little);
        sampleRate = data.getUint32(content + 4, Endian.little);
        byteRate = data.getUint32(content + 8, Endian.little);
        bits = data.getUint16(content + 14, Endian.little);
      } else if (id == 'data') {
        audioLength = length;
      }
      offset = content + length + (length.isOdd ? 1 : 0);
    }
    if (encoding == null ||
        channels == null ||
        sampleRate == null ||
        byteRate == null ||
        bits == null ||
        audioLength == null) {
      throw const WavValidationException('Erforderliche WAV-Blöcke fehlen.');
    }
    if (encoding != 1 && encoding != 3 && encoding != 0xfffe) {
      throw WavValidationException(
        'Nicht unterstützte WAV-Codierung: $encoding.',
      );
    }
    if (channels < 1 || channels > 2) {
      throw WavValidationException(
        'Nur Mono- oder Stereo-WAV wird unterstützt.',
      );
    }
    if (sampleRate < 8000 || sampleRate > 192000) {
      throw WavValidationException(
        'Nicht unterstützte Sample-Rate: $sampleRate Hz.',
      );
    }
    if (!const {16, 24, 32}.contains(bits)) {
      throw WavValidationException('Nicht unterstützte Bit-Tiefe: $bits Bit.');
    }
    if (byteRate <= 0 || audioLength <= 0) {
      throw const WavValidationException(
        'Die WAV-Datei enthält keine Audiodaten.',
      );
    }
    return ValidatedWav(
      channels: channels,
      sampleRateHz: sampleRate,
      bitsPerSample: bits,
      durationMs: (audioLength * 1000 / byteRate).round(),
    );
  }
}
