import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../models/guitar_profile.dart';
import '../sounds/sound_labels.dart';
import '../sounds/sound_selection.dart';
import '../sounds/sound_session.dart';
import '../tonevault/tone_vault_model.dart';
import '../tonevault/tone_vault_query.dart';
import '../ui/wyrm_components.dart';
import '../ui/wyrm_design.dart';
import 'your_sound_page.dart';

/// What the search understood, handed to the detail page as a starting point.
class SoundSeed {
  const SoundSeed({this.variant, this.modifiers = const [], this.effects = const [], this.tuning});
  final ToneVariantKind? variant;
  final List<ToneModifierIntent> modifiers;
  final List<ToneEffectIntent> effects;
  final GuitarTuning? tuning;
}

/// One sound: what it is, how it is meant to sound, made personal (guitar, tuning, variant) and
/// quick adjustments. "Sound verwenden" then creates the local sound.
class SoundDetailPage extends StatefulWidget {
  const SoundDetailPage({
    required this.controller,
    required this.session,
    required this.entryId,
    this.seed = const SoundSeed(),
    this.openProfile,
    super.key,
  });
  final RecommendationController controller;
  final SoundSession session;
  final String entryId;
  final SoundSeed seed;
  final VoidCallback? openProfile;

  @override
  State<SoundDetailPage> createState() => _SoundDetailPageState();
}

class _SoundDetailPageState extends State<SoundDetailPage> {
  ToneVariantKind? _variant;
  GuitarTuning? _tuning;
  bool _tuningTouched = false;
  final Map<String, int> _levels = {}; // axis id -> -3..3 (negative = "less" side)
  final List<ToneModifierIntent> _extra = [];
  late List<ToneEffectIntent> _effects;

