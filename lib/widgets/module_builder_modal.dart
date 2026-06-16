import 'package:flutter/material.dart';

class ModuleBuilderModal extends StatefulWidget {
  final Function(String moduleName, List<String> fields, int iconCode, int colorValue) onSave;

  const ModuleBuilderModal({super.key, required this.onSave});

  @override
  State<ModuleBuilderModal> createState() => _ModuleBuilderModalState();
}

class _ModuleBuilderModalState extends State<ModuleBuilderModal> {
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
    Colors.green, Colors.blue, Colors.orange, 
    Colors.purple, Colors.redAccent, Colors.teal, 
    Colors.indigo, Colors.amber, Colors.pinkAccent
  ];

  final List<String> _suggestedFields = ['Сума', 'Товар', 'Послуга', 'Кількість', 'Нотатки'];

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
                const Text("➔ Клікніть на іконку для вибору"),
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
              onChanged: (val) => _moduleName = val,
            ),
            const SizedBox(height: 20),
            
            const Text("Поля таблиці:", style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 8,
              children: _suggestedFields.map((f) => ActionChip(
                label: Text('+ $f'),
                onPressed: () { if (!_fields.contains(f)) setState(() => _fields.add(f)); },
              )).toList(),
            ),
            
            Row(
              children: [
                Expanded(child: TextField(controller: _fieldController, decoration: const InputDecoration(hintText: "Своє поле..."))),
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
            
            const SizedBox(height: 10),
            SizedBox(
              height: 100,
              child: ReorderableListView(
                shrinkWrap: true,
                children: _fields.map((f) => ListTile(
                  key: ValueKey(f),
                  title: Text(f, style: const TextStyle(fontSize: 14)),
                  trailing: const Icon(Icons.drag_handle, size: 18),
                )).toList(),
                onReorder: (oldIdx, newIdx) {
                  setState(() {
                    if (newIdx > oldIdx) newIdx -= 1;
                    _fields.insert(newIdx, _fields.removeAt(oldIdx));
                  });
                },
              ),
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
              child: const Text("Зберегти модуль"),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}