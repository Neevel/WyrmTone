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

      expect(find.byKey(const Key('dashboard-create')), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      await tester.tap(find.text('Profil'));
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

  testWidgets('Sounds tab is the search-first entry, without the retired reference list', (tester) async {
    final usb = FakeUsbService();
    addTearDown(usb.dispose);
    await tester.pumpWidget(WyrmToneApp(usbService: usb));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sounds'));
    // the sound library is still loading through the asset bundle (a busy indicator never settles): pump, do not settle
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Was möchtest du spielen?'), findsOneWidget);
    expect(find.byKey(const Key('sound-search')), findsOneWidget);
    expect(find.textContaining('Referenz-Sounds'), findsNothing);
    expect(find.text('Schritt 1 von 7'), findsNothing);
  });
}
