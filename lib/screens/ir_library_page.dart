import 'package:flutter/material.dart';

import '../controllers/recommendation_controller.dart';
import '../controllers/tone3000_controller.dart';
import '../models/ir_catalog_entry.dart';
import '../tone3000/local_ir_record.dart';
import '../tone3000/tone3000_models.dart';
import '../ui/wyrm_design.dart';

class IrLibraryPage extends StatefulWidget {
  const IrLibraryPage({
    required this.controller,
    this.tone3000,
    this.embedded = false,
    super.key,
  });
  final RecommendationController controller;
  final Tone3000Controller? tone3000;
  final bool embedded;

  @override
  State<IrLibraryPage> createState() => _IrLibraryPageState();
}

class _IrLibraryPageState extends State<IrLibraryPage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        if (widget.tone3000 != null) widget.tone3000!,
      ]),
      builder: (context, _) {
        final normalized = query.toLowerCase().trim();
        final availableEntries = widget.controller.libraryEntries
            .where((entry) => entry.status != IrAvailabilityStatus.missing)
            .toList();
        final entries = availableEntries.where((entry) {
          if (normalized.isEmpty) return true;
          return [
            entry.metadata.fileName,
            entry.metadata.manufacturerOrCollection,
            entry.metadata.cabinet,
            entry.metadata.speaker,
            entry.metadata.microphone,
            entry.status.label,
            ...entry.metadata.detectedTags,
            ...?entry.reference?.suitabilityHints,
          ].whereType<String>().any(
            (value) => value.toLowerCase().contains(normalized),
          );
        }).toList();
        return WyrmScaffold(
          title: 'IR-Bibliothek',
          embedded: widget.embedded,
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const WyrmSection(
                title: 'Impulse Responses',
                subtitle: 'Cabinet & Mikrofon · WAV · Keine Geräteübertragung',
                child: SizedBox.shrink(),
              ),
              TextField(
                key: const Key('ir-search-field'),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'IRs durchsuchen',
                ),
                onChanged: (value) => setState(() {
                  query = value;
                }),
              ),
              const SizedBox(height: 16),
              if (widget.tone3000 case final tone3000?) ...[
                _Tone3000Section(controller: tone3000, query: query),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                key: const Key('select-ir-folder-button'),
                onPressed: widget.controller.busy
                    ? null
                    : widget.controller.selectIrFolder,
                icon: const Icon(Icons.folder_open),
                label: const Text('Externen IR-Ordner auswählen'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Nur lesender Zugriff · Ordner bleibt nach Neustart verfügbar · Keine Geräteübertragung.',
              ),
              if (widget.controller.selectedFolderUri != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${widget.controller.folderFiles.length} WAV-Datei(en) im ausgewählten Ordner',
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Keine externe IR-Sammlung ausgewählt.'),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final status in IrAvailabilityStatus.values)
                    Chip(
                      key: Key('status-${status.name}'),
                      label: Text(
                        '${status.label}: ${widget.controller.countFor(status)}',
                      ),
                    ),
                ],
              ),
              if (widget.controller.message case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(message),
                ),
              if (entries.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      availableEntries.isEmpty
                          ? 'Keine WAV-Dateien im ausgewählten externen Ordner. '
                                'Fehlende Referenzeinträge werden nicht einzeln angezeigt.'
                          : 'Keine passenden gefundenen IR-Dateien.',
                    ),
                  ),
                )
              else
                for (final entry in entries) _IrCard(entry: entry),
            ],
          ),
        );
      },
    );
  }
}

class _Tone3000Section extends StatelessWidget {
  const _Tone3000Section({required this.controller, this.query = ''});
  final Tone3000Controller controller;
  final String query;

