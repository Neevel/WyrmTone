import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The benchmark harness must never be able to change the product package of a normal build.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();

  test('the product application id is the default and only an explicit ".bench" id can differ', () {
    expect(gradle, contains('applicationId = benchApplicationId ?: "de.neevel.wyrmtone"'));
    expect(gradle, contains('namespace = "de.neevel.wyrmtone"'));
    expect(gradle, contains('require(benchApplicationId == null || benchApplicationId.startsWith("de.neevel.wyrmtone.bench"))'));
    // exactly one place assigns the application id
    expect(RegExp(r'applicationId\s*=').allMatches(gradle).length, 1);
  });

  test('no committed configuration sets the benchmark id; the harness is not wired into the product', () {
    expect(File('android/gradle.properties').readAsStringSync(), isNot(contains('wyrmtoneBenchApplicationId')));
    expect(File('android/local.properties').existsSync() ? File('android/local.properties').readAsStringSync() : '', isNot(contains('wyrmtoneBenchApplicationId')));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    // Only the derived runtime signals are app assets; the research recordings never are.
    expect(pubspec, contains('assets/tonematch/runtime/'));
    expect(pubspec, isNot(contains('tonematch/evaluation')), reason: 'research recordings must not become app assets');
    expect(pubspec, isNot(contains('.wav')));
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      expect(f.readAsStringSync(), isNot(contains('tonematch_android_bench')), reason: f.path);
    }
  });
}