  ToneVaultEntry? get _entry => widget.session.vault?.entry(widget.entryId);

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    _effects = [...seed.effects];
    for (final m in seed.modifiers) {
      final axis = adjustmentAxes.where((a) => a.more == m.modifier || a.less == m.modifier).firstOrNull;
      if (axis == null) {
        _extra.add(m);
      } else {
        final step = switch (m.intensity) {
          ToneIntensity.slight => 1,
          ToneIntensity.normal => 2,
          ToneIntensity.strong => 3,
        };
        _levels[axis.id] = axis.more == m.modifier ? step : -step;
      }
    }
    widget.session.ensureLoaded();
  }

  SoundSelection _selection(GuitarTuning tuning, ToneVariantKind? variant) => SoundSelection(
    entryId: widget.entryId,
    tuning: tuning,
    variant: variant,
    modifiers: [
      for (final a in adjustmentAxes)
        if ((_levels[a.id] ?? 0) != 0)
          ToneModifierIntent(
            _levels[a.id]! > 0 ? a.more : a.less,
            switch (_levels[a.id]!.abs()) {
              1 => ToneIntensity.slight,
              2 => ToneIntensity.normal,
              _ => ToneIntensity.strong,
            },
          ),
      ..._extra,
    ],
    effects: _effects,
  );

  void _step(AdjustmentAxis axis, int delta) =>
      setState(() => _levels[axis.id] = ((_levels[axis.id] ?? 0) + delta).clamp(-3, 3));

  String _levelText(AdjustmentAxis axis) {
    final v = _levels[axis.id] ?? 0;
    if (v == 0) return 'unverändert';
    final word = v > 0 ? axis.moreWord : axis.lessWord;
    return switch (v.abs()) {
      1 => '$word (etwas)',
      2 => word,
      _ => '$word (deutlich)',
    };
  }

  Future<void> _use(GuitarTuning tuning, ToneVariantKind? variant) async {
    final session = widget.session;
    final ok = await session.use(_selection(tuning, variant));
    if (!mounted) return;
    if (ok) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => YourSoundPage(controller: widget.controller, session: session, openProfile: widget.openProfile),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.session, widget.controller]),
      builder: (context, _) {
        final entry = _entry;
        if (entry == null) {
          return WyrmScaffold(
            title: 'Sound',
            background: true,
            backgroundIntensity: WyrmBackgroundIntensity.medium,
            body: Padding(
              padding: WyrmTokens.pagePadding,
              child: widget.session.vaultError != null
                  ? WyrmErrorState(
                      title: 'Sound nicht verfügbar',
                      message: 'Die Sound-Bibliothek konnte nicht geladen werden.',
                      action: WyrmSecondaryButton(label: 'Erneut versuchen', onPressed: widget.session.retryLoad),
                    )
                  : widget.session.ready
                  ? const WyrmEmptyState(title: 'Sound nicht gefunden', message: 'Dieser Sound ist nicht mehr in der Bibliothek.', icon: Icons.search_off)
                  : const Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final variant = _variant ?? (entry.roles.contains(widget.seed.variant) ? widget.seed.variant : (entry.roles.isEmpty ? null : entry.roles.first));
        final c = widget.controller;
        final probe = _selection(GuitarTuning.dropC, variant);
        final definition = widget.session.definitionOf(probe)!;
        final tuning = _tuning ?? widget.seed.tuning ?? widget.session.defaultTuning(definition);
        final theme = Theme.of(context);
        final vault = widget.session.vault!;
        return WyrmScaffold(
          title: 'Sound',
          background: true,
          backgroundIntensity: WyrmBackgroundIntensity.medium,
          body: ListView(
            key: const PageStorageKey('sound-detail'),
            padding: WyrmTokens.pagePadding,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: WyrmTokens.contentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WyrmCard(
                        accent: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entryDisplayTitle(entry), key: const Key('sound-title'), style: theme.textTheme.headlineSmall),
                            Text(entrySubtitle(entry, vault.taxonomy), style: theme.textTheme.bodyMedium),
                            const SizedBox(height: WyrmTokens.space8),
                            Wrap(
                              spacing: WyrmTokens.space8,
                              runSpacing: WyrmTokens.space4,
                              children: [
                                WyrmChip(sourceLabel(entry.sourceClass), icon: Icons.verified_outlined),
                                for (final t in entry.tags.take(3)) WyrmChip(tagLabel(t)),
                              ],
                            ),
                            const SizedBox(height: WyrmTokens.space8),
                            Text(definition.disclaimers.first, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      const WyrmSectionHeader('Soundcharakter'),
                      WyrmCard(
                        child: Column(
                          key: const Key('sound-metrics'),
                          children: [for (final m in soundMetricsOf(definition.dimensions, definition.resolved)) WyrmToneMetric(label: m.label, value: m.value)],
                        ),
                      ),
                      const WyrmSectionHeader('Für dich angepasst', subtitle: 'Gitarre, Stimmung und Variante'),
                      WyrmCard(child: _personal(context, entry, variant, tuning)),
                      const WyrmSectionHeader('Anpassen', subtitle: 'Kleine Wünsche an den Sound'),
                      WyrmCard(child: _adjustments(context, definition)),
                      if (widget.session.notice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: WyrmTokens.space12),
                          child: Row(
                            children: [
                              Expanded(child: Text(widget.session.notice!, key: const Key('sound-notice'))),
                              if (c.selectedProfile == null && widget.openProfile != null)
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).popUntil((r) => r.isFirst);
                                    widget.openProfile!();
                                  },
                                  child: const Text('Gitarre anlegen'),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: WyrmTokens.space16),
                      FilledButton.icon(
                        key: const Key('use-sound'),
                        onPressed: widget.session.busy ? null : () => _use(tuning, variant),
                        icon: const Icon(Icons.check),
                        label: Text(widget.session.busy ? 'Sound wird vorbereitet …' : 'Sound verwenden'),
                      ),
                      const SizedBox(height: WyrmTokens.space24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _personal(BuildContext context, ToneVaultEntry entry, ToneVariantKind? variant, GuitarTuning tuning) {
    final c = widget.controller;
    final tunings = [for (final t in GuitarTuning.values) if (t != GuitarTuning.custom) t];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.profiles.isEmpty)
          Row(
            children: [
              const Expanded(child: Text('Noch keine Gitarre angelegt. Damit der Sound zu deiner Gitarre passt, lege zuerst ein Profil an.')),
              if (widget.openProfile != null)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    widget.openProfile!();
                  },
                  child: const Text('Gitarre anlegen'),
                ),
            ],
          )
        else
          DropdownButtonFormField<String>(
            key: ValueKey('guitar-${c.selectedProfileId}'),
            isExpanded: true,
            initialValue: c.profiles.any((p) => p.id == c.selectedProfileId) ? c.selectedProfileId : null,
            decoration: const InputDecoration(labelText: 'Gitarre'),
            items: [for (final p in c.profiles) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))],
            onChanged: (id) {
              if (id == null) return;
              c.selectProfile(id);
              if (!_tuningTouched) setState(() => _tuning = c.selectedProfile?.tuning);
            },
          ),
        const SizedBox(height: WyrmTokens.space12),
        DropdownButtonFormField<GuitarTuning>(
          key: ValueKey('tuning-${tuning.name}'),
          isExpanded: true,
          initialValue: tuning,
          decoration: const InputDecoration(labelText: 'Stimmung'),
          items: [for (final t in tunings) DropdownMenuItem(value: t, child: Text(t.label))],
          onChanged: (t) => setState(() {
            _tuning = t;
            _tuningTouched = true;
          }),
        ),
        if (entry.roles.length > 1) ...[
          const SizedBox(height: WyrmTokens.space12),
          Text('Variante', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: WyrmTokens.space4),
          Wrap(
            spacing: WyrmTokens.space8,
            runSpacing: WyrmTokens.space4,
            children: [for (final r in entry.roles) WyrmChip(variantLabel(r), selected: variant == r, onTap: () => setState(() => _variant = r))],
          ),
        ],
      ],
    );
  }

  Widget _adjustments(BuildContext context, definition) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in adjustmentAxes)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WyrmTokens.space4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.label, style: theme.textTheme.bodyMedium),
                      Text(_levelText(a), key: Key('adjust-${a.id}-value'), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('adjust-${a.id}-less'),
                  tooltip: a.lessWord,
                  onPressed: (_levels[a.id] ?? 0) <= -3 ? null : () => _step(a, -1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  key: Key('adjust-${a.id}-more'),
                  tooltip: a.moreWord,
                  onPressed: (_levels[a.id] ?? 0) >= 3 ? null : () => _step(a, 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ),
        if (_extra.isNotEmpty || _effects.isNotEmpty) ...[
          const Divider(),
          Wrap(
            spacing: WyrmTokens.space8,
            runSpacing: WyrmTokens.space4,
            children: [
              for (var i = 0; i < _extra.length; i++)
                InputChip(
                  key: Key('wish-$i'),
                  label: Text(modifierLabel(_extra[i])),
                  onDeleted: () => setState(() => _extra.removeAt(i)),
                  deleteButtonTooltipMessage: 'Wunsch entfernen',
                ),
              for (var i = 0; i < _effects.length; i++)
                InputChip(
                  key: Key('effect-$i'),
                  label: Text(effectLabel(_effects[i])),
                  onDeleted: () => setState(() => _effects.removeAt(i)),
                  deleteButtonTooltipMessage: 'Wunsch entfernen',
                ),
            ],
          ),
        ],
        if (definition.skippedModifierDimensions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: WyrmTokens.space8),
            child: Text(
              'Hinweis: Manche Wünsche wirken bei diesem Sound nicht, weil er dafür keinen Wert festlegt.',
              key: const Key('wish-ignored-note'),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
