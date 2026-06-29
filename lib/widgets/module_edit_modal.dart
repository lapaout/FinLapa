import 'package:flutter/material.dart';

import 'warehouse_linked_info_banner.dart';

class ModuleEditModal extends StatefulWidget {
  final Map<String, dynamic> initialDashboard;
  final Function(String moduleName, List<String> fields, int iconCode, int colorValue) onSave;

  const ModuleEditModal({super.key, required this.initialDashboard, required this.onSave});

  @override
  State<ModuleEditModal> createState() => _ModuleEditModalState();
}

class _ModuleEditModalState extends State<ModuleEditModal> {
  late TextEditingController _nameController;
  final TextEditingController _fieldController = TextEditingController();
  
  late String _moduleName;
  late IconData _selectedIcon;
  late Color _selectedColor;
  
  final List<String> _fields = []; 
  int _lockedFieldsCount = 0; // Скільки полів не можна чіпати

  // ВЕЛИЧЕЗНА БІБЛІОТЕКА ІКОНОК (як у твоєму коді)
  final List<IconData> _iconOptions = [
    Icons.monetization_on, Icons.attach_money, Icons.euro, Icons.currency_pound, Icons.currency_bitcoin,
    Icons.account_balance, Icons.account_balance_wallet, Icons.savings, Icons.credit_card, Icons.receipt,
    Icons.shopping_cart, Icons.shopping_basket, Icons.shopping_bag, Icons.storefront, Icons.local_shipping,
    Icons.local_mall, Icons.sell, Icons.price_check, Icons.loyalty, Icons.card_giftcard,
    Icons.work, Icons.business_center, Icons.cases, Icons.assignment, Icons.folder,
    Icons.description, Icons.analytics, Icons.trending_up, Icons.pie_chart, Icons.bar_chart,
    Icons.computer, Icons.laptop, Icons.smartphone, Icons.tablet_mac, Icons.watch,
    Icons.sports_esports, Icons.gamepad, Icons.memory, Icons.mouse, Icons.keyboard,
    Icons.print, Icons.camera_alt, Icons.headphones, Icons.speaker, Icons.tv,
    Icons.directions_car, Icons.local_taxi, Icons.two_wheeler, Icons.pedal_bike, Icons.flight,
    Icons.local_gas_station, Icons.build, Icons.handyman, Icons.construction, Icons.tire_repair,
    Icons.inventory_2, Icons.layers, Icons.category, Icons.extension, Icons.toys,
    Icons.chair, Icons.bed, Icons.checkroom, Icons.watch, Icons.diamond,
    Icons.restaurant, Icons.local_cafe, Icons.local_pizza, Icons.fastfood, Icons.local_bar,
    Icons.cake, Icons.bakery_dining, Icons.apple, Icons.liquor, Icons.emoji_food_beverage,
    Icons.home, Icons.house, Icons.apartment, Icons.domain, Icons.key,
    Icons.favorite, Icons.health_and_safety, Icons.medical_services, Icons.fitness_center, Icons.sports_soccer,
    Icons.pets, Icons.school, Icons.menu_book, Icons.music_note, Icons.palette,
    Icons.star, Icons.bolt, Icons.flash_on, Icons.lightbulb, Icons.notifications,
    Icons.push_pin, Icons.bookmark, Icons.label, Icons.flag, Icons.shield
  ];

  final List<Color> _colorOptions = [
    Colors.green, Colors.blue, Colors.amber, 
    Colors.purple, Colors.redAccent, Colors.teal, Colors.black,
    Colors.indigo, Colors.orange, Colors.pinkAccent
  ];

  @override
  void initState() {
    super.initState();
    // Підтягуємо існуючі дані
    _moduleName = widget.initialDashboard['title'];
    _nameController = TextEditingController(text: _moduleName);
    
    _selectedIcon = IconData(widget.initialDashboard['icon'] ?? Icons.dashboard.codePoint, fontFamily: 'MaterialIcons');
    _selectedColor = Color(widget.initialDashboard['color'] ?? Colors.green.value);
    
    _fields.addAll(List<String>.from(widget.initialDashboard['fields']));
    _lockedFieldsCount = _fields.length; // Запам'ятовуємо, скільки полів було спочатку
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fieldController.dispose();
    super.dispose();
  }

  void _showPicker(String title, List<IconData> icons) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                  crossAxisCount: 5, crossAxisSpacing: 15, mainAxisSpacing: 15
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

  bool get _isWarehouseLinked =>
      widget.initialDashboard['isWarehouseLinked'] == true;

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
            const Text("Налаштування модуля", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            if (_isWarehouseLinked) ...[
              const SizedBox(height: 12),
              const WarehouseLinkedInfoBanner(),
            ],
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
                  child: Text("➔ Клікніть для зміни"),
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
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Назва модуля", border: OutlineInputBorder()),
              onChanged: (val) => _moduleName = val,
            ),
            const SizedBox(height: 20),
            
            const Text("Поля таблиці:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            // Список полів (старі з замочком, нові з корзиною)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: _fields.asMap().entries.map((entry) {
                  int idx = entry.key;
                  String field = entry.value;
                  bool isLocked = idx < _lockedFieldsCount;

                  return ListTile(
                    dense: true,
                    title: Text(field, style: TextStyle(color: isLocked ? Colors.grey.shade700 : Colors.black, fontWeight: isLocked ? FontWeight.normal : FontWeight.bold)),
                    trailing: isLocked
                        ? const Icon(Icons.lock_outline, size: 18, color: Colors.grey)
                        : IconButton(
                            icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                            tooltip: 'Видалити поле',
                            onPressed: () => setState(() => _fields.removeAt(idx)),
                          ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            
            Row(
              children: [
                Expanded(child: TextField(controller: _fieldController, decoration: const InputDecoration(hintText: "Додати нове поле..."))),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.blueAccent),
                  onPressed: () {
                    final text = _fieldController.text.trim();
                    if (text.isNotEmpty && !_fields.contains(text)) {
                      setState(() { _fields.add(text); _fieldController.clear(); });
                    }
                  },
                )
              ],
            ),
            
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14), 
                backgroundColor: _selectedColor, 
                foregroundColor: Colors.white
              ),
              onPressed: () {
                if (_moduleName.isNotEmpty && _fields.isNotEmpty) {
                  widget.onSave(_moduleName, _fields, _selectedIcon.codePoint, _selectedColor.value);
                }
              },
              child: const Text("Зберегти зміни"),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}