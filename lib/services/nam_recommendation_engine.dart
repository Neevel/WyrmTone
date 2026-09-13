import '../devices/device_profile.dart';
import '../models/recommendation.dart';
import '../models/target_sound.dart';
import '../nam/local_nam_capture.dart';

class NamRecommendationEngine {
  const NamRecommendationEngine();
  List<NamRecommendation> recommend({
    required TargetDeviceId device,
    required TargetSound target,
    required List<LocalNamCapture> captures,
  }) {
    if (device != TargetDeviceId.matriboxOne) return const [];
    final desired = switch (target.id) {
      'cky-96-qbb' => ['marshall', 'jcm', 'mid', 'alternative'],
      'cob-angels-dont-kill' => [
        'marshall',
        'jcm',
        'high gain',
        'v30',
        'tight',
      ],
      _ => ['clean', 'crunch', 'warm'],
    };
    final ranked =
        captures.where((c) => c.compatibility == NamCompatibility.compatible).map((
          c,
        ) {
          final haystack =
              '${c.toneName} ${c.captureName} ${c.make ?? ''} ${c.gearType ?? ''} ${c.tags.join(' ')} ${c.description ?? ''}'
                  .toLowerCase();
          final hits = desired.where(haystack.contains).toList();
          final reasons = <String>['Lokales kompatibles NAM-A1-Capture.'];
          if (hits.isNotEmpty) {
            reasons.add('Metadaten passen: ${hits.join(', ')}.');
          }
          final uncertainties = <String>[];
          final needsIr = switch (c.cabinetContent) {
            NamCabinetContent.withoutCabinet => true,
            NamCabinetContent.withCabinet || NamCabinetContent.fullRig => false,
            NamCabinetContent.unknown => null,
          };
          if (needsIr == null) {
            uncertainties.add(
              'Cabinet-Anteil unbekannt; zusätzliche IR nicht automatisch festlegen.',
            );
          }
          return NamRecommendation(
            capture: c,
            score: (55 + hits.length * 12).clamp(0, 100),
            reasons: reasons,
            additionalIrRequired: needsIr,
            uncertainties: uncertainties,
          );
        }).toList()..sort((a, b) => b.score.compareTo(a.score));
    return ranked.take(3).toList();
  }
}
