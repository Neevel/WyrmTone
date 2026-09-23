/// What the user picked in the sound flow, in a small persistable form: the built-in sound, the
/// variant, the tuning and the user's wishes. The heavy draft is NOT stored: it is rebuilt
/// deterministically from this selection, the sound library and the current guitar profile.
library;

import 'dart:convert';

import '../models/guitar_profile.dart';
import '../services/local_persistence.dart';
import '../tonevault/tone_vault_model.dart' show ToneVariantKind;
import '../tonevault/tone_vault_query.dart';

const soundSelectionVersion = 1;

class SoundSelection {
  const SoundSelection({
    required this.entryId,
    required this.tuning,
    this.variant,
    this.modifiers = const [],
    this.effects = const [],
  });

  final String entryId;
  final GuitarTuning tuning;
  final ToneVariantKind? variant;
  final List<ToneModifierIntent> modifiers;
  final List<ToneEffectIntent> effects;

  /// The request the sound library applies (role, tuning, wishes). No text parsing involved.
  ToneQuery toQuery() => ToneQuery(
    role: variant,
    tuning: tuning.name,
    modifiers: [for (final m in modifiers) m.modifier],
    modifierIntents: modifiers,
    effects: effects,
  );

  SoundSelection copyWith({GuitarTuning? tuning, ToneVariantKind? variant, List<ToneModifierIntent>? modifiers, List<ToneEffectIntent>? effects}) =>
      SoundSelection(
        entryId: entryId,
        tuning: tuning ?? this.tuning,
        variant: variant ?? this.variant,
        modifiers: modifiers ?? this.modifiers,
        effects: effects ?? this.effects,
      );

  Map<String, Object?> toJson() => {
    'version': soundSelectionVersion,
    'entry': entryId,
    'tuning': tuning.name,
    if (variant != null) 'variant': variant!.wire,
    'modifiers': [
      for (final m in modifiers) {'modifier': m.modifier.wire, 'intensity': m.intensity.wire},
    ],
    'effects': [
      for (final e in effects) {'effect': e.kind.name, 'off': e.off},
    ],
  };

  /// Identity of the selection (used to compare with a draft and to avoid duplicate recents).
  String get signature => jsonEncode(toJson());

  /// Strict: anything unexpected returns null (a damaged saved sound must never crash the app).
  static SoundSelection? tryParse(Object? raw) {
    try {
      if (raw is! Map || raw['version'] != soundSelectionVersion) return null;
      final entry = raw['entry'];
      final tuning = GuitarTuning.values.where((t) => t.name == raw['tuning']).firstOrNull;
      if (entry is! String || entry.isEmpty || tuning == null) return null;
      ToneVariantKind? variant;
      if (raw['variant'] != null) {
        variant = ToneVariantKind.values.where((v) => v.wire == raw['variant']).firstOrNull;
        if (variant == null) return null;
      }
      final modifiers = <ToneModifierIntent>[];
      for (final m in (raw['modifiers'] as List? ?? const [])) {
        final modifier = ToneModifier.tryParse('${(m as Map)['modifier']}');
        final intensity = ToneIntensity.tryParse('${m['intensity']}');
        if (modifier == null || intensity == null) return null;
        modifiers.add(ToneModifierIntent(modifier, intensity));
      }
      final effects = <ToneEffectIntent>[];
      for (final e in (raw['effects'] as List? ?? const [])) {
        final kind = ToneEffectKind.tryParse('${(e as Map)['effect']}');
        if (kind == null) return null;
        effects.add(ToneEffectIntent(kind, off: e['off'] == true));
      }
      return SoundSelection(entryId: entry, tuning: tuning, variant: variant, modifiers: modifiers, effects: effects);
    } catch (_) {
      return null;
    }
  }

  static SoundSelection? tryDecode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      return tryParse(jsonDecode(text));
    } catch (_) {
      return null;
    }
  }
}

/// Persists the current sound and a short "recently used" list through the app's simple string store.
class SoundSelectionRepository {
  SoundSelectionRepository(this._store);
  final StringStore _store;

  static const currentKey = 'wyrmtone.sound.current.v1';
  static const recentKey = 'wyrmtone.sound.recent.v1';
  static const maxRecent = 6;

  Future<SoundSelection?> loadCurrent() async => SoundSelection.tryDecode(await _store.read(currentKey));

  Future<void> saveCurrent(SoundSelection selection) => _store.write(currentKey, jsonEncode(selection.toJson()));

  Future<void> clearCurrent() => _store.write(currentKey, '');

  Future<List<SoundSelection>> loadRecent() async {
    try {
      final text = await _store.read(recentKey);
      if (text == null || text.isEmpty) return const [];
      final list = jsonDecode(text);
      if (list is! List) return const [];
      return [for (final item in list) ?SoundSelection.tryParse(item)];
    } catch (_) {
      return const [];
    }
  }

  Future<List<SoundSelection>> addRecent(SoundSelection selection) async {
    final current = await loadRecent();
    final next = [selection, for (final s in current) if (s.entryId != selection.entryId || s.variant != selection.variant) s].take(maxRecent).toList();
    await _store.write(recentKey, jsonEncode([for (final s in next) s.toJson()]));
    return next;
  }
}
