import 'package:flutter/material.dart';

import '../core/dashboard_theme_options.dart';
import '../utils/ui_helpers.dart';
import '../../models/dashboard.dart';

class ModuleBuilderModal extends StatefulWidget {
  final String dashboardType;
  final Future<void> Function(
    String moduleName,
    List<String> fields,
    int iconCode,
    int colorValue,
    bool isWarehouseLinked,
  ) onSave;

  const ModuleBuilderModal({
    super.key,
    required this.onSave,
    this.dashboardType = Dashboard.typeIncome,
  });

  @override
  State<ModuleBuilderModal> createState() => _ModuleBuilderModalState();
}
class _ModuleBuilderModalState extends State<ModuleBuilderModal> {
  bool _isSaving = false;
  bool _isWarehouseLinked = false;

  String _moduleName = "";
  final List<String> _fields = []; 
  final TextEditingController _fieldController = TextEditingController();
  
  IconData _selectedIcon = Icons.monetization_on;
  Color _selectedColor = Colors.green;

  List<IconData> get _iconOptions => DashboardThemeOptions.icons;
  List<Color> get _colorOptions => DashboardThemeOptions.colors;

  final List<String> _suggestedFields = ['Сума', 'Товар', 'Послуга', 'Кількість', '№', 'Нотатки'];

  @override
  void dispose() {
    _fieldController.dispose();
    super.dispose();
  }

