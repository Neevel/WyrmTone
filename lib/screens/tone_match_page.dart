import 'package:flutter/material.dart';

import '../controllers/usb_controller.dart';
import '../nam/local_nam_capture.dart';
import '../tonematch/acoustic_target.dart';
import '../tonematch/tone_match_controller.dart';
import '../tonematch/tone_match_models.dart';
import '../ui/wyrm_components.dart';
import '../ui/wyrm_design.dart';
import 'nam_detail_page.dart';

/// Tone Match: say which song/artist sound you want, get the best matching sounds from your own NAM
/// library. Plain language only; the technical evidence sits behind "Details". Nothing is ever
/// transferred automatically: "NAM ansehen" opens the existing NAM detail page, where every
/// transfer step is confirmed by the user.
class ToneMatchPage extends StatefulWidget {
  const ToneMatchPage({
    required this.controller,
    required this.usbController,
    this.openLibrary,
    super.key,
  });
  final ToneMatchController controller;
  final UsbController usbController;
  final VoidCallback? openLibrary;

  @override
  State<ToneMatchPage> createState() => _ToneMatchPageState();
}

class _ToneMatchPageState extends State<ToneMatchPage> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  static const examples = [
    'Gary Moore - The Loner',
    'Pantera - Heresy',
    'Metallica - Master of Puppets',
    'Gojira - Silvera',
  ];

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(String text) {
    _focus.unfocus();
    widget.controller.start(text);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return WyrmScaffold(
        title: 'Tone Match',
        background: true,
        body: ListView(
          key: const PageStorageKey('tone-match-page'),
          padding: WyrmTokens.pagePadding,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Text(
              'Welchen Sound suchst du?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (c.result == null && !c.busy) ...[
              const SizedBox(height: WyrmTokens.space8),
              const Text(
                'Nenne Künstler und Song. WyrmTone sucht in deiner NAM-Bibliothek die Sounds, die am besten dazu passen.',
                style: TextStyle(color: WyrmTokens.muted),
              ),
            ],
            const SizedBox(height: WyrmTokens.gap),
            WyrmSearchField(
              fieldKey: const Key('tone-match-input'),
              controller: _text,
              focusNode: _focus,
              hint: 'z. B. Gary Moore - The Loner',
              onSubmitted: c.busy ? null : _go,
            ),
            const SizedBox(height: WyrmTokens.space12),
            WyrmPrimaryButton(
              key: const Key('tone-match-find'),
              label: 'Sound finden',
              icon: Icons.graphic_eq,
              onPressed: c.busy ? null : () => _go(_text.text),
            ),
            const SizedBox(height: WyrmTokens.gap),
            if (c.busy)
              _Progress(controller: c)
            else if (c.result != null)
              _ResultView(controller: c, result: c.result!, page: widget)
            else ...[
              if (c.wasCancelled)
                const Padding(
                  padding: EdgeInsets.only(bottom: WyrmTokens.space12),
                  child: Text(
                    'Die Suche wurde abgebrochen.',
                    key: Key('tone-match-cancelled'),
                    style: TextStyle(color: WyrmTokens.muted),
                  ),
                ),
              _Examples(
                onPick: (t) {
                  _text.text = t;
                  _go(t);
                },
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _Examples extends StatelessWidget {
  const _Examples({required this.onPick});
  final ValueChanged<String> onPick;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Beispiele', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: WyrmTokens.space8),
      Wrap(
        spacing: WyrmTokens.space8,
        runSpacing: WyrmTokens.space8,
        children: [
          for (final e in _ToneMatchPageState.examples)
            ActionChip(label: Text(e), onPressed: () => onPick(e)),
        ],
      ),
    ],
  );
}

/// Real progress only: which sound out of how many is being checked.
class _Progress extends StatelessWidget {
  const _Progress({required this.controller});
  final ToneMatchController controller;
  @override
  Widget build(BuildContext context) {
    final p = controller.progress;
    final label = switch (controller.phase) {
      ToneMatchPhase.understanding => 'Dein Wunschsound wird verstanden',
      ToneMatchPhase.searching => 'Passende Sounds werden vorausgewählt',
      ToneMatchPhase.analyzing => 'Passende Sounds werden geprüft',
      _ => 'Ergebnis wird vorbereitet',
    };
    final showCount =
        controller.phase == ToneMatchPhase.analyzing &&
        p != null &&
        p.total > 0;
    final current = showCount ? (p.done + 1).clamp(1, p.total) : 0;
    return WyrmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            controller.cancelling ? 'Suche wird abgebrochen …' : label,
            key: const Key('tone-match-progress-label'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (showCount && !controller.cancelling) ...[
            const SizedBox(height: WyrmTokens.space4),
            Text(
              'Sound $current von ${p.total}',
              key: const Key('tone-match-progress-count'),
            ),
            if (p.currentName != null)
              Text(
                p.currentName!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: WyrmTokens.muted),
              ),
          ],
          const SizedBox(height: WyrmTokens.space12),
          // A bar that reflects finished sounds (real progress), otherwise a plain activity bar.
          LinearProgressIndicator(value: showCount ? p.done / p.total : null),
          const SizedBox(height: WyrmTokens.space12),
          WyrmSecondaryButton(
            key: const Key('tone-match-cancel'),
            label: 'Abbrechen',
            onPressed: controller.cancelling ? null : controller.cancel,
          ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.controller,
    required this.result,
    required this.page,
  });
  final ToneMatchController controller;
  final ToneMatchResult result;
  final ToneMatchPage page;

  @override
  Widget build(BuildContext context) {
    final r = result;
    switch (r.failure) {
      case ToneMatchFailure.emptyQuery:
        return const WyrmEmptyState(
          title: 'Noch keine Eingabe',
          message: 'Gib einen Künstler und Song ein, z. B. „Pantera - Heresy“.',
          icon: Icons.edit_outlined,
        );
      case ToneMatchFailure.noKnowledge:
        return WyrmEmptyState(
          title: 'Dazu habe ich keine Klangbeschreibung',
          message:
              'Für „${r.request.text}“ ist nichts hinterlegt. Versuche einen bekannten Künstler oder einen Stil wie „Metal Rhythmus“.',
          icon: Icons.search_off,
        );
      case ToneMatchFailure.noNams:
        return _withHeader(
          context,
          r,
          WyrmEmptyState(
            key: const Key('tone-match-no-nams'),
            title: 'Du hast noch keine NAM-Modelle in deiner Bibliothek.',
            message: 'Lade ein Modell aus TONE3000 oder importiere eine Datei, dann kann Tone Match daraus die passendsten Sounds heraussuchen.',
            action: page.openLibrary == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: WyrmTokens.space12),
                    child: WyrmSecondaryButton(
                      key: const Key('tone-match-open-library'),
                      label: 'Zur Bibliothek',
                      onPressed: page.openLibrary,
                    ),
                  ),
          ),
        );
      case ToneMatchFailure.noSuitableNams:
        return _withHeader(
          context,
          r,
          const WyrmEmptyState(
            title: 'Kein passendes Modell nutzbar',
            message: 'Deine NAM-Modelle sind für das Zielgerät nicht als nutzbar geprüft. Lade ein kompatibles Modell (Architektur A1).',
            icon: Icons.block,
          ),
        );
      case ToneMatchFailure.analysisFailed:
        return _withHeader(
          context,
          r,
          WyrmEmptyState(
            key: const Key('tone-match-analysis-failed'),
            title: 'Die Sounds konnten nicht geprüft werden',
            message: 'Keines der vorausgewählten Modelle ließ sich prüfen. Versuche es erneut oder wähle andere Modelle in der Bibliothek.',
            icon: Icons.error_outline,
            action: Padding(
              padding: const EdgeInsets.only(top: WyrmTokens.space12),
              child: WyrmSecondaryButton(
                label: 'Erneut versuchen',
                onPressed: () => controller.start(r.request.text),
              ),
            ),
          ),
        );
      case null:
        return _success(context, r);
    }
  }

  Widget _header(BuildContext context, ToneIntent i) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        i.artist ?? i.matchedTitle ?? i.query,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (i.song != null)
        Text(i.song!, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: WyrmTokens.space4),
      Text(
        [i.role.label, ...i.descriptors].join(' · '),
        key: const Key('tone-match-characteristics'),
        style: const TextStyle(color: WyrmTokens.ember),
      ),
    ],
  );

  Widget _withHeader(BuildContext context, ToneMatchResult r, Widget below) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.intent != null) _header(context, r.intent!),
          const SizedBox(height: WyrmTokens.gap),
          below,
        ],
      );

  Widget _success(BuildContext context, ToneMatchResult r) {
    final device = r.plan?.device;
    final noNamDevice = device != null && !device.namTransfer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, r.intent!),
        const SizedBox(height: WyrmTokens.gap),
        if (r.analysisUnavailable)
          const Padding(
            padding: EdgeInsets.only(bottom: WyrmTokens.space12),
            child: Text(
              'Die Klanganalyse ist gerade nicht verfügbar. Die Reihenfolge beruht nur auf den Beschreibungen deiner Modelle.',
              key: Key('tone-match-no-analysis'),
              style: TextStyle(color: WyrmTokens.warning),
            ),
          ),
        Text(
          r.measured
              ? 'Unsere passendsten Sounds'
              : 'Vorauswahl nach Beschreibung',
          key: const Key('tone-match-results-title'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: WyrmTokens.space8),
        // The "does it fit the Matribox" note is the same for every imported model: say it once.
        for (final h in r.hits)
          _HitCard(
            hit: h,
            page: page,
            showOpen: !noNamDevice,
            showCompatNote:
                h.candidate.capture.compatibility == NamCompatibility.unknown &&
                r.hits
                        .firstWhere(
                          (x) =>
                              x.candidate.capture.compatibility ==
                              NamCompatibility.unknown,
                        )
                        .rank ==
                    h.rank,
          ),
        if (noNamDevice)
          Padding(
            padding: const EdgeInsets.only(bottom: WyrmTokens.space8),
            child: Text(
              '${device.name} kann keine NAM-Modelle verwenden. Wähle ein anderes Gerät, wenn du einen Sound übertragen möchtest.',
              key: const Key('tone-match-device-note'),
              style: const TextStyle(color: WyrmTokens.muted),
            ),
          ),
        if (r.skippedCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: WyrmTokens.space8),
            child: Text(
              '${r.skippedCount} Modell(e) konnten nicht geprüft werden und wurden übersprungen.',
              style: const TextStyle(color: WyrmTokens.muted),
            ),
          ),
        if (r.moreAvailable > 0) ...[
          const SizedBox(height: WyrmTokens.space4),
          WyrmSecondaryButton(
            key: const Key('tone-match-more'),
            label: 'Weitere Sounds prüfen',
            icon: Icons.add,
            onPressed: controller.checkMore,
          ),
          const SizedBox(height: WyrmTokens.space4),
          Text(
            '${r.moreAvailable} weitere Sounds in deiner Bibliothek. Das dauert eine Weile.',
            style: const TextStyle(color: WyrmTokens.muted),
          ),
        ],
        const SizedBox(height: WyrmTokens.gap),
        wyrmStoredTile(
          'tone-match-details',
          ExpansionTile(
            key: const Key('tone-match-details'),
            title: const Text('Details'),
            tilePadding: EdgeInsets.zero,
            children: _details(r),
          ),
        ),
      ],
    );
  }

  static Widget _left(Widget w) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Align(alignment: Alignment.centerLeft, child: w),
  );
  static Widget _head(String t) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
    ),
  );

  List<Widget> _details(ToneMatchResult r) {
    final i = r.intent!;
    String aspect(String k) => switch (k) {
      'song' => 'Song',
      'amp' => 'Verstärker-Richtung',
      'gain' => 'Gain und Klangformung',
      'role' => 'Rolle',
      'effects' => 'Effekte',
      'cabinet' => 'Box',
      'guitar' => 'Gitarre',
      _ => k,
    };
    String brightness(BrightnessTarget t) => switch (t) {
      BrightnessTarget.bright => 'eher hell',
      BrightnessTarget.dark => 'eher dunkel',
      BrightnessTarget.neutral => 'ausgewogene Höhen',
    };
    String mids(MidTarget t) => switch (t) {
      MidTarget.forward => 'kräftige Mitten',
      MidTarget.scooped => 'zurückgenommene Mitten',
      MidTarget.neutral => 'ausgewogene Mitten',
    };
    String dynamics(DynamicsTarget t) => switch (t) {
      DynamicsTarget.compressed => 'eher komprimierte Dynamik',
      DynamicsTarget.dynamic => 'eher lebendige Dynamik',
      DynamicsTarget.neutral => 'ausgewogene Dynamik',
    };
    final t = r.target;
    return [
      _head('Woher die Beschreibung stammt'),
      for (final e in i.evidence.entries)
        _left(
          Text('${aspect(e.key)}: ${e.value.kind.label} – ${e.value.source}'),
        ),
      _left(
        const Text(
          'Das ist eine Stilbeschreibung, keine Aussage über das Originalequipment.',
          style: TextStyle(color: WyrmTokens.muted),
        ),
      ),
      if (t != null && t.hasAcousticTargets) ...[
        _head('Wonach gesucht wurde'),
        if (t.brightness != null)
          _left(
            Text(
              'Klang: ${brightness(t.brightness!.value)} – ${t.brightness!.evidence.kind.label}',
            ),
          ),
        if (t.mids != null)
          _left(
            Text(
              'Mitten: ${mids(t.mids!.value)} – ${t.mids!.evidence.kind.label}',
            ),
          ),
        if (t.dynamics != null)
          _left(
            Text(
              'Dynamik: ${dynamics(t.dynamics!.value)} – ${t.dynamics!.evidence.kind.label}',
            ),
          ),
        _left(
          const Text(
            'Die Reihenfolge vergleicht die geprüften Sounds untereinander. Es ist keine absolute Bewertung und keine Prozentzahl.',
            style: TextStyle(color: WyrmTokens.muted),
          ),
        ),
      ],
      if (t != null && t.unmapped.isNotEmpty) ...[
        _head('Nicht berücksichtigt'),
        for (final u in t.unmapped) _left(Text('${u.aspect}: ${u.reason}')),
      ],
      _head('So wurde geprüft'),
      _left(
        const Text(
          'Alle Sounds wurden mit derselben festen Testaufnahme geprüft, nicht mit deiner Gitarre.',
        ),
      ),
      if (r.request.guitarName != null)
        _left(
          Text(
            'Deine Gitarre (${r.request.guitarName}) fließt nur in die Einordnung ein, nicht in die Messung.',
          ),
        ),
      if (r.plan != null && r.plan!.plan.needsIr == null)
        _left(
          const Text(
            'Ob beim besten Sound noch eine Box (IR) nötig ist, ist unbekannt.',
          ),
        ),
    ];
  }
}

