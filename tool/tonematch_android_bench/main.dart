/// Internal Tone Match Android performance harness (docs/TONE_MATCH.md section 10). READ/COMPUTE
/// ONLY: no USB, no MIDI, no Matribox, no writes except its own results/cache files. Not part of the
/// product UI and never built into the release APK (separate entry point: `flutter build apk -t`).
///
/// Modes (from `bench_config.json` in the app's external files dir):
///  - "perf": scripted suite (cold/warm x RHYTHM/LEAD x 5/10 candidates, memory, cancel, run after cancel)
///  - "ui":   one LEAD x 10 cold run with a visible UI (scroll list, animation, Cancel button) that the
///            host drives with `adb input` while it records frame/heartbeat statistics.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'bench_worker.dart';

const _files = '/storage/emulated/0/Android/data/de.neevel.wyrmtone.bench/files';

/// Writes a result file, relaxes its mode so `adb pull` can read it (best effort) and also dumps it to
/// logcat in chunks (tag flutter) as a fallback: the file system copy is the primary channel.
void _publish(String name, String json) {
  final f = File('$_files/$name')..writeAsStringSync(json);
  try {
    Process.runSync('chmod', ['666', f.path]);
  } on Object {
    // best effort only
  }
  const chunk = 3000;
  for (var i = 0; i < json.length; i += chunk) {
    // ignore: avoid_print
    print('BENCH_JSON $name ${i ~/ chunk} ${json.substring(i, i + chunk > json.length ? json.length : i + chunk)}');
  }
}

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: BenchPage()));

class BenchPage extends StatefulWidget {
  const BenchPage({super.key});
  @override
  State<BenchPage> createState() => _BenchPageState();
}

class _Metrics {
  double maxLateMs = 0;
  final late = <double>[];
  int frames = 0, jank16 = 0, jank33 = 0, jank100 = 0;
  double worstFrameMs = 0;
  Map<String, Object?> toJson() {
    final s = [...late]..sort();
    return {
      'heartbeatMaxLateMs': maxLateMs,
      'heartbeatP99LateMs': s.isEmpty ? 0 : s[(s.length * 0.99).floor().clamp(0, s.length - 1)],
      'heartbeatTicks': late.length,
      'frames': frames,
      'frames>16.7ms': jank16,
      'frames>33ms': jank33,
      'frames>100ms': jank100,
      'worstFrameMs': worstFrameMs,
    };
  }
}

