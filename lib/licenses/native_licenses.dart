import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bundled notice for the native third-party components of the NAM bridge (NeuralAmpModelerCore, nlohmann/json,
/// Eigen). The text lives in the repository root file THIRD_PARTY_NOTICES.md, which is a pubspec asset.
const thirdPartyNoticesAsset = 'THIRD_PARTY_NOTICES.md';

/// Registers the native notices with Flutter's [LicenseRegistry]: they then appear on the license page
/// (Profil → Open-Source-Lizenzen) next to the licenses of the Flutter framework and the Dart packages.
void registerNativeThirdPartyLicenses({AssetBundle? bundle}) {
  LicenseRegistry.addLicense(() async* {
    final text = await (bundle ?? rootBundle).loadString(
      thirdPartyNoticesAsset,
    );
    yield LicenseEntryWithLineBreaks(const [
      'NeuralAmpModelerCore',
      'nlohmann/json',
      'Eigen',
    ], text);
  });
}
