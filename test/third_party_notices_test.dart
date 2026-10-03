import 'dart:io';

import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wyrmtone/app.dart';
import 'package:wyrmtone/licenses/native_licenses.dart';

import 'support/fake_usb_service.dart';

/// Distribution compliance for the native third-party code of the NAM bridge: the notices are a bundled asset,
/// registered with Flutter's license registry and reachable from the app (Profil -> Open-Source-Lizenzen).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  String norm(String s) => s.replaceAll('\r\n', '\n').trim();

  test('the notice file is a pubspec asset and names every compiled component with its pinned revision and license', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- THIRD_PARTY_NOTICES.md'),
    );
    final n = File('THIRD_PARTY_NOTICES.md').readAsStringSync();
    for (final must in [
      'NeuralAmpModelerCore',
      '0b3d3c97b0859a3a8c92a8628c4dd89a25eb5842',
      'Copyright (c) 2023 Steven Atkinson',
      'nlohmann/json',
      'Niels Lohmann',
      'Eigen',
      'bc3b39870ecb690a623a3f49149a358b95c5781d',
      'https://gitlab.com/libeigen/eigen',
      'Mozilla Public License',
      'Mark Borgerding',
    ]) {
      expect(n, contains(must));
    }
    expect(
      n,
      isNot(contains('AudioDSPTools\n\n```')),
      reason: 'AudioDSPTools is not compiled and gets no license section',
    );
  });

  test('the license texts are verbatim copies of the pinned upstream files (when the submodule is checked out)', () {
    final n = norm(File('THIRD_PARTY_NOTICES.md').readAsStringSync());
    const core = 'third_party/NeuralAmpModelerCore';
    final files = {
      '$core/LICENSE': 'NeuralAmpModelerCore MIT license',
      '$core/Dependencies/eigen/COPYING.MPL2': 'Eigen MPL-2.0 text',
    };
    for (final e in files.entries) {
      final f = File(e.key);
      // submodule not initialised in this checkout: nothing to compare
      if (!f.existsSync()) {
        continue;
      }
      expect(n, contains(norm(f.readAsStringSync())), reason: e.value);
    }
  });

  test(
    'the native notices are registered with the Flutter license registry',
    () async {
      registerNativeThirdPartyLicenses(bundle: rootBundle);
      final entries = await LicenseRegistry.licenses.toList();
      final mine = entries.where((e) => e.packages.contains('Eigen')).toList();
      expect(mine, hasLength(1));
      expect(
        mine.single.packages,
        containsAll(['NeuralAmpModelerCore', 'nlohmann/json', 'Eigen']),
      );
      final text = mine.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('Mozilla Public License'));
      expect(text, contains('MIT License'));
    },
  );

  testWidgets('Profil offers the open-source license page', (tester) async {
    registerNativeThirdPartyLicenses();
    final usb = FakeUsbService();
    addTearDown(usb.dispose);
    await tester.pumpWidget(WyrmToneApp(usbService: usb));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-source-licenses')), findsOneWidget);
    expect(find.text('Open-Source-Lizenzen'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('open-source-licenses')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-source-licenses')));
    // the license page shows a progress indicator while it collects the licenses (never settles): pump, do not settle
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('WyrmTone'), findsWidgets);
  });
}
