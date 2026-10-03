import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'analysis_interfaces.dart';
import 'evaluation_resampler.dart';
import 'evaluation_signal.dart';
import 'evaluation_wav.dart';

/// Loads an evaluation WAV through [readBytes] (a file in development/tests; an asset or cached
/// file later). The descriptor's SHA-256 identifies the ORIGINAL file bytes.
class FileEvaluationSignalLoader implements EvaluationSignalLoader {
  const FileEvaluationSignalLoader(this.readBytes);
  final Future<Uint8List> Function(String path) readBytes;

  @override
  Future<PreparedEvaluationSignal> prepare(EvaluationSignalDescriptor descriptor) async {
    final problems = descriptor.validate();
    if (problems.isNotEmpty) throw EvaluationSignalException(problems.join(' '));
    final decodeWatch = Stopwatch()..start();
    final bytes = await readBytes(descriptor.file);
    if (sha256.convert(bytes).toString() != descriptor.sha256) {
      throw EvaluationSignalException('SHA-256 von ${descriptor.id} stimmt nicht mit dem Descriptor überein.');
    }
    final dry = EvaluationWavReader.readDryLeft(bytes);
    decodeWatch.stop();
    final resampleWatch = Stopwatch()..start();
    final samples = EvaluationResampler.to48k(dry.samples);
    resampleWatch.stop();
    return PreparedEvaluationSignal(
      descriptor: descriptor,
      samples: samples,
      decodeMs: decodeWatch.elapsedMilliseconds,
      resampleMs: resampleWatch.elapsedMilliseconds,
    );
  }
}
