import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wyrmtone/services/nam_preparation_service.dart';

/// Android NAM Inference V1, section 12: practical, on-device proof that
/// running the full Reference Signal V4 through [NamPreparationService]
/// (its `Isolate.run`-based execution) does NOT block the main/UI isolate.
/// A `Timer.periodic` increments a counter on the main isolate concurrently
/// with the multi-second native call; if the main isolate were blocked, the
/// counter would stop advancing for the whole native call's duration.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('main isolate keeps running while NamPreparationService infers on JVM410H', (tester) async {
    var ticks = 0;
    final ticker = Timer.periodic(const Duration(milliseconds: 50), (_) => ticks++);

    final service = NamPreparationService();
    final sw = Stopwatch()..start();
    final output = await service.runReferenceSignalInference('/data/local/tmp/jvm410h.nam');
    sw.stop();

    ticker.cancel();
    expect(output.length, greaterThan(0));

    // If the main isolate were blocked for the whole native call, ticks
    // would be ~0; a healthy, unblocked isolate keeps ticking at roughly
    // its 50ms period throughout.
    final expectedMinTicks = (sw.elapsedMilliseconds / 50 * 0.5).floor(); // 50% margin
    // ignore: avoid_print
    print(
      'UI_THREAD_RESULT {"inferMs":${sw.elapsedMilliseconds},"ticks":$ticks,"expectedMinTicks":$expectedMinTicks}',
    );
    expect(
      ticks,
      greaterThanOrEqualTo(expectedMinTicks),
      reason: 'main isolate ticker must keep advancing during native inference on a background isolate',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
