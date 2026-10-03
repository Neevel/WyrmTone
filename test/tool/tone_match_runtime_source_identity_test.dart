import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_loader.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_t15.dart';
import 'package:wyrmtone/tonematch/tone_match_runtime_signals.dart';

/// Research / source identity: the bundled runtime signals must equal the validated derivation of the
/// original evaluation recordings, byte for byte. The recordings are local, git-ignored research files, so this
/// runs only with WYRMTONE_RUN_SOURCE_IDENTITY=1 (like the other research tests) and never in a normal test run.
void main() {
  final run = Platform.environment['WYRMTONE_RUN_SOURCE_IDENTITY'] == '1';
  final haveSources = EvaluationRole.values.every(
    (r) => File(EvaluationSignalRegistry.forRole(r)!.file).existsSync(),
  );
  Uint8List bytesOf(Float32List f) =>
      f.buffer.asUint8List(f.offsetInBytes, f.lengthInBytes);

  test(
    'bundled PCM equals the validated derivation of the research recordings (byte for byte) and its pinned hash',
    () async {
      final provider = BundledToneMatchSignalProvider(
        load: (a) async => ByteData.sublistView(await File(a).readAsBytes()),
      );
      const loader = FileEvaluationSignalLoader(_read);
      for (final role in EvaluationRole.values) {
        final bundled = (await provider.samplesFor(role))!;
        final prepared = await loader.prepare(
          EvaluationSignalRegistry.forRole(role)!,
        );
        final expected = role == EvaluationRole.clean
            ? prepared.samples
            : EvaluationSignalT15.derive(prepared.samples);
        expect(bundled.length, expected.length, reason: role.name);
        expect(bytesOf(bundled), bytesOf(expected), reason: role.name);
        expect(
          sha256.convert(bytesOf(bundled)).toString(),
          ToneMatchRuntimeSignals.spec(role).pcmSha256,
          reason: role.name,
        );
      }
    },
    skip: run ? (haveSources ? false : 'local evaluation recordings missing') : 'set WYRMTONE_RUN_SOURCE_IDENTITY=1 (needs the local evaluation WAVs)',
  );
}

Future<Uint8List> _read(String p) => File(p).readAsBytes();
