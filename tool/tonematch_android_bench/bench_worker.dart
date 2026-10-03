/// Worker side of the Tone Match Android performance harness. Runs in its own isolate so the Flutter
/// main isolate never computes. Candidates are analysed strictly one after the other with the
/// EXISTING analyzer (AnalysisVersion 1); cancellation uses a shared native flag (no isolate kill).
/// Harness code only: nothing in lib/ imports it.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:wyrmtone/services/local_persistence.dart';
import 'package:wyrmtone/services/nam_inference_engine.dart';
import 'package:wyrmtone/tonematch/analysis_interfaces.dart';
import 'package:wyrmtone/tonematch/evaluation_signal.dart';
import 'package:wyrmtone/tonematch/evaluation_signal_loader.dart';
import 'package:wyrmtone/tonematch/nam_inference_analyzer.dart';
import 'package:wyrmtone/tonematch/tone_features.dart';
import 'package:wyrmtone/tonematch/tone_match_cache.dart';
import 'package:wyrmtone/tonematch/tone_match_models.dart';

import '../tonematch_gate/gate_dsp.dart';

/// File-backed [StringStore] (one file per key) so the cache-write cost includes real storage I/O.
class FileStringStore implements StringStore {
  FileStringStore(this.dir) {
    Directory(dir).createSync(recursive: true);
  }
  final String dir;
  File _file(String key) => File('$dir/${sha256.convert(utf8.encode(key))}.json');
  @override
  Future<String?> read(String key) async {
    final f = _file(key);
    return f.existsSync() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async => _file(key).writeAsString(value, flush: true);

  void clear() {
    final d = Directory(dir);
    if (d.existsSync()) d.deleteSync(recursive: true);
    d.createSync(recursive: true);
  }
}

class WorkerJob {
  const WorkerJob({
    required this.port,
    required this.cancelAddress,
    required this.filesDir,
    required this.role,
    required this.namIds,
    required this.namSha,
    required this.warm,
    required this.cacheDir,
    this.derived,
  });
  final SendPort port;
  final int cancelAddress;
  final String filesDir, role, cacheDir;
  final List<String> namIds;
  final Map<String, String> namSha;
  final bool warm;