class _BenchPageState extends State<BenchPage> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  final Pointer<Uint8> _cancel = calloc<Uint8>();
  String _status = 'bereit';
  String _progress = '';
  bool _running = false;
  _Metrics _metrics = _Metrics();
  Timer? _heartbeat, _rssTimer;
  final _sw = Stopwatch()..start();
  int _lastBeat = 0;
  bool _measuring = false;
  int _rssPeakKb = 0;
  Map<String, Object?> _cfg = {};

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback((timings) {
      if (!_measuring) return;
      for (final t in timings) {
        final ms = t.totalSpan.inMicroseconds / 1000;
        _metrics.frames++;
        if (ms > 16.7) _metrics.jank16++;
        if (ms > 33.3) _metrics.jank33++;
        if (ms > 100) _metrics.jank100++;
        if (ms > _metrics.worstFrameMs) _metrics.worstFrameMs = ms;
      }
    });
    _lastBeat = _sw.elapsedMicroseconds;
    _heartbeat = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final now = _sw.elapsedMicroseconds;
      final late = (now - _lastBeat) / 1000 - 10;
      _lastBeat = now;
      if (_measuring) {
        _metrics.late.add(late < 0 ? 0 : late);
        if (late > _metrics.maxLateMs) _metrics.maxLateMs = late;
      }
    });
    _rssTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_measuring) {
        final v = _readStatus()['VmRSS'] ?? 0;
        if (v > _rssPeakKb) _rssPeakKb = v;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Map<String, int> _readStatus() {
    final out = <String, int>{};
    try {
      for (final l in File('/proc/self/status').readAsLinesSync()) {
        final m = RegExp(r'^(VmRSS|VmHWM|VmSize):\s+(\d+) kB').firstMatch(l);
        if (m != null) out[m.group(1)!] = int.parse(m.group(2)!);
      }
    } on Object {
      // not available: leave empty
    }
    return out;
  }

  int _pssKb() {
    try {
      for (final l in File('/proc/self/smaps_rollup').readAsLinesSync()) {
        final m = RegExp(r'^Pss:\s+(\d+) kB').firstMatch(l);
        if (m != null) return int.parse(m.group(1)!);
      }
    } on Object {
      // ignore
    }
    return 0;
  }

  Future<void> _boot() async {
    final cfgFile = File('$_files/bench_config.json');
    if (!cfgFile.existsSync()) {
      setState(() => _status = 'keine bench_config.json');
      return;
    }
    _cfg = (jsonDecode(cfgFile.readAsStringSync()) as Map).cast<String, Object?>();
    await Future<void>.delayed(const Duration(seconds: 2)); // let the first frames settle
    if (_cfg['mode'] == 'perf') {
      await _perfSuite();
    } else if (_cfg['mode'] == 'ui') {
      await _uiRun();
    }
  }

  List<String> _ids(int n) => ((_cfg[n == 5 ? 'set5' : 'set10'])! as List).cast<String>();
  Map<String, String> get _namSha => ((_cfg['nams'])! as Map).map((k, v) => MapEntry(k as String, (v as Map)['sha'] as String));

  /// One Tone Match run in a worker isolate. [cancelAfterCandidate]: request cancel [cancelDelayMs]
  /// after that candidate started (simulating the Cancel button).
  Future<Map<String, Object?>> _run(String role, int n, {required bool warm, Map<String, String>? derived, int? cancelAfterCandidate, int cancelDelayMs = 1000}) async {
    _cancel.value = 0;
    final rp = ReceivePort();
    final before = _readStatus();
    _rssPeakKb = before['VmRSS'] ?? 0;
    _metrics = _Metrics();
    _measuring = true;
    final startEpoch = DateTime.now().millisecondsSinceEpoch;
    final wall = Stopwatch()..start();
    final cacheDir = '$_files/cache_${role}_$n';
    final isolate = await Isolate.spawn(workerMain, WorkerJob(
      port: rp.sendPort,
      cancelAddress: _cancel.address,
      filesDir: _files,
      role: role,
      namIds: _ids(n),
      namSha: _namSha,
      warm: warm,
      cacheDir: cacheDir,
      derived: derived,
    ));
    final events = <Map<String, Object?>>[];
    int? cancelRequestedMs;
    Map<String, Object?>? last;
    await for (final raw in rp) {
      final m = (raw as Map).cast<String, Object?>();
      events.add(m);
      if (mounted) {
        setState(() {
          _progress = m['type'] == 'candidateStart' ? 'Analysiere ${(m['index']! as int) + 1} von $n' : _progress;
          _status = '$role × $n ${warm ? 'warm' : 'cold'}';
        });
      }
      if (cancelAfterCandidate != null && m['type'] == 'candidateStart' && m['index'] == cancelAfterCandidate) {
        Timer(Duration(milliseconds: cancelDelayMs), () {
          cancelRequestedMs = wall.elapsedMilliseconds;
          _cancel.value = 1; // same effect as the Cancel button
        });
      }
      if (m['type'] == 'done' || m['type'] == 'cancelled' || m['type'] == 'error') {
        last = m;
        break;
      }
    }
    final wallMs = wall.elapsedMilliseconds;
    _measuring = false;
    rp.close();
    isolate.kill();
    final after = _readStatus();
    return {
      'role': role,
      'n': n,
      'warm': warm,
      'startEpochMs': startEpoch,
      'endEpochMs': DateTime.now().millisecondsSinceEpoch,
      'wallMs': wallMs,
      'end': last,
      'cancelRequestedAtMs': cancelRequestedMs,
      'cancelLatencyMs': cancelRequestedMs == null || last?['type'] != 'cancelled' ? null : wallMs - cancelRequestedMs!,
      'rssBeforeKb': before['VmRSS'],
      'rssPeakKb': _rssPeakKb,
      'rssAfterKb': after['VmRSS'],
      'vmHwmKb': after['VmHWM'],
      'pssAfterKb': _pssKb(),
      'main': _metrics.toJson(),
      'events': events,
    };
  }

  Future<void> _perfSuite() async {
    setState(() => _running = true);
    final out = <String, Object?>{
      'device': {'os': Platform.operatingSystemVersion, 'dart': Platform.version, 'cpus': Platform.numberOfProcessors},
      'baselineRssKb': _readStatus()['VmRSS'],
      'basePssKb': _pssKb(),
      'runs': <Map<String, Object?>>[],
    };
    final runs = out['runs']! as List<Map<String, Object?>>;
    void save() => File('$_files/results_perf.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
    void publish() => _publish('results_perf.json', const JsonEncoder.withIndent(' ').convert(out));
    for (final role in ['rhythm', 'lead']) {
      for (final n in [5, 10]) {
        Map<String, String>? derived;
        for (var i = 0; i < 3; i++) {
          final r = await _run(role, n, warm: false);
          r['label'] = 'cold ${role}x$n run ${i + 1}';
          runs.add(r);
          for (final e in (r['events']! as List).cast<Map<String, Object?>>()) {
            if (e['type'] == 'signal' && e['derivedId'] != null) derived = {'id': e['derivedId']! as String, 'sha256': e['derivedSha256']! as String};
          }
          save();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        for (var i = 0; i < 3; i++) {
          final r = await _run(role, n, warm: true, derived: derived);
          r['label'] = 'warm ${role}x$n run ${i + 1}';
          runs.add(r);
          save();
        }
      }
    }
    // cancel during a 10-candidate cold run, then a fresh run
    final c = await _run('lead', 10, warm: false, cancelAfterCandidate: 2);
    c['label'] = 'cancel leadx10 (after candidate 3 started +1 s)';
    runs.add(c);
    save();
    final after = await _run('rhythm', 5, warm: false);
    after['label'] = 'run after cancel rhythmx5';
    runs.add(after);
    out['idleRssKb'] = _readStatus()['VmRSS'];
    save();
    publish();
    File('$_files/PERF_DONE').writeAsStringSync('done');
    setState(() {
      _running = false;
      _status = 'perf suite fertig';
    });
  }

  Future<void> _uiRun() async {
    setState(() => _running = true);
    final r = await _run('lead', 10, warm: false);
    r['label'] = 'ui run leadx10';
    _publish('results_ui.json', const JsonEncoder.withIndent(' ').convert(r));
    if (mounted) {
      setState(() {
        _running = false;
        _status = (r['end'] as Map?)?['type'] == 'cancelled' ? 'abgebrochen' : 'fertig';
      });
    }
    File('$_files/UI_DONE').writeAsStringSync('done');
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _rssTimer?.cancel();
    _spin.dispose();
    calloc.free(_cancel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tone Match Benchmark')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              RotationTransition(turns: _spin, child: const Icon(Icons.autorenew, size: 36)),
              const SizedBox(width: 12),
              Expanded(child: Text('$_status\n$_progress', key: const Key('status'))),
              FilledButton(key: const Key('cancel'), onPressed: _running ? () => _cancel.value = 1 : null, child: const Text('Abbrechen')),
            ],
          ),
        ),
        const LinearProgressIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: 120,
            itemBuilder: (_, i) => ListTile(title: Text('Eintrag $i'), subtitle: const Text('scrollbar während der Analyse')),
          ),
        ),
      ],
    ),
  );
}
