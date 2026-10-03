import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:wyrmtone/presets/canonical_preset.dart' show canonicalJson;

import 'capture_analysis.dart';
import 'nam_clodata_converter.dart';
import 'nam_file_profile.dart';
import 'nam_golden_corpus.dart';
import 'nam_transfer_analysis.dart';
import 'usb_capture_reader.dart';

/// Offline NAM-transfer evidence tool. Reads files only: no USB, MIDI, adb or
/// network access, and nothing is ever sent to a device.
///
/// ```text
/// describe-nam FILE.nam [--output report.json]
/// inspect CAPTURE.pcapng [--nam FILE.nam] [--include-isochronous] [--output report.json]
/// compare A=CAPTURE B=CAPTURE [C=CAPTURE ...] [--output report.json]
/// messages CAPTURE [--output messages.jsonl]   (canonical logical messages)
/// analyze-transfer A=CAPTURE B=CAPTURE ... [--nam-for A=FILE.nam ...] --out-dir DIR [--output report.json]
/// golden-report [--captures DIR] [--output report.json]   (corpus validation, ~25 s per case)
/// nam-to-clodata 48000.wav nam_output_wav.wav --name FILE.nam --clodata OUT.bin [--output report.json]
/// ```
/// Run with `dart run tool/matribox_nam_analysis/matribox_nam_analysis.dart`.
void main(List<String> args) {
  try {
    if (args.isEmpty) throw const FormatException(_usage);
    final options = _Options.parse(args.skip(1).toList());
    final report = switch (args.first) {
      'describe-nam' => _describe(options),
      'inspect' => _inspect(options),
      'compare' => _compare(options),
      'messages' => _messages(options),
      'analyze-transfer' => _analyzeTransfer(options),
      'nam-to-clodata' => _namToCloData(options),
      'golden-report' => _goldenReport(options),
      _ => throw const FormatException(_usage),
    };
    final json = report is String
        ? report
        : '${canonicalJson(report, pretty: true)}\n';
    if (options.output != null) {
      File(options.output!).writeAsStringSync(json);
      stdout.writeln('Report written to ${options.output}');
    } else {
      stdout.write(json);
    }
  } on Object catch (error) {
    stderr.writeln('matribox_nam_analysis failed: $error');
    exitCode = 1;
  }
}

const _usage =
    'Usage: describe-nam <file.nam> | inspect <capture> [--nam f] | '
    'compare A=<capture> B=<capture> [...] [--output report.json] | '
    'nam-to-clodata <48000.wav> <nam_output_wav.wav> --name <f.nam> --clodata <out.bin>';

class _Options {
  _Options(
    this.positional,
    this.output,
    this.nam,
    this.includeIsochronous,
    this.namFor,
    this.outDir,
    this.name,
    this.cloDataPath,
    this.captures,
  );
  final List<String> positional;
  final Map<String, String> namFor;
  final String? outDir;
  final String? name;
  final String? cloDataPath;
  final String? captures;
  final String? output;
  final String? nam;
  final bool includeIsochronous;

  factory _Options.parse(List<String> args) {
    final positional = <String>[];
    String? output, nam, outDir, name, cloDataPath, captures;
    final namFor = <String, String>{};
    var iso = false;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--output':
          output = args[++i];
        case '--nam':
          nam = args[++i];
        case '--nam-for':
          final split = args[++i].split('=');
          if (split.length < 2) {
            throw const FormatException('Use --nam-for LABEL=FILE.');
          }
          namFor[split.first] = split.sublist(1).join('=');
        case '--out-dir':
          outDir = args[++i];
        case '--name':
          name = args[++i];
        case '--clodata':
          cloDataPath = args[++i];
        case '--captures':
          captures = args[++i];
        case '--include-isochronous':
          iso = true;
        default:
          if (args[i].startsWith('--')) {
            throw FormatException('Unknown option ${args[i]}');
          }
          positional.add(args[i]);
      }
    }
    return _Options(
      positional,
      output,
      nam,
      iso,
      namFor,
      outDir,
      name,
      cloDataPath,
      captures,
    );
  }
}

NamFileProfile _profile(String path) => NamFileProfile.describe(
  File(path).readAsBytesSync(),
  fileName: File(path).uri.pathSegments.last,
);

Map<String, Object?> _describe(_Options o) {
  if (o.positional.length != 1) throw const FormatException(_usage);
  final profile = _profile(o.positional.single);
  return {
    'schemaVersion': 1,
    'offlineOnly': true,
    'file': profile.report,
    'needles': [
      for (final n in profile.needles)
        {'label': n.label, 'length': n.bytes.length},
    ],
  };
}

UsbCapture _read(String path) =>
    readUsbCapture(Uint8List.fromList(File(path).readAsBytesSync()));

Map<String, Object?> _inspect(_Options o) {
  if (o.positional.length != 1) throw const FormatException(_usage);
  final profile = o.nam == null ? null : _profile(o.nam!);
  return {
    'schemaVersion': 1,
    'offlineOnly': true,
    'source': File(o.positional.single).uri.pathSegments.last,
    'nam': profile?.report,
    ...inspectCapture(
      _read(o.positional.single),
      needles: profile?.needles ?? const [],
      options: AnalysisOptions(includeIsochronous: o.includeIsochronous),
    ),
  };
}

