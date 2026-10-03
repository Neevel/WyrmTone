import 'package:flutter/material.dart';

import '../controllers/usb_controller.dart';
import '../nam/local_nam_capture.dart';
import '../services/matribox_clone_slot_policy.dart';
import '../services/matribox_nam_payload.dart';
import '../services/matribox_nam_transfer_codec.dart' show MatriboxCloneSlot;
import '../services/matribox_nam_transfer_service.dart';
import '../services/nam_preparation_service.dart';
import '../ui/clone_slot_picker.dart';
import '../ui/wyrm_design.dart';

/// [LocalNamCapture.localUri] is stored as a `file://` URI string
/// (`File.uri.toString()`, percent-encoded -- see `nam_download_service.dart`/
/// `nam_import_service.dart`), but the native NAM inference loader wants a
/// plain filesystem path. [Uri.toFilePath] does the scheme-stripping and
/// percent-decoding; falls back to the raw string for anything that is
/// already a plain path (no scheme) rather than throwing.
String _localFilePath(String localUri) {
  final uri = Uri.tryParse(localUri);
  if (uri == null || (uri.scheme.isNotEmpty && uri.scheme != 'file'))
    return localUri;
  try {
    return uri.toFilePath();
  } on UnsupportedError {
    return localUri;
  }
}

/// Product NAM → Matribox workflow V1: local/downloaded NAM detail and the
/// full transfer journey (prepare on-device -> connect Matribox -> choose
/// Clone slot -> confirm overwrite -> transfer -> result), all as phases of
/// one page -- same shape as `ToneTransferPage` for presets. UI code here
/// never sees FFI details, native pointers, raw inference buffers or
/// estimator stages: only [NamPreparationService]/[MatriboxNamPayload] and
/// [MatriboxNamTransferService]/[MatriboxNamTransferResult].
enum _Phase {
  idle,
  preparing,
  preparationFailed,
  preparationCancelled,
  connectMatribox,
  transferring,
  success,
  failed,
}

/// Matches [NamPreparationService.prepare]'s signature -- injectable so
/// widget tests can drive every phase without touching real FFI/native
/// inference. Defaults to a real [NamPreparationService].
typedef NamPreparationRunner = Future<NamPreparationResult> Function(
  String namPath, {
  required String namName,
  required String namSha256,
  Object? cancelToken,
  void Function(NamPreparationStage stage)? onProgress,
});

/// Matches [MatriboxNamTransferService.transfer]'s signature -- injectable
/// for the same reason (no real USB/MIDI in a widget test).
typedef MatriboxNamTransferRunner = Future<MatriboxNamTransferResult> Function({
  required MatriboxNamPayload payload,
  required MatriboxCloneSlot slot,
  void Function(MatriboxNamTransferProgress progress)? onProgress,
});

class NamDetailPage extends StatefulWidget {
  const NamDetailPage({
    required this.capture,
    required this.usbController,
    this.prepare,
    this.transfer,
    this.cancelPreparation,
    this.cancelTransfer,
    super.key,
  });
  final LocalNamCapture capture;
  final UsbController usbController;

  /// Test-only override for the preparation step; production code leaves
  /// this null and gets a real [NamPreparationService].
  final NamPreparationRunner? prepare;

  /// Test-only override for the transfer step; production code leaves this
  /// null and gets a real [MatriboxNamTransferService] over
  /// [UsbController.service].
  final MatriboxNamTransferRunner? transfer;
  final Future<void> Function()? cancelPreparation;
  final Future<void> Function()? cancelTransfer;

  @override
  State<NamDetailPage> createState() => _NamDetailPageState();
}

class _NamDetailPageState extends State<NamDetailPage> {
  _Phase _phase = _Phase.idle;
  String? _preflightError;
  NamPreparationResult? _preparationResult;
  MatriboxTransferCloneSlot? _selectedSlot;
  MatriboxNamTransferResult? _transferResult;
  int _confirmedCount = 0;
  int _totalFrames = 0;

