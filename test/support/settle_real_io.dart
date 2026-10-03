import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits -- in REAL time, so it must be called inside `tester.runAsync` -- until a page driven by
/// real file I/O has actually finished what it was asked to do, instead of sleeping a fixed
/// number of milliseconds and hoping the I/O chain was done by then (which only holds on an idle
/// machine; under a loaded full-suite run it was the source of sporadic failures).
///
/// "Finished" means all of:
///  * no progress indicator is shown (the pages show one for as long as they work),
///  * [until] -- the caller's explicit expected outcome (a widget key, a counter, a file) -- holds,
///  * and everything observable ([state] plus every visible text) has stopped changing for
///    [stablePolls] consecutive polls, so a last frame or a trailing write cannot be missed.
///
/// How long that takes is decided by the machine, not by the test. The only time-based value is
/// [timeout]: a generous deadline that turns "never settles" into a clear failure message instead
/// of a hang, and plays no part in a passing run.
Future<void> settleRealIo(
  WidgetTester tester, {
  bool Function()? until,
  String Function()? state,
  String reason = 'the page to finish its real I/O',
  Duration timeout = const Duration(seconds: 30),
  Duration poll = const Duration(milliseconds: 10),
  int stablePolls = 8,
}) async {
  final deadline = DateTime.now().add(timeout);
  var stable = 0;
  String? last;
  while (true) {
    await Future<void>.delayed(poll);
    await tester.pump();
    final working = find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
        find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
    final reached = !working && (until?.call() ?? true);
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join('|');
    final fingerprint = '$texts#${state?.call() ?? ''}';
    stable = (reached && fingerprint == last) ? stable + 1 : 0;
    last = fingerprint;
    if (stable >= stablePolls) return;
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timed out after $timeout waiting for $reason (working: $working, reached: $reached).');
    }
  }
}

/// True when any widget with one of [keys] is currently in the tree.
bool anyKeyShown(Iterable<Key> keys) => keys.any((key) => find.byKey(key).evaluate().isNotEmpty);
