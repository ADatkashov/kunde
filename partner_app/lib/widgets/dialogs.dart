import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../core/theme.dart';

/// Plain yes/no confirmation. Returns true only on explicit confirmation.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  String? confirmLabel,
}) async {
  final s = S.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: Text(s.back)),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel ?? s.confirm)),
      ],
    ),
  );
  return result == true;
}

/// Asks for a 3–300 character reason; null when dismissed.
Future<String?> reasonDialog(
  BuildContext context, {
  required String title,
  List<String> suggestions = const [],
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(title: title, suggestions: suggestions),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.suggestions});
  final String title;
  final List<String> suggestions;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _valid {
    final n = _c.text.trim().length;
    return n >= 3 && n <= 300;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.suggestions.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: [
                for (final text in widget.suggestions)
                  ActionChip(
                    label: Text(text),
                    onPressed: () => setState(() => _c.text = text),
                  ),
              ]),
            ),
          if (widget.suggestions.isNotEmpty) const SizedBox(height: Gap.md),
          TextField(
            controller: _c,
            maxLength: 300,
            minLines: 2,
            maxLines: 4,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: s.cancelReasonLabel),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(s.back)),
        FilledButton(
          onPressed:
              _valid ? () => Navigator.pop(context, _c.text.trim()) : null,
          child: Text(s.confirm),
        ),
      ],
    );
  }
}

/// Asks for an amount in tenge (0..1 000 000); returns tiyn, or null when dismissed.
Future<int?> amountDialog(BuildContext context,
    {required String title, String? hint}) {
  return showDialog<int>(
      context: context,
      builder: (_) => _AmountDialog(title: title, hint: hint));
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({required this.title, this.hint});
  final String title;
  final String? hint;
  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int? get _tiyn {
    final v = int.tryParse(_c.text.trim());
    return v == null || v < 0 || v > 1000000 ? null : v * 100;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (widget.hint != null) Text(widget.hint!),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _c,
          autofocus: true,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: widget.title,
              errorText:
                  _c.text.isNotEmpty && _tiyn == null ? s.priceInvalid : null),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(s.back)),
        FilledButton(
            onPressed:
                _tiyn == null ? null : () => Navigator.pop(context, _tiyn),
            child: Text(s.confirm)),
      ],
    );
  }
}

/// Shows a short feedback message; replaces any message already visible.
void showToast(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? context.colors.error : null,
    ));
}