  @override
  Widget build(BuildContext context) {
    final selection = controller.selection;
    return Card(
      key: const Key('tone3000-section'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (controller.localRecords.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'Lokal gespeicherte TONE3000-IRs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Diese Dateien liegen geschützt in der App. Mit Exportieren '
                'kannst du eine sichtbare Kopie in einem Ordner deiner Wahl speichern.',
              ),
              for (final record in controller.localRecords.where(
                (r) => '${r.fileName} ${r.creatorName} ${r.toneName}'
                    .toLowerCase()
                    .contains(query.toLowerCase()),
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.audio_file_outlined),
                  title: Text(record.fileName),
                  subtitle: Text(
                    'IR · TONE3000 · ${record.creatorName} · Lizenz: ${record.license.isEmpty ? 'unbekannt' : record.license}\n'
                    '${_availabilityLabel(record.availability)} · '
                    '${record.channels == 1 ? 'Mono' : 'Stereo'} · '
                    '${record.sampleRateHz} Hz · ${record.bitsPerSample} Bit · '
                    '${record.fileSize} Byte\nGerätekompatibilität: manuell prüfen',
                  ),
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        key: Key('tone3000-open-${record.tone3000ModelId}'),
                        onPressed: () => controller.openLocalIr(record),
                        tooltip: 'IR öffnen',
                        icon: const Icon(Icons.play_arrow),
                      ),
                      IconButton(
                        key: Key('tone3000-export-${record.tone3000ModelId}'),
                        onPressed: () => controller.exportLocalIr(record),
                        tooltip: 'IR exportieren',
                        icon: const Icon(Icons.save_alt),
                      ),
                    ],
                  ),
                ),
            ],
            WyrmTone3000Header(controller: controller),
            if (controller.isConfigured && !controller.isConnected)
              FilledButton.icon(
                key: const Key('tone3000-connect'),
                onPressed: controller.busy ? null : controller.connectOrBrowse,
                icon: const Icon(Icons.login),
                label: const Text('Mit TONE3000 verbinden'),
              )
            else if (controller.isConnected) ...[
              Text('Angemeldet als ${controller.user!.username}'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('tone3000-browse'),
                    onPressed: controller.busy
                        ? null
                        : controller.connectOrBrowse,
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('TONE3000 durchsuchen'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('tone3000-disconnect'),
                    onPressed: controller.busy ? null : controller.disconnect,
                    icon: const Icon(Icons.logout),
                    label: const Text('Verbindung trennen'),
                  ),
                ],
              ),
            ],
            if (tone3000VisibleMessage(controller) case final message?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  message.startsWith('EXISTS:')
                      ? 'Datei bereits vorhanden.'
                      : message,
                ),
              ),
            if (selection != null) ...[
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      selection.tone.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const Key('tone3000-close-selection'),
                    onPressed: controller.downloadingModelId == null
                        ? controller.closeSelection
                        : null,
                    tooltip: 'TONE3000-Auswahl schließen',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                'TONE3000 · ${selection.tone.creatorName} · '
                'Lizenz: ${selection.tone.license}',
              ),
              if (selection.tone.description case final description?)
                Text(description, maxLines: 4, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              for (final model in selection.models)
                _Tone3000ModelTile(
                  tone: selection.tone,
                  model: model,
                  controller: controller,
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _availabilityLabel(LocalIrAvailability availability) =>
      switch (availability) {
        LocalIrAvailability.downloaded => 'Lokal vorhanden',
        LocalIrAvailability.invalid => 'Ungültig/inkompatibel',
        LocalIrAvailability.duplicate => 'Duplikat',
      };
}

class _Tone3000ModelTile extends StatelessWidget {
  const _Tone3000ModelTile({
    required this.tone,
    required this.model,
    required this.controller,
  });

  final Tone3000Tone tone;
  final Tone3000Model model;
  final Tone3000Controller controller;

  @override
  Widget build(BuildContext context) {
    final downloading = controller.downloadingModelId == model.id;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(model.name, style: Theme.of(context).textTheme.titleMedium),
            Text(
              'Creator: ${tone.creatorName} · Lizenz: ${tone.license}\n'
              'TONE3000-Modellgröße: ${model.sizeClass} · '
              'Dateigröße wird beim Download ermittelt.',
            ),
            if (downloading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: controller.downloadProgress),
              TextButton.icon(
                onPressed: controller.cancelDownload,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Download abbrechen'),
              ),
            ] else
              FilledButton.tonalIcon(
                key: Key('tone3000-download-${model.id}'),
                onPressed: controller.downloadingModelId == null
                    ? () => _download(context)
                    : null,
                icon: const Icon(Icons.download),
                label: const Text('IR herunterladen'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _download(BuildContext context) async {
    final completed = await controller.downloadModel(model);
    if (completed || !context.mounted) return;
    final message = controller.message;
    if (message == null || !message.startsWith('EXISTS:')) return;
    final fileName = message.substring('EXISTS:'.length);
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Datei bereits vorhanden'),
        content: Text('$fileName wirklich ersetzen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ersetzen'),
          ),
        ],
      ),
    );
    if (replace == true) {
      await controller.downloadModel(model, replaceExisting: true);
    }
  }
}

class _IrCard extends StatelessWidget {
  const _IrCard({required this.entry});
  final IrLibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final metadata = entry.metadata;
    final reference = entry.reference;
    String value(String? item) => item ?? 'unbekannt';
    final color = switch (entry.status) {
      IrAvailabilityStatus.present => WyrmTokens.success,
      IrAvailabilityStatus.missing => Colors.grey,
      IrAvailabilityStatus.unknown => WyrmTokens.ember,
      IrAvailabilityStatus.duplicate => WyrmTokens.muted,
    };
    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.audio_file_outlined, color: color),
        title: Text(metadata.fileName),
        subtitle: Text(
          '${entry.status.label} · ${value(metadata.cabinet)} · '
          '${value(metadata.speaker)} · '
          '${(metadata.confidence * 100).round()} % Erkennung',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Quelle: Externer Ordner · Urheber: unbekannt · Lizenz: unbekannt\nGerätekompatibilität: unbestätigt\nStatus: ${entry.status.label}${entry.status == IrAvailabilityStatus.present ? ' · lokal importiert' : ''}\n'
              'Treffer im Ordner: ${entry.matchedFiles.length}\n'
              'Format: ${_format(reference?.format)}\n'
              'Sammlung/Hersteller: ${value(metadata.manufacturerOrCollection)}\n'
              'Mikrofon: ${value(metadata.microphone)} · Position: ${value(metadata.microphonePosition)}\n'
              'Brightness: ${metadata.brightness ?? '?'} · Tightness: ${metadata.tightness ?? '?'} · Low-End: ${metadata.lowEnd ?? '?'}\n'
              'Tags: ${metadata.detectedTags.isEmpty ? 'keine' : metadata.detectedTags.join(', ')}\n'
              'Eignung: ${reference?.suitabilityHints.join('; ') ?? 'Nicht im Referenzkatalog; manuell prüfen.'}\n'
              '${reference?.duplicateGroup == null ? '' : 'Bekannte Dublettengruppe: ${reference!.duplicateGroup}\n'}'
              '${metadata.note ?? ''}',
            ),
          ),
        ],
      ),
    );
  }

  String _format(WavFormatInfo? format) {
    if (format == null) return 'unbekannt';
    final rate = format.sampleRateHz == null
        ? '? Hz'
        : '${format.sampleRateHz} Hz';
    final channels = switch (format.channels) {
      1 => 'Mono',
      2 => 'Stereo',
      final value? => '$value Kanäle',
      null => '? Kanäle',
    };
    return '${format.container}, ${format.encoding}, $rate, $channels, '
        '${format.bitsPerSample ?? '?'} Bit, ${format.durationMs ?? '?'} ms';
  }
}
