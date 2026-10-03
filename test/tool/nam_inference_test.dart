@TestOn('windows')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/matribox_nam_analysis/nam_clodata_converter.dart';
import '../../tool/matribox_nam_analysis/nam_golden_corpus.dart';
import '../../tool/nam_inference/nam_inference_engine.dart';

/// V4a: native NAM inference (NeuralAmpModelerCore via dart:ffi) and the
/// end-to-end .nam → CloData comparison against the five official goldens.
///
/// Windows-only (see @TestOn above): the native bridge
/// (`native/nam_bridge/build/wyrmtone_nam.dll`) is a Windows DLL for this
/// validation stage; it is not built or run on other platforms and the
/// whole file is skipped there rather than failing.
///
/// Cases whose external evidence (local .nam / official WAV / official
/// CloData) is not present are SKIPPED, never reported as passed — the
/// same rule as the golden corpus tests in matribox_nam_analysis_test.dart.
void main() {
  final dllExists = File('native/nam_bridge/build/wyrmtone_nam.dll')
      .existsSync();
  final skipNoNative = dllExists
      ? false
      : 'native/nam_bridge/build/wyrmtone_nam.dll not built (see native/nam_bridge/build.bat)';

  group('native load/process/unload lifecycle', () {
    test('load, process a short buffer, unload, reload a different model', () {
      final engine = NamInferenceEngine.create();
      addTearDown(engine.dispose);
      final fndr = File(
        r'D:\Desktop 3d sachen\Desktop\AMP Presets\Fender Pano-Verb\FNDR PANO Clean2 BAL 6V6 CAB.nam',
      );
      if (!fndr.existsSync()) {
        markTestSkipped('local FNDR PANO .nam not available');
        return;
      }
      engine.load(fndr.path);
      expect(engine.isLoaded, isTrue);
      expect(engine.expectedSampleRate, greaterThan(0));
      final input = Float32List.fromList([
        for (var i = 0; i < 2000; i++) 0.1 * math.sin(i * 0.05),
      ]);
      final out = engine.process(input);
      expect(out.length, input.length);
      expect(out.any((v) => v.isNaN || v.isInfinite), isFalse);
      engine.unload();
      expect(engine.isLoaded, isFalse);

      final solid = File(
        r'D:\Desktop 3d sachen\Desktop\Solid Ryhthm Mid Hi.nam',
      );
      if (solid.existsSync()) {
        engine.load(solid.path);
        expect(engine.isLoaded, isTrue);
        final out2 = engine.process(input);
        expect(out2.any((v) => v.isNaN || v.isInfinite), isFalse);
      }
    }, skip: skipNoNative);

    test(
      'deterministic: same input twice on a fresh load yields identical output',
      () {
        final fndr = File(
          r'D:\Desktop 3d sachen\Desktop\AMP Presets\Fender Pano-Verb\FNDR PANO Clean2 BAL 6V6 CAB.nam',
        );
        if (!fndr.existsSync()) {
          markTestSkipped('local FNDR PANO .nam not available');
          return;
        }
        final input = Float32List.fromList([
          for (var i = 0; i < 5000; i++) 0.3 * math.sin(i * 0.03),
        ]);
        Float32List runOnce() {
          final e = NamInferenceEngine.create();
          e.load(fndr.path);
          final out = e.process(input);
          e.dispose();
          return out;
        }

        final a = runOnce();
        final b = runOnce();
        expect(a, orderedEquals(b));
      },
      skip: skipNoNative,
    );

    test('invalid NAM path is rejected with a structured error, engine reusable afterwards', () {
      final engine = NamInferenceEngine.create();
      addTearDown(engine.dispose);
      expect(
        () => engine.load('does/not/exist.nam'),
        throwsA(
          isA<NamInferenceException>().having(
            (e) => e.kind,
            'kind',
            NamInferenceErrorKind.fileNotFound,
          ),
        ),
      );
      expect(engine.isLoaded, isFalse);
    }, skip: skipNoNative);

    test('corrupt NAM (invalid JSON) is rejected, not a crash', () {
      final bad = File(
        '${Directory.systemTemp.path}/wyrmtone_bad_${DateTime.now().microsecondsSinceEpoch}.nam',
      );
      bad.writeAsStringSync('not json');
      addTearDown(() => bad.deleteSync());
      final engine = NamInferenceEngine.create();
      addTearDown(engine.dispose);
      expect(
        () => engine.load(bad.path),
        throwsA(
          isA<NamInferenceException>().having(
            (e) => e.kind,
            'kind',
            NamInferenceErrorKind.loadFailed,
          ),
        ),
      );
    }, skip: skipNoNative);

    test('processing without a loaded model throws notLoaded', () {
      final engine = NamInferenceEngine.create();
      addTearDown(engine.dispose);
      expect(
        () => engine.process(Float32List(10)),
        throwsA(
          isA<NamInferenceException>().having(
            (e) => e.kind,
            'kind',
            NamInferenceErrorKind.notLoaded,
          ),
        ),
      );
    }, skip: skipNoNative);

    test('dispose is idempotent; use-after-dispose throws StateError', () {
      final engine = NamInferenceEngine.create();
      engine.dispose();
      engine.dispose(); // no-op, must not throw
      expect(() => engine.isLoaded, throwsStateError);
      expect(() => engine.process(Float32List(1)), throwsStateError);
    }, skip: skipNoNative);
  });

  group('native runner vs Dart FFI identity', () {
    test('same NAM + input produce byte-identical samples through the native runner and through FFI', () {
      final runner = File('native/nam_bridge/build/nam_bridge_runner.exe');
      final fndr = File(
        r'D:\Desktop 3d sachen\Desktop\AMP Presets\Fender Pano-Verb\FNDR PANO Clean2 BAL 6V6 CAB.nam',
      );
      final ref = File(r'D:\Develop\wyrmtone-captures\v3\48000.wav');
      if (!runner.existsSync() || !fndr.existsSync() || !ref.existsSync()) {
        markTestSkipped(
          'native runner, FNDR PANO .nam or reference WAV not available',
        );
        return;
      }
      final referenceSamples = MatriboxNamWav.parse(ref.readAsBytesSync())
          .samples;
      // Only the first 200,000 frames: enough to prove FFI does not alter
      // samples relative to the native runner, without a multi-second run.
      final input = Float32List.sublistView(referenceSamples, 0, 200000);

      final engine = NamInferenceEngine.create();
      addTearDown(engine.dispose);
      engine.load(fndr.path);
      final ffiOutput = engine.process(input);

      final tmpDir = Directory.systemTemp.createTempSync(
        'wyrmtone_nam_identity_',
      );
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final inWav = File('${tmpDir.path}/in.wav');
      inWav.writeAsBytesSync(_encodeMono24Wav(input, 48000));
      final outWav = '${tmpDir.path}/out.wav';
      final outF32 = '${tmpDir.path}/out.f32';
      final result = Process.runSync(runner.absolute.path, [
        fndr.path,
        inWav.path,
        outWav,
        outF32,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final runnerOutput = Float32List.fromList(
        File(outF32).readAsBytesSync().buffer.asFloat32List(),
      );

      expect(ffiOutput.length, runnerOutput.length);
      expect(ffiOutput, orderedEquals(runnerOutput));
    }, skip: skipNoNative);
  });

  group(
    'V4b: output-scale characterization (evidence, not a production rule)',
    () {
      // Guards the V4b finding so it cannot silently regress or get lost:
      // official = raw_inference * k, with k tightly clustered around 0.3100
      // for every one of the five goldens (see docs V4b for the full
      // per-model measurement table). This is a MEASUREMENT, not a
      // correction: nothing in tool/nam_inference or the frozen converter
      // applies this scalar.
      test(
        'official/raw scale is ~0.3100 for every golden with local evidence',
        () {
          final cases = <(String, String)>[
            ('solid', 'v3/nam_output_wav.wav'),
            ('gojira', 'v3/gojira_nam_output_wav.wav'),
            ('jvm', 'v4/jvm410h_standard/nam_output_wav.wav'),
            ('fender', 'v4/fender_super_reverb_akg414/nam_output_wav.wav'),
            ('fndr', 'v4/fndr_pano_wavenet_054/nam_output_wav.wav'),
          ];
          var tested = 0;
          for (final (name, officialRel) in cases) {
            final f32 = File('native/nam_bridge/out/${name}_out.f32');
            final official = File('$matriboxCaptureRoot/$officialRel');
            if (!f32.existsSync() || !official.existsSync()) continue;
            tested++;
            final mine = f32.readAsBytesSync().buffer.asFloat32List();
            final off = MatriboxNamWav.parse(official.readAsBytesSync())
                .samples;
            final n = math.min(mine.length, off.length);
            var num = 0.0, den = 0.0;
            for (var i = 0; i < n; i++) {
              num += mine[i] * off[i];
              den += mine[i] * mine[i];
            }
            final k = num / den;
            expect(k, closeTo(0.3100, 0.002), reason: '$name: k=$k');
          }
          if (tested == 0) {
            markTestSkipped(
              'no local raw-inference/official-WAV evidence available',
            );
          }
        },
        skip: skipNoNative,
      );

      test(
        'pre-scaling the INPUT by 0.31 does NOT reproduce the official output '
        '(rules out an input-side explanation for JVM410H, a high-gain model)',
        () {
          final scaledInput = File(
            'native/nam_bridge/out/jvm_scaledinput_out.f32',
          );
          final official = File(
            '$matriboxCaptureRoot/v4/jvm410h_standard/nam_output_wav.wav',
          );
          if (!scaledInput.existsSync() || !official.existsSync()) {
            markTestSkipped(
              'scaled-input experiment output or official WAV not available',
            );
            return;
          }
          final mine = scaledInput.readAsBytesSync().buffer.asFloat32List();
          final off = MatriboxNamWav.parse(official.readAsBytesSync()).samples;
          final n = math.min(mine.length, off.length);
          var dot = 0.0, mm = 0.0, oo = 0.0;
          for (var i = 0; i < n; i++) {
            dot += mine[i] * off[i];
            mm += mine[i] * mine[i];
            oo += off[i] * off[i];
          }
          final corr = dot / math.sqrt(mm * oo);
          // Output-side scaling achieves corr > 0.99999 (see the test above);
          // input-side scaling must be clearly, not marginally, worse for a
          // model with real nonlinearity.
          expect(corr, lessThan(0.95), reason: 'corr=$corr');
        },
        skip: skipNoNative,
      );
    },
  );

  group('inference -> frozen CloData converter (raw, no scaling)', () {
    // Root-cause note (V4a evidence, not a converter change): across all
    // five goldens, raw NeuralAmpModelerCore output equals the official
    // nam_output_wav.wav times a constant ~3.226 (i.e. official = ours *
    // 0.31), correlation > 0.9999985 at zero lag. See
    // docs/MATRIBOX_NAM_TRANSFER_RESEARCH.md (V4a) for the full analysis.
    // The frozen converter is therefore run UNCHANGED on the raw,
    // unscaled inference output, exactly as instructed; the resulting
    // byte differences are the measured result, not a bug to silence here.
    for (final golden in matriboxGoldenCorpus) {
      test(
        '${golden.displayName}: raw inference -> CloData vs official (measurement, not pass/fail)',
        () {
          final namFile = golden.namLocalPath == null
              ? null
              : File(golden.namLocalPath!);
          final runner = File('native/nam_bridge/build/nam_bridge_runner.exe');
          final ref = File('$matriboxCaptureRoot/${golden.referenceWav}');
          if (namFile == null ||
              !namFile.existsSync() ||
              !runner.existsSync() ||
              !ref.existsSync()) {
            markTestSkipped(
              'NOT VALIDATED: local .nam, native runner or reference WAV not available',
            );
            return;
          }
          final tmpDir = Directory.systemTemp.createTempSync('wyrmtone_e2e_');
          addTearDown(() => tmpDir.deleteSync(recursive: true));
          final outWav = '${tmpDir.path}/out.wav';
          final outF32 = '${tmpDir.path}/out.f32';
          final result = Process.runSync(runner.absolute.path, [
            namFile.path,
            ref.absolute.path,
            outWav,
            outF32,
          ]);
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );

          final ours = File(outWav).readAsBytesSync();
          final converted = const MatriboxNamCloDataConverter()
              .convert(
                referenceWav: ref.readAsBytesSync(),
                modelOutputWav: ours,
                fileName: golden.storedName,
              )
              .requireComplete();
          final official = golden.capture != null
              ? matriboxCloDataFromCapture(
                  File('$matriboxCaptureRoot/${golden.capture}')
                      .readAsBytesSync(),
                )
              : File('$matriboxCaptureRoot/${golden.officialClodata}')
                    .readAsBytesSync();
          final diff = MatriboxCloDataDiff(official, converted);
          // Deliberately not `expect(diff.identical, isTrue)`: this is a
          // measurement, reported in the V4a report, not a pass/fail gate.
          // eslint-disable-next-line
          // ignore: avoid_print
          print(
            '${golden.id}: matching=${diff.matching}/8232 sha_official=${sha256.convert(official)} '
            'sha_ours=${sha256.convert(converted)}',
          );
        },
        skip: skipNoNative,
      );
    }
  });
}

/// Encodes [samples] as a mono 24-bit PCM WAV (matching 48000.wav's own
/// format), for the FFI/native-runner identity test's short input clip.
Uint8List _encodeMono24Wav(Float32List samples, int sampleRate) {
  final n = samples.length;
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
    var v = (samples[i].clamp(-1.0, 1.0) * 8388608.0).round();
    if (v > 8388607) v = 8388607;
    if (v < -8388608) v = -8388608;
    final u = v & 0xffffff;
    bytes[44 + i * 3] = u & 0xff;
    bytes[44 + i * 3 + 1] = (u >> 8) & 0xff;
    bytes[44 + i * 3 + 2] = (u >> 16) & 0xff;
  }
  return bytes;
}
