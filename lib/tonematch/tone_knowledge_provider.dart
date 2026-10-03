import '../models/tone_target.dart' show SoundRole, ToneDimension;
import '../tonevault/tone_vault.dart';
import '../tonevault/tone_vault_model.dart';
import 'tone_match_models.dart';

/// Source of tone knowledge. The core depends only on this interface; a local implementation
/// (ToneVault) is the default, an optional online provider could be added later without any
/// change to the engine. No provider may be required for the core function.
abstract interface class ToneKnowledgeProvider {
  /// Returns null when the provider knows nothing about the request.
  Future<ToneIntent?> resolve(ToneMatchRequest request);
}

/// Curated, deliberately small role hints for songs that have no own ToneVault entry. They only
/// pick RHYTHM/LEAD/CLEAN; they never state equipment. Marked HEURISTIC in the evidence.
const _songRoleHints = <String, SoundRole>{
  'the loner': SoundRole.lead,
  'still got the blues': SoundRole.lead,
  'parisienne walkways': SoundRole.lead,
  'heresy': SoundRole.rhythm,
  'master of puppets': SoundRole.rhythm,
  'silvera': SoundRole.rhythm,
  'come as you are': SoundRole.clean,
  'downfall': SoundRole.lead,
};

const _tagWords = {
  'singing': 'singend',
  'sustaining': 'sustainreich',
  'thick': 'dicht',
  'groove': 'groovig',
  'sharp': 'scharf',
  'scooped': 'ausgehöhlte Mitten',
};

class LocalToneKnowledgeProvider implements ToneKnowledgeProvider {
  LocalToneKnowledgeProvider(this.vault);
  final ToneVault vault;

  /// "Artist - Song" -> (artist, song). Without a separator the whole text is free text.
  static (String?, String?) splitArtistSong(String text) {
    final parts = text.split(RegExp(r'\s+[-–—]\s+'));
    if (parts.length < 2) return (null, null);
    return (parts.first.trim(), parts.sublist(1).join(' - ').trim());
  }

  @override
  Future<ToneIntent?> resolve(ToneMatchRequest request) async {
    final text = request.text.trim();
    if (text.isEmpty) return null;
    final (artistPart, songPart) = splitArtistSong(text);
    final nlu = vault.nlu.understand(text);
    final candidate =
        nlu.resolution.primary ?? nlu.resolution.candidates.firstOrNull;
    if (candidate == null) return null;
    final entry = candidate.entry;
    final isSong = entry.type == ToneEntryType.song;

    final songKey = (songPart ?? entry.song ?? '').toLowerCase();
    final hintedRole = _songRoleHints[songKey];
    final explicitVariant = nlu.query.role;
    final role = explicitVariant != null
        ? _roleOf(explicitVariant)
        : hintedRole ?? _roleOfEntry(entry);
    final variant = switch (role) {
      SoundRole.lead => ToneVariantKind.lead,
      SoundRole.clean => ToneVariantKind.clean,
      SoundRole.rhythm => ToneVariantKind.rhythm,
    };
    final def = vault.definition(entry.id, variant: variant);
    final res = def.resolved;
    final dims = Map<ToneDimension, int>.of(def.dimensions);

    final amp = res.ampFamilies ?? const <String>[];
    final tags = res.namTags ?? const <String>[];
    final delay = res.kinds[ToneKindSlot.delay];
    final reverb = res.kinds[ToneKindSlot.reverb];

    final src = entry.title;
    // Where the statement comes from: sources (KNOWN), WyrmTone's own curated/style description
    // (CURATED), or community/automatic content (INFERRED).
    final basis = switch (entry.sourceClass) {
      SourceClass.researched => EvidenceKind.known,
      SourceClass.curated ||
      SourceClass.styleInspired ||
      SourceClass.wyrmOriginal ||
      SourceClass.guitarReimagined => EvidenceKind.curated,
      SourceClass.community || SourceClass.aiGenerated => EvidenceKind.inferred,
    };
    final evidence = <String, ToneEvidence>{
      'song': isSong
          ? ToneEvidence(EvidenceKind.known, 'ToneVault: ${entry.title}')
          : ToneEvidence(
              EvidenceKind.unknown,
              songPart == null
                  ? 'Kein Song angegeben.'
                  : 'Für „$songPart“ gibt es keinen eigenen Eintrag; es wird der Stil von ${entry.artist ?? entry.title} verwendet.',
            ),
      'amp': amp.isEmpty
          ? const ToneEvidence(
              EvidenceKind.unknown,
              'Keine Amp-Familie hinterlegt.',
            )
          : ToneEvidence(basis, src),
      'gain': ToneEvidence(basis, src),
      'role': explicitVariant != null
          ? const ToneEvidence(EvidenceKind.userInput, 'Aus deiner Eingabe.')
          : hintedRole != null
          ? const ToneEvidence(
              EvidenceKind.heuristic,
              'Kuratierter Rollenhinweis zum Songtitel.',
            )
          : const ToneEvidence(
              EvidenceKind.heuristic,
              'Erste hinterlegte Rolle des Künstlerprofils.',
            ),
      'effects': (delay == null && reverb == null)
          ? const ToneEvidence(
              EvidenceKind.unknown,
              'Keine Effektangaben hinterlegt.',
            )
          : ToneEvidence(EvidenceKind.inferred, src),
      if (res.cabinet != null)
        'cabinet': ToneEvidence(EvidenceKind.inferred, src),
      if (request.guitarName != null)
        'guitar': ToneEvidence(EvidenceKind.userInput, request.guitarName!),
    };

    final confidence = switch ((
      isSong,
      entry.confidence,
      nlu.resolution.kind.name,
    )) {
      (true, ToneConfidence.high, 'exact') => IntentConfidence.high,
      (_, ToneConfidence.low, _) || (_, _, 'choose') => IntentConfidence.low,
      (false, _, _) => IntentConfidence.medium,
      _ => IntentConfidence.medium,
    };

    return ToneIntent(
      query: text,
      artist: entry.artist ?? artistPart,
      song: songPart ?? entry.song,
      matchedTitle: entry.title,
      songKnown: isSong,
      role: role,
      dimensions: dims,
      ampFamilies: amp,
      namTags: tags,
      cabinet: res.cabinet ?? '',
      delayKind: delay,
      reverbKind: reverb,
      descriptors: _descriptors(entry, dims),
      confidence: confidence,
      evidence: evidence,
    );
  }

  static SoundRole _roleOf(ToneVariantKind k) => switch (k) {
    ToneVariantKind.lead || ToneVariantKind.solo => SoundRole.lead,
    ToneVariantKind.clean || ToneVariantKind.ambient => SoundRole.clean,
    _ => SoundRole.rhythm,
  };

  static SoundRole _roleOfEntry(ToneVaultEntry e) =>
      e.roles.isEmpty ? SoundRole.rhythm : _roleOf(e.roles.first);

  static List<String> _descriptors(
    ToneVaultEntry e,
    Map<ToneDimension, int> d,
  ) {
    final out = <String>[];
    for (final t in e.tags) {
      final w = _tagWords[t];
      if (w != null) out.add(w);
    }
    final gain = d[ToneDimension.gain] ?? 0;
    if (gain >= 65) {
      out.add('High-Gain');
    } else if (gain >= 40) {
      out.add('Crunch');
    } else if (gain > 0) {
      out.add('Clean/Edge');
    }
    return out.take(3).toList();
  }
}