/// Offline conversion of the editor's reference/model-output WAV pair into
/// the 8,232-byte CloData block (about 10 s). Writes a file only.
Map<String, Object?> _namToCloData(_Options o) {
  if (o.positional.length != 2 || o.name == null || o.cloDataPath == null) {
    throw const FormatException(_usage);
  }
  final result = const MatriboxNamCloDataConverter().convert(
    referenceWav: File(o.positional[0]).readAsBytesSync(),
    modelOutputWav: File(o.positional[1]).readAsBytesSync(),
    fileName: o.name!,
    log: (message) => stderr.writeln(message),
  );
  File(o.cloDataPath!).writeAsBytesSync(result.requireComplete());
  return {
    'schemaVersion': 1,
    'offlineOnly': true,
    'clodata': o.cloDataPath,
    'length': result.bytes.length,
  };
}

/// Runs every golden-corpus case twice and reports byte comparison, hashes
/// and determinism. Cases with missing files are reported as NOT TESTED.
Map<String, Object?> _goldenReport(_Options o) {
  final root = o.captures ?? matriboxCaptureRoot;
  final cases = <Map<String, Object?>>[];
  for (final golden in matriboxGoldenCorpus) {
    final files = [
      File('$root/${golden.referenceWav}'),
      File('$root/${golden.outputWav}'),
      File('$root/${golden.capture ?? golden.officialClodata}'),
    ];
    final missing = [
      for (final f in files)
        if (!f.existsSync()) f.path,
    ];
    if (missing.isNotEmpty) {
      cases.add({
        'id': golden.id,
        'result': 'NOT TESTED',
        'missingFiles': missing,
      });
      continue;
    }
    final data = [for (final f in files) f.readAsBytesSync()];
    final hashes = [for (final d in data) sha256.convert(d).toString()];
    final namFile = golden.namLocalPath == null
        ? null
        : File(golden.namLocalPath!);
    final namHash = namFile != null && namFile.existsSync()
        ? sha256.convert(namFile.readAsBytesSync()).toString()
        : null;
    final inputsMatch =
        hashes[0] == golden.referenceWavSha256 &&
        hashes[1] == golden.outputWavSha256 &&
        hashes[2] == (golden.captureSha256 ?? golden.clodataSha256) &&
        (namHash == null || namHash == golden.namSha256);
    final expected = golden.capture != null
        ? matriboxCloDataFromCapture(data[2])
        : data[2];
    final runs = [
      for (var i = 0; i < 2; i++)
        const MatriboxNamCloDataConverter()
            .convert(
              referenceWav: data[0],
              modelOutputWav: data[1],
              fileName: golden.storedName,
            )
            .bytes,
    ];
    final diff = MatriboxCloDataDiff(expected, runs[0]);
    final runHashes = [for (final r in runs) sha256.convert(r).toString()];
    cases.add({
      'id': golden.id,
      'result': inputsMatch && diff.identical ? 'IDENTICAL' : 'MISMATCH',
      'inputHashesMatchCorpus': inputsMatch,
      'expectedSize': diff.expectedLength,
      'actualSize': diff.actualLength,
      'matchingBytes': diff.matching,
      'differingBytes': diff.differing,
      'firstDifferingOffset': diff.firstDifference,
      'differingRegions': diff.regions.length,
      'expectedSha256': sha256.convert(expected).toString(),
      'expectedFromCapture': golden.capture != null,
      'namHashChecked': namHash != null,
      'actualSha256': runHashes[0],
      'deterministic': runHashes[0] == runHashes[1],
    });
  }
  return {
    'schemaVersion': 1,
    'offlineOnly': true,
    'cases': cases,
    'needsOfficialOutput': [
      for (final c in matriboxGoldenCandidates)
        {
          'name': c.displayName,
          'namSha256': c.namSha256,
          'characteristics': c.characteristics,
        },
    ],
  };
}

final _nl = String.fromCharCode(10);

/// One JSON object per line: index, time, direction, endpoint, kind, hex.
String _messages(_Options o) {
  if (o.positional.length != 1) throw const FormatException(_usage);
  final messages = extractMessages(
    _read(o.positional.single),
    AnalysisOptions(includeIsochronous: o.includeIsochronous),
  );
  return [
        for (final m in messages)
          jsonEncode({
            'i': m.index,
            't': m.timestampUs,
            'dir': m.direction.name,
            'ep': m.endpoint,
            'kind': m.kind,
            'hex': m.bytes
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(),
          }),
      ].join(_nl) +
      _nl;
}

Map<String, Object?> _compare(_Options o) {
  final captures = <String, UsbCapture>{};
  for (final entry in o.positional) {
    final split = entry.indexOf('=');
    if (split <= 0) {
      throw const FormatException('Use LABEL=<capture> for compare.');
    }
    captures[entry.substring(0, split)] = _read(entry.substring(split + 1));
  }
  return {
    'schemaVersion': 1,
    'offlineOnly': true,
    ...compareCaptures(
      captures,
      options: AnalysisOptions(includeIsochronous: o.includeIsochronous),
    ),
  };
}

Map<String, Object?> _analyzeTransfer(_Options o) {
  final captures = <String, UsbCapture>{};
  for (final entry in o.positional) {
    final split = entry.indexOf('=');
    if (split <= 0) throw const FormatException('Use LABEL=<capture>.');
    captures[entry.substring(0, split)] = _read(entry.substring(split + 1));
  }
  final analysis = analyzeCloneTransfers(
    captures,
    namFiles: {
      for (final e in o.namFor.entries) e.key: File(e.value).readAsBytesSync(),
    },
    namFileNames: {
      for (final e in o.namFor.entries)
        e.key: File(e.value).uri.pathSegments.last,
    },
  );
  final dir = o.outDir;
  if (dir != null) {
    Directory(dir).createSync(recursive: true);
    for (final artifact in analysis.artifacts.entries) {
      File('$dir/${artifact.key}').writeAsBytesSync(artifact.value);
    }
  }
  return analysis.report;
}
