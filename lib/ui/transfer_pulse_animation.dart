import 'package:flutter/material.dart';

import 'wyrm_design.dart';

/// What the transfer animation shows -- purely a rendering hint DERIVED from the real product
/// state machine ([MatriboxToneTransferRecord]/prepare/send/readback results). It never decides
/// anything and is never itself the source of a "success"; see [TransferPulseAnimation].
enum TransferVisualPhase {
  /// Nothing prepared yet, or a fresh restart.
  idle,

  /// Reading + backing up the current preset.
  preparing,

  /// The live write is actually in flight.
  sending,

  /// Live write done, waiting for the user's manual save at the device.
  awaitingSave,

  /// A fresh saved-state read is running.
  verifying,

  /// MANUAL_SAVE_PERSISTENCE_VERIFIED.
  success,

  /// Any stopped/blocked/mismatched/stale outcome.
  failed,
}

/// Sound → Matribox, with a small signal impulse that only ever moves while a real transfer step
/// is actually in flight. The state comes from [phase] -- set by the page from the SAME fields
/// (`_busy`, the stored record, the run/readback results) that already drive every button and every
/// text on this page, so the animation can never show something the product state does not agree
/// with, and a failure stops it immediately (no timer ever fabricates a success).
class TransferPulseAnimation extends StatefulWidget {
  const TransferPulseAnimation({required this.phase, required this.presetLabel, super.key});
  final TransferVisualPhase phase;

  /// "P01" (or "P01 · Presetname" once a saved name is known) -- never a raw id.
  final String presetLabel;

  @override
  State<TransferPulseAnimation> createState() => _TransferPulseAnimationState();
}

class _TransferPulseAnimationState extends State<TransferPulseAnimation> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  bool get _reducedMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TransferPulseAnimation old) {
    super.didUpdateWidget(old);
    if (old.phase != widget.phase) _sync();
  }

  void _sync() {
    final moving = widget.phase == TransferVisualPhase.sending || widget.phase == TransferVisualPhase.verifying;
    if (moving && !_reducedMotion) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = switch (widget.phase) {
        TransferVisualPhase.idle || TransferVisualPhase.preparing => 0,
        TransferVisualPhase.success => 1,
        TransferVisualPhase.failed => 0.5,
        TransferVisualPhase.sending || TransferVisualPhase.verifying => 0.5, // reduced-motion: a fixed mid position
        TransferVisualPhase.awaitingSave => 1,
      };
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = _reducedMotion;
    final label = switch (widget.phase) {
      TransferVisualPhase.idle => 'Noch nicht vorbereitet',
      TransferVisualPhase.preparing => 'Aktuellen Speicherplatz sichern …',
      TransferVisualPhase.sending => 'Sound wird übertragen …',
      TransferVisualPhase.awaitingSave => 'Sound ist live auf der Matribox aktiv',
      TransferVisualPhase.verifying => 'Gespeicherter Sound wird geprüft …',
      TransferVisualPhase.success => 'Preset erfolgreich gespeichert',
      TransferVisualPhase.failed => 'Nicht verifiziert',
    };
    final color = widget.phase == TransferVisualPhase.failed
        ? WyrmTokens.danger
        : widget.phase == TransferVisualPhase.success
        ? WyrmTokens.success
        : WyrmTokens.ember;
    return Semantics(
      label: 'Übertragungsstatus: $label',
      // The text status is never only decoration -- it is present and readable even when the
      // graphic below is static (reduced motion) or not shown at all to assistive tech.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 72,
            child: Row(
              children: [
                const _EndpointIcon(icon: Icons.graphic_eq, label: 'Dein Sound'),
                Expanded(
                  child: reduced
                      ? _StaticTrack(phase: widget.phase, color: color)
                      : AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) => _Track(phase: widget.phase, t: _controller.value, color: color),
                        ),
                ),
                _EndpointIcon(icon: Icons.speaker, label: 'Matribox 1\n${widget.presetLabel}', highlight: widget.phase == TransferVisualPhase.success),
              ],
            ),
          ),
          const SizedBox(height: WyrmTokens.space4),
          if (widget.phase == TransferVisualPhase.preparing || widget.phase == TransferVisualPhase.verifying)
            const Padding(padding: EdgeInsets.only(bottom: WyrmTokens.space4), child: LinearProgressIndicator(minHeight: 3)),
          Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _EndpointIcon extends StatelessWidget {
  const _EndpointIcon({required this.icon, required this.label, this.highlight = false});
  final IconData icon;
  final String label;
  final bool highlight;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 84,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: highlight ? WyrmTokens.success.withValues(alpha: 0.25) : WyrmTokens.raised,
          child: Icon(icon, color: highlight ? WyrmTokens.success : WyrmTokens.ember, size: 16),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11, height: 1.1),
        ),
      ],
    ),
  );
}

/// The moving connector: a line with a small glowing dot at fraction [t] (0..1), only ever painted
/// while [phase] is actually `sending` (left-to-right) or `verifying` (right-to-left).
class _Track extends StatelessWidget {
  const _Track({required this.phase, required this.t, required this.color});
  final TransferVisualPhase phase;
  final double t;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final active = phase == TransferVisualPhase.sending || phase == TransferVisualPhase.verifying;
    final fraction = phase == TransferVisualPhase.verifying ? 1 - t : t;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(height: 2, color: WyrmTokens.outline),
          if (active)
            Positioned(
              left: (constraints.maxWidth - 12) * fraction.clamp(0.0, 1.0),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]),
              ),
            )
          else if (phase == TransferVisualPhase.success || phase == TransferVisualPhase.awaitingSave)
            const Align(alignment: Alignment.center, child: Icon(Icons.check_circle, color: WyrmTokens.success, size: 16))
          else if (phase == TransferVisualPhase.failed)
            const Align(alignment: Alignment.center, child: Icon(Icons.error_outline, color: WyrmTokens.danger, size: 16)),
        ],
      ),
    );
  }
}

/// Reduced-motion fallback: the same track, but nothing ever moves -- a fixed icon communicates the
/// phase instead of an animated dot.
class _StaticTrack extends StatelessWidget {
  const _StaticTrack({required this.phase, required this.color});
  final TransferVisualPhase phase;
  final Color color;
  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      Container(height: 2, color: WyrmTokens.outline),
      Icon(
        switch (phase) {
          TransferVisualPhase.success => Icons.check_circle,
          TransferVisualPhase.failed => Icons.error_outline,
          TransferVisualPhase.sending || TransferVisualPhase.verifying => Icons.sync,
          _ => Icons.remove,
        },
        color: color,
        size: 16,
      ),
    ],
  );
}