class _HitCard extends StatelessWidget {
  const _HitCard({
    required this.hit,
    required this.page,
    required this.showOpen,
    required this.showCompatNote,
  });
  final ToneMatchHit hit;
  final ToneMatchPage page;
  final bool showOpen, showCompatNote;

  @override
  Widget build(BuildContext context) {
    final cap = hit.candidate.capture;
    void open() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NamDetailPage(capture: cap, usbController: page.usbController),
      ),
    );
    return WyrmCard(
      key: Key('tone-match-hit-${hit.rank}'),
      accent: hit.rank == 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: WyrmTokens.raised,
                child: Text(
                  '${hit.rank}',
                  style: const TextStyle(color: WyrmTokens.ember),
                ),
              ),
              const SizedBox(width: WyrmTokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cap.toneName,
                      key: Key('tone-match-hit-name-${hit.rank}'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'von ${cap.creatorName}',
                      style: const TextStyle(color: WyrmTokens.muted),
                    ),
                    if (showCompatNote)
                      Text(
                        'Ob importierte Modelle zur Matribox passen, prüft die Detailansicht.',
                        key: Key('tone-match-compat-${hit.rank}'),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: WyrmTokens.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (hit.reasons.isNotEmpty)
            wyrmStoredTile(
              'tone-match-why-${hit.rank}',
              ExpansionTile(
                key: Key('tone-match-why-${hit.rank}'),
                title: const Text('Warum dieser Sound?'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: hit.rank == 1,
                children: [
                  for (final r in hit.reasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('• $r'),
                      ),
                    ),
                ],
              ),
            ),
          if (showOpen) ...[
            const SizedBox(height: WyrmTokens.space8),
            // Only the best hit gets the filled button; the others stay quieter so the list scans well.
            if (hit.rank == 1)
              WyrmPrimaryButton(
                key: Key('tone-match-open-nam-${hit.rank}'),
                label: 'NAM ansehen',
                icon: Icons.arrow_forward,
                onPressed: open,
              )
            else
              WyrmSecondaryButton(
                key: Key('tone-match-open-nam-${hit.rank}'),
                label: 'NAM ansehen',
                icon: Icons.arrow_forward,
                onPressed: open,
              ),
          ],
        ],
      ),
    );
  }
}
