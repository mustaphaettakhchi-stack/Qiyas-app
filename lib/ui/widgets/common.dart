import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/messages.dart';
import '../../data/app_state.dart';
import '../../domain/models.dart';

/// Champ texte qui garde son propre contrôleur (le curseur ne saute pas quand
/// l'état se reconstruit) et se met à jour si la valeur change ailleurs.
class EditField extends StatefulWidget {
  const EditField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.enabled = true,
    this.hint,
    this.maxLength,
    this.inputFormatters,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool enabled;
  final String? hint;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<EditField> createState() => _EditFieldState();
}

class _EditFieldState extends State<EditField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant EditField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        focusNode: _focus,
        enabled: widget.enabled,
        keyboardType: widget.keyboardType,
        maxLines: widget.maxLines,
        maxLength: widget.maxLength,
        inputFormatters: widget.inputFormatters,
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint, counterText: ''),
        onChanged: widget.onChanged,
      );
}

String numInput(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

/// Champ numérique (virgule ou point acceptés), aligné à droite.
class NumField extends StatefulWidget {
  const NumField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.suffix,
    this.decimals = 2,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final String? suffix;
  final int decimals;

  @override
  State<NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<NumField> {
  late final TextEditingController _c = widget.controller ?? TextEditingController(text: _fmt(widget.value));
  late final FocusNode _focus = widget.focusNode ?? FocusNode();

  String _fmt(double v) => v.toStringAsFixed(widget.decimals).replaceAll('.', ',');

  @override
  void didUpdateWidget(covariant NumField old) {
    super.didUpdateWidget(old);
    if (widget.controller == null && !_focus.hasFocus && parseNum(_c.text) != widget.value) {
      _c.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) _c.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        focusNode: _focus,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        textAlign: TextAlign.right,
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix),
        onChanged: (s) {
          final v = parseNum(s);
          if (v != null) widget.onChanged(v);
        },
      );
}

/// Pastille de statut d'un projet ou d'un devis. `null` = relevé en cours, sans devis.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final QuoteStatus? status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg, String label) = switch (status) {
      null => (cs.tertiaryContainer, cs.onTertiaryContainer, 'Relevé en cours'),
      QuoteStatus.draft => (cs.surfaceContainerHighest, cs.onSurfaceVariant, kStatusLabel[status]!),
      QuoteStatus.sent => (cs.primaryContainer, cs.onPrimaryContainer, kStatusLabel[status]!),
      QuoteStatus.accepted => (const Color(0xFFDCEFE3), const Color(0xFF1F6B44), kStatusLabel[status]!),
      QuoteStatus.refused => (cs.errorContainer, cs.onErrorContainer, kStatusLabel[status]!),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

enum AlertKind { info, warning, error }

class AlertBox extends StatelessWidget {
  const AlertBox(this.text, {super.key, this.kind = AlertKind.info, this.action});
  final String text;
  final AlertKind kind;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (kind) {
      AlertKind.info => (cs.primaryContainer, cs.onPrimaryContainer),
      AlertKind.warning => (cs.tertiaryContainer, cs.onTertiaryContainer),
      AlertKind.error => (cs.errorContainer, cs.onErrorContainer),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: TextStyle(color: fg)),
        if (action != null) ...[const SizedBox(height: 8), action!],
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Indicateur de synchronisation affiché dans les barres d'application.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final n = s.unsyncedCount;
    final online = s.data.online;
    final color = online && n == 0 ? const Color(0xFF2F7D55) : const Color(0xFFB5651D);
    final label = !online ? 'Hors connexion' : (n == 0 ? 'Synchronisé' : '$n à synchroniser');
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 9, color: color),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Confirmer'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r ?? false;
}
