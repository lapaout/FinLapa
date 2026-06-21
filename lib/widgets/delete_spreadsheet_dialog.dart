import 'package:flutter/material.dart';

/// Підтвердження безповоротного видалення таблиці (потрібна точна назва).
Future<bool> showDeleteSpreadsheetDialog(
  BuildContext context, {
  required String spreadsheetName,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _DeleteSpreadsheetDialog(
      spreadsheetName: spreadsheetName,
    ),
  ).then((value) => value == true);
}

class _DeleteSpreadsheetDialog extends StatefulWidget {
  final String spreadsheetName;

  const _DeleteSpreadsheetDialog({required this.spreadsheetName});

  @override
  State<_DeleteSpreadsheetDialog> createState() => _DeleteSpreadsheetDialogState();
}

class _DeleteSpreadsheetDialogState extends State<_DeleteSpreadsheetDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canDelete => _controller.text.trim() == widget.spreadsheetName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Увага: безповоротна дія'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Таблицю «${widget.spreadsheetName}» буде назавжди видалено з Google Drive.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Щоб підтвердити, введіть точну назву таблиці:',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.spreadsheetName,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.redAccent,
            disabledBackgroundColor: Colors.redAccent.withOpacity(0.4),
          ),
          onPressed: _canDelete ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Видалити'),
        ),
      ],
    );
  }
}
