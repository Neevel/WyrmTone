import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/matribox_nam_analysis/capture_analysis.dart';
import '../../tool/matribox_nam_analysis/clone_data.dart';
import '../../tool/matribox_nam_analysis/nam_transfer_codec.dart';
import '../../tool/matribox_nam_analysis/nam_clodata_converter.dart';
import '../../tool/matribox_nam_analysis/nam_golden_corpus.dart';
import '../../tool/matribox_nam_analysis/nam_file_profile.dart';
import '../../tool/matribox_nam_analysis/usb_capture_reader.dart';

Uint8List _json(Object value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

/// One USBPcap frame: request (host data) or completion (device data).
Uint8List _frame({
  required int endpoint,
  required int transfer,
  required bool completion,
  List<int> payload = const [],
}) {
  final data = ByteData(27 + payload.length)
    ..setUint16(0, 27, Endian.little)
    ..setUint8(16, completion ? 1 : 0)
    ..setUint8(21, endpoint)
    ..setUint8(22, transfer)
    ..setUint32(23, payload.length, Endian.little);
  final bytes = data.buffer.asUint8List();
  bytes.setRange(27, 27 + payload.length, payload);
  return bytes;
}

Uint8List _pcapng(List<Uint8List> frames, {int linkType = 249}) {
  final out = BytesBuilder();
  void block(int type, List<int> body) {
    final padded = (body.length + 3) & ~3;
    final header = ByteData(8)
      ..setUint32(0, type, Endian.little)
      ..setUint32(4, padded + 12, Endian.little);
    out
      ..add(header.buffer.asUint8List())
      ..add(body)
      ..add(List.filled(padded - body.length, 0))
      ..add(header.buffer.asUint8List(4, 4));
  }

  block(
    0x0a0d0d0a,
    (ByteData(16)
          ..setUint32(0, 0x1a2b3c4d, Endian.little)
          ..setUint16(4, 1, Endian.little)
          ..setUint64(8, -1, Endian.little))
        .buffer
        .asUint8List(),
  );
  block(
    1,
    (ByteData(8)
          ..setUint16(0, linkType, Endian.little)
          ..setUint32(4, 65535, Endian.little))
        .buffer
        .asUint8List(),
  );
  var tick = 1000000;
  for (final frame in frames) {
    final body = ByteData(20)
      ..setUint32(4, 0, Endian.little)
      ..setUint32(8, tick, Endian.little)
      ..setUint32(12, frame.length, Endian.little)
      ..setUint32(16, frame.length, Endian.little);
    tick += 1000; // 1 ms apart
    block(6, [...body.buffer.asUint8List(), ...frame]);
  }
  return out.toBytes();
}

Uint8List _pcap(List<Uint8List> frames) {
  final out = BytesBuilder();
  out.add(
    (ByteData(24)
          ..setUint32(0, 0xa1b2c3d4, Endian.little)
          ..setUint32(20, 249, Endian.little))
        .buffer
        .asUint8List(),
  );
  for (final frame in frames) {
    out.add(
      (ByteData(16)
            ..setUint32(8, frame.length, Endian.little)
            ..setUint32(12, frame.length, Endian.little))
          .buffer
          .asUint8List(),
    );
    out.add(frame);
  }
  return out.toBytes();
}

/// USB-MIDI 1.0 packets (cable 0) for one SysEx message.
List<int> _usbMidiSysex(List<int> sysex) {
  final packets = <int>[];
  for (var i = 0; i < sysex.length; i += 3) {
    final chunk = sysex.sublist(i, i + 3 > sysex.length ? sysex.length : i + 3);
    final last = i + 3 >= sysex.length;
    final cin = last ? const [0, 5, 6, 7][chunk.length] : 4;
    packets.addAll([cin, ...chunk, ...List.filled(3 - chunk.length, 0)]);
  }
  return packets;
}

UsbCapture _hostSysexCapture(List<List<int>> messages) => readUsbCapture(
  _pcapng([
    for (final m in messages)
      _frame(
        endpoint: 3,
        transfer: 3,
        completion: false,
        payload: _usbMidiSysex(m),
      ),
  ]),
);

List<int> _nibbleSysex(List<int> data, {int header = 8}) => [
  0xf0,
  ...List.filled(header - 1, 0x11),
  for (final b in data) ...[b >> 4, b & 0x0f],
  0xf7,
];

void main() {
  group('NamFileProfile', () {
    final wavenet = {
      'version': '0.5.4',
      'architecture': 'WaveNet',
      'config': {'layers': []},
      'weights': [0.5, -0.25, 1.5, 2.0, 3.0],
      'sample_rate': 48000,
      'metadata': {'name': 'Test Amp', 'gain': 0.5},
    };
    final container = {
      'version': '0.7.0',
      'architecture': 'SlimmableContainer',
      'config': {
        'submodels': [
          for (final v in [0.5, 1.0])
            {
              'max_value': v,
              'model': {
                'version': '0.7.0',
                'architecture': 'WaveNet',
                'weights': List.filled(5, v),
                'sample_rate': 48000,
              },
            },
        ],
      },
      'weights': [],
      'sample_rate': 48000,
    };

    test('describes known NAM layouts deterministically', () {
      for (final (value, arch, total, slimmable) in [
        (wavenet, 'WaveNet', 5, false),
        (container, 'SlimmableContainer', 10, true),
      ]) {
        final bytes = _json(value);
        final a = NamFileProfile.describe(bytes, fileName: 'x.nam');
        final b = NamFileProfile.describe(bytes, fileName: 'x.nam');
        expect(jsonEncode(a.report), jsonEncode(b.report));
        expect(a.report['sha256'], sha256.convert(bytes).toString());
        expect(a.report['architecture'], arch);
        expect(a.report['weightCountTotal'], total);
        expect(a.report['isSlimmableContainer'], slimmable);
        expect(a.needles.map((n) => n.label), contains('file-head-24'));
      }
    });

    test('describes non-JSON without needles and rejects empty input', () {
      final text = NamFileProfile.describe(
        Uint8List.fromList(utf8.encode('not json at all')),
      );
      expect(text.report['isJsonObject'], isFalse);
      expect(text.needles, isEmpty);
      final binary = NamFileProfile.describe(
        Uint8List.fromList([0xff, 0xfe, 0x00, 0x80]),
      );
      expect(binary.report['isUtf8'], isFalse);
      expect(
        () => NamFileProfile.describe(Uint8List(0)),
        throwsFormatException,
      );
    });

    test('handles a multi-megabyte model', () {
      final big = {...wavenet, 'weights': List.generate(300000, (i) => i / 7)};
      final profile = NamFileProfile.describe(_json(big));
      expect(profile.report['weightCountTotal'], 300000);
      expect(profile.report['sizeBytes'] as int, greaterThan(3 * 1024 * 1024));
    });
  });

  group('readUsbCapture', () {
    final frames = [
      _frame(
        endpoint: 0x03,
        transfer: 3,
        completion: false,
        payload: [1, 2, 3, 4],
      ),
      _frame(endpoint: 0x83, transfer: 3, completion: true, payload: [9, 8]),
      _frame(
        endpoint: 0x03,
        transfer: 3,
        completion: true,
      ), // OUT completion, no data
      _frame(
        endpoint: 0x00,
        transfer: 254,
        completion: false,
        payload: [7],
      ), // IRP info
    ];

    test('reads pcapng and classic pcap identically', () {
      for (final bytes in [_pcapng(frames), _pcap(frames)]) {
        final capture = readUsbCapture(bytes);
        expect(capture.frameCount, 4);
        expect(capture.emptyTransfers, 1);
        expect(capture.ignoredFrames, 1);
        final [out, inn] = capture.transfers;
        expect(out.direction, UsbDirection.hostToDevice);
        expect(out.endpointLabel, '0x03');
        expect(out.payload, [1, 2, 3, 4]);
        expect(inn.direction, UsbDirection.deviceToHost);
        expect(inn.endpointLabel, '0x83');
      }
      expect(readUsbCapture(_pcapng(frames)).transfers[1].timestampUs, 1001000);
    });

    test('rejects empty, corrupt, truncated and foreign captures', () {
      final good = _pcapng(frames);
      for (final bad in [
        Uint8List(0),
        Uint8List.fromList(List.filled(64, 0x41)),
        good.sublist(0, good.length - 5),
        _pcapng(frames, linkType: 1),
        _pcap(frames).sublist(0, 30),
      ]) {
        expect(() => readUsbCapture(bad), throwsFormatException);
      }
    });
  });

  group('capture analysis', () {
    test(
      'finds a needle raw, split across URBs and inside nibble-encoded SysEx',
      () {
        final needle = NamNeedle(
          'n',
          Uint8List.fromList(List.generate(20, (i) => 0x40 + i)),
        );
        final raw = readUsbCapture(
          _pcapng([
            for (final part in [
              [0, 0, ...needle.bytes.take(8)],
              [...needle.bytes.skip(8), 0, 0],
            ])
              _frame(
                endpoint: 2,
                transfer: 3,
                completion: false,
                payload: part,
              ),
          ]),
        );
        final rawHits =
            inspectCapture(raw, needles: [needle])['needleHits'] as List;
        expect(
          (rawHits.single as Map)['hits'].toString(),
          contains('urb-stream 0x02 hostToDevice'),
        );

        final sysex = _hostSysexCapture([
          _nibbleSysex([1, 2, ...needle.bytes, 3]),
        ]);
        final hit =
            ((inspectCapture(sysex, needles: [needle])['needleHits'] as List)
                        .single
                    as Map)['hits']
                as List;
        expect(
          hit.map((h) => (h as Map)['view']),
          contains('sysex-nibbles-hi-lo@0'),
        );
        // header byte + 6 filler bytes, then data[2] starts at message index 12 -> decoded offset 6
        expect((hit.first as Map)['offset'], 6);
      },
    );

    test(
      'groups a chunk sequence into one burst and detects large payloads',
      () {
        final capture = readUsbCapture(
          _pcapng([
            for (var i = 0; i < 10; i++)
              _frame(
                endpoint: 2,
                transfer: 3,
                completion: false,
                payload: List.filled(64, i),
              ),
          ]),
        );
        final report = inspectCapture(capture);
        final burst = (report['bursts'] as List).single as Map;
        expect(burst['lengthPattern'], '64x10');
        expect(burst['totalBytes'], 640);
        expect(
          ((report['endpoints'] as List).single as Map)['largePayloads'],
          0,
        );
      },
    );

    test(
      'compare reports constant and variable byte positions per direction',
      () {
        final base = List.generate(30, (i) => i);
        final a = _hostSysexCapture([_nibbleSysex(base)]);
        final slot = _hostSysexCapture([
          _nibbleSysex([...base]..[3] = 0x21),
        ]);
        final again = _hostSysexCapture([_nibbleSysex(base)]);
        final shorter = _hostSysexCapture([
          _nibbleSysex(base.take(20).toList()),
        ]);
        final report = compareCaptures({
          'A': a,
          'B': slot,
          'D': again,
          'S': shorter,
        });
        Map<String, Object?> host(int i) =>
            ((report['comparisons'] as List)[i] as Map)['hostToDevice']
                as Map<String, Object?>;
        expect(host(0)['differentSameLength'], 1);
        final diff = (host(0)['differences'] as List).single as Map;
        // data[3] = 0x21 changes both nibbles at message bytes 14 and 15
        expect(diff['variableRanges'], [
          [14, 15],
        ]);
        expect(diff['constantBytes'], (diff['length'] as int) - 2);
        expect(host(1)['identical'], 1);
        expect(host(2)['lengthMismatch'], 1);
        expect(() => compareCaptures({'A': a}), throwsFormatException);
      },
    );
  });

  group('Clone transfer codec', () {
    // Real frames from captures A/B/C (name bytes only, no model data).
    const blockA0 =
        'f021257f514d453212120010130000000407040f040a0409050204010200020d0200040a040f040502000404080cf7';
    const blockB0 =
        'f021257f514d453212120010130400000407040f040a0409050204010200020d0200040a040f040502000404080cf7';
    const blockC0 =
        'f021257f514d453212120010130000000503060f060c06090604020005020709060807040608060d0200040d0a0ef7';
    const lastBlock =
        'f021257f514d4532121200101300044b0000000000000000000000000f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f00f7';
    List<int> bytes(String hex) => [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];

    Uint8List syntheticCloData({String name = 'Synthetic Amp'}) {
      final data = Uint8List(MatriboxCloneData.totalLength);
      final view = ByteData.sublistView(data);
      data.setRange(0, name.length, name.codeUnits);
      view
        ..setUint32(0x20, MatriboxCloneData.vtsiMagic, Endian.little)
        ..setUint32(0x24, MatriboxCloneData.vtsiSize, Endian.little)
        ..setUint32(0x34, MatriboxCloneData.dataLength, Endian.little)
        ..setUint32(0xa0, 128, Endian.little)
        ..setUint32(0xa4, 1024, Endian.little);
      var x = 12345;
      for (var i = 0xa8; i < 0xa8 + 0x1200; i++) {
        x = (x * 1103515245 + 12345) & 0x7fffffff;
        data[i] = x >> 16;
      }
      data.fillRange(data.length - 8, data.length, 0xff);
      return data;
    }

    test(
      'nibble payload codec is high-nibble-first and round-trips every byte',
      () {
        for (final payload in [
          List.filled(14, 0),
          List.filled(14, 0xff),
          List.generate(14, (i) => i * 19),
          [0xab, 0xcd, ...List.filled(12, 0x5a)],
        ]) {
          final wire = encodeTransferPayload(payload);
          expect(wire.length, 28);
          expect(wire.every((n) => n <= 0x0f), isTrue);
          expect(decodeTransferPayload(wire), payload);
        }
        expect(encodeTransferPayload([0xab, ...List.filled(13, 0)]).take(2), [
          0xa,
          0xb,
        ]);
        expect(
          () => decodeTransferPayload(List.filled(28, 0x10)),
          throwsFormatException,
        );
        expect(
          () => decodeTransferPayload(List.filled(27, 0)),
          throwsFormatException,
        );
        expect(
          () => encodeTransferPayload(List.filled(13, 0)),
          throwsFormatException,
        );
      },
    );

    test('captured frames parse and re-encode byte-identically; slot is byte 13 only', () {
      for (final (hex, slot, block, text) in [
        (blockA0, 0, 0, 'GOJIRA - JOE D'),
        (blockB0, 4, 0, 'GOJIRA - JOE D'),
        (blockC0, 0, 0, 'Solid Ryhthm M'),
      ]) {
        final frame = NamTransferFrame.parse(bytes(hex));
        expect((frame.slot, frame.block), (slot, block));
        expect(String.fromCharCodes(frame.payload), text);
        expect(frame.encode(), bytes(hex));
      }
      final last = NamTransferFrame.parse(bytes(lastBlock));
      expect(
        last.block,
        587,
      ); // two 7-bit bytes [0x04, 0x4b], most significant first
      expect(last.payload, [0, 0, 0, 0, 0, 0, ...List.filled(8, 0xff)]);
      final a = bytes(blockA0), b = bytes(blockB0);
      expect(
        [
          for (var i = 0; i < a.length; i++)
            if (a[i] != b[i]) i,
        ],
        [13],
      );
    });

    test('malformed frames and ACKs are rejected', () {
      List<int> mutate(int index, int value) =>
          [...bytes(blockA0)]..[index] = value;
      for (final bad in [
        mutate(44, 0x09), // checksum nibble
        mutate(5, 0x00), // prefix
        mutate(46, 0x00), // missing F7
        mutate(20, 0x90), // data byte above 0x7F
        bytes(blockA0).sublist(0, 46),
      ]) {
        expect(() => NamTransferFrame.parse(bad), throwsFormatException);
      }
      const ackHex = 'f021257f514d4532121200101300044b01f7';
      final ack = NamTransferAck.parse(bytes(ackHex));
      expect((ack.slot, ack.block, ack.isObservedOk), (0, 587, true));
      expect(ack.encode(), bytes(ackHex));
      expect(
        () => NamTransferAck.parse(bytes(ackHex).sublist(0, 17)),
        throwsFormatException,
      );
      expect(
        () => NamTransferFrame(
          slot: 0,
          block: 0x4000,
          payload: List.filled(14, 0),
        ),
        throwsFormatException,
      );
    });

    test('reconstruction reports missing, repeated, conflicting and corrupt blocks', () {
      final data = Uint8List.fromList(List.generate(56, (i) => i)); // 4 blocks
      final clean = encodeCloneTransfer(data, 0);
      expect(clean.length, 6);
      final ok = reconstructCloneTransfer(clean);
      expect(ok.isComplete, isTrue);
      expect(ok.cloData, data);
      expect(ok.duplicateBlocks, {3: 2});

      final withGap = reconstructCloneTransfer([clean[0], clean[2], clean[3]]);
      expect(withGap.isComplete, isFalse);
      expect(withGap.missingBlocks, [1]);

      final other = NamTransferFrame(
        slot: 0,
        block: 1,
        payload: List.filled(14, 9),
      ).encode();
      expect(reconstructCloneTransfer([...clean, other]).conflictingBlocks, [
        1,
      ]);

      final broken = [...clean.first]..[44] ^= 0x01;
      final corrupt = reconstructCloneTransfer([broken, ...clean.skip(1)]);
      expect((corrupt.checksumFailures, corrupt.isComplete), (1, false));
      expect(reconstructCloneTransfer(const []).isComplete, isFalse);
    });

    test('simulator output differs between slots only at the slot byte', () {
      final data = syntheticCloData();
      final slot0 = encodeCloneTransfer(data, MatriboxCloneSlot(1).wireValue);
      final slot4 = encodeCloneTransfer(data, MatriboxCloneSlot(5).wireValue);
      expect(slot0.length, 590); // 588 blocks + 2 observed repeats of the last
      expect(reconstructCloneTransfer(slot0).cloData, data);
      final differing = <int>{
        for (var i = 0; i < slot0.length; i++)
          for (var p = 0; p < slot0[i].length; p++)
            if (slot0[i][p] != slot4[i][p]) p,
      };
      expect(differing, {13});
      expect(MatriboxCloneSlot(1).evidence, CloneSlotEvidence.confirmed);
      expect(MatriboxCloneSlot(3).evidence, CloneSlotEvidence.stronglyInferred);
      expect(() => MatriboxCloneSlot(6), throwsFormatException);
      expect(
        () => encodeCloneTransfer(Uint8List(15), 0),
        throwsFormatException,
      );
    });

    test(
      'CloData model round-trips byte-exactly and rejects foreign layouts',
      () {
        final data = syntheticCloData();
        final model = MatriboxCloneData.parse(data);
        expect(model.serialize(), data);
        expect((model.nameText, model.firTapCount), ('Synthetic Amp', 1152));
        for (final bad in [
          Uint8List(8231),
          syntheticCloData()..[0x20] = 0,
          syntheticCloData()..[0x25] = 0x22,
          syntheticCloData()..[0xa5] = 0,
        ]) {
          expect(() => MatriboxCloneData.parse(bad), throwsFormatException);
        }
      },
    );

    // Golden values from the official-editor captures; skipped where the local
    // capture files (kept outside the repository) are not available.
    final dir = Directory('D:/Desktop 3d sachen/Desktop');
    final files = ['nam test.pcapng', 'nam test 2.pcapng', 'nam test 3.pcapng'];
    final available = files.every((f) => File('${dir.path}/$f').existsSync());
    test('captures A/B/C reconstruct, match the simulator and hold the golden hashes', () {
      final hashes = <String>[];
      final host = <List<Uint8List>>[];
      final clo = <Uint8List>[];
      for (final f in files) {
        final capture = readUsbCapture(
          File('${dir.path}/$f').readAsBytesSync(),
        );
        final blocks = [
          for (final m in extractMessages(capture, const AnalysisOptions()))
            if (m.direction == UsbDirection.hostToDevice &&
                m.bytes.length == namBlockMessageLength)
              m.bytes,
        ];
        final rebuilt = reconstructCloneTransfer(blocks);
        expect(rebuilt.isComplete, isTrue);
        expect((rebuilt.blockCount, rebuilt.cloData!.length), (588, 8232));
        clo.add(rebuilt.cloData!);
        hashes.add(sha256.convert(rebuilt.cloData!).toString());
        host.add(blocks);
        expect(
          MatriboxCloneData.parse(rebuilt.cloData!).serialize(),
          rebuilt.cloData,
        );
      }
      // A (Clone 1) and B (Clone 5) carry the same NAM: identical CloData.
      expect(hashes[0], hashes[1]);
      expect(
        hashes[0],
        'c3a44e9282b679130104c14d2f97e690e6e3172b7efa0a4b1d47615de19c35b1',
      );
      expect(
        hashes[2],
        'a3fffddfc155a3b5a6f9fd2e56e67a7a0aa01210ed497c022ad4e7a95bd79414',
      );
      // The offline simulator reproduces every captured block message.
      for (final (index, slot) in [(0, 0), (1, 4), (2, 0)]) {
        final simulated = encodeCloneTransfer(clo[index], slot);
        expect(simulated.length, host[index].length);
        for (var i = 0; i < simulated.length; i++) {
          expect(
            simulated[i],
            host[index][i],
            reason: 'capture $index message $i',
          );
        }
      }
    }, skip: available ? false : 'local capture files not available');
  });

  group('MatriboxNamCloDataConverter', () {
    Uint8List wav({
      int rate = 48000,
      int frames = 3360000,
      int bits = 16,
      bool float = false,
      double? bad,
    }) {
      final width = float ? 4 : bits ~/ 8;
      final data = frames * width;
      final out = ByteData(44 + data)
        ..setUint32(0, 0x46464952, Endian.little)
        ..setUint32(4, 36 + data, Endian.little)
        ..setUint32(8, 0x45564157, Endian.little)
        ..setUint32(12, 0x20746d66, Endian.little)
        ..setUint32(16, 16, Endian.little)
        ..setUint16(20, float ? 3 : 1, Endian.little)
        ..setUint16(22, 1, Endian.little)
        ..setUint32(24, rate, Endian.little)
        ..setUint32(28, rate * width, Endian.little)
        ..setUint16(32, width, Endian.little)
        ..setUint16(34, width * 8, Endian.little)
        ..setUint32(36, 0x61746164, Endian.little)
        ..setUint32(40, data, Endian.little);
      if (bad != null) out.setFloat32(44, bad, Endian.little);
      return out.buffer.asUint8List();
    }

    const converter = MatriboxNamCloDataConverter();
    final output = wav();

    // Parameterized golden corpus (nam_golden_corpus.dart): every case needs
    // the official editor's model output and the CloData reconstructed from
    // the USB capture. Both live outside the repository; a case whose files
    // are absent is SKIPPED (not validated), and files are SHA-256 checked so
    // a wrong artifact can never pass.
    for (final golden in matriboxGoldenCorpus) {
      // The official CloData comes from a capture (preferred) or from a file
      // that was reconstructed from one; the converter never provides it.
      final files =
          {
            'reference': (golden.referenceWav, golden.referenceWavSha256),
            'output': (golden.outputWav, golden.outputWavSha256),
            'official': (
              golden.capture ?? golden.officialClodata!,
              golden.captureSha256 ?? golden.clodataSha256,
            ),
          }.map(
            (k, v) => MapEntry(k, (File('$matriboxCaptureRoot/${v.$1}'), v.$2)),
          );
      test(
        '${golden.displayName}: all 8232 bytes are identical to the official '
        'editor and deterministic',
        () {
          Uint8List load(String key) {
            final (file, sha) = files[key]!;
            final bytes = file.readAsBytesSync();
            expect(sha256.convert(bytes).toString(), sha, reason: file.path);
            return bytes;
          }

          final nam = golden.namLocalPath == null
              ? null
              : File(golden.namLocalPath!);
          if (nam != null && nam.existsSync()) {
            expect(
              sha256.convert(nam.readAsBytesSync()).toString(),
              golden.namSha256,
              reason: 'imported NAM identity',
            );
          }
          final reference = load('reference');
          final output = load('output');
          final official = golden.capture != null
              ? matriboxCloDataFromCapture(load('official'))
              : load('official');
          expect(sha256.convert(official).toString(), golden.clodataSha256);
          final runs = [
            for (var i = 0; i < 2; i++)
              converter
                  .convert(
                    referenceWav: reference,
                    modelOutputWav: output,
                    fileName: golden.storedName,
                  )
                  .requireComplete(),
          ];
          for (final run in runs) {
            final diff = MatriboxCloDataDiff(official, run);
            expect(diff.identical, isTrue, reason: '$diff');
            expect(diff.matching, 8232);
            expect(sha256.convert(run).toString(), golden.clodataSha256);
          }
          expect(runs[0], runs[1]);
        },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: files.values.every((f) => f.$1.existsSync())
            ? false
            : 'NOT VALIDATED: local capture files not available',
      );
    }

    test('diff report classifies regions', () {
      final diff = MatriboxCloDataDiff([1, 2, 3, 4, 5], [1, 9, 8, 4, 7]);
      expect(diff.identical, isFalse);
      expect(diff.firstDifference, 1);
      expect(diff.differing, 3);
      expect(diff.regions, [(start: 1, end: 3), (start: 4, end: 5)]);
    });

    test('name rules', () {
      final long = MatriboxNamCloDataConverter.nameBytes(
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ.NAM',
      );
      expect(String.fromCharCodes(long), 'ABCDEFGHIJKLMNOP');
      expect(MatriboxNamCloDataConverter.nameBytes('ab.nam'), [
        0x61,
        0x62,
        ...List.filled(14, 0),
      ]);
    });

    test('invalid WAV, wrong rate/length and NaN/Inf are rejected', () {
      final bad = <String, Uint8List>{
        'not a wav': Uint8List.fromList(List.filled(64, 7)),
        'truncated': output.sublist(0, 1000),
        'wrong rate': wav(rate: 44100),
        'wrong length': wav(frames: 48000),
        'NaN': wav(float: true, bad: double.nan),
        'Inf': wav(float: true, bad: double.infinity),
        'unsupported bits': wav(bits: 8),
      };
      for (final entry in bad.entries) {
        expect(
          () => converter.convert(
            referenceWav: entry.value,
            modelOutputWav: output,
            fileName: 'x.nam',
          ),
          throwsFormatException,
          reason: entry.key,
        );
      }
    });
  });

  test('tool sources cannot reach a device (files in, JSON out)', () {
    const banned = [
      'package:flutter',
      'usb_service',
      'MethodChannel',
      'Socket',
      'HttpClient',
      'Process.',
      'dart:ffi',
      'dart:isolate',
    ];
    for (final entity in Directory(
      'tool/matribox_nam_analysis',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final word in banned) {
        expect(
          source.contains(word),
          isFalse,
          reason: '${entity.path} uses $word',
        );
      }
      // Only these known offline files may touch local files/stdin/stdout;
      // everything else here (codec, analysis, transfer-plan/state-machine
      // logic) is pure functions over bytes already in memory.
      // `v5b_execute_clone5_transfer.dart` reads a confirmation phrase from
      // stdin and never opens a device (see its own docstring);
      // `v5_clodata_builder.dart` reads local .nam/.wav files to build
      // CloData offline. Neither imports any of the banned words above.
      const fileIoAllowed = {
        'matribox_nam_analysis.dart',
        'v5b_execute_clone5_transfer.dart',
        'v5_clodata_builder.dart',
      };
      if (!fileIoAllowed.any(entity.path.endsWith)) {
        expect(
          source.contains('dart:io'),
          isFalse,
          reason: '${entity.path} imports dart:io',
        );
      }
    }
  });
}
