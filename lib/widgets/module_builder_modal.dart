import 'package:flutter/material.dart';

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

  // ВЕЛИЧЕЗНА БІБЛІОТЕКА ІКОНОК (100 штук на всі випадки життя)
  final List<IconData> _iconOptions = [
    // Фінанси та Гроші
    Icons.monetization_on, Icons.attach_money, Icons.euro, Icons.currency_pound, Icons.currency_bitcoin,
    Icons.account_balance, Icons.account_balance_wallet, Icons.savings, Icons.credit_card, Icons.receipt,
    // Торгівля та Магазин
    Icons.shopping_cart, Icons.shopping_basket, Icons.shopping_bag, Icons.storefront, Icons.local_shipping,
    Icons.local_mall, Icons.sell, Icons.price_check, Icons.loyalty, Icons.card_giftcard,
    // Робота та Аналітика
    Icons.work, Icons.business_center, Icons.cases, Icons.assignment, Icons.folder,
    Icons.description, Icons.analytics, Icons.trending_up, Icons.pie_chart, Icons.bar_chart,
    // Техніка та Ігри (3D друк, Nintendo)
    Icons.computer, Icons.laptop, Icons.smartphone, Icons.tablet_mac, Icons.watch,
    Icons.sports_esports, Icons.gamepad, Icons.memory, Icons.mouse, Icons.keyboard,
    Icons.print, Icons.camera_alt, Icons.headphones, Icons.speaker, Icons.tv,
    // Авто та Ремонт (Склад тата)
    Icons.directions_car, Icons.local_taxi, Icons.two_wheeler, Icons.pedal_bike, Icons.flight,
    Icons.local_gas_station, Icons.build, Icons.handyman, Icons.construction, Icons.tire_repair,
    // Предмети та Інвентар
    Icons.inventory_2, Icons.layers, Icons.category, Icons.extension, Icons.toys,
    Icons.chair, Icons.bed, Icons.checkroom, Icons.watch, Icons.diamond,
    // Їжа та Напої
    Icons.restaurant, Icons.local_cafe, Icons.local_pizza, Icons.fastfood, Icons.local_bar,
    Icons.cake, Icons.bakery_dining, Icons.apple, Icons.liquor, Icons.emoji_food_beverage,
    // Нерухомість та Дім
    Icons.home, Icons.house, Icons.apartment, Icons.domain, Icons.key,
    // Життя, Хобі, Спорт
    Icons.favorite, Icons.health_and_safety, Icons.medical_services, Icons.fitness_center, Icons.sports_soccer,
    Icons.pets, Icons.school, Icons.menu_book, Icons.music_note, Icons.palette,
    // Абстрактні та Інтерфейс
    Icons.star, Icons.bolt, Icons.flash_on, Icons.lightbulb, Icons.notifications,
    Icons.push_pin, Icons.bookmark, Icons.label, Icons.flag, Icons.shield
  ];

  final List<Color> _colorOptions = [
    Colors.green, Colors.blue, Colors.amber, 
    Colors.purple, Colors.redAccent, Colors.teal, Colors.black,
    Colors.indigo, Colors.orange, Colors.pinkAccent
  ];

  final List<String> _suggestedFields = ['Сума', 'Товар', 'Послуга', 'Кількість', '№', 'Нотатки'];

  @override
  void dispose() {
    _fieldController.dispose();
    super.dispose();
  }

  // Оновлене вікно вибору іконок (високе, зі скролом)
  void _showPicker(String title, List<IconData> icons) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Дозволяємо вікну бути великим
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.7, // Займає 70% екрану, щоб було зручно гортати 100 іконок
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Оберіть іконку", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5, 
                  crossAxisSpacing: 15, 
                  mainAxisSpacing: 15
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
                      color: _selectedIcon == icons[index] ? _selectedColor.withOpacity(0.2) : Colors.transparent,
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
        left: 24, right: 24, top: 24
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
                    backgroundColor: _selectedColor.withOpacity(0.1),
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
                separatorBuilder: (_, __) => const SizedBox(width: 10),
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
                  onReorder: (oldIdx, newIdx) {
                    setState(() {
                      if (newIdx > oldIdx) newIdx -= 1;
                      _fields.insert(newIdx, _fields.removeAt(oldIdx));
                    });
                  },
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
                foregroundColor: Colors.white
              ),
              onPressed: (_isSaving || !_canSave)
                  ? null
                  : () async {
                      setState(() => _isSaving = true);

                      await widget.onSave(
                        _moduleName.trim(),
                        _resolveFieldsToSave(),
                        _selectedIcon.codePoint,
                        _selectedColor.value,
                        _isWarehouseLinked,
                      );
                    },
              // Змінюємо текст на крутилку, якщо йде збереження
              child: _isSaving 
                  ? const SizedBox(
                      height: 20, 
                      width: 20, 
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
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