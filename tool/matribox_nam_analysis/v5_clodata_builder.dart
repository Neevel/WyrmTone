/// V5A: builds the final, offline, WyrmTone-owned CloData for one NAM
/// model, using ONLY the frozen Reference Signal V4 pipeline (own signal
/// generation, own native NAM inference, the unchanged, frozen
/// `MatriboxNamCloDataConverter`). No Sonicake asset is read here. Does
/// not touch hardware, USB, MIDI, or any transport code.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../nam_inference/nam_inference_engine.dart';
import '../nam_inference/wyrmtone_reference_signal_v4.dart';
import 'nam_clodata_converter.dart';

class V5CloDataIdentity {
  V5CloDataIdentity({
    required this.namPath,
    required this.namSha256Hex,
    required this.cloneName,
    required this.cloData,
    required this.cloDataSha256Hex,
    required this.allFinite,
    required this.allBounded,
  });

  final String namPath;
  final String namSha256Hex;
  final String cloneName;
  final Uint8List cloData;
  final String cloDataSha256Hex;
  final bool allFinite;
  final bool allBounded;
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

Uint8List _toMono24Wav(Float32List mono, int sampleRate) {
  final n = mono.length;
  final data = n * 3;
  final out = ByteData(44 + data);
  out.setUint32(0, 0x46464952, Endian.little);
  out.setUint32(4, 36 + data, Endian.little);
  out.setUint32(8, 0x45564157, Endian.little);
  out.setUint32(12, 0x20746d66, Endian.little);
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, 1, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 3, Endian.little);
  out.setUint16(32, 3, Endian.little);
  out.setUint16(34, 24, Endian.little);
  out.setUint32(36, 0x61746164, Endian.little);
  out.setUint32(40, data, Endian.little);
  final bytes = out.buffer.asUint8List();
  for (var i = 0; i < n; i++) {
    var v = (mono[i].clamp(-1.0, 1.0) * 8388608.0).round();
    if (v > 8388607) v = 8388607;
    if (v < -8388608) v = -8388608;
    final u = v & 0xffffff;
    bytes[44 + i * 3] = u & 0xff;
    bytes[44 + i * 3 + 1] = (u >> 8) & 0xff;
    bytes[44 + i * 3 + 2] = (u >> 16) & 0xff;
  }
  return bytes;
}

Uint8List _toStereo16Wav(Float32List mono, int sampleRate) {
  final n = mono.length;
  final data = n * 4;
  final b = ByteData(44 + data);
  b.setUint32(0, 0x46464952, Endian.little);
  b.setUint32(4, 36 + data, Endian.little);
  b.setUint32(8, 0x45564157, Endian.little);
  b.setUint32(12, 0x20746d66, Endian.little);
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 2, Endian.little);
  b.setUint32(24, sampleRate, Endian.little);
  b.setUint32(28, sampleRate * 4, Endian.little);
  b.setUint16(32, 4, Endian.little);
  b.setUint16(34, 16, Endian.little);
  b.setUint32(36, 0x61746164, Endian.little);
  b.setUint32(40, data, Endian.little);
  for (var i = 0; i < n; i++) {
    var v = (mono[i].clamp(-1.0, 1.0) * 32768.0).round();
    if (v > 32767) v = 32767;
    if (v < -32768) v = -32768;
    b.setInt16(44 + i * 4, v, Endian.little);
    b.setInt16(46 + i * 4, v, Endian.little);
  }
  return b.buffer.asUint8List();
}

/// Reads [namPath] and its bytes' SHA-256, without any inference.
({List<int> bytes, String sha256Hex}) readNamFile(String namPath) {
  final bytes = File(namPath).readAsBytesSync();
  return (bytes: bytes, sha256Hex: _sha256Hex(bytes));
}

/// Builds the final V4 CloData for one NAM model. [namPath] must point to
/// an already-validated Golden NAM file; [cloneName] becomes the embedded
/// clone name field (<=16 bytes after encoding).
V5CloDataIdentity buildV5CloData({required String namPath, required String cloneName}) {
  final nam = readNamFile(namPath);

  final signal = WyrmToneReferenceSignalV4.generate();
  final engine = NamInferenceEngine.create();
  engine.load(namPath);
  final output = engine.process(signal);
  engine.dispose();

  final refWav = _toMono24Wav(signal, WyrmToneReferenceSignalV4.sampleRate);
  final outWav = _toStereo16Wav(output, WyrmToneReferenceSignalV4.sampleRate);

  final conversion = const MatriboxNamCloDataConverter().convert(
    referenceWav: refWav,
    modelOutputWav: outWav,
    fileName: cloneName,
  );
  final cloData = conversion.requireComplete();

  // Same float regions V4e/V4g/V4i's own structural CloData checks use:
  // the 4 non-linearity params at 0x88, then FIR1 (128) + FIR2 (1024 of
  // its 2048, matching the earlier established check) starting at 0xa8.
  var allFinite = true, allBounded = true;
  final view = ByteData.sublistView(cloData);
  void checkFloat(int offset) {
    final v = view.getFloat32(offset, Endian.little);
    if (!v.isFinite) allFinite = false;
    if (v.abs() > 1.0e6) allBounded = false;
  }

  for (var i = 0; i < 4; i++) {
    checkFloat(0x88 + 4 * i);
  }
  for (var i = 0; i < 128 + 1024; i++) {
    checkFloat(0xa8 + 4 * i);
  }

  return V5CloDataIdentity(
    namPath: namPath,
    namSha256Hex: nam.sha256Hex,
    cloneName: cloneName,
    cloData: cloData,
    cloDataSha256Hex: _sha256Hex(cloData),
    allFinite: allFinite,
    allBounded: allBounded,
  );
}

/// Convenience: JSON-safe summary (no raw CloData bytes) for logs/reports.
Map<String, Object?> v5IdentitySummary(V5CloDataIdentity id) => {
  'namPath': id.namPath,
  'namSha256': id.namSha256Hex,
  'cloneName': id.cloneName,
  'cloDataLength': id.cloData.length,
  'cloDataSha256': id.cloDataSha256Hex,
  'allFinite': id.allFinite,
  'allBounded': id.allBounded,
};
