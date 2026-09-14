import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/tone3000_controller.dart';
import '../devices/device_profile.dart';
import '../models/guitar_profile.dart';
import '../models/recommendation.dart';
import '../models/tone_target.dart';
import '../services/offline_sound_profiles.dart';
import '../ui/wyrm_design.dart';
import 'preset_workspace_page.dart';

/// Presentation-only wizard. Existing controller owns creation and corrections.
class OfflineSoundPanel extends StatefulWidget {
  const OfflineSoundPanel({
    required this.controller,
    this.library,
    this.openProfile,
    super.key,
  });
  final RecommendationController controller;
  final Tone3000Controller? library;
  final VoidCallback? openProfile;
  @override
  State<OfflineSoundPanel> createState() => _OfflineSoundPanelState();
}

class _OfflineSoundPanelState extends State<OfflineSoundPanel> {
  final _query = TextEditingController();
  String? _profileId, _artist, _selectedNamId, _lastGuitar;
  GuitarTuning? _tuning;
  SoundRole _role = SoundRole.rhythm;
  String _resolution = '';
  bool _initialized = false;
  int _step = 0;
  final _progressKey = GlobalKey();
  RecommendationFeedback? _feedback;
  static const steps = [
    'Song & Stil',
    'Gitarre & Stimmung',
    'Rolle',
    'Zielgerät',
    'Amp / NAM / IR',
    'Preset-Vorschau',
    'Klangkorrekturen',
  ];
  @override
  void initState() {
    super.initState();
    loadDevicePresetCatalog();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadOfflineProfiles();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _clear() {
    widget.controller.clearOfflineDraft();
    _selectedNamId = null;
  }

  void _goToStep(int step) {
    setState(() => _step = step);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _progressKey.currentContext;
      if (mounted && context != null) {
        Scrollable.ensureVisible(context, alignment: 0);
      }
    });
  }

  void _resolve() {
    final match = OfflineSoundProfiles.resolve(
      _query.text,
      widget.controller.offlineProfiles,
    );
    setState(() {
      _clear();
      if (match.tuning != null) _tuning = match.tuning;
      if (match.role != null) _role = match.role!;
      if (match.matches.length == 1) {
        _profileId = match.matches.single.id;
        _artist = match.matches.single.artist;
        _resolution =
            'Vorhandenes Songprofil erkannt · kuratierte Klangannäherung.';
      } else {
        _profileId = null;
        _artist = null;
        _resolution = match.matches.isEmpty
            ? 'Kein exaktes Songprofil gefunden. Genre-Fallback bewusst auswählen.'
            : 'Mehrere Profile passen. Bitte geführt auswählen.';
      }
    });
  }

  Future<void> _create() async {
    final c = widget.controller;
    final sound = c.offlineProfiles
        .where((p) => p.id == _profileId)
        .firstOrNull;
    if (sound == null) return;
    await c.createOfflineSound(
      sound: sound,
      tuning: _tuning ?? c.selectedProfile?.tuning ?? GuitarTuning.dropC,
      role: _role,
      nams: widget.library?.namCaptures ?? const [],
      irs: widget.library?.localRecords ?? const [],
      selectedNamId: _selectedNamId,
    );
    if (mounted && c.offlineDraft != null) {
      _goToStep(4);
    }
  }

  Widget _field<T>(
    String label,
    T? value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> changed,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<T>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      isDense: false,
      itemHeight: null,
      decoration: InputDecoration(labelText: label),
      items: items,
      onChanged: widget.controller.offlineBusy ? null : changed,
    ),
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller, profiles = c.offlineProfiles;
      if (!_initialized && profiles.isNotEmpty) {
        _initialized = true;
        _profileId = profiles.first.id;
        _artist = profiles.first.artist;
      }
      if (_lastGuitar != c.selectedProfileId) {
        _lastGuitar = c.selectedProfileId;
        _tuning = null;
        _selectedNamId = null;
      }
      final draft = c.offlineDraft;
      if (draft != null && _profileId != draft.profile.id) {
        _profileId = draft.profile.id;
        _artist = draft.profile.artist;
        _role = draft.role;
        _tuning = draft.tuning;
      }
      final sound = profiles.where((p) => p.id == _profileId).firstOrNull;
      final tuning = _tuning ?? c.selectedProfile?.tuning ?? GuitarTuning.dropC;
      final effectiveStep = draft == null && _step > 3 ? 3 : _step;
      final valid =
          sound != null &&
          c.selectedProfile != null &&
          sound.roles.contains(_role);
      final content = <Widget>[];
      switch (effectiveStep) {
        case 0:
          content.addAll([
            const Text(
              'Bekanntes Songprofil suchen oder einen Stil bewusst wählen. Kein freies KI-Sprachverständnis.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              key: const Key('offline-request'),
              decoration: const InputDecoration(
                labelText: 'Künstler / Song',
                hintText: 'COB Angels Don’t Kill Drop C',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {
                _clear();
                _profileId = null;
              }),
            ),
            TextButton(
              onPressed: profiles.isEmpty ? null : _resolve,
              child: const Text('Profil suchen'),
            ),
            if (_resolution.isNotEmpty) Text(_resolution),
            if (profiles.isEmpty)
              const Text('Offline-Profilkatalog wird geladen.'),
            _field<String>(
              'Künstler / Genre',
              _artist,
              profiles
                  .map((p) => p.artist)
                  .toSet()
                  .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                  .toList(),
              (v) => setState(() {
                _artist = v;
                _profileId = null;
                _clear();
              }),
            ),
            _field<String>(
              'Song / Genre-Fallback',
              _profileId,
              profiles
                  .where((p) => _artist == null || p.artist == _artist)
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        '${p.song} · ${profileKindLabel(p.profileKind)}',
                      ),
                    ),
                  )
                  .toList(),
              (v) => setState(() {
                if (v == null) return;
                _profileId = v;
                _artist = profiles.firstWhere((p) => p.id == v).artist;
                _clear();
              }),
            ),
            if (sound != null)
              WyrmStatusBadge(profileKindLabel(sound.profileKind)),
          ]);
        case 1:
          content.addAll([
            const Text(
              'Pickup-Pegel, Klangcharakter und Stimmung beeinflussen die Startwerte.',
            ),
            if (c.profiles.isEmpty)
              WyrmEmptyState(
                title: 'Deine Gitarre fehlt noch',
                message: 'Lege unter Profil zuerst eine Gitarre an.',
                action: widget.openProfile == null
                    ? null
                    : TextButton(
                        onPressed: widget.openProfile,
                        child: const Text('Zum Gitarrenprofil'),
                      ),
              ),
            if (c.profiles.isNotEmpty)
              _field<String>(
                'Gitarrenprofil',
                c.selectedProfileId,
                c.profiles
                    .map(
                      (g) => DropdownMenuItem(value: g.id, child: Text(g.name)),
                    )
                    .toList(),
                (v) {
                  if (v != null) {
                    c.selectProfile(v);
                    setState(() {
                      _tuning = null;
                    });
                  }
                },
              ),
            if (c.selectedProfile != null)
              Text(c.selectedProfile!.pickupType.label),
            _field<GuitarTuning>(
              'Zielstimmung',
              tuning,
              GuitarTuning.values
                  .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                  .toList(),
              (v) => setState(() {
                _tuning = v;
                _clear();
              }),
            ),
          ]);
        case 2:
          content.addAll([
            const Text(
              'Die Rolle bestimmt Dynamik und Raumanteil. Nur kuratierte Varianten sind verfügbar.',
            ),
            _field<SoundRole>(
              'Rolle',
              _role,
              SoundRole.values
                  .map(
                    (r) =>
                        DropdownMenuItem(value: r, child: Text(roleLabel(r))),
                  )
                  .toList(),
              (v) => setState(() {
                if (v != null) _role = v;
                _clear();
              }),
            ),
            if (sound != null && !sound.roles.contains(_role))
              const Text(
                'Für diese Rolle ist keine kuratierte Variante vorhanden.',
              ),
          ]);
        case 3:
          content.addAll([
            const Text(
              'Der Entwurf verwendet nur bekannte Modelle und Wertebereiche. Ein angeschlossenes Gerät ist nicht erforderlich.',
            ),
            _field<TargetDeviceId>(
              'Zielgerät',
              c.selectedTargetDevice,
              toneDeviceAdapters
                  .map(
                    (d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(
                        d.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              (v) {
                if (v != null) c.selectTargetDevice(v);
              },
            ),
            if (!valid)
              const Text(
                'Bitte Songprofil, Gitarre und eine unterstützte Rolle wählen.',
              ),
            FilledButton.icon(
              key: const Key('offline-create'),
              onPressed: valid && !c.offlineBusy ? _create : null,
              icon: const Icon(Icons.graphic_eq),
              label: Text(c.offlineBusy ? 'Lokal prüfen …' : 'Sound erstellen'),
            ),
            if (c.offlineMessage != null && draft == null)
              Text(c.offlineMessage!),
          ]);
        case 4:
          if (draft != null) {
            final nams = draft.candidates['NAM']!.where((n) => n.eligible);
            content.addAll([
              const Text(
                'Bewertete Klangquellen aus deinem lokalen Bestand. Keine automatischen Downloads.',
              ),
              if (nams.isNotEmpty)
                _field<String>(
                  'Klangquelle vormerken',
                  draft.selectedNamId,
                  [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Interner Amp'),
                    ),
                    ...nams.map(
                      (n) => DropdownMenuItem(
                        value: n.id,
                        child: Text(n.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  (v) async {
                    _selectedNamId = v;
                    await _create();
                  },
                ),
              ..._candidates(draft),
            ]);
          }
        case 5:
          if (draft != null) content.addAll(_preset(context, draft));
        case 6:
          if (draft != null) content.addAll(_corrections(draft));
      }
      final canContinue = switch (effectiveStep) {
        0 => sound != null,
        1 => c.selectedProfile != null,
        2 => sound != null && sound.roles.contains(_role),
        3 => false,
        _ => draft != null,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WyrmStatusBadge(
            draft == null
                ? 'Offline · Ohne KI'
                : 'Offline erstellt · Keine KI verwendet',
          ),
          const SizedBox(height: 12),
          Row(
            key: _progressKey,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Schritt ${effectiveStep + 1} von 7',
                      key: const Key('wizard-progress'),
                    ),
                    Text(
                      steps[effectiveStep],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<int>(
                key: const Key('wizard-step-menu'),
                tooltip: 'Schritt auswählen',
                icon: const Icon(Icons.format_list_numbered),
                onSelected: _goToStep,
                itemBuilder: (_) => [
                  for (var i = 0; i < steps.length; i++)
                    PopupMenuItem(
                      value: i,
                      enabled: i <= 3 || draft != null,
                      child: Text(
                        '${i + 1}. ${steps[i]}${i > 3 && draft == null ? ' · nach Entwurf' : ''}',
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (effectiveStep + 1) / steps.length),
          if (sound != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${sound.displayName}\n${c.selectedProfile?.name ?? 'Gitarre noch wählen'} · ${tuning.label} · ${roleLabel(_role)}',
                key: const Key('wizard-summary'),
                softWrap: true,
              ),
            ),
          WyrmSection(
            title: 'Deine Auswahl',
            child: WyrmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: content,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              if (effectiveStep > 0)
                OutlinedButton(
                  onPressed: () => _goToStep(effectiveStep - 1),
                  child: const Text('Zurück'),
                ),
              if (effectiveStep < 6 && effectiveStep != 3)
                FilledButton(
                  key: const Key('wizard-next'),
                  onPressed: canContinue && !c.offlineBusy
                      ? () => _goToStep(effectiveStep + 1)
                      : null,
                  child: const Text('Weiter'),
                ),
            ],
          ),
          if (draft != null)
            ExpansionTile(
              key: const PageStorageKey('draft-evidence'),
              title: const Text('Quelle, Begründungen & Verlauf'),
              children: [
                Text(
                  'Quelle: ${draft.tone.source}\nProfil v${draft.tone.version} · Vertrauen ${draft.tone.confidence}/100',
                ),
                Text([...draft.reasons, ...draft.warnings].join('\n')),
                for (var i = 0; i < draft.history.length; i++)
                  Text('${i + 1}. ${draft.history[i]}'),
              ],
            ),
        ],
      );
    },
  );
  List<Widget> _candidates(PresetDraft draft) => [
    for (final category in ['AMP', 'NAM', 'IR'])
      WyrmSection(
        title: '${category == 'AMP' ? 'Amp' : category}-Kandidaten',
        child: Column(
          children: [
            if (draft.candidates[category]!.isEmpty)
              const WyrmEmptyState(
                title: 'Keine lokalen Kandidaten',
                message:
                    'Der Entwurf bleibt mit internen Amp-Modellen möglich.',
              ),
            for (final candidate in draft.candidates[category]!)
              ExpansionTile(
                key: PageStorageKey('candidate-$category-${candidate.id}'),
                title: Text('${candidate.name} · ${candidate.score}/100'),
                subtitle: Text(
                  candidate.eligible
                      ? 'Verfügbar · lokal'
                      : 'Ausgeschlossen · Details prüfen',
                ),
                children: [
                  Text(
                    'Lokal: ${candidate.localAvailable ? 'ja' : 'nein'} · Manueller Download: ${candidate.manualDownload ? 'erforderlich' : 'nein'}',
                  ),
                  Text(
                    candidate.parts.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n'),
                  ),
                  Text(
                    [
                      ...candidate.reasons,
                      ...candidate.exclusions,
                      ...candidate.uncertainties,
                    ].join('\n'),
                  ),
                ],
              ),
          ],
        ),
      ),
    for (final requirement in draft.searchRequirements)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(requirement),
      ),
  ];
  List<Widget> _preset(BuildContext context, PresetDraft draft) => [
    const Text(
      'Lokaler Preset-Entwurf · Manuell einstellen · Nicht übertragen',
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < draft.blocks.length; i++) ...[
          WyrmStatusBadge(
            '${_blockLabel(draft.blocks[i].slot)} ${draft.blocks[i].enabled ? 'an' : 'aus'}',
          ),
          if (i < draft.blocks.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Icon(Icons.arrow_forward, size: 20),
            ),
        ],
      ],
    ),
    for (final block in draft.blocks)
      Card(
        shape: block.slot == 'AMP' || block.slot == 'CAB'
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WyrmTokens.radius),
                side: const BorderSide(color: WyrmTokens.ember),
              )
            : null,
        child: ExpansionTile(
          key: PageStorageKey('block-${block.slot}'),
          title: Text(
            '${_blockLabel(block.slot)} · ${block.model ?? 'Manuelle Empfehlung'}',
          ),
          subtitle: Text(
            '${block.enabled ? 'Aktiv' : 'Inaktiv'} · ${block.parameters.isEmpty ? 'Manuell einzustellen' : 'Kuratierte Werte · Bereich bestätigt'}'
            '${block.parameters.isEmpty ? '' : '\n${block.parameters.entries.take(2).map((e) => '${e.key} ${e.value}').join(' · ')}'}',
          ),
          children: [
            Text(block.note),
            for (final p in block.parameters.entries)
              ListTile(
                title: Text('${p.key}: ${p.value}'),
                subtitle: Text(block.provenance[p.key] ?? ''),
              ),
          ],
        ),
      ),
    if (draft.selectedNamId != null)
      const Text(
        'NAM vorgemerkt: interner Amp deaktiviert. Keine erfundenen NAM-Regler.',
      ),
    ExpansionTile(
      title: const Text('Geräteunabhängiges Klangziel'),
      children: [
        const Text('0 = wenig, 100 = viel. Gate-Öffnung: höher = schneller.'),
        for (final e in draft.tone.values.entries)
          ListTile(title: Text(toneLabel(e.key)), trailing: Text('${e.value}')),
      ],
    ),
    FilledButton.icon(
      key: const Key('open-preset-workspace'),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PresetWorkspacePage(
            controller: widget.controller,
            library: widget.library,
          ),
        ),
      ),
      icon: const Icon(Icons.rule_folder_outlined),
      label: const Text('Preset speichern, vergleichen & planen'),
    ),
  ];
  String _blockLabel(String slot) => switch (slot) {
    'AMP' => 'Amp / NAM',
    'CAB' => 'Cab / IR',
    'DLY' => 'Delay',
    'RVB' => 'Reverb',
    _ => slot,
  };
  List<Widget> _corrections(PresetDraft draft) {
    final c = widget.controller, preview = c.offlinePreview;
    return [
      const Text(
        'Wähle eine klangliche Korrektur. Erst die Bestätigung verändert den lokalen Entwurf.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: RecommendationFeedback.values
            .map(
              (f) => ActionChip(
                label: Text(f.label),
                onPressed: () {
                  _feedback = f;
                  c.previewCorrection(f);
                },
              ),
            )
            .toList(),
      ),
      if (preview != null)
        WyrmCard(
          accent: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Änderungsvorschau: ${_feedback?.label ?? 'Klangkorrektur'}',
              ),
              const Text(
                'Nur nach „Anwenden“ wird der lokale Entwurf verändert. Keine Geräteübertragung.',
              ),
              ..._differences(draft, preview).map(Text.new),
              if (_feedback != null)
                Text(
                  _feedback == RecommendationFeedback.gateCutsNotes
                      ? 'Gate vorsichtiger öffnen. Bestätigte ATTACK-Abbildung nur beim DNAfx; Matribox bleibt manuell.'
                      : _feedback!.proposedCorrection,
                ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: const Key('offline-apply'),
                    onPressed: c.applyCorrection,
                    child: const Text('Anwenden'),
                  ),
                  TextButton(
                    onPressed: c.cancelCorrection,
                    child: const Text('Abbrechen'),
                  ),
                ],
              ),
            ],
          ),
        ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            key: const Key('offline-undo'),
            onPressed: c.canUndoCorrection ? c.undoCorrection : null,
            child: const Text('Letzten Schritt rückgängig'),
          ),
          TextButton(
            key: const Key('offline-reset'),
            onPressed: c.resetCorrections,
            child: const Text('Ausgangsvorschlag wiederherstellen'),
          ),
        ],
      ),
    ];
  }

  List<String> _differences(PresetDraft before, PresetDraft after) {
    final result = <String>[];
    for (final dim in ToneDimension.values) {
      if (before.tone[dim] != after.tone[dim]) {
        result.add(
          'Klangziel ${toneLabel(dim)}: ${before.tone[dim]} → ${after.tone[dim]} (Korrekturbudget berücksichtigt).',
        );
      }
    }
    for (var i = 0; i < before.blocks.length; i++) {
      final old = before.blocks[i], next = after.blocks[i];
      for (final p in old.parameters.entries) {
        if (p.value != next.parameters[p.key]) {
          result.add(
            '${old.slot}/${p.key}: ${p.value} → ${next.parameters[p.key]}',
          );
        }
      }
    }
    for (final category in ['IR', 'NAM']) {
      final old = before.candidates[category]!,
          next = after.candidates[category]!;
      result.add(
        '$category-Rangfolge: ${old.map((c) => '${c.name} (${c.score})').join(', ')} → ${next.map((c) => '${c.name} (${c.score})').join(', ')}',
      );
    }
    return result;
  }
}
