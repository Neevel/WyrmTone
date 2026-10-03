import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/matribox_nam_analysis/engine/f32.dart';
import '../../tool/matribox_nam_analysis/engine/r8b_resampler.dart';
import '../../tool/matribox_nam_analysis/engine/ucrt_float.dart';

/// Bit-level vectors of the single-precision routines the NAM engine port
/// depends on (expected values recorded from the Windows UCRT, FMA path), and
/// of the 48 -> 44.1 kHz resampler. Full-pipeline identity is covered by the
/// golden tests in `matribox_nam_analysis_test.dart`.
void main() {
  double f(int bits) => f32FromBits(bits);

  test('UCRT float math is reproduced bit-exactly', () {
    final cases = <String, (double Function(double), List<(int, int)>)>{
      'expf': (
        expf,
        [
          (0xc06ccccd, 0x3cca88fe),
          (0x3a83126f, 0x3f8020c9),
          (0x3fa00000, 0x405f61c7),
          (0x41280000, 0x470ddb81),
          (0xc2b00000, 0x41edc4),
        ],
      ),
      'logf': (
        logf,
        [
          (0x3b449ba6, 0xc0b9e480),
          (0x3f400000, 0xbe934b11),
          (0x3fc00000, 0x3ecf991f),
          (0x42f6e979, 0x409a1bba),
          (0x4b095440, 0x41801a15),
        ],
      ),
      'log10f': (
        log10f,
        [
          (0x3c23d70a, 0xc0000000),
          (0x3f000000, 0xbe9a209b),
          (0x40400000, 0x3ef4493d),
          (0x44426ccd, 0x40390311),
          (0x47c35000, 0x40a00000),
        ],
      ),
      'cosf': (
        cosf,
        [
          (0x3dcccccd, 0x3f7eb898),
          (0x3f800000, 0x3f0a5140),
          (0x40600000, 0xbf6fbba0),
          (0x42c80000, 0x3f5cc0ee),
          (0xc0e80000, 0x3f11637b),
        ],
      ),
      'sinf': (
        sinf,
        [
          (0x3dcccccd, 0x3dcc7577),
          (0x3f800000, 0x3f576aa4),
          (0x40600000, 0xbeb399dc),
          (0x42c80000, 0xbf01a12e),
          (0xc0e80000, 0xbf52b56e),
        ],
      ),
    };
    for (final entry in cases.entries) {
      final (fn, vectors) = entry.value;
      for (final (input, expected) in vectors) {
        expect(
          f32Bits(fn(f(input))),
          expected,
          reason: '${entry.key}(0x${input.toRadixString(16)})',
        );
      }
    }
    for (final (a, b, expected) in [
      (0x41200000, 0x3e99999a, 0x3fff64c2),
      (0x40000000, 0xbfc00000, 0x3eb504f3),
      (0x3f333333, 0x40866666, 0x3e64ef4c),
      (0x42f60000, 0x3c23d70a, 0x3f864f6a),
      (0x3f800347, 0x43960000, 0x3f83e60d),
    ]) {
      expect(f32Bits(powf(f(a), f(b))), expected);
    }
    // Under/overflow ends of expf (used by the non-linearity fit).
    expect(expf(-720.0), 0.0);
    expect(expf(100.0), double.infinity);
  });

  test('platform double math matches the Windows/UCRT reference bits', () {
    // The only platform-dependent operations of the engine: FFT twiddles and
    // trig tables (sin/cos/atan), Gaussian kernels and Bessel windows (exp),
    // Hann-like windows and dB floors (pow). If this fails on another
    // platform, byte identity of the converter is NOT given there.
    void check(double actual, int expectedBits, String what) {
      expect(f64Bits(actual), expectedBits, reason: what);
    }

    check(math.sin(0.3), 0x3fd2e9cd95baba33, 'sin 0.3');
    check(math.sin(2.0943951023931953), 0x3febb67ae8584cab, 'sin 2pi/3');
    check(math.sin(100.5), 0xbf9fb3f833470ff1, 'sin 100.5');
    check(math.cos(0.3), 0x3fee921dd42f09ba, 'cos 0.3');
    check(math.cos(0.7853981633974483), 0x3fe6a09e667f3bcd, 'cos pi/4');
    check(math.cos(42.25), 0xbfc495157c78ea06, 'cos 42.25');
    check(math.exp(-1.2345), 0x3fd29f6b7bfe469d, 'exp -1.2345');
    check(math.exp(-0.02), 0x3fef5dc99badec5b, 'exp -0.02');
    check(math.exp(6.5), 0x4084c92210816c89, 'exp 6.5');
    check(math.atan(1.0), 0x3fe921fb54442d18, 'atan 1');
    check(math.atan(0.25), 0x3fcf5b75f92c80dd, 'atan 0.25');
    check(math.pow(0.37, 1.51553897).toDouble(), 0x3fcc5dc6898aabd3, 'pow a');
    check(math.pow(10.0, -1.75).toDouble(), 0x3f9235a71c5ee5cc, 'pow 10^-1.75');
    check(math.pow(0.99, 1.51553897).toDouble(), 0x3fef842ae77d1419, 'pow b');
  });

  test('fma64 is a single rounding', () {
    // (1 + 2^-52)^2 - 1 - 2^-51 = 2^-104: lost without a fused multiply-add.
    final a = 1.0 + math.pow(2, -52).toDouble();
    expect(fma64(a, a, -1.0 - math.pow(2, -51).toDouble()), math.pow(2, -104));
  });

  test('48 -> 44.1 kHz resampler output lengths and samples', () {
    final small = Float32List.fromList([
      for (var i = 0; i < 128; i++) f32(0.5 * math.sin(i * 0.05)),
    ]);
    final r1 = resample48to44(small);
    expect(r1.length, 117);
    final bits1 = Uint32List.view(r1.buffer);
    expect([0, 1, 2, 50, 100, 116].map((i) => bits1[i]), [
      0x3a2622d8,
      0x3cdc8478,
      0x3d5f1534,
      0x3e50f28d,
      0xbebea05f,
      0x3ca5ba7a,
    ]);
    final large = Float32List.fromList([
      for (var i = 0; i < 2048; i++) f32(0.25 * math.cos(i * 0.013)),
    ]);
    final r2 = resample48to44(large);
    expect(r2.length, 1881);
    final bits2 = Uint32List.view(r2.buffer);
    expect([0, 7, 500, 1000, 1880].map((i) => bits2[i]), [
      0x3e7381fc,
      0x3e80b28b,
      0x3e33e295,
      0xbb4cadc0,
      0x3ce3c9c3,
    ]);
  });
}