  NamPreparationService? _preparationService;
  Object? _cancelToken;
  MatriboxNamTransferService? _transferService;

  bool get _isBusy =>
      _phase == _Phase.preparing || _phase == _Phase.transferring;

  @override
  void initState() {
    super.initState();
    widget.usbController.addListener(_onConnectionChanged);
  }

  @override
  void dispose() {
    widget.usbController.removeListener(_onConnectionChanged);
    super.dispose();
  }

  void _onConnectionChanged() {
    // Section 11: a connection event never advances the flow by itself --
    // only triggers a rebuild so the "Matribox verbinden" screen can show
    // its now-available "Weiter" action. Nothing here sends anything.
    if (mounted) setState(() {});
  }

  bool get _matriboxConnected =>
      widget.usbController.connectionState == DeviceConnectionState.connected;

  Future<void> _startTransfer() async {
    // Section 7: lightweight preflight, no write.
    final capture = widget.capture;
    if (capture.compatibility != NamCompatibility.compatible) {
      setState(
        () => _preflightError =
            'Dieses NAM ist für die Matribox nicht kompatibel.',
      );
      return;
    }
    if (capture.compatibility == NamCompatibility.missingLocalFile) {
      setState(() => _preflightError = 'Die lokale NAM-Datei fehlt.');
      return;
    }
    setState(() {
      _preflightError = null;
      _phase = _Phase.preparing;
      _preparationResult = null;
    });
    NamPreparationRunner runner;
    if (widget.prepare != null) {
      runner = widget.prepare!;
    } else {
      final service = NamPreparationService();
      _preparationService = service;
      _cancelToken = service.createCancelToken();
      runner =
          (
            namPath, {
            required namName,
            required namSha256,
            cancelToken,
            onProgress,
          }) => service.prepare(
            namPath,
            namName: namName,
            namSha256: namSha256,
            cancelToken: _cancelToken,
            onProgress: onProgress,
          );
    }
    // Lifecycle fix: a backstop, matching the one in MatriboxNamTransferService
    // -- NamPreparationService.prepare() is designed to never throw (every
    // failure becomes a NamPreparationResult), but an uncaught exception
    // here must still never leave this page stuck showing "preparing"
    // forever; convert it into the same failed phase a reported failure
    // would reach.
    NamPreparationResult result;
    try {
      result = await runner(
        _localFilePath(capture.localUri),
        namName: capture.captureName,
        namSha256: capture.sha256,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preparationResult = null;
        _phase = _Phase.preparationFailed;
      });
      return;
    }
    if (!mounted) return;
    // Session-lifecycle fix: the connect step must never rely purely on
    // whatever connection state was last cached from a push event -- see
    // UsbController.reconnectMatriboxIfNeeded's own docs. A still-attached
    // Matribox whose MIDI session silently needs reopening gets a fresh,
    // active chance here, before the "Matribox verbinden" card is shown.
    if (result.outcome == NamPreparationOutcome.success) {
      await widget.usbController.reconnectMatriboxIfNeeded();
      if (!mounted) return;
    }
    setState(() {
      _preparationResult = result;
      _phase = switch (result.outcome) {
        NamPreparationOutcome.success => _Phase.connectMatribox,
        NamPreparationOutcome.failed => _Phase.preparationFailed,
        NamPreparationOutcome.cancelled => _Phase.preparationCancelled,
      };
    });
  }

  Future<void> _cancelPreparation() async {
    if (widget.cancelPreparation != null) {
      await widget.cancelPreparation!();
      return;
    }
    final token = _cancelToken;
    if (token != null) _preparationService?.cancel(token);
  }

  Future<void> _continueAfterPreparation() async {
    if (!_matriboxConnected) return;
    final payload = _preparationResult?.payload;
    if (payload == null) return;
    final slot = await CloneSlotPicker.pick(
      context,
      selectedCloneNumber: _selectedSlot?.cloneNumber,
    );
    if (slot == null || !mounted) return;
    final confirmed = await _confirmOverwrite(slot);
    if (confirmed != true || !mounted) return;
    setState(() {
      _selectedSlot = slot;
      _phase = _Phase.transferring;
      _confirmedCount = 0;
      _totalFrames = 0;
    });
    MatriboxNamTransferRunner runner;
    if (widget.transfer != null) {
      runner = widget.transfer!;
    } else {
      final service = MatriboxNamTransferService(widget.usbController.service);
      _transferService = service;
      runner = service.transfer;
    }
    // Lifecycle fix: a backstop, matching the one in _startTransfer --
    // MatriboxNamTransferService.transfer() is designed to never throw
    // uncaught (every native-side failure, including the watchdog timeout
    // and the "session already active" guard, becomes a
    // MatriboxNamTransferResult), but this page must never again get stuck
    // showing "transferring" forever if something unexpected still throws.
    MatriboxNamTransferResult result;
    try {
      result = await runner(
        payload: payload,
        slot: slot.slot,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _confirmedCount = progress.confirmedCount;
            _totalFrames = progress.totalFrames;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _transferResult = null;
        _phase = _Phase.failed;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _transferResult = result;
      _phase = switch (result.outcome) {
        MatriboxNamTransferOutcome.success => _Phase.success,
        MatriboxNamTransferOutcome.failed => _Phase.failed,
        MatriboxNamTransferOutcome.cancelled => _Phase.failed,
      };
    });
  }

  Future<bool?> _confirmOverwrite(MatriboxTransferCloneSlot slot) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Auf Matribox übertragen?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('NAM: ${widget.capture.captureName}'),
              Text('Ziel: ${slot.label}'),
              const SizedBox(height: 12),
              Text(
                'Der vorhandene Inhalt von ${slot.label} wird überschrieben.',
                style: const TextStyle(color: WyrmTokens.danger),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              key: const Key('nam-transfer-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Übertragen'),
            ),
          ],
        ),
      );

  Future<void> _cancelTransfer() async {
    if (widget.cancelTransfer != null) {
      await widget.cancelTransfer!();
      return;
    }
    await _transferService?.cancel();
  }

  void _reset() => setState(() {
    _phase = _Phase.idle;
    _preparationResult = null;
    _transferResult = null;
    _selectedSlot = null;
    _preflightError = null;
  });

  @override
  Widget build(BuildContext context) => PopScope(
    // Never let an accidental back-swipe silently abandon an in-flight
    // preparation/transfer -- the explicit cancel actions on those cards
    // are the only way to stop them.
    canPop: !_isBusy,
    child: WyrmScaffold(
      title: widget.capture.captureName,
      background: true,
      backgroundIntensity: WyrmBackgroundIntensity.dim,
      body: ListView(
        key: const Key('nam-detail-list'),
        padding: const EdgeInsets.all(16),
        children: [
          _DetailCard(capture: widget.capture),
          const SizedBox(height: 16),
          _phaseCard(context),
        ],
      ),
    ),
  );

  Widget _phaseCard(BuildContext context) => switch (_phase) {
    _Phase.idle => _IdleCard(
      capture: widget.capture,
      error: _preflightError,
      onTransfer: _startTransfer,
    ),
    _Phase.preparing => _PreparingCard(onCancel: _cancelPreparation),
    _Phase.preparationFailed => _FailedCard(
      key: const Key('nam-preparation-failed'),
      title: 'Vorbereitung fehlgeschlagen',
      message:
          'Das NAM-Modell konnte nicht für die Matribox vorbereitet werden.',
      technicalMessage: _preparationResult?.error?.message,
      onRetry: _reset,
    ),
    _Phase.preparationCancelled => _FailedCard(
      key: const Key('nam-preparation-cancelled'),
      title: 'Vorbereitung abgebrochen',
      message: 'Die Vorbereitung wurde abgebrochen. Es wurde nichts an die Matribox gesendet.',
      onRetry: _reset,
    ),
    _Phase.connectMatribox => _ConnectCard(
      connected: _matriboxConnected,
      onContinue: _continueAfterPreparation,
      onRetryConnection: () => widget.usbController.reconnectMatriboxIfNeeded(),
    ),
    _Phase.transferring => _TransferringCard(
      namName: widget.capture.captureName,
      cloneLabel: _selectedSlot?.label ?? '',
      confirmedCount: _confirmedCount,
      totalFrames: _totalFrames,
      onCancel: _cancelTransfer,
    ),
    _Phase.success => _SuccessCard(
      namName: widget.capture.captureName,
      cloneLabel: _selectedSlot?.label ?? '',
      onDone: () => Navigator.of(context).pop(),
    ),
    _Phase.failed => _FailedCard(
      key: const Key('nam-transfer-failed'),
      title: 'Übertragung fehlgeschlagen',
      message:
          _transferResult?.userMessage ?? 'Die Übertragung ist fehlgeschlagen.',
      technicalMessage: _transferResult?.technicalMessage,
      showIncompleteWarning:
          _transferResult?.outcome == MatriboxNamTransferOutcome.cancelled,
      onRetry: _reset,
    ),
  };
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.capture});
  final LocalNamCapture capture;

  @override
  Widget build(BuildContext context) => WyrmCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          capture.captureName,
          style: Theme.of(context).textTheme.titleLarge,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(namSourceSummary(capture)),
        const SizedBox(height: 8),
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
        ExpansionTile(
          key: const Key('nam-metadata-details'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: const Text('Weitere Angaben'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lizenz: ${capture.license.isEmpty ? 'unbekannt' : capture.license}',
                  ),
                  Text(
                    'Architektur: ${capture.architecture == NamArchitecture.unknown ? 'unbekannt' : capture.architecture.name.toUpperCase()}',
                  ),
                  if (capture.attribution.isNotEmpty)
                    Text('Urheberhinweis: ${capture.attribution}'),
                  if (capture.source != 'local') Text(capture.source),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _IdleCard extends StatelessWidget {
  const _IdleCard({
    required this.capture,
    required this.error,
    required this.onTransfer,
  });
  final LocalNamCapture capture;
  final String? error;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    final canTransfer = capture.compatibility == NamCompatibility.compatible;
    return WyrmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Auf Matribox übertragen',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (!canTransfer)
            Text(
              'Übertragung nicht verfügbar: ${compatibilityLabel(capture.compatibility)}.',
              style: const TextStyle(color: WyrmTokens.danger),
            )
          else
            const Text(
              'WyrmTone bereitet das NAM-Modell direkt auf deinem Gerät für die Matribox vor.',
            ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: const TextStyle(color: WyrmTokens.danger)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('nam-detail-transfer'),
            onPressed: canTransfer ? onTransfer : null,
            icon: const Icon(Icons.cable),
            label: const Text('Auf Matribox übertragen'),
          ),
        ],
      ),
    );
  }
}

