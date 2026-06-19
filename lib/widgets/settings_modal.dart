import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/repositories/settings_repository.dart';
import '../models/module_type.dart';

class SettingsModal extends StatefulWidget {
  final GoogleSignIn googleSignIn;
  final SettingsRepository settingsRepository;
  final bool initialIncome;
  final bool initialExpense;
  final bool initialWarehouse;
  final VoidCallback onSettingsChanged;

  const SettingsModal({
    super.key,
    required this.googleSignIn,
    required this.settingsRepository,
    required this.initialIncome,
    required this.initialExpense,
    required this.initialWarehouse,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsModal> createState() => _SettingsModalState();
}

class _SettingsModalState extends State<SettingsModal> {
  late bool _showIncome;
  late bool _showExpense;
  late bool _showWarehouse;

  @override
  void initState() {
    super.initState();
    _showIncome = widget.initialIncome;
    _showExpense = widget.initialExpense;
    _showWarehouse = widget.initialWarehouse;
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
          const Divider(height: 30),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            icon: const Icon(Icons.logout),
            label: const Text("Вийти з акаунта"),
            onPressed: () {
              Navigator.pop(context);
              widget.googleSignIn.signOut();
            },
          ),
        ],
      ),
    );
  }
}
