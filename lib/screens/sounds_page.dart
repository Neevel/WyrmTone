import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../models/guitar_profile.dart';
import '../sounds/sound_labels.dart';
import '../sounds/sound_selection.dart';
import '../sounds/sound_session.dart';
import '../tonevault/tone_nlu.dart';
import '../tonevault/tone_vault.dart';
import '../tonevault/tone_vault_model.dart';
import '../tonevault/tone_vault_search.dart';
import '../ui/wyrm_components.dart';
import '../ui/wyrm_design.dart';
import 'sound_detail_page.dart';
import 'your_sound_page.dart';

/// Where a sound starts: describe what you want to play (a song, an artist, a genre or a free
/// description), pick a result, adjust it, use it.
class SoundsPage extends StatefulWidget {
  const SoundsPage({required this.controller, required this.session, this.openProfile, super.key});
  final RecommendationController controller;
  final SoundSession session;
  final VoidCallback? openProfile;

  @override
  State<SoundsPage> createState() => _SoundsPageState();
}

enum _Filter {
  all('Alle', null),
  artists('Künstler & Klangphasen', {ToneEntryType.artistSignature, ToneEntryType.eraSignature}),
  songs('Songs & Alben', {ToneEntryType.song, ToneEntryType.albumSignature}),
  genres('Genres & Stile', {ToneEntryType.genreTemplate, ToneEntryType.styleTemplate}),
  special('Wyrm Originals & neu gedacht', {ToneEntryType.guitarReimagined, ToneEntryType.originalWyrmtone});

  const _Filter(this.label, this.types);
  final String label;
  final Set<ToneEntryType>? types;
}

