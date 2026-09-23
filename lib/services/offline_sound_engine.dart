import '../devices/device_profile.dart';
import '../models/guitar_profile.dart';
import '../models/recommendation.dart';
import '../models/target_sound.dart';
import '../models/tone_target.dart';
import '../models/ir_catalog_entry.dart';
import '../nam/local_nam_capture.dart';
import '../tone3000/local_ir_record.dart';

class DraftParameterSpec {
  const DraftParameterSpec(this.dimension, this.maximum);
  final ToneDimension? dimension;
  final int maximum;
}

/// Deliberately small catalogue. Matribox: locally verified algorithm.xml
/// Sol 100 OD lines 568–574, Sol 100 LD 622–628; names/ranges only, no wire codes.
/// DNAfx: existing confirmedDnafxCapabilities and project reference, 0..100.
class OfflineDeviceCatalog {
  static Map<String, Map<String, DraftParameterSpec>> amps(
    TargetDeviceId device,
  ) => device == TargetDeviceId.matriboxOne
      ? {
          for (final name in ['Sol 100 OD', 'Sol 100 LD'])
            name: const {
              'Gain': DraftParameterSpec(ToneDimension.gain, 99),
              'PRES': DraftParameterSpec(ToneDimension.presence, 99),
              'Master': DraftParameterSpec(null, 99),
              'Bass': DraftParameterSpec(ToneDimension.bass, 99),
              'Middle': DraftParameterSpec(ToneDimension.mids, 99),
              'Treble': DraftParameterSpec(ToneDimension.treble, 99),
            },
        }
      : {
          'J900': const {
            'GAIN': DraftParameterSpec(ToneDimension.gain, 100),
            'BASS': DraftParameterSpec(ToneDimension.bass, 100),
            'MID': DraftParameterSpec(ToneDimension.mids, 100),
            'TREBLE': DraftParameterSpec(ToneDimension.treble, 100),
            'PRESENCE': DraftParameterSpec(ToneDimension.presence, 100),
          },
        };

  static void validate(PresetDraft draft) {
    final models = amps(draft.device);
    for (final block in draft.blocks) {
      Map<String, DraftParameterSpec> parameters = const {};
      if (block.slot == 'AMP') {
        if (!models.containsKey(block.model)) {
          throw ArgumentError('Unbekanntes Ampmodell.');
        }
        parameters = models[block.model]!;
      } else if (block.slot == 'Gate' &&
          draft.device == TargetDeviceId.dnafxGitCore) {
        if (block.model != null) {
          throw ArgumentError('Unbekanntes Gate-Modell.');
        }
        parameters = const {
          'NOISE_GATE_ATTACK': DraftParameterSpec(
            ToneDimension.gateOpening,
            100,
          ),
        };
      } else if (block.model != null &&
          !(draft.device == TargetDeviceId.dnafxGitCore &&
              block.slot == 'Boost' &&
              block.model == 'PURE BOOST')) {
        throw ArgumentError('Unbekanntes Effektmodell.');
      }
      for (final entry in block.parameters.entries) {
        final spec = parameters[entry.key];
        if (spec == null ||
            entry.value < 0 ||
            entry.value > spec.maximum ||
            !block.provenance.containsKey(entry.key)) {
          throw ArgumentError('Unbekannter oder ungültiger Parameter.');
        }
      }
    }
  }
}

class OfflineSoundEngine {
  const OfflineSoundEngine();
  static const correctionBudget = 15;
  static int bounded(int value) => value.clamp(0, 100);

