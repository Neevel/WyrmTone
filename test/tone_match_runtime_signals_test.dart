import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyrmtone/tonematch/acoustic_target.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/isolate_tone_analysis_runner.dart';
import 'package:wyrmtone/tonematch/runtime_signal_wav.dart';
import 'package:wyrmtone/tonematch/tone_analysis_runner.dart';
import 'package:wyrmtone/tonematch/tone_knowledge_provider.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';
import 'package:wyrmtone/tonematch/tone_match_runtime_signals.dart';

import 'support/sound_flow_support.dart';

/// The bundled Tone Match measuring signals: only the versioned runtime assets are used here (no research
/// recordings, no local datasets); the comparison with the original recordings is the gated test
/// test/tool/tone_match_runtime_source_identity_test.dart.
void main() {
  Future<ByteData> fromDisk(String asset) async {
    final b = await File(asset).readAsBytes();
    return ByteData.sublistView(b);
  }

  Uint8List bytesOf(Float32List f) =>
      f.buffer.asUint8List(f.offsetInBytes, f.lengthInBytes);

  test(
    'rhythm, lead and clean are bundled; nothing else is in the runtime folder',
    () {
      final files = Directory('assets/tonematch/runtime')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      expect(files, {
        for (final s in ToneMatchRuntimeSignals.all) s.asset.split('/').last,
      });
      expect(
        ToneMatchRuntimeSignals.all.map((s) => s.role).toSet(),
        EvaluationRole.values.toSet(),
      );
    },
  );

  test('every bundled signal is a strict 48 kHz mono float WAV with the pinned length and PCM hash', () async {
    final provider = BundledToneMatchSignalProvider(load: fromDisk);
    const expectedSeconds = {
      EvaluationRole.rhythm: 15.5,
      EvaluationRole.lead: 15.5,
      EvaluationRole.clean: 685259 / 48000,
    };
    for (final role in EvaluationRole.values) {
      final spec = ToneMatchRuntimeSignals.spec(role);
      final file = File(spec.asset);
      expect(
        file.existsSync(),
        isTrue,
        reason: '${role.name}: ${spec.asset} must be versioned',
      );
      final bytes = file.readAsBytesSync();
      final d = ByteData.sublistView(bytes);
      expect(
        String.fromCharCodes(bytes.sublist(0, 4)),
        'RIFF',
        reason: role.name,
      );
      expect(
        d.getUint16(20, Endian.little),
        3,
        reason: '${role.name}: IEEE float',
      ); // format tag
      expect(d.getUint16(22, Endian.little), 1, reason: '${role.name}: mono');
      expect(
        d.getUint32(24, Endian.little),
        evaluationSampleRate,
        reason: '${role.name}: sample rate',
      );
      expect(d.getUint16(34, Endian.little), 32, reason: '${role.name}: bits');
      expect(
        bytes.length,
        RuntimeSignalWav.headerBytes + spec.sampleCount * 4,
        reason: '${role.name}: size',
      );
      final samples = (await provider.samplesFor(role))!;
      expect(samples.length, spec.sampleCount, reason: role.name);
      expect(
        samples.length / evaluationSampleRate,
        closeTo(expectedSeconds[role]!, 1e-9),
        reason: '${role.name}: duration',
      );
      expect(
        sha256.convert(bytesOf(samples)).toString(),
        spec.pcmSha256,
        reason: '${role.name}: PCM hash',
      );
    }
  });

  test('the cache identity is unchanged: original recording hash + validated signal id', () {
    expect(
      CanonicalSignal.forRole(EvaluationRole.rhythm).keyFor('n').signalId,
      'wyrmtone-rhythm-v1#T15',
    );
    expect(
      CanonicalSignal.forRole(EvaluationRole.lead).keyFor('n').signalId,
      'wyrmtone-lead-v1#T15',
    );
    expect(
      CanonicalSignal.forRole(EvaluationRole.clean).keyFor('n').signalId,
      'wyrmtone-clean-v1',
    );
    for (final role in EvaluationRole.values) {
      expect(
        CanonicalSignal.forRole(role).keyFor('n').signalSha256,
        EvaluationSignalRegistry.forRole(role)!.sha256,
      );
    }
  });

  test(
    'the product flow really asks for the clean signal for clean targets',
    () async {
      final p = LocalToneKnowledgeProvider(await loadTestVault());
      final roles = <EvaluationRole>{};
      for (final text in [
        'Nirvana - Come As You Are',
        'Pantera - Heresy',
        'Gary Moore - The Loner',
      ]) {
        final intent = (await p.resolve(ToneMatchRequest(text: text)))!;
        roles.add(const AcousticTargetMapper().map(intent).signalRole);
      }
      expect(roles, {
        EvaluationRole.clean,
        EvaluationRole.rhythm,
        EvaluationRole.lead,
      });
    },
  );

  test('a missing, damaged or wrong signal gives null and a log line, never an exception', () async {
    final good = await File(
      ToneMatchRuntimeSignals.spec(EvaluationRole.lead).asset,
    ).readAsBytes();
    final flipped = Uint8List.fromList(good)..[1000] ^= 0x01;
    final cases = <String, Future<ByteData> Function(String)>{
      'missing': (a) async => throw const FileSystemException('missing'),
      'flipped bit': (a) async => ByteData.sublistView(flipped),
      'truncated': (a) async =>
          ByteData.sublistView(good.sublist(0, good.length - 8)),
      'garbage': (a) async => ByteData.sublistView(Uint8List(100)),
    };
    for (final e in cases.entries) {
      final logs = <String>[];
      final provider = BundledToneMatchSignalProvider(
        load: e.value,
        log: logs.add,
      );
      expect(
        await provider.samplesFor(EvaluationRole.lead),
        isNull,
        reason: e.key,
      );
      expect(logs, hasLength(1), reason: e.key);
      final runner = IsolateToneAnalysisRunner(bundled: provider);
      expect(
        await runner.isAvailableFor(EvaluationRole.lead),
        isFalse,
        reason: e.key,
      );
      // The user-facing text never mentions the technical cause.
      expect(logs.single.toLowerCase(), contains('signal'));
    }
  });

  test('a release build never reads the development override folder; the bundled signals are the product source', () {
    final app = File('lib/app.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(app, contains('kReleaseMode ? null : toneMatchSignalDirectory'));
    expect(app, contains('BundledToneMatchSignalProvider()'));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('assets/tonematch/runtime/'));
    expect(pubspec, isNot(contains('tonematch/evaluation')));
  });

  test('container round trip is exact and strict', () {
    final pcm = Float32List.fromList([0, 1, -1, 0.123456789, 1e-30, -3.4e38]);
    final wav = RuntimeSignalWav.encode(pcm);
    expect(bytesOf(RuntimeSignalWav.decode(wav)!), bytesOf(pcm));
    expect(RuntimeSignalWav.decode(wav, sampleRate: 44100), isNull);
    expect(RuntimeSignalWav.decode(Uint8List.fromList(wav)..[20] = 1), isNull);
  });
}
