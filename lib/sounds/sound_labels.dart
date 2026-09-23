/// User-facing German wording for the sound flow. Internal names (sound library, recipe, NLU, ids)
/// never reach the normal UI; this file is the single place where they are translated.
library;

import 'package:flutter/material.dart' show IconData, Icons;

import '../models/tone_target.dart' show ToneDimension;
import '../tonevault/tone_vault_composer.dart' show ResolvedTone;
import '../tonevault/tone_vault_model.dart';
import '../tonevault/tone_vault_query.dart';
import '../tonevault/tone_vault_taxonomy.dart';

String sourceLabel(SourceClass c) => switch (c) {
  SourceClass.researched => 'Recherchiert',
  SourceClass.curated => 'Kuratiert',
  SourceClass.styleInspired => 'Inspiriert',
  SourceClass.wyrmOriginal => 'Wyrm Original',
  SourceClass.guitarReimagined => 'Auf Gitarre neu gedacht',
  SourceClass.community => 'Community',
  SourceClass.aiGenerated => 'Automatisch erzeugt',
};

String variantLabel(ToneVariantKind v) => switch (v) {
  ToneVariantKind.rhythm => 'Rhythmus',
  ToneVariantKind.lead => 'Lead',
  ToneVariantKind.solo => 'Solo',
  ToneVariantKind.clean => 'Clean',
  ToneVariantKind.crunch => 'Crunch',
  ToneVariantKind.ambient => 'Ambient',
  ToneVariantKind.special => 'Spezial',
};

/// The name a person expects on a card ("Metallica", "Master of Puppets"), not the internal entry title.
String entryDisplayTitle(ToneVaultEntry e) {
  switch (e.type) {
    case ToneEntryType.artistSignature:
      return e.artist ?? e.title;
    case ToneEntryType.song:
      return e.song ?? e.title;
    case ToneEntryType.albumSignature:
      return e.album ?? e.title;
    case ToneEntryType.guitarReimagined:
      return e.song ?? e.title;
    case ToneEntryType.genreTemplate || ToneEntryType.styleTemplate:
      return e.title.replaceAll(RegExp(r'\s*\((Basis|Style)\)\s*$'), '');
    case ToneEntryType.eraSignature || ToneEntryType.originalWyrmtone:
      return e.title;
  }
}

/// One short line below the title: who/what kind of sound this is.
String entrySubtitle(ToneVaultEntry e, ToneTaxonomy taxonomy) {
  final genre = e.genres.isEmpty ? null : taxonomy.genres[e.genres.first]?.name;
  return switch (e.type) {
    ToneEntryType.artistSignature => ['Künstler', ?genre].join(' · '),
    ToneEntryType.eraSignature => e.artist == null ? 'Klangphase' : '${e.artist} · Klangphase',
    ToneEntryType.albumSignature => [?e.artist, 'Album'].join(' · '),
    ToneEntryType.song => [?e.artist, 'Song'].join(' · '),
    ToneEntryType.genreTemplate => ['Genre', ?genre].join(' · '),
    ToneEntryType.styleTemplate => ['Stil', ?genre].join(' · '),
    ToneEntryType.guitarReimagined => [?e.artist, 'Auf Gitarre neu gedacht'].join(' · '),
    ToneEntryType.originalWyrmtone => 'Wyrm Original',
  };
}

String tagLabel(String tag) => tag.replaceAll('-', ' ');

/// One glance icon so a search suggestion's kind (Song/Artist/Genre/...) is visible without
/// showing the internal type name.
IconData entryTypeIcon(ToneEntryType type) => switch (type) {
  ToneEntryType.song => Icons.music_note,
  ToneEntryType.albumSignature => Icons.album_outlined,
  ToneEntryType.artistSignature => Icons.person_outline,
  ToneEntryType.eraSignature => Icons.history_outlined,
  ToneEntryType.genreTemplate => Icons.category_outlined,
  ToneEntryType.styleTemplate => Icons.style_outlined,
  ToneEntryType.guitarReimagined => Icons.bolt_outlined,
  ToneEntryType.originalWyrmtone => Icons.auto_awesome_outlined,
};

/// A short, non-technical word for the same kind, used as a caption next to the icon.
String entryTypeWord(ToneEntryType type) => switch (type) {
  ToneEntryType.song => 'Song',
  ToneEntryType.albumSignature => 'Album',
  ToneEntryType.artistSignature => 'Künstler',
  ToneEntryType.eraSignature => 'Klangphase',
  ToneEntryType.genreTemplate => 'Genre',
  ToneEntryType.styleTemplate => 'Stil',
  ToneEntryType.guitarReimagined => 'Neu gedacht',
  ToneEntryType.originalWyrmtone => 'Wyrm Original',
};

class SoundMetric {
  const SoundMetric(this.label, this.value);
  final String label;
  final int value;
}

/// The character of a sound as a few understandable properties (0..100), from what the sound defines.
/// Undefined properties are left out; nothing is invented.
List<SoundMetric> soundMetrics(Map<ToneDimension, int> dims, [Map<CharacterAxis, int> character = const {}]) {
  int? avg(List<ToneDimension> ds) {
    final v = [for (final d in ds) ?dims[d]];
    return v.isEmpty ? null : (v.reduce((a, b) => a + b) / v.length).round();
  }

  final rows = <(String, int?)>[
    ('Gain', dims[ToneDimension.gain]),
    ('Straffheit', dims[ToneDimension.tightness]),
    ('Körper', avg([ToneDimension.bass, ToneDimension.lowMids])),
    ('Mitten', avg([ToneDimension.mids, ToneDimension.upperMids])),
    ('Helligkeit', avg([ToneDimension.treble, ToneDimension.presence, ToneDimension.irBrightness])),
    ('Sustain', dims[ToneDimension.sustain]),
    ('Aggression', character[CharacterAxis.aggression]),
    ('Wärme', character[CharacterAxis.warmth]),
    ('Raum', avg([ToneDimension.reverb, ToneDimension.space])),
    ('Delay', dims[ToneDimension.delay]),
    ('Modulation', dims[ToneDimension.modulation]),
  ];
  return [for (final r in rows) if (r.$2 != null) SoundMetric(r.$1, r.$2!.clamp(0, 100))];
}

