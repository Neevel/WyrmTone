import 'package:wyrmtone/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_usb_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'navigation preserves USB page and creates a local guitar profile',
    (tester) async {
      final usb = FakeUsbService();
      addTearDown(usb.dispose);
      await tester.pumpWidget(WyrmToneApp(usbService: usb));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('search-button')), findsOneWidget);
      await tester.tap(find.text('Gitarren'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-profile-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('profile-name-field')),
        'Samsung Testgitarre',
      );
      await tester.tap(find.byKey(const Key('save-profile-button')));
      await tester.pumpAndSettle();

      expect(find.text('Samsung Testgitarre'), findsOneWidget);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('guitar_profiles_v1'),
        contains('Samsung Testgitarre'),
      );
    },
  );

  testWidgets('all three supplied sounds are selectable in navigation', (
    tester,
  ) async {
    final usb = FakeUsbService();
    addTearDown(usb.dispose);
    await tester.pumpWidget(WyrmToneApp(usbService: usb));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sounds'));
    await tester.pumpAndSettle();

    expect(find.textContaining('CKY'), findsOneWidget);
    expect(find.textContaining('Children of Bodom'), findsOneWidget);
    expect(find.textContaining('Nirvana'), findsOneWidget);
  });
}