  (ToneTarget, List<String>) adapt(
    ToneTarget original,
    GuitarProfile guitar,
    GuitarTuning tuning,
    SoundRole role,
  ) {
    final deltas = <ToneDimension, int>{};
    final reasons = <String>[];
    void change(ToneDimension dim, int amount, String reason) {
      final previous = deltas[dim] ?? 0;
      final next = ((previous + amount).clamp(
        -10,
        10,
      )).clamp(-original[dim], 100 - original[dim]);
      deltas[dim] = next;
      final applied = next - previous;
      reasons.add('${dim.name} ${applied >= 0 ? '+' : ''}$applied: $reason');
    }

    if (tuning.depth >= 2) {
      change(
        ToneDimension.bass,
        tuning.depth >= 4 ? -7 : -4,
        'Tiefe Stimmung ${tuning.label}; Tiefbass vor Verzerrung begrenzen.',
      );
      change(
        ToneDimension.tightness,
        6,
        'Tiefere Stimmung verlangt einen strafferen Ausgangspunkt.',
      );
    }
    if (guitar.pickupType == PickupType.activeHumbucker ||
        guitar.outputLevel == OutputLevel.high) {
      change(
        ToneDimension.gain,
        -5,
        'Hoher Pickup-Ausgangspegel; weniger Amp-Sättigung nötig.',
      );
    }
    if (guitar.toneCharacter == ToneCharacter.bright) {
      change(
        ToneDimension.treble,
        -4,
        'Heller Pickup; Spitzen vorsichtig behandeln.',
      );
      change(ToneDimension.presence, -4, 'Heller Pickup; Presence begrenzen.');
    } else if (guitar.toneCharacter == ToneCharacter.dark) {
      change(
        ToneDimension.upperMids,
        5,
        'Dunkler Pickup; Definition bevorzugt über obere Mitten, nicht pauschal Treble.',
      );
      change(ToneDimension.mids, 2, 'Dunkler Pickup; moderate Mittenstütze.');
    }
    if (guitar.pickupType == PickupType.singleCoil ||
        guitar.pickupType == PickupType.p90) {
      change(
        ToneDimension.gateStrength,
        -8,
        'Brummanfälliger Pickup; Gate vorsichtiger als Ausgangspunkt.',
      );
      change(
        ToneDimension.compression,
        3,
        'Moderate Dynamikstütze, keine Brummunterdrückung behauptet.',
      );
    }
    if (role == SoundRole.rhythm) {
      change(ToneDimension.delay, -10, 'Rhythmus bleibt trocken.');
      change(ToneDimension.reverb, -4, 'Rhythmus: Hall sparsam.');
    } else if (role == SoundRole.lead) {
      change(ToneDimension.sustain, 8, 'Lead braucht mehr Sustain.');
      change(ToneDimension.delay, 8, 'Lead: moderates Delay.');
      change(ToneDimension.reverb, 4, 'Lead: etwas Räumlichkeit.');
    }
    return (
      original.changed({
        for (final e in deltas.entries)
          e.key: bounded(original[e.key] + e.value),
      }),
      reasons,
    );
  }

  Map<ToneDimension, int> correction(RecommendationFeedback feedback) =>
      switch (feedback) {
        RecommendationFeedback.tooBright => {
          ToneDimension.presence: -6,
          ToneDimension.treble: -4,
          ToneDimension.irBrightness: -6,
        },
        RecommendationFeedback.tooDark => {
          ToneDimension.presence: 4,
          ToneDimension.treble: 3,
          ToneDimension.irBrightness: 6,
        },
        RecommendationFeedback.tooMuddy => {
          ToneDimension.bass: -6,
          ToneDimension.gain: -3,
          ToneDimension.tightness: 6,
          ToneDimension.attack: 4,
        },
        RecommendationFeedback.tooMuchGain => {
          ToneDimension.gain: -6,
          ToneDimension.saturation: -4,
        },
        RecommendationFeedback.tooLittleGain => {
          ToneDimension.gain: 5,
          ToneDimension.saturation: 3,
        },
        RecommendationFeedback.tooThin => {
          ToneDimension.bass: 4,
          ToneDimension.lowMids: 5,
        },
        RecommendationFeedback.gateCutsNotes => {
          ToneDimension.gateStrength: -8,
          ToneDimension.gateOpening: 5,
        },
        RecommendationFeedback.tooBassy => {
          ToneDimension.bass: -6,
          ToneDimension.lowMids: -3,
        },
        RecommendationFeedback.tooNasal => {
          ToneDimension.mids: -4,
          ToneDimension.upperMids: -3,
        },
        RecommendationFeedback.notCutting => {
          ToneDimension.mids: 5,
          ToneDimension.upperMids: 4,
          ToneDimension.presence: 2,
          ToneDimension.bass: -2,
        },
        RecommendationFeedback.softAttack => {
          ToneDimension.attack: 5,
          ToneDimension.tightness: 4,
          ToneDimension.gain: -2,
        },
        RecommendationFeedback.lowSustain => {
          ToneDimension.sustain: 6,
          ToneDimension.compression: 4,
        },
        RecommendationFeedback.tooWet => {
          ToneDimension.reverb: -6,
          ToneDimension.space: -5,
        },
        RecommendationFeedback.tooDry => {
          ToneDimension.reverb: 4,
          ToneDimension.space: 4,
        },
      };

