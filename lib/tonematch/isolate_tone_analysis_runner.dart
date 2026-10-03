import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../services/nam_inference_engine.dart';
import 'analysis_interfaces.dart';
import 'evaluation_signal.dart';
import 'evaluation_signal_loader.dart';
import 'evaluation_signal_t15.dart';
import 'nam_inference_analyzer.dart';
import 'tone_analysis_runner.dart';
import 'tone_match_models.dart';
import 'tone_match_runtime_signals.dart';

/// Production runner: measures the NAMs in ONE worker isolate (the Flutter main isolate never
/// computes), strictly one after the other with the existing [NamInferenceAnalyzer]. Cancellation uses
/// a flag in shared native memory (no isolate kill): the running 1-second chunk finishes, nothing
/// further starts, the unfinished result is discarded and the engine is released.
class IsolateToneAnalysisRunner implements ToneAnalysisRunner {
  /// The signals come from the app ([bundled]). [developmentOverrideDirectory] is for development and
  /// tests only: if it holds the research recording (`wyrmtone-<role>-v1.wav`) for a role, that is used
  /// instead; the app passes it only outside release builds, so a release user never depends on it.
  IsolateToneAnalysisRunner({
    required this.bundled,
    this.developmentOverrideDirectory,
  });
  final BundledToneMatchSignalProvider bundled;
  final Future<String?> Function()? developmentOverrideDirectory;
  Pointer<Uint8>? _flag;

  Future<String?> _overrideFor(EvaluationRole role) async {
    final dir = await developmentOverrideDirectory?.call();
    if (dir == null) return null;
    return File('$dir/${EvaluationSignalRegistry.forRole(role)!.id}.wav')
            .existsSync()
        ? dir
        : null;
  }

  @override
  Future<bool> isAvailableFor(EvaluationRole role) async =>
      await _overrideFor(role) != null ||
      await bundled.samplesFor(role) != null;

  @override
  void cancel() {
    final f = _flag;
    if (f != null) f.value = 1;
  }

  @override
  Stream<AnalysisEvent> run(
    EvaluationRole role,
    List<AnalysisCandidate> candidates,
  ) {
    final controller = StreamController<AnalysisEvent>();
    // A listener that leaves early means "cancel"; the worker still ends on its own and cleans up.
    controller.onCancel = cancel;
    unawaited(_run(controller, role, candidates));
    return controller.stream;
  }

  Future<void> _run(
    StreamController<AnalysisEvent> out,
    EvaluationRole role,
    List<AnalysisCandidate> candidates,
  ) async {
    void emit(AnalysisEvent e) {
      if (!out.isClosed && out.hasListener) out.add(e);
    }

    final dir = await _overrideFor(role);
    final bundledSamples = dir == null ? await bundled.samplesFor(role) : null;
    if (dir == null && bundledSamples == null) {
      for (final c in candidates) {
        emit(CandidateFailed(c.id, 'Messsignal nicht verfügbar'));
      }
      await out.close();
      return;
    }
    final flag = calloc<Uint8>();
    _flag = flag;
    final port = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        toneAnalysisWorkerMain,
        ToneAnalysisJob(
          port: port.sendPort,
          cancelAddress: flag.address,
          signalDir: dir,
          samples: bundledSamples == null
              ? null
              : TransferableTypedData.fromList([bundledSamples]),
          role: role.name,
          candidates: [
            for (final c in candidates) [c.id, c.path, c.sha256],
          ],
        ),
      );
      await for (final raw in port) {
        final m = (raw as Map).cast<String, Object?>();
        switch (m['type']) {
          case 'started':
            emit(CandidateStarted(m['id']! as String));
          case 'analyzed':
            emit(
              CandidateAnalyzed(
                m['id']! as String,
                NamAnalysis.fromJson(
                  (m['analysis']! as Map).cast<String, Object?>(),
                ),
              ),
            );
          case 'failed':
            emit(CandidateFailed(m['id']! as String, m['message']! as String));
          case 'stopped':
            emit(const AnalysisStopped());
          case 'fatal':
            for (final c in candidates) {
              emit(CandidateFailed(c.id, m['message']! as String));
            }
        }
        if (m['type'] == 'done' ||
            m['type'] == 'stopped' ||
            m['type'] == 'fatal') {
          break;
        }
      }
    } finally {
      isolate?.kill();
      port.close();
      _flag = null;
      calloc.free(flag);
      await out.close();
    }
  }
}

/// Message sent to the worker isolate (internal to the runner).
class ToneAnalysisJob {
  const ToneAnalysisJob({
    required this.port,
    required this.cancelAddress,
    required this.signalDir,
    required this.samples,
    required this.role,
    required this.candidates,
  });
  final SendPort port;
  final int cancelAddress;

  /// Exactly one of the two is set: a development folder with the research recording, or the bundled PCM.
  final String? signalDir;
  final TransferableTypedData? samples;
  final String role;
  final List<List<String>> candidates; // [id, path, sha256]
}

/// Worker entry (top level so it can be spawned). One signal load, then the candidates in order.
Future<void> toneAnalysisWorkerMain(ToneAnalysisJob job) async {
  final out = job.port;
  final cancel = Pointer<Uint8>.fromAddress(job.cancelAddress);
  bool cancelled() => cancel.value != 0;
  try {
    final role = EvaluationRole.values.byName(job.role);
    final canonical = CanonicalSignal.forRole(role);
    Float32List samples;
    var decodeMs = 0, resampleMs = 0;
    if (job.samples != null) {
      samples = job.samples!.materialize().asFloat32List();
    } else {
      final descriptor = EvaluationSignalDescriptor.fromJson({
        ...canonical.descriptor.toJson(),
        'file': '${job.signalDir}/${canonical.descriptor.id}.wav',
      });
      final prepared = await const FileEvaluationSignalLoader(_read)
          .prepare(descriptor);
      samples = canonical.derivesT15
          ? EvaluationSignalT15.derive(prepared.samples)
          : prepared.samples;
      decodeMs = prepared.decodeMs;
      resampleMs = prepared.resampleMs;
    }
    // The signal's cache identity is the ORIGINAL recording + id; the PCM only feeds the engine.
    final signal = PreparedEvaluationSignal(
      descriptor: EvaluationSignalDescriptor.fromJson({
        ...canonical.descriptor.toJson(),
        'id': canonical.keyId,
      }),
      samples: samples,
      decodeMs: decodeMs,
      resampleMs: resampleMs,
    );
    final analyzer = NamInferenceAnalyzer(
      createEngine: NamInferenceEngine.create,
    );
    for (final c in job.candidates) {
      if (cancelled()) {
        out.send({'type': 'stopped'});
        return;
      }
      out.send({'type': 'started', 'id': c[0]});
      try {
        final analysis = await analyzer.analyze(
          NamAnalysisSource(path: c[1], sha256: c[2]),
          signal,
          isCancelled: cancelled,
        );
        out.send({
          'type': 'analyzed',
          'id': c[0],
          'analysis': analysis.toJson(),
        });
      } on AnalysisCancelled {
        out.send({'type': 'stopped'});
        return;
      } on Object catch (e) {
        out.send({'type': 'failed', 'id': c[0], 'message': '$e'});
      }
    }
    out.send({'type': 'done'});
  } on Object catch (e) {
    out.send({'type': 'fatal', 'message': '$e'});
  }
}

Future<Uint8List> _read(String p) => File(p).readAsBytes();
