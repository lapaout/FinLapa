import 'package:flutter/material.dart';

/// Підтвердження безповоротного видалення дашборда (потрібна точна назва).
Future<bool> showDeleteDashboardDialog(
  BuildContext context, {
  required String dashboardTitle,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _DeleteDashboardDialog(
      dashboardTitle: dashboardTitle,
    ),
  ).then((value) => value == true);
}

class _DeleteDashboardDialog extends StatefulWidget {
  final String dashboardTitle;

  const _DeleteDashboardDialog({required this.dashboardTitle});

  @override
  State<_DeleteDashboardDialog> createState() => _DeleteDashboardDialogState();
}

class _DeleteDashboardDialogState extends State<_DeleteDashboardDialog> {
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

  bool get _canDelete => _controller.text.trim() == widget.dashboardTitle;

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
              'Дашборд «${widget.dashboardTitle}» буде назавжди видалено '
              'разом із Google-таблицею та всіма записами.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Щоб підтвердити, введіть точну назву дашборда:',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.dashboardTitle,
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