  ToneTarget corrected(
    ToneTarget current,
    ToneTarget baseline,
    RecommendationFeedback feedback,
  ) => current.changed({
    for (final e in correction(feedback).entries)
      e.key: bounded(
        (current[e.key] + e.value).clamp(
          baseline[e.key] - correctionBudget,
          baseline[e.key] + correctionBudget,
        ),
      ),
  });

  static List<DraftCandidate> topThree(List<DraftCandidate> list) {
    list.sort((a, b) {
      if (a.eligible != b.eligible) return a.eligible ? -1 : 1;
      final score = b.score.compareTo(a.score);
      return score == 0 ? a.id.compareTo(b.id) : score;
    });
    return List.unmodifiable(list.take(3));
  }

  static bool local(String uri, Set<String> available) {
    final parsed = Uri.tryParse(uri);
    return parsed != null &&
        {'file', 'content'}.contains(parsed.scheme) &&
        available.contains(uri);
  }

  static int closeness(int actual, int target, int weight) =>
      ((100 - (actual - target).abs()).clamp(0, 100) * weight / 100).round();

  PresetDraft create({
    required TargetDeviceId device,
    required TargetSound profile,
    required GuitarProfile guitar,
    required GuitarTuning tuning,
    required SoundRole role,
    required List<LocalNamCapture> nams,
    required List<LocalIrRecord> irs,
    required List<IrLibraryEntry> folderIrs,
    required Set<String> availableUris,
    ToneTarget? toneOverride,
    List<String>? history,
    String? selectedNamId,
  }) {
    if (!profile.roles.contains(role)) {
      throw ArgumentError('Keine kuratierte ${role.name}-Variante vorhanden.');
    }
    final base = profile.toneTarget;
    if (base == null) {
      throw ArgumentError('Kein kuratiertes Offline-Klangziel.');
    }
    final (adapted, guitarReasons) = adapt(base, guitar, tuning, role);
    // explicit user wishes come after the corrections (USER_OVERRIDE in the recipe)
    final tone = toneOverride ??
        (adapted.userAdjustments.isEmpty ? adapted : adapted.changed(adapted.userAdjustments.apply(adapted.values)));
    final adapter = toneDeviceAdapters.firstWhere((a) => a.id == device);
    final warnings = <String>[
      ...tone.uncertainties,
      'Pickup-Position und Mensur sind im bestehenden Gitarrenprofil nicht erfasst.',
      'Effekte ohne bestätigte Gerätemodelle/Parameter sind nur manuelle Empfehlungen.',
    ];
    if (!profile.supportedTunings.contains(tuning)) {
      warnings.add('Stimmung nicht im kuratierten Profil erprobt.');
    }
    if (guitar.stringGauge != null) {
      warnings.add(
        'Saitenstärke ${guitar.stringGauge}: verfügbar, aber keine belastbare automatische Skalierung; Saitenspannung manuell prüfen.',
      );
    }
    final ampCandidates = topThree(
      OfflineDeviceCatalog.amps(device).keys
          .map(
            (name) => DraftCandidate(
              id: name,
              name: name,
              parts: {
                'Amp-Familie':
                    name == 'J900' && tone.ampFamilies.contains('british')
                    ? 35
                    : 25,
                'Gain': closeness(
                  name.endsWith('LD') ? 80 : 65,
                  tone[ToneDimension.gain],
                  25,
                ),
                'Straffheit': closeness(78, tone[ToneDimension.tightness], 20),
                'Mitten/Rolle': closeness(65, tone[ToneDimension.mids], 20),
              },
              reasons: ['Modell im kleinen Zielgerätekatalog vorhanden.'],
              uncertainties: [
                'Klangmerkmale kuratierte Annäherung, keine gemessene Modellanalyse.',
              ],
            ),
          )
          .toList(),
    );
    final namCandidates = topThree(
      nams.map((capture) {
        final present = local(capture.localUri, availableUris);
        final exclusions = <String>[];
        if (!adapter.capabilities.supportsNam) {
          exclusions.add('Zielgerät unterstützt kein NAM.');
        }
        if (!present) exclusions.add('Datei nicht lokal vorhanden.');
        if (capture.architecture != NamArchitecture.a1 ||
            capture.compatibility != NamCompatibility.compatible ||
            capture.targetDevice != device) {
          exclusions.add(
            'Architektur/Validierung/Zielgerät nicht kompatibel bestätigt.',
          );
        }
        if (capture.cabinetContent == NamCabinetContent.unknown) {
          exclusions.add(
            'Cabinet-Inhalt unbekannt; doppelte Cab-Simulation nicht sicher ausschließbar.',
          );
        }
        if (guitar.usesRealGuitarCab &&
            capture.cabinetContent != NamCabinetContent.withoutCabinet) {
          exclusions.add('Cabinet im Capture plus reale Gitarrenbox.');
        }
        final tags =
            '${capture.toneName} ${capture.captureName} ${capture.make ?? ''} ${capture.tags.join(' ')}'
                .toLowerCase();
        final tagHits = tone.namTags
            .where((t) => tags.contains(t.toLowerCase()))
            .length;
        return DraftCandidate(
          id: capture.localId,
          name: capture.captureName,
          localAvailable: present,
          manualDownload: !present,
          exclusions: exclusions,
          parts: {
            'Kompatibilität/lokal': exclusions.isEmpty ? 35 : 0,
            'Amp-/NAM-Tags': (tagHits * 15).clamp(0, 45),
            'Rolle': tags.contains(role.name) ? 10 : 0,
            'Attribution':
                capture.creatorName.isNotEmpty && capture.license.isNotEmpty
                ? 10
                : 0,
          },
          reasons: [
            'Cabinet-Inhalt: ${capture.cabinetContent.name}; Quelle ${capture.source}.',
            'Creator ${capture.creatorName}; Lizenz ${capture.license}.',
          ],
          uncertainties: [
            ...capture.validationWarnings,
            if (tagHits == 0) 'Keine passenden Modell-Tags.',
            if (capture.creatorName.isEmpty || capture.license.isEmpty)
              'Attribution/Lizenz unbekannt.',
          ],
        );
      }).toList(),
    );
    LocalNamCapture? selectedNam;
    if (selectedNamId != null) {
      if (!namCandidates.any((c) => c.id == selectedNamId && c.eligible)) {
        throw ArgumentError(
          'NAM ist ausgeschlossen oder nicht unter den verfügbaren Top-Kandidaten.',
        );
      }
      selectedNam = nams.firstWhere((n) => n.localId == selectedNamId);
    }
    final cabEnabled =
        !guitar.usesRealGuitarCab &&
        (selectedNam == null ||
            selectedNam.cabinetContent == NamCabinetContent.withoutCabinet);
    if (!cabEnabled) {
      warnings.add(
        'Zusätzliche CAB/IR deaktiviert: reale Gitarrenbox oder NAM mit Cabinet/Full Rig.',
      );
    }
    final seenIrUris = <String>{};
    final irCandidates = cabEnabled
        ? topThree([
            for (final ir in irs)
              if (seenIrUris.add(ir.localUri))
                _irCandidate(ir, tone, availableUris, device),
            for (final ir in folderIrs)
              if (ir.matchedFiles.isNotEmpty &&
                  seenIrUris.add(ir.matchedFiles.first.uri))
                DraftCandidate(
                  id: ir.matchedFiles.first.uri,
                  name: ir.metadata.fileName,
                  parts: const {},
                  localAvailable: availableUris.contains(
                    ir.matchedFiles.first.uri,
                  ),
                  exclusions: const [
                    'SAF-Datei nur gelistet; tatsächliches WAV-Format und Gerätekompatibilität noch nicht geprüft.',
                  ],
                  uncertainties: const [
                    'Referenzkatalog ist Metadatenhinweis, kein Beweis für die tatsächlichen Dateibytes.',
                  ],
                ),
          ])
        : <DraftCandidate>[];
    final amp = ampCandidates.first.name;
    final ampParameters = OfflineDeviceCatalog.amps(device)[amp]!;
    final source =
        '${tone.source}; ${tone.profileId} v${tone.version}; Gitarren-/Tuning-Regeln; bestätigte sitzungsbezogene Korrekturen';
    final blocks = <DraftBlock>[
      DraftBlock(
        slot: 'Gate',
        model: null,
        enabled: tone[ToneDimension.gateStrength] > 0,
        parameters: device == TargetDeviceId.dnafxGitCore
            ? {'NOISE_GATE_ATTACK': tone[ToneDimension.gateOpening]}
            : const {},
        provenance: device == TargetDeviceId.dnafxGitCore
            ? {
                'NOISE_GATE_ATTACK':
                    '$source; DNAfx: höher bedeutet schnelleres Öffnen.',
              }
            : const {},
        note: device == TargetDeviceId.matriboxOne
            ? 'Gate-Stärke ${tone[ToneDimension.gateStrength]} nur manuell; Matribox-Parametersemantik nicht belegt.'
            : 'Öffnungsreaktion ist keine pauschale Gate-Schwelle.',
      ),
      DraftBlock(
        slot: 'Boost',
        model: device == TargetDeviceId.dnafxGitCore ? 'PURE BOOST' : null,
        enabled: tone[ToneDimension.tightness] >= 75,
        parameters: const {},
        provenance: const {},
        note: 'Bass vor dem Amp kontrollieren; konkrete Boost-Werte manuell, Modell/Parameter ggf. nicht verfügbar.',
      ),
      DraftBlock(
        slot: 'AMP',
        model: amp,
        enabled: selectedNam == null,
        parameters: {
          for (final e in ampParameters.entries)
            e.key: e.value.dimension == null
                ? 50
                : (tone[e.value.dimension!] * e.value.maximum / 100)
                      .round()
                      .clamp(0, e.value.maximum),
        },
        provenance: {
          for (final e in ampParameters.entries)
            e.key: e.value.dimension == null
                ? 'Editor-Standardwert 50; keine automatische Lautstärkekorrektur.'
                : source,
        },
        note: selectedNam == null
            ? 'Interner Amp als manuelle Einstellung; keine Geräteübertragung.'
            : 'Interner Amp deaktiviert; NAM ${selectedNam.captureName} nur manuell zuweisen, keine erfundenen NAM-Regler.',
      ),
      for (final slot in ['CAB', 'EQ', 'DLY', 'RVB'])
        DraftBlock(
          slot: slot,
          model: null,
          enabled: slot == 'CAB'
              ? cabEnabled
              : slot == 'DLY'
              ? tone[ToneDimension.delay] > 0
              : slot == 'RVB'
              ? tone[ToneDimension.reverb] > 0
              : false,
          parameters: const {},
          provenance: const {},
          note: 'Manuelle Einstellung erforderlich; konkretes Geräte-Modell/Parameter noch nicht katalogisiert.',
        ),
    ];
    final draft = PresetDraft(
      device: device,
      profile: profile,
      guitar: guitar,
      tuning: tuning,
      role: role,
      tone: tone,
      blocks: List.unmodifiable(blocks),
      candidates: {
        'AMP': ampCandidates,
        'NAM': namCandidates,
        'IR': irCandidates,
      },
      reasons: [tone.reason, ...guitarReasons],
      warnings: warnings,
      selectedNamId: selectedNamId,
      history:
          history ??
          [
            'Ausgangsprofil ${profile.id} v${profile.profileVersion} erzeugt.',
            ...guitarReasons,
          ],
      searchRequirements: [
        if (cabEnabled && !irCandidates.any((c) => c.eligible))
          'IR gesucht: geschlossene ${tone.cabinet}, ${tone.speaker}-artig, mittlere Helligkeit ${tone[ToneDimension.irBrightness]}, einzelnes ${tone.microphone}-artiges Mikrofon; technisch passende Mono-Datei manuell prüfen.',
        if (adapter.capabilities.supportsNam &&
            !namCandidates.any((c) => c.eligible))
          'NAM gesucht: A1, Amp ohne Cabinet, Tags ${tone.namTags.join(', ')}; manuelle Auswahl, kein automatischer Download.',
      ],
    );
    OfflineDeviceCatalog.validate(draft);
    return draft;
  }

