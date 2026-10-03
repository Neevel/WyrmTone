import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sound_flow_support.dart';

/// Regression: with the on-screen keyboard open, a page inside the shell must keep a usable height.
/// (The shell used to remove the keyboard inset and then bring it back, so the page's own Scaffold
/// shrank twice and the "Sound finden" button was not reachable while typing.)
void main() {
  testWidgets('Tone Match keeps its button above the keyboard on a phone-sized screen', (tester) async {
    await pumpShell(tester, width: 360, height: 800);
    await tester.tap(find.text('Tone Match').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tone-match-input')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280); // keyboard
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('tone-match-find'));
    expect(button, findsOneWidget);
    final rect = tester.getRect(button);
    expect(rect.bottom, lessThanOrEqualTo(800 - 280), reason: 'button must sit above the keyboard');
    final list = tester.getRect(find.byType(Scrollable).first);
    expect(list.height, greaterThan(300), reason: 'the page must not collapse to a sliver');
  });

  testWidgets('the Sounds search field behaves the same way', (tester) async {
    await pumpShell(tester, width: 360, height: 800);
    await openSoundsTab(tester);
    await tester.tap(find.byKey(const Key('sound-search')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Scrollable).first).height, greaterThan(300));
  });
}
