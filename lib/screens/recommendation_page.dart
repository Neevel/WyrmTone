import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/tone3000_controller.dart';
import '../models/recommendation.dart';
import '../devices/device_profile.dart';
import 'offline_sound_panel.dart';
import '../ui/wyrm_design.dart';

class RecommendationPage extends StatefulWidget {
  const RecommendationPage({
    required this.controller,
    this.tone3000,
    this.openProfile,
    this.close,
    super.key,
  });
  final RecommendationController controller;
  final Tone3000Controller? tone3000;
  final VoidCallback? openProfile, close;

  @override
  State<RecommendationPage> createState() => _RecommendationPageState();
}

class _RecommendationPageState extends State<RecommendationPage> {
  RecommendationFeedback? feedback;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final profile = widget.controller.selectedProfile;
        final sound = widget.controller.selectedSound;
        final recommendation = widget.controller.recommendation;
        return WyrmScaffold(
          title: 'Sound erstellen',
          actions: [
            if (widget.close != null)
              IconButton(
                tooltip: 'Sound-Wizard schließen · Zur Soundübersicht',
                onPressed: widget.close,
                icon: const Icon(Icons.close),
              ),
          ],
          body: ListView(
            key: const Key('recommendation-view'),
            padding: const EdgeInsets.all(16),
            children: [
              OfflineSoundPanel(
                controller: widget.controller,
                library: widget.tone3000,
                openProfile: widget.openProfile,
              ),
              const SizedBox(height: 24),
              ExpansionTile(
                key: const Key('legacy-recommendations'),
                title: const Text('Bestehende Referenzempfehlungen'),
                children: [
                  DropdownButtonFormField<TargetDeviceId>(
                    isExpanded: true,
                    initialValue: widget.controller.selectedTargetDevice,
                    decoration: const InputDecoration(labelText: 'Zielgerät'),
                    items: toneDeviceAdapters
                        .map(
                          (device) => DropdownMenuItem(
                            value: device.id,
                            child: Text(device.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        widget.controller.selectTargetDevice(value);
                      }
                    },
                  ),
                  if (widget.controller.selectedTargetDevice ==
                      TargetDeviceId.matriboxOne)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'Matribox 1: NAM A1 kompatibel. A2/A2-Lite und USB-Protokoll unbestätigt. Übertragung noch nicht verfügbar.',
                        ),
                      ),
                    ),
                  if (widget.controller.profiles.isNotEmpty)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: profile?.id,
                      decoration: const InputDecoration(
                        labelText: 'Gitarrenprofil',
                      ),
                      items: widget.controller.profiles
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          widget.controller.selectProfile(value);
                        }
                      },
                    ),
                  const SizedBox(height: 8),
                  if (widget.controller.offlineDraft == null) ...[
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: sound.id,
                      decoration: const InputDecoration(
                        labelText: 'Ziel-Sound',
                      ),
                      items: widget.controller.sounds
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.displayName),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) widget.controller.selectSound(value);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (widget.controller.selectedTargetDevice ==
                        TargetDeviceId.matriboxOne) ...[
                      ..._namRecommendationWidgets(context),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Die Vorschläge sind Startpunkte anhand belegter Metadaten, keine exakte Rekonstruktion der Studioaufnahme.',
                        ),
                      ),
                    ] else if (recommendation == null)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Lege unter „Gitarren“ ein Profil an, um eine Empfehlung zu berechnen.',
                          ),
                        ),
                      )
                    else ...[
                      if (widget.controller.selectedTargetDevice ==
                          TargetDeviceId.matriboxOne) ...[
                        Text(
                          'NAM-Empfehlungen',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (widget.tone3000 == null ||
                            widget.controller
                                .namRecommendations(
                                  widget.tone3000!.namCaptures,
                                )
                                .isEmpty)
                          const Text(
                            'Keine passenden lokalen NAM-A1-Captures. Internes Matribox-Ampmodell bleibt eine Option; konkrete Modellnamen werden nicht erfunden.',
                          )
                        else
                          for (final candidate
                              in widget.controller.namRecommendations(
                                widget.tone3000!.namCaptures,
                              ))
                            Card(
                              child: ListTile(
                                title: Text(candidate.capture.captureName),
                                trailing: Text('${candidate.score} %'),
                                subtitle: Text(
                                  '${candidate.reasons.join(' ')}\nZusätzliche IR: ${candidate.additionalIrRequired == null
                                      ? 'unklar – Warnung'
                                      : candidate.additionalIrRequired!
                                      ? 'benötigt'
                                      : 'normalerweise deaktiviert'}${candidate.uncertainties.isEmpty ? '' : '\n${candidate.uncertainties.join(' ')}'}',
                                ),
                              ),
                            ),
                      ],
                      _section(
                        context,
                        'Vorgeschlagene Kette',
                        '${recommendation.effectChain.join(' → ')}\n'
                            'Cab/Custom-IR: ${recommendation.cabSimulationEnabled ? 'aktiv' : 'deaktiviert'}',
                      ),
                      _section(
                        context,
                        'Amp- und Effektwerte',
                        recommendation.parameters
                            .map(
                              (parameter) =>
                                  '${parameter.name}: ${parameter.value} '
                                  '(Basis ${parameter.baseValue})\n  ${parameter.reasons.join(' ')}'
                                  '${parameter.confirmed ? ' · bestätigt' : ' · Annäherung'}',
                            )
                            .join('\n'),
                      ),
                      Text(
                        'IR-Empfehlungen',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (!recommendation.cabSimulationEnabled)
                        const Text(
                          'Keine IR-Auswahl: reale Gitarrenbox ist ausgewählt.',
                        )
                      else if (recommendation.irCandidates.isEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Wähle in der IR-Bibliothek einen Ordner mit WAV-Dateien aus oder suche gezielt bei TONE3000.',
                            ),
                            if (widget.tone3000 case final tone3000?)
                              TextButton.icon(
                                key: const Key(
                                  'recommendation-tone3000-browse',
                                ),
                                onPressed: tone3000.isConfigured
                                    ? tone3000.connectOrBrowse
                                    : null,
                                icon: const Icon(Icons.travel_explore),
                                label: const Text('TONE3000 durchsuchen'),
                              ),
                          ],
                        )
                      else
                        for (final candidate in recommendation.irCandidates)
                          Card(
                            key: Key(
                              'ir-recommendation-${candidate.ir.fileName}',
                            ),
                            child: Column(
                              children: [
                                ListTile(
                                  title: Text(candidate.ir.fileName),
                                  trailing: Text('${candidate.score} %'),
                                  subtitle: Text(
                                    '${candidate.reasons.join(' ')}'
                                    '${candidate.isUncertain ? '\nUnsichere Empfehlung' : ''}',
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'IR ist lokal vorhanden. DNAfx-Übertragung bleibt deaktiviert.',
                                                ),
                                              ),
                                            ),
                                    icon: const Icon(Icons.folder_open),
                                    label: const Text('IR öffnen'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      _section(
                        context,
                        'Begründungen',
                        recommendation.reasons.join('\n• '),
                      ),
                      if (recommendation.warnings.isNotEmpty)
                        _section(
                          context,
                          'Warnungen und Unsicherheiten',
                          recommendation.warnings.join('\n• '),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'Feedback für spätere Korrektur',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Wrap(
                        spacing: 6,
                        children: RecommendationFeedback.values
                            .map(
                              (item) => ChoiceChip(
                                label: Text(item.label),
                                selected: feedback == item,
                                onSelected: (_) =>
                                    setState(() => feedback = item),
                              ),
                            )
                            .toList(),
                      ),
                      if (feedback case final selected?)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Künftige regelbasierte Korrektur: ${selected.proposedCorrection}',
                            ),
                          ),
                        ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Dies ist ein nachvollziehbarer Ausgangspunkt zum Feinabstimmen, keine exakte Rekonstruktion der Studioaufnahme.',
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _namRecommendationWidgets(BuildContext context) {
    final recommendations = widget.tone3000 == null
        ? const <NamRecommendation>[]
        : widget.controller.namRecommendations(widget.tone3000!.namCaptures);
    return [
      Text('Klangquelle', style: Theme.of(context).textTheme.titleLarge),
      const Card(
        child: ListTile(
          title: Text('Internes Matribox-Ampmodell'),
          subtitle: Text(
            'Allgemeine Option; konkrete Modellnamen und Parameter sind noch nicht belegt.',
          ),
        ),
      ),
      Text(
        'Lokale NAM-A1-Empfehlungen',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (recommendations.isEmpty)
        const Text('Keine passenden, lokal vorhandenen NAM-A1-Captures.')
      else
        for (final candidate in recommendations)
          Card(
            child: ListTile(
              title: Text(candidate.capture.captureName),
              trailing: Text('${candidate.score} %'),
              subtitle: Text(
                'Kompatibilität: ${compatibilityLabel(candidate.capture.compatibility)}\n'
                '${candidate.reasons.join(' ')}\n'
                'Zusätzliche IR: ${candidate.additionalIrRequired == null
                    ? 'unklar – Warnung'
                    : candidate.additionalIrRequired!
                    ? 'benötigt'
                    : 'normalerweise deaktiviert'}'
                '${candidate.uncertainties.isEmpty ? '' : '\n${candidate.uncertainties.join(' ')}'}',
              ),
            ),
          ),
    ];
  }

  Widget _section(BuildContext context, String title, String body) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('• $body'),
        ],
      ),
    ),
  );
}
