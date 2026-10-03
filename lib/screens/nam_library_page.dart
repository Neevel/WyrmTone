import 'package:flutter/material.dart';

import '../controllers/tone3000_controller.dart';
import '../controllers/usb_controller.dart';
import '../nam/local_nam_capture.dart';
import '../tone3000/tone3000_models.dart';
import '../ui/wyrm_design.dart';
import 'nam_detail_page.dart';

class NamLibraryPage extends StatefulWidget {
  const NamLibraryPage({
    required this.controller,
    required this.usbController,
    this.embedded = false,
    super.key,
  });
  final Tone3000Controller controller;
  final UsbController usbController;
  final bool embedded;
  @override
  State<NamLibraryPage> createState() => _NamLibraryPageState();
}

class _NamLibraryPageState extends State<NamLibraryPage> {
  String query = '';
  NamCompatibility? compatibility;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final selection = controller.namSelection;
      final captures = controller.namCaptures.where((c) {
        final text =
            '${c.captureName} ${c.creatorName} ${c.make ?? ''} ${c.tags.join(' ')}'
                .toLowerCase();
        return text.contains(query.toLowerCase()) &&
            (compatibility == null || c.compatibility == compatibility);
      }).toList();
      return WyrmScaffold(
        title: 'NAM-Bibliothek',
        embedded: widget.embedded,
        background: true,
        backgroundIntensity: WyrmBackgroundIntensity.dim,
        body: ListView(
          key: const Key('nam-library-list'),
          padding: const EdgeInsets.all(16),
          children: [
            const WyrmSection(
              title: 'Neural Amp Models',
              subtitle: 'Amp-Captures · NAM · Auf Matribox übertragbar',
            ),
            const SizedBox(height: 8),
            // Discovery sits at the top: with many NAMs in the list, an entry point at the
            // bottom (and the result list it opens) would be off-screen.
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  key: const Key('tone3000-browse-nam'),
                  onPressed: controller.busy || !controller.isConfigured
                      ? null
                      : () => controller.connectOrBrowse(
                          mode: Tone3000SelectionMode.namA1,
                        ),
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('NAM bei TONE3000 auswählen'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('import-nam-file'),
                  onPressed: controller.busy ? null : controller.importNam,
                  icon: const Icon(Icons.file_open),
                  label: const Text('Lokale .nam-Datei importieren'),
                ),
              ],
            ),
            if (!controller.isConfigured)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'TONE3000 ist noch nicht eingerichtet – Details weiter unten.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (tone3000VisibleMessage(controller) != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(tone3000VisibleMessage(controller)!),
              ),
            if (selection != null) ...[
              WyrmCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            selection.tone.title,
                            style: Theme.of(context).textTheme.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          key: const Key('tone3000-close-nam-selection'),
                          onPressed: controller.closeNamSelection,
                          tooltip: 'NAM-Auswahl schließen',
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    Text(
                      '${selection.tone.creatorName} · Lizenz: ${selection.tone.license}',
                    ),
                    for (final model in selection.models)
                      _NamModelTile(controller: controller, model: model),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'NAM durchsuchen',
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            DropdownButton<NamCompatibility?>(
              isExpanded: true,
              value: compatibility,
              hint: const Text('Kompatibilität'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Alle Status'),
                ),
                ...NamCompatibility.values.map(
                  (v) => DropdownMenuItem(
                    value: v,
                    child: Text(compatibilityLabel(v)),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => compatibility = v),
            ),
            if (captures.isEmpty)
              const WyrmEmptyState(
                title: 'Noch keine lokalen NAM-Captures.',
                message: 'Importiere eine vorhandene .nam-Datei oder wähle bei TONE3000 ein passendes NAM-Modell aus.',
              )
            else
              for (final capture in captures)
                WyrmCard(
                  key: Key('nam-card-${capture.localId}'),
                  // Always reachable: NamDetailPage itself gates the actual
                  // "Auf Matribox übertragen" action on capture.compatibility,
                  // the real signal for that decision (the sound-recommendation
                  // target device, a separate concept, plays no role here).
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NamDetailPage(capture: capture, usbController: widget.usbController),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              capture.captureName,
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              namSourceSummary(capture),
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            // Raw metadata (license code, source URL, attribution,
                            // architecture) lives under "Weitere Angaben" on the detail
                            // page; the list only answers "which one, and can I use it".
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                WyrmStatusBadge(
                                  compatibilityLabel(capture.compatibility),
                                  positive: capture.compatibility == NamCompatibility.compatible,
                                  warning: capture.compatibility != NamCompatibility.compatible,
                                ),
                                WyrmStatusBadge(namSizeLabel(capture.fileSize)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Lokales NAM löschen',
                        onPressed: () => _confirmDelete(context, capture),
                      ),
                    ],
                  ),
                ),
            WyrmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WyrmTone3000Header(controller: controller),
                  const Text(
                    'Kompatible NAM-Modelle lassen sich direkt auf deine Matribox übertragen.',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _confirmDelete(
    BuildContext context,
    LocalNamCapture capture,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('NAM-Capture löschen?'),
        content: Text('${capture.captureName} wird nur lokal gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (yes == true) await widget.controller.deleteNam(capture);
  }
}

class _NamModelTile extends StatelessWidget {
  const _NamModelTile({required this.controller, required this.model});
  final Tone3000Controller controller;
  final Tone3000Model model;
  @override
  Widget build(BuildContext context) {
    final busy = controller.downloadingModelId == model.id;
    return WyrmCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(model.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            'Architektur: ${model.architectureVersion ?? 'unbekannt'} · nur A1 wird angeboten',
          ),
          if (busy) ...[
            LinearProgressIndicator(value: controller.downloadProgress),
            TextButton(
              onPressed: controller.cancelDownload,
              child: const Text('Download abbrechen'),
            ),
          ] else
            FilledButton.tonalIcon(
              key: Key('nam-download-${model.id}'),
              onPressed: () => _download(context),
              icon: const Icon(Icons.download),
              label: const Text('NAM herunterladen'),
            ),
        ],
      ),
    );
  }

  Future<void> _download(BuildContext context) async {
    final ok = await controller.downloadNam(model);
    if (ok ||
        !context.mounted ||
        !(controller.message?.startsWith('NAM_EXISTS:') ?? false)) {
      return;
    }
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Datei vorhanden'),
        content: const Text('Vorhandenes NAM-Capture ersetzen?'),
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
      await controller.downloadNam(model, replaceExisting: true);
    }
  }
}