List<SoundMetric> soundMetricsOf(Map<ToneDimension, int> dims, ResolvedTone? resolved) => soundMetrics(dims, resolved?.character ?? const {});

/// A quick adjustment the user can make: two opposite wishes on one property.
class AdjustmentAxis {
  const AdjustmentAxis(this.id, this.label, this.more, this.less, this.moreWord, this.lessWord);
  final String id, label, moreWord, lessWord;
  final ToneModifier more, less;
}

const adjustmentAxes = <AdjustmentAxis>[
  AdjustmentAxis('gain', 'Gain', ToneModifier.moreGain, ToneModifier.lessGain, 'Mehr Gain', 'Weniger Gain'),
  AdjustmentAxis('bass', 'Bass', ToneModifier.moreBass, ToneModifier.lessBass, 'Mehr Bass', 'Weniger Bass'),
  AdjustmentAxis('mids', 'Mitten', ToneModifier.moreMids, ToneModifier.lessMids, 'Mehr Mitten', 'Weniger Mitten'),
  AdjustmentAxis('bright', 'Helligkeit', ToneModifier.brighter, ToneModifier.darker, 'Heller', 'Dunkler'),
  AdjustmentAxis('tight', 'Straffheit', ToneModifier.tighter, ToneModifier.looser, 'Straffer', 'Lockerer'),
  AdjustmentAxis('body', 'Körper', ToneModifier.moreBody, ToneModifier.lessBody, 'Mehr Körper', 'Weniger Körper'),
  AdjustmentAxis('reverb', 'Hall', ToneModifier.moreReverb, ToneModifier.lessReverb, 'Mehr Hall', 'Weniger Hall'),
  AdjustmentAxis('delay', 'Delay', ToneModifier.moreDelay, ToneModifier.lessDelay, 'Mehr Delay', 'Weniger Delay'),
  AdjustmentAxis('aggression', 'Aggression', ToneModifier.moreAggressive, ToneModifier.lessAggressive, 'Aggressiver', 'Weicher'),
  AdjustmentAxis('era', 'Stil', ToneModifier.moreModern, ToneModifier.moreVintage, 'Moderner', 'Vintage'),
];

String intensityWord(ToneIntensity i) => switch (i) {
  ToneIntensity.slight => 'etwas',
  ToneIntensity.normal => '',
  ToneIntensity.strong => 'deutlich',
};

const _otherModifierWords = <ToneModifier, String>{
  ToneModifier.moreTreble: 'Mehr Höhen',
  ToneModifier.lessTreble: 'Weniger Höhen',
  ToneModifier.morePresence: 'Mehr Präsenz',
  ToneModifier.lessPresence: 'Weniger Präsenz',
  ToneModifier.moreClarity: 'Klarer',
  ToneModifier.lessClarity: 'Weniger klar',
  ToneModifier.moreCompression: 'Mehr Kompression',
  ToneModifier.lessCompression: 'Weniger Kompression',
  ToneModifier.moreModulation: 'Mehr Modulation',
  ToneModifier.lessModulation: 'Weniger Modulation',
  ToneModifier.moreAmbient: 'Atmosphärischer',
  ToneModifier.lessAmbient: 'Weniger Atmosphäre',
  ToneModifier.dirtier: 'Dreckiger',
  ToneModifier.cleaner: 'Sauberer',
  ToneModifier.warmer: 'Wärmer',
  ToneModifier.colder: 'Kälter',
  ToneModifier.drier: 'Trockener',
  ToneModifier.wetter: 'Nasser',
};

/// "Weniger Gain (etwas)" style wording of one wish.
String modifierLabel(ToneModifierIntent i) {
  final base = _wordOf(i.modifier);
  final level = intensityWord(i.intensity);
  return level.isEmpty ? base : '$base ($level)';
}

String _wordOf(ToneModifier m) {
  for (final a in adjustmentAxes) {
    if (a.more == m) return a.moreWord;
    if (a.less == m) return a.lessWord;
  }
  return _otherModifierWords[m] ?? m.wire;
}

String effectLabel(ToneEffectIntent e) {
  const names = {
    ToneEffectKind.boost: 'Boost',
    ToneEffectKind.overdrive: 'Overdrive',
    ToneEffectKind.distortion: 'Distortion',
    ToneEffectKind.fuzz: 'Fuzz',
    ToneEffectKind.compressor: 'Kompressor',
    ToneEffectKind.gate: 'Gate',
    ToneEffectKind.chorus: 'Chorus',
    ToneEffectKind.flanger: 'Flanger',
    ToneEffectKind.phaser: 'Phaser',
    ToneEffectKind.tremolo: 'Tremolo',
    ToneEffectKind.vibrato: 'Vibrato',
    ToneEffectKind.delay: 'Delay',
    ToneEffectKind.reverb: 'Hall',
    ToneEffectKind.wah: 'Wah',
    ToneEffectKind.octave: 'Oktave',
    ToneEffectKind.eq: 'EQ',
  };
  final n = names[e.kind] ?? e.kind.name;
  return e.off ? 'Ohne $n' : 'Mit $n';
}
