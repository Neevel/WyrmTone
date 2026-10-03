import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// DEVELOPMENT/TEST OVERRIDE ONLY. Tone Match ships its measuring signals inside the app
/// (`BundledToneMatchSignalProvider`); this folder (`.../Android/data/<app>/files/tonematch/evaluation`,
/// fillable with `adb push`) can replace them with the research recordings in non-release builds.
/// A release build never looks here. Returns null where no such folder exists (other platforms, tests).
Future<String?> toneMatchSignalDirectory() async {
  if (!Platform.isAndroid) return null;
  try {
    final dir = await getExternalStorageDirectory();
    return dir == null ? null : '${dir.path}/tonematch/evaluation';
  } on Object {
    return null;
  }
}
