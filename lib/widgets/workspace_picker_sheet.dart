import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/repositories/workspace_repository.dart';
import '../models/finlapa_spreadsheet.dart';
import 'create_spreadsheet_dialog.dart';
import 'delete_spreadsheet_dialog.dart';

/// Bottom sheet для перемикання між таблицями FinLapa.
class WorkspacePickerSheet extends StatefulWidget {
  final GoogleSignInAccount user;
  final String activeSpreadsheetId;
  final ValueChanged<FinLapaSpreadsheet> onSelected;
  final VoidCallback? onActiveWorkspaceDeleted;
  final Future<FinLapaSpreadsheet> Function(String name)? onCreate;

  const WorkspacePickerSheet({
    super.key,
    required this.user,
    required this.activeSpreadsheetId,
    required this.onSelected,
    this.onActiveWorkspaceDeleted,
    this.onCreate,
  });

  @override
  State<WorkspacePickerSheet> createState() => _WorkspacePickerSheetState();
}

class _WorkspacePickerSheetState extends State<WorkspacePickerSheet> {
  final WorkspaceRepository _workspaceRepository = WorkspaceRepository();

  bool _isLoading = true;
  bool _isDeleting = false;
  String? _error;
  List<FinLapaSpreadsheet> _spreadsheets = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final spreadsheets =
          await _workspaceRepository.listWorkspaces(user: widget.user);
      if (!mounted) return;
      setState(() {
        _spreadsheets = spreadsheets;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _notifySelected(FinLapaSpreadsheet spreadsheet) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSelected(spreadsheet);
    });
  }

  Future<void> _createNew() async {
    final name = await showCreateSpreadsheetDialog(context);
    if (!mounted) return;
    if (name == null || name.isEmpty) return;

    Navigator.of(context).pop();

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    try {
      final spreadsheet = widget.onCreate != null
          ? await widget.onCreate!(name)
          : await _workspaceRepository.createWorkspace(
              user: widget.user,
              name: name,
            );
      if (!mounted) return;
      await _notifySelected(spreadsheet);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка створення: $error')),
      );
    }
  }

  Future<void> _confirmDelete(FinLapaSpreadsheet spreadsheet) async {
    final confirmed = await showDeleteSpreadsheetDialog(
      context,
      spreadsheetName: spreadsheet.name,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      final wasActive = await _workspaceRepository.deleteWorkspace(
        user: widget.user,
        workspace: spreadsheet,
      );

      if (!mounted) return;

      if (wasActive) {
        Navigator.of(context).pop();
        await Future<void>.delayed(Duration.zero);
        widget.onActiveWorkspaceDeleted?.call();
        return;
      }

      setState(() {
        _spreadsheets =
            _spreadsheets.where((item) => item.id != spreadsheet.id).toList();
        _isDeleting = false;
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка видалення: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Робочі таблиці',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Усі таблиці зберігаються в папці FinLapa на Google Drive',
            style: TextStyle(fontSize: 13, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_isLoading || _isDeleting)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (_isDeleting) ...[
                      const SizedBox(height: 12),
                      const Text('Видалення таблиці...'),
                    ],
                  ],
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, textAlign: TextAlign.center),
            )
          else ...[
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _spreadsheets.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final spreadsheet = _spreadsheets[index];
                  final isActive = spreadsheet.id == widget.activeSpreadsheetId;

                  return ListTile(
                    leading: Icon(
                      isActive ? Icons.check_circle : Icons.table_chart_outlined,
                      color: isActive ? Colors.green : null,
                    ),
                    title: Text(
                      spreadsheet.name,
                      style: TextStyle(
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: isActive ? const Text('Активна') : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      tooltip: 'Видалити таблицю',
                      onPressed: () => _confirmDelete(spreadsheet),
                    ),
                    onTap: isActive
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            _notifySelected(spreadsheet);
                          },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
              title: const Text(
                '➕ Створити нову таблицю',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: _createNew,
            ),
          ],
        ],
      ),
    );
  }
}
