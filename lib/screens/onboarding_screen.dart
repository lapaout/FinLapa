import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/repositories/workspace_repository.dart';
import '../models/finlapa_spreadsheet.dart';
import '../widgets/create_spreadsheet_dialog.dart';

/// Onboarding: перша таблиця або вибір з існуючих у папці FinLapa.
class OnboardingScreen extends StatefulWidget {
  final GoogleSignInAccount user;
  final Future<void> Function(FinLapaSpreadsheet) onComplete;

  const OnboardingScreen({
    super.key,
    required this.user,
    required this.onComplete,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final WorkspaceRepository _workspaceRepository = WorkspaceRepository();

  bool _isLoading = true;
  String? _error;
  List<FinLapaSpreadsheet> _spreadsheets = [];
  bool _isCreating = false;
  bool _autoCreateDialogShown = false;

  @override
  void initState() {
    super.initState();
    _loadSpreadsheets();
  }

  Future<void> _loadSpreadsheets() async {
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

      if (spreadsheets.isEmpty && !_autoCreateDialogShown) {
        _autoCreateDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _promptCreateFirstSpreadsheet();
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _promptCreateFirstSpreadsheet() async {
    final name = await showCreateSpreadsheetDialog(
      context,
      title: 'Ласкаво просимо!',
      message: 'Як назвати вашу першу таблицю?',
      initialName: 'Мої фінанси',
    );

    if (!mounted) return;
    if (name != null && name.trim().isNotEmpty) {
      await _createSpreadsheet(name.trim());
    }
  }

  Future<void> _notifyComplete(FinLapaSpreadsheet spreadsheet) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await widget.onComplete(spreadsheet);
  }

  Future<void> _createSpreadsheet(String name) async {
    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      final spreadsheet = await _workspaceRepository.createWorkspace(
        user: widget.user,
        name: name,
      );
      if (!mounted) return;
      await _notifyComplete(spreadsheet);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isCreating = false;
      });
    }
  }

  Future<void> _selectSpreadsheet(FinLapaSpreadsheet spreadsheet) async {
    setState(() => _isCreating = true);
    try {
      await _workspaceRepository.activateWorkspace(workspace: spreadsheet);
      if (!mounted) return;
      await _notifyComplete(spreadsheet);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isCreating = false;
      });
    }
  }

  Future<void> _createNewFromList() async {
    final name = await showCreateSpreadsheetDialog(context);
    if (!mounted) return;
    if (name == null || name.isEmpty) return;
    await _createSpreadsheet(name);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _isCreating) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                _isCreating ? 'Створення таблиці...' : 'Завантаження таблиць з FinLapa...',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loadSpreadsheets,
                  child: const Text('Спробувати знову'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _spreadsheets.isEmpty
              ? 'Створіть першу таблицю'
              : 'Оберіть робочу таблицю',
        ),
        automaticallyImplyLeading: false,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _spreadsheets.isEmpty ? 1 : _spreadsheets.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (_spreadsheets.isEmpty) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.folder_outlined, size: 40, color: Colors.teal),
                    const SizedBox(height: 12),
                    const Text(
                      'У папці FinLapa ще немає таблиць.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Створіть першу таблицю або натисніть «Скасувати» у діалозі, '
                      'щоб повернутися сюди.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _createNewFromList,
                      icon: const Icon(Icons.add),
                      label: const Text('Створити нову таблицю'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (index == _spreadsheets.length) {
            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.4)),
              ),
              leading: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
              title: const Text(
                '➕ Створити нову таблицю',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onTap: _createNewFromList,
            );
          }

          final spreadsheet = _spreadsheets[index];
          return ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            leading: const Icon(Icons.table_chart_outlined),
            title: Text(spreadsheet.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _selectSpreadsheet(spreadsheet),
          );
        },
      ),
    );
  }
}
