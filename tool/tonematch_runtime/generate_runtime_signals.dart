// Generates the bundled Tone Match runtime signals from the research recordings with the ALREADY
// validated derivation only (24-bit decode of the LEFT/dry channel -> the single 44.1 -> 48 kHz
// resampler -> T15 for rhythm/lead, unchanged for clean). No new DSP decision lives here.
//
//   dart run tool/tonematch_runtime/generate_runtime_signals.dart
//
// It also re-derives T15 with the validation-gate implementation and refuses to write unless both
// are byte-identical. Prints the facts that go into lib/tonematch/tone_match_runtime_signals.dart.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_loader.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_t15.dart';
import 'package:wyrmtone/tonematch/runtime_signal_wav.dart';

import '../tonematch_gate/gate_dsp.dart';

Future<void> main() async {
  const loader = FileEvaluationSignalLoader(_read);
  for (final role in EvaluationRole.values) {
    final d = EvaluationSignalRegistry.forRole(role)!;
    final prepared = await loader.prepare(d);
    Float32List pcm;
    if (role == EvaluationRole.clean) {
      pcm = prepared.samples;
    } else {
      pcm = EvaluationSignalT15.derive(prepared.samples);
      final gate = buildVariants(
        prepared.samples,
        contentSeconds: [15],
      ).firstWhere((v) => v.id == 'T15').samples;
      final same =
          gate.length == pcm.length &&
          _bytes(gate).toString() == _bytes(pcm).toString();
      if (!same) {
        stderr.writeln(
          'STOP: product T15 differs from the validated gate T15 for ${role.name}',
        );
        exitCode = 1;
        return;
      }
    }
    final name = role == EvaluationRole.clean
        ? '${d.id}-full.wav'
        : '${d.id}-t15.wav';
    final file = File('assets/tonematch/runtime/$name');
    final wav = RuntimeSignalWav.encode(pcm);
    file.writeAsBytesSync(wav);
    final back = RuntimeSignalWav.decode(wav)!;
    stdout.writeln(
      '${role.name}: file=$name samples=${pcm.length} seconds=${pcm.length / evaluationSampleRate} '
      'pcmSha256=${sha256.convert(_bytes(pcm))} roundTrip=${sha256.convert(_bytes(back)) == sha256.convert(_bytes(pcm))} fileBytes=${wav.length} '
      'originalSha256=${d.sha256}',
    );
  }
}

Uint8List _bytes(Float32List f) =>
    f.buffer.asUint8List(f.offsetInBytes, f.lengthInBytes);

Future<Uint8List> _read(String p) => File(p).readAsBytes();
