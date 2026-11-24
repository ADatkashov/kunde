import 'package:flutter/material.dart';

class EducationTextDialog extends StatefulWidget {
  const EducationTextDialog(
      {required this.title, required this.maxLength, super.key});

  final String title;
  final int maxLength;

  @override
  State<EducationTextDialog> createState() => _EducationTextDialogState();
}

class _EducationTextDialogState extends State<EducationTextDialog> {
  String _text = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          autofocus: true,
          maxLength: widget.maxLength,
          minLines: 3,
          maxLines: 5,
          onChanged: (value) => setState(() => _text = value.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel)),
          FilledButton(
              onPressed:
                  _text.isEmpty ? null : () => Navigator.pop(context, _text),
              child: Text(MaterialLocalizations.of(context).okButtonLabel)),
        ],
      );
}