class _PreparingCard extends StatelessWidget {
  const _PreparingCard({required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => WyrmCard(
    key: const Key('nam-preparing-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NAM wird für Matribox vorbereitet',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'WyrmTone bereitet das NAM-Modell direkt auf deinem Gerät für die Matribox vor. '
          'Das dauert je nach Smartphone etwa eine halbe bis eine Minute.',
        ),
        const SizedBox(height: 12),
        // Indeterminate on purpose: the native inference + estimator run is
        // one atomic operation with no honest intermediate percentage (see
        // NamPreparationService's own docs on NamPreparationStage).
        const LinearProgressIndicator(
          minHeight: 4,
          semanticsLabel: 'Sound wird vorbereitet',
        ),
        const SizedBox(height: 8),
        const Text('Modell wird verarbeitet …'),
        const SizedBox(height: 12),
        TextButton(onPressed: onCancel, child: const Text('Abbrechen')),
      ],
    ),
  );
}

class _ConnectCard extends StatelessWidget {
  const _ConnectCard({
    required this.connected,
    required this.onContinue,
    required this.onRetryConnection,
  });
  final bool connected;
  final VoidCallback onContinue;
  final VoidCallback onRetryConnection;

  @override
  Widget build(BuildContext context) => WyrmCard(
    key: const Key('nam-connect-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          connected ? 'Matribox verbunden' : 'Matribox verbinden',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          connected
              ? 'Die Matribox ist bereit. Wähle als Nächstes den Clone-Slot aus.'
              : 'Verbinde deine Matribox per USB mit diesem Gerät.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('nam-connect-continue'),
              onPressed: connected ? onContinue : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Weiter'),
            ),
            if (!connected)
              TextButton.icon(
                key: const Key('nam-connect-retry'),
                onPressed: onRetryConnection,
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
          ],
        ),
      ],
    ),
  );
}