class _SoundsPageState extends State<SoundsPage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  ToneNluResult? _result;
  _Filter _filter = _Filter.all;
  Timer? _debounce;

  /// How long a keystroke waits before the local resolver runs again -- imperceptible to a person,
  /// but keeps every frame of typing cheap; no suggestion request per frame.
  static const _suggestDebounce = Duration(milliseconds: 180);

  static const _suggestions = [
    'Master of Puppets Rhythmus',
    '80er Hard Rock Lead',
    'warmer Blues Crunch',
    'moderner Metalcore für Drop C',
    'Sandstorm auf Gitarre',
  ];
  static const _genreIds = [
    'thrash_metal',
    'heavy_metal',
    'melodic_death_metal',
    'metalcore',
    'nu_metal',
    'grunge',
    'hard_rock',
    'blues_rock',
    'punk_rock',
    'funk',
    'jazz',
    'ambient',
    'synthwave',
  ];
  static const _exploreIds = [
    'reimagined.darude_sandstorm',
    'original.cyberpunk_lead',
    'original.vhs_chorus_clean',
    'original.neon_outrun_lead',
    'reimagined.prodigy_firestarter',
    'original.telephone_guitar',
  ];

  @override
  void initState() {
    super.initState();
    widget.session.ensureLoaded();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _run(String text) {
    final vault = widget.session.vault;
    setState(() {
      _filter = _Filter.all;
      _result = vault == null || text.trim().isEmpty ? null : vault.nlu.understand(text);
    });
  }

  /// Local-only, debounced: every keystroke schedules a re-run of the existing resolver a little
  /// later instead of on every frame; typing more before it fires just reschedules it.
  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(_suggestDebounce, () {
      if (mounted) _run(text);
    });
  }

  void _ask(String text) {
    _debounce?.cancel();
    _search.text = text;
    _search.selection = TextSelection.collapsed(offset: text.length);
    _run(text);
  }

  /// A genre/style the free text clearly named, even when the sentence around it confused the
  /// overall resolver into no candidate at all. Only ever looked up by an id the resolver itself
  /// already extracted -- never guessed -- and only used if that curated entry really exists.
  ToneVaultEntry? _describedGenreEntry(ToneVault vault, ToneNluResult r) {
    for (final id in [r.query.subgenre, r.query.genre]) {
      if (id == null) continue;
      final entry = vault.entry('tpl.genre.$id') ?? vault.entry('tpl.style.$id');
      if (entry != null) return entry;
    }
    return null;
  }

  /// Prefer a known Song/Artist tie over a Genre/Style tie over everything else, matching the
  /// ranking the milestone asks for; the match TIER itself (below) always decides first.
  static int _typeWeight(ToneEntryType t) => switch (t) {
    ToneEntryType.song || ToneEntryType.originalWyrmtone || ToneEntryType.guitarReimagined => 0,
    ToneEntryType.artistSignature => 1,
    ToneEntryType.genreTemplate || ToneEntryType.styleTemplate => 2,
    ToneEntryType.albumSignature || ToneEntryType.eraSignature => 3,
  };

  /// Live, local suggestions for a short/partial word the full resolver would not yet accept as a
  /// complete phrase ("mas", "child", "metalco"): same catalog, same display names the resolver
  /// itself uses, just matched by prefix/substring instead of full-phrase understanding. Selecting
  /// one always goes through the real resolver ([_ask]/[_openDetail]) -- this never builds a sound
  /// on its own and never invents a second scoring model for what "the right sound" is.
  List<ToneVaultEntry> _prefixSuggestions(ToneVault vault, String rawText) {
    final needle = rawText.trim().toLowerCase();
    if (needle.length < 2) return const [];

    /// 0 exact, 1 starts-with, 2 a word inside starts-with, 3 substring anywhere; null = no match.
    int? tierOf(Iterable<String> names) {
      int? best;
      for (final raw in names) {
        final n = raw.toLowerCase();
        if (n.isEmpty) continue;
        if (n == needle) return 0;
        if (n.startsWith(needle)) {
          best = best == null ? 1 : (best < 1 ? best : 1);
        } else if (n.split(RegExp(r'\s+')).any((t) => t.startsWith(needle))) {
          best ??= 2;
        } else if (n.contains(needle)) {
          best ??= 3;
        }
      }
      return best;
    }

    // What the entry itself IS (its own name) always outranks a match that only comes from WHO
    // it is attributed to (e.g. every song by an artist would otherwise tie with that artist).
    (int tier, bool ownName)? matchOf(ToneVaultEntry e) {
      final ownNames = <String>{entryDisplayTitle(e), ?e.song, ?e.album};
      if (tierOf(ownNames) case final t?) return (t, true);
      final attributionNames = <String>{?e.artist, ...e.searchAliases, ...e.artistAliases, ...e.songAliases, ...e.albumAliases};
      if (tierOf(attributionNames) case final t?) return (t, false);
      return null;
    }

    final scored = <(ToneVaultEntry, int, bool)>[
      for (final e in vault.entries)
        if (matchOf(e) case (final tier, final own)?) (e, tier, own),
    ];
    scored.sort((a, b) {
      final byTier = a.$2.compareTo(b.$2);
      if (byTier != 0) return byTier;
      final byOwn = (a.$3 ? 0 : 1).compareTo(b.$3 ? 0 : 1);
      if (byOwn != 0) return byOwn;
      return _typeWeight(a.$1.type).compareTo(_typeWeight(b.$1.type));
    });
    return [for (final s in scored.take(8)) s.$1];
  }

  List<Widget> _prefixSuggestionCards(BuildContext context, ToneVault vault, List<ToneVaultEntry> entries) => [
    Padding(
      padding: const EdgeInsets.only(top: WyrmTokens.space16, bottom: WyrmTokens.space4),
      child: Text('Vorschläge', key: const Key('prefix-suggestions'), style: Theme.of(context).textTheme.titleSmall),
    ),
    for (final e in entries) _entryCard(context, vault, e),
  ];

  Future<void> _openDetail(ToneVaultEntry entry, {ToneNluResult? from}) async {
    final q = from?.query;
    final tuningName = from?.tuning?.guitarTuning;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SoundDetailPage(
          controller: widget.controller,
          session: widget.session,
          entryId: entry.id,
          seed: SoundSeed(
            variant: q?.role,
            modifiers: q?.modifierIntents ?? const [],
            effects: q?.effects ?? const [],
            tuning: tuningName == null ? null : GuitarTuning.values.where((t) => t.name == tuningName).firstOrNull,
          ),
          openProfile: widget.openProfile,
        ),
      ),
    );
  }

  Future<void> _openCurrent() => openYourSound(
    context,
    controller: widget.controller,
    session: widget.session,
    openProfile: widget.openProfile,
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.session, widget.controller]),
      builder: (context, _) {
        final session = widget.session;
        // the library may have finished loading after the user typed: interpret again
        if (_result == null && session.ready && _search.text.trim().isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _result == null) _run(_search.text);
          });
        }
        return WyrmScaffold(
          title: 'Sounds',
          background: true,
          backgroundIntensity: WyrmBackgroundIntensity.strong,
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            // Tapping anywhere outside the field puts the keyboard away; the result/suggestion
            // list itself is just page content, so it never needs a separate "close" action.
            onTap: () => _searchFocus.unfocus(),
            child: ListView(
              key: const PageStorageKey('sounds-page'),
              padding: WyrmTokens.pagePadding,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: WyrmTokens.contentWidth),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _content(context)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _content(BuildContext context) {
    final session = widget.session;
    final theme = Theme.of(context);
    final vault = session.vault;
    return [
      Text('Was möchtest du spielen?', style: theme.textTheme.headlineSmall),
      const SizedBox(height: WyrmTokens.space12),
      WyrmSearchField(
        fieldKey: const Key('sound-search'),
        controller: _search,
        focusNode: _searchFocus,
        hint: 'Song, Künstler, Genre oder Sound beschreiben …',
        onChanged: _onChanged,
        onSubmitted: _run,
      ),
      if (_search.text.isEmpty) ...[
        const SizedBox(height: WyrmTokens.space12),
        Wrap(
          spacing: WyrmTokens.space8,
          runSpacing: WyrmTokens.space4,
          children: [for (final s in _suggestions) WyrmChip(s, icon: Icons.north_west, onTap: () => _ask(s))],
        ),
      ],
      if (session.vaultError != null)
        Padding(
          padding: const EdgeInsets.only(top: WyrmTokens.space16),
          child: WyrmErrorState(
            title: 'Die Sound-Bibliothek ist nicht verfügbar',
            message: 'Die Sounds konnten nicht geladen werden. Bitte versuche es erneut.',
            action: WyrmSecondaryButton(label: 'Erneut versuchen', icon: Icons.refresh, onPressed: session.retryLoad),
          ),
        )
      else if (vault == null)
        const Padding(padding: EdgeInsets.only(top: WyrmTokens.space24), child: LinearProgressIndicator()),
      if (session.restoreFailed) _restoreFailed(),
      if (vault != null && _result != null) ..._results(context, vault, _result!),
      if (vault != null && _result == null) ..._start(context, vault),
    ];
  }

  Widget _restoreFailed() => Padding(
    padding: const EdgeInsets.only(top: WyrmTokens.space16),
    child: WyrmCard(
      key: const Key('restore-failed'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dein gespeicherter Sound ist nicht mehr verfügbar', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: WyrmTokens.space8),
          const Text('Er passt nicht mehr zur aktuellen Sound-Bibliothek. Suche einfach einen neuen Sound.'),
          const SizedBox(height: WyrmTokens.space8),
          WyrmSecondaryButton(label: 'Verwerfen', icon: Icons.delete_outline, onPressed: widget.session.discardCurrent),
        ],
      ),
    ),
  );

  // ---------------------------------------------------------------------------------- start view

  List<Widget> _start(BuildContext context, ToneVault vault) {
    final session = widget.session;
    final current = session.current;
    final definition = current == null ? null : session.definitionOf(current);
    final recent = [
      for (final s in session.recent)
        if (s.entryId != current?.entryId || s.variant != current?.variant) s,
    ].take(4).toList();
    return [
      if (current != null && definition != null)
        Padding(
          padding: const EdgeInsets.only(top: WyrmTokens.space16),
          child: WyrmCard(
            key: const Key('current-sound-card'),
            accent: true,
            onTap: _openCurrent,
            child: Row(
              children: [
                const Icon(Icons.graphic_eq, color: WyrmTokens.ember),
                const SizedBox(width: WyrmTokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dein Sound', style: Theme.of(context).textTheme.bodySmall),
                      Text(entryDisplayTitle(definition.entry), style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        [
                          if (current.variant != null) variantLabel(current.variant!),
                          current.tuning.label,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      if (recent.isNotEmpty) ...[
        const WyrmSectionHeader('Zuletzt verwendet'),
        for (final s in recent) _recentCard(context, vault, s),
      ],
      const WyrmSectionHeader('Genres', subtitle: 'Tippe ein Genre an, um passende Sounds zu sehen'),
      Wrap(
        spacing: WyrmTokens.space8,
        runSpacing: WyrmTokens.space4,
        children: [
          for (final id in _genreIds)
            if (vault.taxonomy.genres[id] case final g?) WyrmChip(g.name, onTap: () => _ask(g.name)),
        ],
      ),
      const WyrmSectionHeader('Entdecken', subtitle: 'Wyrm Originals und Songs, auf Gitarre neu gedacht'),
      for (final id in _exploreIds)
        if (vault.entry(id) case final e?) _entryCard(context, vault, e),
    ];
  }

  Widget _recentCard(BuildContext context, ToneVault vault, SoundSelection s) {
    final e = vault.entry(s.entryId);
    if (e == null) return const SizedBox.shrink();
    return WyrmCard(
      key: Key('recent-${s.entryId}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SoundDetailPage(
            controller: widget.controller,
            session: widget.session,
            entryId: s.entryId,
            seed: SoundSeed(variant: s.variant, modifiers: s.modifiers, effects: s.effects, tuning: s.tuning),
            openProfile: widget.openProfile,
          ),
        ),
      ),
      child: _cardBody(context, vault, e, variant: s.variant),
    );
  }

  // ---------------------------------------------------------------------------------- results

  List<Widget> _results(BuildContext context, ToneVault vault, ToneNluResult r) {
    final candidates = r.resolution.candidates;
    final shown = [for (final c in candidates) if (_filter.types?.contains(c.entry.type) ?? true) c].take(12).toList();
    // A short prefix ("mas", "child", "metalco") is not a complete phrase the full understanding
    // pipeline resolves; the same named entries still deserve a suggestion the instant they match.
    final prefix = candidates.isEmpty ? _prefixSuggestions(vault, _search.text) : const <ToneVaultEntry>[];
    return [
      if (r.understood) _understood(context, vault, r),
      if (candidates.isEmpty && prefix.isNotEmpty)
        ..._prefixSuggestionCards(context, vault, prefix)
      else if (candidates.isEmpty)
        _noMatch(context, vault, r)
      else ...[
        if (r.needsChoice)
          Padding(
            padding: const EdgeInsets.only(top: WyrmTokens.space12),
            child: Text('Mehrere Sounds passen. Such dir einen aus:', style: Theme.of(context).textTheme.bodyMedium),
          ),
        if (candidates.length > 1) _filterChips(candidates),
        const SizedBox(height: WyrmTokens.space4),
        if (shown.isEmpty)
          const Padding(padding: EdgeInsets.only(top: WyrmTokens.space12), child: Text('In dieser Auswahl gibt es keine Treffer.')),
        for (var i = 0; i < shown.length; i++)
          WyrmCard(
            key: Key('sound-result-${shown[i].entry.id}'),
            accent: i == 0 && r.resolution.kind == ResolutionKind.exact,
            onTap: () => _openDetail(shown[i].entry, from: r),
            child: _cardBody(context, vault, shown[i].entry, variant: shown[i].variantSupported ? shown[i].variant : null),
          ),
      ],
    ];
  }

  /// "Keinen direkten Treffer gefunden" never dead-ends: whenever the free text named a real genre
  /// or style, offer to build the sound from that description right away.
  Widget _noMatch(BuildContext context, ToneVault vault, ToneNluResult r) {
    final described = _describedGenreEntry(vault, r);
    return Padding(
      padding: const EdgeInsets.only(top: WyrmTokens.space16),
      child: WyrmEmptyState(
        title: 'Keinen direkten Treffer gefunden',
        message: described != null
            ? 'Aus deiner Beschreibung lässt sich trotzdem ein Sound bauen.'
            : r.understood
            ? 'Ich habe deinen Wunsch verstanden, aber es fehlt ein Ausgangssound. Nenne zusätzlich einen Künstler, Song oder ein Genre.'
            : 'Versuche einen Künstler, Song oder ein Genre, zum Beispiel „Blues Crunch“ oder „Master of Puppets“.',
        icon: Icons.search_off,
        action: described == null
            ? null
            : FilledButton.icon(
                key: const Key('create-from-description'),
                onPressed: () => _openDetail(described, from: r),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Sound aus deiner Beschreibung erstellen'),
              ),
      ),
    );
  }

  Widget _understood(BuildContext context, ToneVault vault, ToneNluResult r) {
    final q = r.query;
    final labels = <String>[
      for (final m in r.matches)
        if (const {'artist', 'song', 'album', 'title'}.contains(m.kind)) m.value,
      if (q.subgenre != null)
        vault.taxonomy.genres[q.subgenre]?.name ?? q.subgenre!
      else if (q.genre != null)
        vault.taxonomy.genres[q.genre]?.name ?? q.genre!,
      if (q.era != null) vault.taxonomy.eras[q.era]?.name ?? q.era!,
      if (q.role != null) variantLabel(q.role!),
      if (r.tuning != null) r.tuning!.label,
      for (final i in q.modifierIntents) modifierLabel(i),
      for (final e in q.effects) effectLabel(e),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: WyrmTokens.space16),
      child: Semantics(
        label: 'Verstanden: ${labels.join(', ')}',
        child: Wrap(
          key: const Key('understood-chips'),
          spacing: WyrmTokens.space8,
          runSpacing: WyrmTokens.space4,
          children: [for (final l in labels) WyrmChip(l)],
        ),
      ),
    );
  }

  Widget _filterChips(List<ToneCandidate> candidates) {
    int count(_Filter f) => f.types == null ? candidates.length : candidates.where((c) => f.types!.contains(c.entry.type)).length;
    return Padding(
      padding: const EdgeInsets.only(top: WyrmTokens.space8),
      child: Wrap(
        spacing: WyrmTokens.space8,
        runSpacing: WyrmTokens.space4,
        children: [
          for (final f in _Filter.values)
            if (f == _Filter.all || count(f) > 0)
              WyrmChip(
                '${f.label} (${count(f)})',
                selected: _filter == f,
                onTap: () => setState(() => _filter = f),
              ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------------- cards

  Widget _entryCard(BuildContext context, ToneVault vault, ToneVaultEntry e) => WyrmCard(
    key: Key('sound-result-${e.id}'),
    onTap: () => _openDetail(e),
    child: _cardBody(context, vault, e),
  );

  Widget _cardBody(BuildContext context, ToneVault vault, ToneVaultEntry e, {ToneVariantKind? variant}) {
    final theme = Theme.of(context);
    return Semantics(
      label: '${entryTypeWord(e.type)}: ${entryDisplayTitle(e)}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: entryTypeWord(e.type),
            child: Icon(entryTypeIcon(e.type), size: WyrmTokens.iconSmall, color: WyrmTokens.muted),
          ),
          const SizedBox(width: WyrmTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entryDisplayTitle(e), style: theme.textTheme.titleMedium),
                Text('${entrySubtitle(e, vault.taxonomy)} · ${sourceLabel(e.sourceClass)}', style: theme.textTheme.bodySmall),
                _cardTags(variant, e),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardTags(ToneVariantKind? variant, ToneVaultEntry e) {
    if (variant == null && e.tags.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: WyrmTokens.space8),
      child: Wrap(
        spacing: WyrmTokens.space8,
        runSpacing: WyrmTokens.space4,
        children: [
          if (variant != null) WyrmChip(variantLabel(variant), icon: Icons.music_note),
          for (final t in e.tags.take(2)) WyrmChip(tagLabel(t)),
        ],
      ),
    );
  }
}
