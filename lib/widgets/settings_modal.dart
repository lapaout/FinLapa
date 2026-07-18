import 'package:flutter/material.dart';

import '../data/repositories/settings_repository.dart';
import '../data/repositories/workspace_repository.dart';
import '../data/sources/google_api_auth.dart';
import '../models/module_type.dart';

class SettingsModal extends StatefulWidget {
  final SettingsRepository settingsRepository;  final bool initialIncome;
  final bool initialExpense;
  final bool initialWarehouse;
  final bool initialAnalytics;
  final VoidCallback onSettingsChanged;

  const SettingsModal({
    super.key,
    required this.settingsRepository,    required this.initialIncome,
    required this.initialExpense,
    required this.initialWarehouse,
    required this.initialAnalytics,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  late bool _showIncome;
  late bool _showExpense;
  late bool _showWarehouse;
  late bool _showAnalytics;

  @override
  void initState() {
    super.initState();
    _showIncome = widget.initialIncome;
    _showExpense = widget.initialExpense;
    _showWarehouse = widget.initialWarehouse;
    _showAnalytics = widget.initialAnalytics;
  }

  Future<void> _toggleModule(ModuleType type, bool enabled) async {
    await widget.settingsRepository.setModuleEnabled(type, enabled);
    widget.onSettingsChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Модулі системи",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text("Доходи"),
            secondary: const Icon(Icons.trending_up, color: Colors.green),
            value: _showIncome,
            onChanged: (val) {
              setState(() => _showIncome = val);
              _toggleModule(ModuleType.income, val);
            },
          ),
          SwitchListTile(
            title: const Text("Витрати"),
            secondary: const Icon(Icons.trending_down, color: Colors.redAccent),
            value: _showExpense,
            onChanged: (val) {
              setState(() => _showExpense = val);
              _toggleModule(ModuleType.expense, val);
            },
          ),
          SwitchListTile(
            title: const Text("Склад"),
            secondary: const Icon(Icons.inventory_2, color: Colors.orange),
            value: _showWarehouse,
            onChanged: (val) {
              setState(() => _showWarehouse = val);
              _toggleModule(ModuleType.warehouse, val);
            },
          ),
          SwitchListTile(
            title: const Text("Аналітика"),
            secondary: const Icon(Icons.analytics, color: Colors.blueAccent),
            value: _showAnalytics,
            onChanged: (val) {
              setState(() => _showAnalytics = val);
              _toggleModule(ModuleType.analytics, val);
            },
          ),
          const Divider(height: 30),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            icon: const Icon(Icons.logout),
            label: const Text("Вийти з акаунта"),
            onPressed: () async {
              Navigator.pop(context);
              await WorkspaceRepository().clearSessionOnLogout();
              await GoogleApiAuth.disconnect();
            },
          ),
        ],
      ),
    );
  }
}
