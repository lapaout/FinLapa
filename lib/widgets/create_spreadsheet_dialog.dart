import 'package:flutter/material.dart';

/// Діалог введення назви нової Google-таблиці.
Future<String?> showCreateSpreadsheetDialog(
  BuildContext context, {
  String title = 'Нова таблиця',
  String? message,
  String initialName = '',
  bool barrierDismissible = true,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => _CreateSpreadsheetDialog(
      title: title,
      message: message,
      initialName: initialName,
    ),
  );
}

class _CreateSpreadsheetDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String initialName;

  const _CreateSpreadsheetDialog({
    required this.title,
    this.message,
    required this.initialName,
  });

  @override
  State<_CreateSpreadsheetDialog> createState() => _CreateSpreadsheetDialogState();
}

class _CreateSpreadsheetDialogState extends State<_CreateSpreadsheetDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Назва таблиці',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Створити'),
        ),
      ],
    );
  }
}
