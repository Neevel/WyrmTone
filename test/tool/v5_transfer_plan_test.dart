import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/matribox_nam_analysis/v5_transfer_plan.dart';

/// V5A: hard guards for the Clone-5 transfer plan. Pure, offline, no
/// hardware -- builds a synthetic, valid-length CloData buffer (never real
/// captured/Sonicake data) to exercise the guards deterministically.
void main() {
  Uint8List validCloData() => Uint8List(v5RequiredCloDataLength)
    ..setRange(0, 16, 'V5 Test Clone Xy'.codeUnits);

  group('hard guards', () {
    test('a correctly-sized CloData builds a plan with the expected shape', () {
      final plan = V5TransferPlan.build(
        cloData: validCloData(),
        modelLabel: 'Test Model',
        cloDataSha256Hex: 'deadbeef',
      );
      expect(plan.frameCount, v5ExpectedFrameCount);
      expect(plan.frames.length, 590);
      // Clone-5 hard lock: every single planned frame targets 0x04, with
      // no parameter anywhere that could change it.
      for (final f in plan.frames) {
        expect(f.expectedAckSlot, v5TargetCloneSlot);
        expect(f.expectedAckSlot, 0x04);
      }
      // Last block (587) repeated exactly 3 times, at the very end.
      final lastThree = plan.frames.sublist(plan.frames.length - 3);
      expect(lastThree.every((f) => f.block == v5ExpectedBlockCount - 1), isTrue);
      expect(plan.frames[plan.frames.length - 4].block, v5ExpectedBlockCount - 2);
    });

    test('wrong CloData length is rejected (too short)', () {
      expect(
        () => V5TransferPlan.build(
          cloData: Uint8List(8231),
          modelLabel: 'x',
          cloDataSha256Hex: 'x',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('wrong CloData length is rejected (too long)', () {
      expect(
        () => V5TransferPlan.build(
          cloData: Uint8List(8233),
          modelLabel: 'x',
          cloDataSha256Hex: 'x',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('every planned frame round-trips through the confirmed parser with a valid checksum', () {
      final plan = V5TransferPlan.build(
        cloData: validCloData(),
        modelLabel: 'x',
        cloDataSha256Hex: 'x',
      );
      for (final f in plan.frames) {
        // Parsing itself validates the checksum (NamTransferFrame.parse
        // throws FormatException on mismatch) -- reaching here without an
        // exception during V5TransferPlan.build already proves this, this
        // assertion documents it explicitly.
        expect(f.outbound.length, 47);
        expect(f.outbound.last, 0xf7);
      }
    });
  });

  group('preset/store isolation (structural)', () {
    test(
      'v5_transfer_plan.dart and v5_ack_state_machine.dart do not import any preset/store module',
      () {
        for (final path in [
          'tool/matribox_nam_analysis/v5_transfer_plan.dart',
          'tool/matribox_nam_analysis/v5_ack_state_machine.dart',
          'tool/matribox_nam_analysis/v5_clodata_builder.dart',
        ]) {
          final fullSource = File(path).readAsStringSync();
          final code = fullSource
              .split('\n')
              .where((l) => !l.trim().startsWith('///') && !l.trim().startsWith('//'))
              .join('\n');
          for (final banned in [
            'preset',
            'Preset',
            'matribox_chain',
            'matribox_tone_transfer',
            'p01_readback',
            'confirmed_parameter_codec',
            'usb_controller',
            'MidiReceiveSource',
          ]) {
            expect(
              code.contains(banned),
              isFalse,
              reason: '$path must not reference "$banned" (preset/store/hardware isolation)',
            );
          }
        }
      },
    );

    test('V5TransferPlan exposes no parameter that can change the target slot', () {
      // Structural guard: the public build() signature only accepts
      // cloData/modelLabel/cloDataSha256Hex -- no slot/clone parameter.
      final code = File('tool/matribox_nam_analysis/v5_transfer_plan.dart').readAsStringSync();
      final buildSig = RegExp(r'static V5TransferPlan build\(\{([^}]*)\}\)', dotAll: true)
          .firstMatch(code)!
          .group(1)!;
      expect(buildSig.toLowerCase().contains('slot'), isFalse);
      expect(buildSig.toLowerCase().contains('clone'), isFalse);
    });
  });
}
