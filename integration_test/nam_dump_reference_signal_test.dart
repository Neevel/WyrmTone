import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wyrmtone/services/wyrmtone_reference_signal_v4.dart';

/// Diagnostic only (Android NAM Inference V1, section 5 follow-up): dumps
/// the raw on-device Reference-Signal-V4 float32 bytes to a world-readable
/// path so they can be `adb pull`ed and diffed against the Windows-side
/// bytes sample-by-sample -- the SHA-256 fingerprint alone tells us THAT
/// the two platforms differ, not WHERE or by how much.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dump Reference Signal V4 bytes for offline cross-platform diff', (tester) async {
    final sig = WyrmToneReferenceSignalV4.generate();
    final bytes = sig.buffer.asUint8List();
    // /data/local/tmp is not writable from inside the app sandbox (SELinux),
    // despite its loose Unix permissions -- use the app's own cache dir and
    // pull it out afterwards with `adb shell run-as <pkg> cat ...`.
    final file = File('${Directory.systemTemp.path}/android_refsignal_v4.bin');
    file.writeAsBytesSync(bytes);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), bytes.length);
    // ignore: avoid_print
    print('WROTE ${file.path} (${file.lengthSync()} bytes)');
    // Diagnostic-only: the test runner uninstalls the app immediately after
    // this test completes, before `adb pull`/`run-as` could read the file
    // above -- hold the process alive long enough to pull it out manually.
    await Future<void>.delayed(const Duration(seconds: 45));
  });
}