  /// For warm runs: the derived T15 signal identity from the cold run ({id, sha256}).
  final Map<String, String>? derived;
}

Future<void> workerMain(WorkerJob job) async {
  final out = job.port;
  final cancel = Pointer<Uint8>.fromAddress(job.cancelAddress);
  bool cancelled() => cancel.value != 0;
  final total = Stopwatch()..start();
  var enginesCreated = 0, analyzeCalls = 0;
  try {
    final store = FileStringStore(job.cacheDir);
    final cache = StringStoreToneMatchCache(store);
    final role = EvaluationRole.values.byName(job.role);
    final base = EvaluationSignalRegistry.forRole(role)!;
    late PreparedEvaluationSignal t15;
    String derivedId, derivedSha;

    if (job.warm) {
      // A cache hit needs no WAV and no engine: the key is NAM sha + derived signal identity + version.
      derivedId = job.derived!['id']!;
      derivedSha = job.derived!['sha256']!;
      t15 = PreparedEvaluationSignal(descriptor: _derivedDescriptor(base, derivedId, derivedSha), samples: Float32List(0), decodeMs: 0, resampleMs: 0);
      out.send({'type': 'signal', 'decodeMs': 0, 'resampleMs': 0, 'deriveMs': 0, 'skipped': true});
    } else {
      store.clear();
      final descriptor = EvaluationSignalDescriptor.fromJson({...base.toJson(), 'file': '${job.filesDir}/${base.id}.wav'});
      final prepared = await const FileEvaluationSignalLoader(_read).prepare(descriptor);
      final derive = Stopwatch()..start();
      final variant = buildVariants(prepared.samples, contentSeconds: [15]).firstWhere((v) => v.id == 'T15');
      derivedId = '${base.id}#T15';
      derivedSha = sha256.convert(variant.samples.buffer.asUint8List(variant.samples.offsetInBytes, variant.samples.lengthInBytes)).toString();
      derive.stop();
      t15 = PreparedEvaluationSignal(descriptor: _derivedDescriptor(base, derivedId, derivedSha), samples: variant.samples, decodeMs: prepared.decodeMs, resampleMs: prepared.resampleMs);
      out.send({'type': 'signal', 'decodeMs': prepared.decodeMs, 'resampleMs': prepared.resampleMs, 'deriveMs': derive.elapsedMilliseconds, 'samples': variant.samples.length, 'derivedId': derivedId, 'derivedSha256': derivedSha});
    }

    final analyzer = NamInferenceAnalyzer(createEngine: () {
      enginesCreated++;
      return NamInferenceEngine.create();
    });
    for (var i = 0; i < job.namIds.length; i++) {
      final id = job.namIds[i];
      if (cancelled()) {
        out.send({'type': 'cancelled', 'before': i, 'enginesCreated': enginesCreated, 'analyzeCalls': analyzeCalls, 'totalMs': total.elapsedMilliseconds});
        return;
      }
      out.send({'type': 'candidateStart', 'index': i, 'id': id});
      final candidate = Stopwatch()..start();
      final key = NamAnalysisKey(namSha256: job.namSha[id]!, signalSha256: derivedSha, signalId: derivedId, analysisVersion: toneAnalysisVersion);
      final readWatch = Stopwatch()..start();
      final hit = await cache.read(key);
      readWatch.stop();
      if (hit != null) {
        out.send({'type': 'candidate', 'index': i, 'id': id, 'cacheHit': true, 'cacheReadMs': readWatch.elapsedMicroseconds / 1000, 'totalMs': candidate.elapsedMicroseconds / 1000, 'tone': _summary(hit)});
        continue;
      }
      NamAnalysis analysis;
      try {
        analyzeCalls++;
        analysis = await analyzer.analyze(NamAnalysisSource(path: '${job.filesDir}/nams/nam_$id.nam', sha256: job.namSha[id]!), t15, isCancelled: cancelled);
      } on AnalysisCancelled {
        out.send({'type': 'cancelled', 'during': i, 'enginesCreated': enginesCreated, 'analyzeCalls': analyzeCalls, 'totalMs': total.elapsedMilliseconds});
        return;
      }
      final write = Stopwatch()..start();
      await cache.write(analysis);
      write.stop();
      out.send({
        'type': 'candidate',
        'index': i,
        'id': id,
        'cacheHit': false,
        'cacheReadMs': readWatch.elapsedMicroseconds / 1000,
        'namLoadMs': analysis.timings.namLoadMs,
        'inferenceMs': analysis.timings.inferenceMs,
        'extractionMs': analysis.timings.extractionMs,
        'cacheWriteMs': write.elapsedMicroseconds / 1000,
        'totalMs': candidate.elapsedMicroseconds / 1000,
        'tone': _summary(analysis),
      });
    }
    out.send({'type': 'done', 'enginesCreated': enginesCreated, 'analyzeCalls': analyzeCalls, 'totalMs': total.elapsedMilliseconds});
  } on Object catch (e, st) {
    out.send({'type': 'error', 'message': '$e', 'stack': '$st'});
  }
}

Map<String, double> _summary(NamAnalysis a) => {
  for (final k in [ToneFeatureIds.centroidHz, ToneFeatureIds.crestDb, ToneFeatureIds.saturationComposite, ToneFeatureIds.attackMs]) k: a.features.tone[k] ?? double.nan,
};

EvaluationSignalDescriptor _derivedDescriptor(EvaluationSignalDescriptor base, String id, String sha) =>
    EvaluationSignalDescriptor.fromJson({...base.toJson(), 'id': id, 'sha256': sha});

Future<Uint8List> _read(String p) => File(p).readAsBytes();