  DraftCandidate _irCandidate(
    LocalIrRecord ir,
    ToneTarget tone,
    Set<String> available,
    TargetDeviceId device,
  ) {
    final present = local(ir.localUri, available);
    final excluded = <String>[];
    if (!present) excluded.add('Datei fehlt lokal.');
    if (ir.availability == LocalIrAvailability.invalid) {
      excluded.add('WAV-Validierung fehlgeschlagen.');
    }
    if (ir.channels != 1) {
      excluded.add(
        'Stereo nicht ohne bestätigte Konvertierung als Geräte-IR anbieten.',
      );
    }
    // Device importer/length limits are not sufficiently verified. Never infer
    // compatibility merely from WavValidator's broad RIFF acceptance.
    excluded.add(
      'Geräte-IR-Samplerate/Bit-Tiefe/Längenlimit noch nicht bestätigt: ${ir.sampleRateHz} Hz / ${ir.bitsPerSample} Bit / ${ir.durationMs} ms. Nur als Suchhinweis.',
    );
    final name = '${ir.fileName} ${ir.toneName}'.toLowerCase();
    final brightness = name.contains('capedge') || name.contains('ribbon')
        ? 40
        : name.contains('cap')
        ? 70
        : 50;
    return DraftCandidate(
      id: ir.localUri,
      name: ir.fileName,
      localAvailable: present,
      manualDownload: !present,
      exclusions: excluded,
      parts: {
        'Cabinet': name.contains(tone.cabinet) ? 25 : 0,
        'Speaker': name.contains(tone.speaker.toLowerCase()) ? 25 : 0,
        'Mikrofon': name.contains(tone.microphone.toLowerCase()) ? 20 : 0,
        'Helligkeit': closeness(
          brightness,
          tone[ToneDimension.irBrightness],
          20,
        ),
        'Attribution': ir.creatorName.isNotEmpty && ir.license.isNotEmpty
            ? 10
            : 0,
      },
      reasons: ['Creator ${ir.creatorName}; Lizenz ${ir.license}.'],
      uncertainties: [
        'Helligkeit aus Dateiname geschätzt; keine Audioanalyse.',
        'Gerätekompatibilität ${device.name} ungeprüft.',
      ],
    );
  }
}