  void _showPicker(String title, List<IconData> icons) {
    showFinLapaBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5, 
                  crossAxisSpacing: 15, 
                  mainAxisSpacing: 15,
                ),
                itemCount: icons.length,
                itemBuilder: (context, index) => InkWell(
                  onTap: () {
                    setState(() => _selectedIcon = icons[index]);
                    Navigator.pop(context);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _selectedIcon == icons[index]
                          ? _selectedColor.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icons[index], size: 32, color: _selectedColor),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasMoneyField(List<String> fields) {
    const moneyKeywords = ['сум', 'amount', 'цін', 'варт'];
    return fields.any((field) {
      final lower = field.toLowerCase();
      return moneyKeywords.any((keyword) => lower.contains(keyword));
    });
  }

  List<String> _ensureMoneyField(List<String> fields) {
    if (_hasMoneyField(fields)) {
      return List<String>.from(fields);
    }
    return ['Сума', ...fields];
  }

  List<String> _resolveFieldsToSave() {
    if (widget.dashboardType == Dashboard.typeWarehouse) {
      return Dashboard.buildWarehouseFields(_fields);
    }

    final fields = List<String>.from(_fields);
    if (widget.dashboardType == Dashboard.typeIncome && _isWarehouseLinked) {
      return _ensureMoneyField(fields);
    }
    return fields;
  }

  bool get _canSave {
    if (_moduleName.trim().isEmpty) return false;

    if (widget.dashboardType == Dashboard.typeWarehouse) {
      return true;
    }

    if (widget.dashboardType == Dashboard.typeIncome && _isWarehouseLinked) {
      return true;
    }

    return _fields.isNotEmpty;
  }

  bool get _showWarehouseLinkToggle =>
      widget.dashboardType == Dashboard.typeIncome;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom, 
        left: 24, right: 24, top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Створити джерело", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                GestureDetector(
                  onTap: () => _showPicker("Оберіть іконку", _iconOptions),
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: _selectedColor.withValues(alpha: 0.1),
                    child: Icon(_selectedIcon, color: _selectedColor, size: 30),
                  ),
                ),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text("➔ Клікніть на іконку для вибору"),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _colorOptions.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () => setState(() => _selectedColor = _colorOptions[index]),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: _colorOptions[index],
                      child: _selectedColor == _colorOptions[index] 
                        ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 20),
            TextField(
              decoration: const InputDecoration(labelText: "Назва", border: OutlineInputBorder()),
              onChanged: (val) => setState(() => _moduleName = val),
            ),
            if (_showWarehouseLinkToggle) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(
                  Icons.inventory_2_outlined,
                  color: _isWarehouseLinked ? Colors.teal : Colors.grey,
                ),
                title: const Text('Підключити до складу'),
                subtitle: const Text(
                  'Продажі з цього дашборду будуть прив\'язані до товарів на складі',
                ),
                value: _isWarehouseLinked,
                onChanged: (value) => setState(() => _isWarehouseLinked = value),
              ),
            ],
            const SizedBox(height: 20),
            if (widget.dashboardType == Dashboard.typeWarehouse) ...[
              const Text(
                'Обов\'язкові поля (додаються автоматично):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: Dashboard.warehouseRequiredFields
                    .map(
                      (field) => Chip(
                        label: Text(field, style: const TextStyle(fontSize: 12)),
                        backgroundColor: Colors.grey.shade200,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              const Text(
                'Додаткові поля:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
            ] else
              const Text("Поля таблиці:", style: TextStyle(fontWeight: FontWeight.bold)),
            if (widget.dashboardType != Dashboard.typeWarehouse)
              Wrap(
                spacing: 8,
                children: _suggestedFields.map((f) => ActionChip(
                  label: Text('+ $f'),
                  onPressed: () { if (!_fields.contains(f)) setState(() => _fields.add(f)); },
                )).toList(),
              ),
            if (widget.dashboardType == Dashboard.typeWarehouse)
              Wrap(
                spacing: 8,
                children: _suggestedFields.map((f) => ActionChip(
                  label: Text('+ $f'),
                  onPressed: () {
                    if (!_fields.contains(f) && !Dashboard.warehouseRequiredFields.contains(f)) {
                      setState(() => _fields.add(f));
                    }
                  },
                )).toList(),
              ),
            
            Row(
              children: [
                Expanded(child: TextField(controller: _fieldController, decoration: const InputDecoration(hintText: "Своє поле..."))),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.blueAccent),
                  onPressed: () {
                    final text = _fieldController.text.trim();
                    if (text.isEmpty || _fields.contains(text)) return;
                    if (widget.dashboardType == Dashboard.typeWarehouse &&
                        Dashboard.warehouseRequiredFields.contains(text)) {
                      return;
                    }
                    setState(() {
                      _fields.add(text);
                      _fieldController.clear();
                    });
                  },
                )
              ],
            ),
            
            if (_fields.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 100,
                child: ReorderableListView(
                  shrinkWrap: true,
                  onReorderItem: (oldIdx, newIdx) {
                    setState(() {
                      _fields.insert(newIdx, _fields.removeAt(oldIdx));
                    });
                  },
                  children: _fields.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final field = entry.value;

                    return ListTile(
                      key: ValueKey('${widget.dashboardType}-field-$idx-$field'),
                      title: Text(field, style: const TextStyle(fontSize: 14)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, size: 20, color: Colors.redAccent),
                            tooltip: 'Видалити поле',
                            onPressed: () => setState(() => _fields.removeAt(idx)),
                          ),
                          const Icon(Icons.drag_handle, size: 18),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
            if (!_canSave && _moduleName.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _showWarehouseLinkToggle && !_isWarehouseLinked
                    ? 'Додайте хоча б одне поле для звичайного дашборду'
                    : 'Заповніть назву модуля',
                style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
            
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14), 
                backgroundColor: _selectedColor, 
                foregroundColor: Colors.white,
              ),
              onPressed: (_isSaving || !_canSave)
                  ? null
                  : () async {
                      setState(() => _isSaving = true);
                      try {
                        await widget.onSave(
                          _moduleName.trim(),
                          _resolveFieldsToSave(),
                          _selectedIcon.codePoint,
                          _selectedColor.toARGB32(),
                          _isWarehouseLinked,
                        );
                      } finally {
                        if (mounted) setState(() => _isSaving = false);
                      }
                    },
              child: _isSaving 
                  ? const SizedBox(
                      height: 20, 
                      width: 20, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text("Зберегти модуль"),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