class _TransferringCard extends StatelessWidget {
  const _TransferringCard({
    required this.namName,
    required this.cloneLabel,
    required this.confirmedCount,
    required this.totalFrames,
    required this.onCancel,
  });
  final String namName, cloneLabel;
  final int confirmedCount, totalFrames;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final fraction = totalFrames == 0 ? 0.0 : confirmedCount / totalFrames;
    return WyrmCard(
      key: const Key('nam-transferring-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Übertragung an Matribox',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text('$namName → $cloneLabel'),
          const SizedBox(height: 12),
          // Section 17: REAL, ACK-confirmed progress -- never derived from
          // frames merely sent.
          LinearProgressIndicator(
            value: totalFrames == 0 ? null : fraction,
            minHeight: 6,
            semanticsLabel: 'Übertragung an die Matribox',
            semanticsValue: totalFrames == 0
                ? null
                : '${(fraction * 100).round()} Prozent',
          ),
          const SizedBox(height: 8),
          Text(
            totalFrames == 0
                ? 'Übertragung wird gestartet …'
                : '$confirmedCount von $totalFrames übertragen (${(fraction * 100).round()} %)',
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const Key('nam-transfer-cancel'),
            onPressed: onCancel,
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({
    required this.namName,
    required this.cloneLabel,
    required this.onDone,
  });
  final String namName, cloneLabel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: WyrmCard(
      key: const Key('nam-transfer-success'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: WyrmTokens.success, size: 32),
              SizedBox(width: 8),
              Expanded(child: Text('Übertragung abgeschlossen')),
            ],
          ),
          const SizedBox(height: 8),
          Text('$namName wurde erfolgreich auf $cloneLabel übertragen.'),
          const SizedBox(height: 4),
          Text('Du kannst den Clone jetzt an deiner Matribox verwenden.'),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('nam-transfer-done'),
            onPressed: onDone,
            child: const Text('Fertig'),
          ),
        ],
      ),
    ),
  );
}

class _FailedCard extends StatelessWidget {
  const _FailedCard({
    required this.title,
    required this.message,
    this.technicalMessage,
    this.showIncompleteWarning = false,
    required this.onRetry,
    super.key,
  });
  final String title, message;
  final String? technicalMessage;
  final bool showIncompleteWarning;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: WyrmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                color: WyrmTokens.danger,
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(message),
          if (showIncompleteWarning) ...[
            const SizedBox(height: 8),
            const Text(
              'Der gewählte Clone-Slot kann unvollständig sein.',
              style: TextStyle(color: WyrmTokens.danger),
            ),
          ],
          if (technicalMessage != null) ...[
            const SizedBox(height: 8),
            ExpansionTile(
              key: const Key('nam-failure-details'),
              title: const Text('Details'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(technicalMessage!),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Erneut versuchen'),
          ),
        ],
      ),
    ),
  );
}
