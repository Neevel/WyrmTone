import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../models/guitar_profile.dart';

class GuitarsPage extends StatelessWidget {
  const GuitarsPage({required this.controller, super.key});
  final RecommendationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Gitarrenprofile')),
        body: controller.profiles.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Lege zuerst ein Gitarrenprofil an.'),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final profile in controller.profiles)
                    Card(
                      child: ListTile(
                        key: Key('profile-${profile.id}'),
                        onTap: () => controller.selectProfile(profile.id),
                        leading: Icon(
                          controller.selectedProfileId == profile.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(profile.name),
                        subtitle: Text(
                          '${profile.guitarType.label} · ${profile.pickupType.label} · '
                          '${profile.tuning.label} · ${profile.playbackPath.label}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Bearbeiten',
                          onPressed: () => _openForm(context, profile),
                          icon: const Icon(Icons.edit),
                        ),
                      ),
                    ),
                ],
              ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('add-profile-button'),
          onPressed: () => _openForm(context, null),
          icon: const Icon(Icons.add),
          label: const Text('Gitarre'),
        ),
      ),
    );
  }

  Future<void> _openForm(BuildContext context, GuitarProfile? profile) async {
    final saved = await Navigator.of(context).push<GuitarProfile>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GuitarProfileForm(profile: profile),
      ),
    );
    if (saved != null) await controller.saveProfile(saved);
  }
}

class GuitarProfileForm extends StatefulWidget {
  const GuitarProfileForm({this.profile, super.key});
  final GuitarProfile? profile;

  @override
  State<GuitarProfileForm> createState() => _GuitarProfileFormState();
}

class _GuitarProfileFormState extends State<GuitarProfileForm> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController gauge;
  late final TextEditingController customTuning;
  late GuitarType guitarType;
  late PickupType pickupType;
  late OutputLevel outputLevel;
  late ToneCharacter tone;
  late GuitarTuning tuning;
  late PlaybackPath playback;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    name = TextEditingController(text: profile?.name);
    gauge = TextEditingController(text: profile?.stringGauge);
    customTuning = TextEditingController(text: profile?.customTuning);
    guitarType = profile?.guitarType ?? GuitarType.superstrat;
    pickupType = profile?.pickupType ?? PickupType.passiveHumbucker;
    outputLevel = profile?.outputLevel ?? OutputLevel.medium;
    tone = profile?.toneCharacter ?? ToneCharacter.neutral;
    tuning = profile?.tuning ?? GuitarTuning.eStandard;
    playback = profile?.playbackPath ?? PlaybackPath.headphones;
  }

  @override
  void dispose() {
    name.dispose();
    gauge.dispose();
    customTuning.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.profile == null ? 'Gitarre anlegen' : 'Gitarre bearbeiten',
        ),
        actions: [
          TextButton(
            key: const Key('save-profile-button'),
            onPressed: _save,
            child: const Text('Speichern'),
          ),
        ],
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('profile-name-field'),
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Name erforderlich'
                  : null,
            ),
            _dropdown(
              'Gitarrentyp',
              guitarType,
              GuitarType.values,
              (value) => setState(() => guitarType = value),
              (value) => value.label,
            ),
            _dropdown(
              'Pickup-Typ',
              pickupType,
              PickupType.values,
              (value) => setState(() => pickupType = value),
              (value) => value.label,
            ),
            _dropdown(
              'Pickup-Ausgangspegel',
              outputLevel,
              OutputLevel.values,
              (value) => setState(() => outputLevel = value),
              (value) => value.label,
            ),
            _dropdown(
              'Klangcharakter',
              tone,
              ToneCharacter.values,
              (value) => setState(() => tone = value),
              (value) => value.label,
            ),
            _dropdown(
              'Stimmung',
              tuning,
              GuitarTuning.values,
              (value) => setState(() => tuning = value),
              (value) => value.label,
            ),
            if (tuning == GuitarTuning.custom)
              TextFormField(
                controller: customTuning,
                decoration: const InputDecoration(labelText: 'Eigene Stimmung'),
              ),
            TextFormField(
              controller: gauge,
              decoration: const InputDecoration(
                labelText: 'Saitenstärke (optional)',
              ),
            ),
            _dropdown(
              'Wiedergabeweg',
              playback,
              PlaybackPath.values,
              (value) => setState(() => playback = value),
              (value) => value.label,
            ),
            if (playback == PlaybackPath.powerAmpAndGuitarCab)
              const Card(
                color: Colors.deepOrange,
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Bei Endstufe + echter Gitarrenbox Cab-Simulation und Custom-IR normalerweise deaktivieren.',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown<T>(
    String label,
    T value,
    List<T> values,
    ValueChanged<T> changed,
    String Function(T) labelFor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: values
            .map(
              (item) =>
                  DropdownMenuItem(value: item, child: Text(labelFor(item))),
            )
            .toList(),
        onChanged: (item) {
          if (item != null) changed(item);
        },
      ),
    );
  }

  void _save() {
    if (!(formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      GuitarProfile(
        id:
            widget.profile?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        guitarType: guitarType,
        pickupType: pickupType,
        outputLevel: outputLevel,
        toneCharacter: tone,
        tuning: tuning,
        customTuning: tuning == GuitarTuning.custom
            ? customTuning.text.trim()
            : null,
        stringGauge: gauge.text.trim().isEmpty ? null : gauge.text.trim(),
        playbackPath: playback,
      ),
    );
  }
}
