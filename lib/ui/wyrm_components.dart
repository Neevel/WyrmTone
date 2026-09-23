import 'package:flutter/material.dart';

import 'wyrm_design.dart';

/// Section title with an optional caption and trailing action.
class WyrmSectionHeader extends StatelessWidget {
  const WyrmSectionHeader(this.title, {this.subtitle, this.trailing, super.key});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: WyrmTokens.space24, bottom: WyrmTokens.space8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
              if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// A tappable choice chip or a plain information chip. A selection is shown by a check mark AND fill, never by colour alone.
class WyrmChip extends StatelessWidget {
  const WyrmChip(this.label, {this.selected = false, this.onTap, this.icon, this.tooltip, super.key});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final chip = onTap == null
        ? Chip(
            label: Text(label),
            avatar: icon == null ? null : Icon(icon, size: WyrmTokens.iconSmall),
            visualDensity: VisualDensity.compact,
          )
        : ChoiceChip(
            label: Text(label),
            avatar: selected
                ? const Icon(Icons.check, size: WyrmTokens.iconSmall)
                : (icon == null ? null : Icon(icon, size: WyrmTokens.iconSmall)),
            selected: selected,
            onSelected: (_) => onTap!(),
            materialTapTargetSize: MaterialTapTargetSize.padded,
          );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

class WyrmPrimaryButton extends StatelessWidget {
  const WyrmPrimaryButton({required this.label, required this.onPressed, this.icon, super.key});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => icon == null
      ? FilledButton(onPressed: onPressed, child: Text(label))
      : FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));
}

class WyrmSecondaryButton extends StatelessWidget {
  const WyrmSecondaryButton({required this.label, required this.onPressed, this.icon, super.key});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => icon == null
      ? OutlinedButton(onPressed: onPressed, child: Text(label))
      : OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));
}

/// The one search field of the app (plain names and natural language alike).
class WyrmSearchField extends StatelessWidget {
  const WyrmSearchField({required this.controller, required this.hint, this.onChanged, this.onSubmitted, this.fieldKey, this.focusNode, super.key});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;
  final FocusNode? focusNode;
  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    focusNode: focusNode,
    textInputAction: TextInputAction.search,
    minLines: 1,
    maxLines: 3,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => value.text.isEmpty
            ? const SizedBox.shrink()
            : IconButton(
                tooltip: 'Eingabe löschen',
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
              ),
      ),
    ),
  );
}

/// A real failure (red is reserved for this). [action] offers a safe way out.
class WyrmErrorState extends StatelessWidget {
  const WyrmErrorState({required this.title, required this.message, this.action, super.key});
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: WyrmTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
              const SizedBox(width: WyrmTokens.space8),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: WyrmTokens.space8),
          Text(message),
          if (action != null) Padding(padding: const EdgeInsets.only(top: WyrmTokens.space12), child: action),
        ],
      ),
    ),
  );
}

/// One perceptual property as a labelled bar. The level is also written ("hoch"), not only drawn.
class WyrmToneMetric extends StatelessWidget {
  const WyrmToneMetric({required this.label, required this.value, super.key});
  final String label;

  /// 0..100
  final int value;

  static String word(int v) => v < 20
      ? 'sehr niedrig'
      : v < 40
      ? 'niedrig'
      : v < 60
      ? 'mittel'
      : v < 80
      ? 'hoch'
      : 'sehr hoch';

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: ${word(value)}',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: WyrmTokens.space4),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Expanded(
            flex: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(WyrmTokens.space4),
              child: LinearProgressIndicator(
                value: value.clamp(0, 100) / 100,
                minHeight: 8,
                backgroundColor: WyrmTokens.raised,
                color: WyrmTokens.ember,
              ),
            ),
          ),
          Expanded(flex: 4, child: Text(word(value), textAlign: TextAlign.end, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    ),
  );
}
