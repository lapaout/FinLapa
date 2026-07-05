import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import '../core/warehouse_analytics.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/sheet_records_repository.dart';
import '../models/dashboard.dart';

class _WarehousePickerItem {
  final String dateTime;
  final String name;
  final String dashboardTitle;

  const _WarehousePickerItem({
    required this.dateTime,
    required this.name,
    required this.dashboardTitle,
  });
}

class DataEntryModal extends StatefulWidget {
  static const String amountFieldName = 'Сума';

  final String title;
  final List<String> fields;
  final Future<void> Function(
    List<String> values, {
    Map<String, String>? extraFields,
    String? recordDateTime,
  }) onSave;
  final bool isSending;
  final bool isWarehouseLinked;
  final GoogleSignInAccount? user;
  final DashboardRepository? dashboardRepository;
  final SheetRecordsRepository? recordsRepository;

  const DataEntryModal({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
    required this.isSending,
    this.isWarehouseLinked = false,
    this.user,
    this.dashboardRepository,
    this.recordsRepository,
  });

  @override
  State<DataEntryModal> createState() => _DataEntryModalState();
}

class _DataEntryModalState extends State<DataEntryModal> {
  late Map<String, TextEditingController> _controllers;
  final TextEditingController _soldQuantityController = TextEditingController();

  bool _isLoadingWarehouseItems = false;
  bool _isSaving = false;
  List<_WarehousePickerItem> _warehouseItems = [];
  String? _selectedWarehouseTitle;
  String? _selectedWarehouseItemId;
  List<Map<String, dynamic>> _cartItems = [];

  List<String> get _warehouseTitles => _warehouseItems
      .map((item) => item.dashboardTitle)
      .toSet()
      .toList()
    ..sort();

  List<_WarehousePickerItem> get _itemsForSelectedWarehouse => _selectedWarehouseTitle == null
      ? const []
      : _warehouseItems
          .where((item) => item.dashboardTitle == _selectedWarehouseTitle)
          .toList();

  String? get _orderNumberFieldKey {
    for (final field in widget.fields) {
      if (field.toLowerCase().contains('номер замовлення')) {
        return field;
      }
    }
    return null;
  }

  bool _isMoneyFieldName(String field) {
    final normalized = field.toLowerCase();
    return normalized.contains('сум') ||
        normalized.contains('amount') ||
        normalized.contains('цін') ||
        normalized.contains('варт');
  }

  bool _isQuantityFieldName(String field) {
    final normalized = field.toLowerCase();
    return normalized.contains('к-сть') || normalized.contains('кількість');
  }

  bool _isDateFieldName(String field) {
    final normalized = field.toLowerCase();
    return normalized.contains('дата') || normalized.contains('date');
  }

  bool _isNoteFieldName(String field) {
    final normalized = field.toLowerCase();
    return normalized.contains('нотат') ||
        normalized.contains('note') ||
        normalized.contains('комент') ||
        normalized.contains('опис');
  }

  bool _isNameOrCategoryField(String field) {
    final normalized = field.toLowerCase();
    return normalized.contains('назв') ||
        normalized.contains('категор') ||
        normalized.contains('category') ||
        normalized == 'назва';
  }

  bool _shouldKeepAfterAddToCart(String field) {
    if (field == _orderNumberFieldKey) return true;
    if (_isMoneyFieldName(field)) return true;
    if (_isQuantityFieldName(field)) return true;
    if (_isDateFieldName(field)) return true;
    return false;
  }

  Map<String, String> _readAllFieldValuesFromUi() {
    return {
      for (final field in widget.fields) field: _controllers[field]!.text.trim(),
    };
  }

  Map<String, String>? _readExtraFieldsFromUi() {
    if (!widget.isWarehouseLinked || _selectedWarehouseItemId == null) {
      return null;
    }

    final selectedItem = _itemsForSelectedWarehouse.firstWhere(
      (entry) => entry.dateTime == _selectedWarehouseItemId,
    );

    return {
      'ID товару (приховано)': _selectedWarehouseItemId!,
      'Продано (шт)': _soldQuantityController.text.trim(),
      'Товар зі складу': '[$_selectedWarehouseTitle] ${selectedItem.name}',
    };
  }

  Map<String, dynamic> _captureFormSnapshot() {
    return {
      'fields': _readAllFieldValuesFromUi(),
      if (_readExtraFieldsFromUi() case final extraFields?)
        'extraFields': extraFields,
    };
  }

  Map<String, dynamic> _cloneCartItem(Map<String, dynamic> item) {
    return {
      'fields': Map<String, String>.from(item['fields'] as Map<String, dynamic>),
      if (item['extraFields'] != null)
        'extraFields': Map<String, String>.from(
          item['extraFields'] as Map<String, dynamic>,
        ),
    };
  }

  String? get _moneyFieldKey {
    for (final field in widget.fields) {
      if (_isMoneyFieldName(field)) {
        return field;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (var field in widget.fields) field: TextEditingController(),
    };

    if (widget.isWarehouseLinked) {
      _loadWarehouseItems();
    }
  }

  Future<void> _loadWarehouseItems() async {
    final user = widget.user;
    final dashboardRepository = widget.dashboardRepository;
    final recordsRepository = widget.recordsRepository;

    if (user == null || dashboardRepository == null || recordsRepository == null) {
      return;
    }

    setState(() => _isLoadingWarehouseItems = true);

    try {
      final dashboardsResult = await dashboardRepository.getDashboards(user: user);
      final warehouseDashboards = dashboardsResult.data
          .where(
            (dashboard) =>
                dashboard.type == Dashboard.typeWarehouse && !dashboard.isArchived,
          )
          .toList();

      final items = <_WarehousePickerItem>[];

      for (final warehouseDashboard in warehouseDashboards) {
        final recordsResult = await recordsRepository.getRecords(
          user: user,
          sheetTitle: warehouseDashboard.title,
        );

        final nameFieldIndex = warehouseDashboard.fields.indexOf('Назва');
        if (nameFieldIndex == -1) continue;

        final valueIndex = nameFieldIndex + 1;

        for (final record in recordsResult.data) {
          final dateTime = record.dateTime;
          if (dateTime == null || dateTime.isEmpty) continue;
          if (record.values.length <= valueIndex) continue;

          final name = record.values[valueIndex].trim();
          if (name.isEmpty) continue;

          items.add(
            _WarehousePickerItem(
              dateTime: dateTime.trim(),
              name: name,
              dashboardTitle: warehouseDashboard.title,
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _warehouseItems = items;
        _isLoadingWarehouseItems = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingWarehouseItems = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _soldQuantityController.dispose();
    super.dispose();
  }

  bool _isNumericField(String field) {
    return _isMoneyFieldName(field) || _isQuantityFieldName(field);
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
      ),
    );
  }

  num? _parsePositiveNumber(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return num.tryParse(trimmed.replaceAll(',', '.'));
  }

  bool _validateWarehouseEntry() {
    if (_selectedWarehouseTitle == null) {
      _showValidationError('Оберіть склад!');
      return false;
    }

    if (_selectedWarehouseItemId == null) {
      _showValidationError('Оберіть товар зі складу!');
      return false;
    }

    final quantity = _parsePositiveNumber(_soldQuantityController.text);
    if (quantity == null || quantity <= 0) {
      _showValidationError('Вкажіть кількість більше 0');
      return false;
    }

    final moneyFieldKey = _moneyFieldKey;
    if (moneyFieldKey == null) {
      _showValidationError('Вкажіть суму більше 0');
      return false;
    }

    final amount = _parsePositiveNumber(_controllers[moneyFieldKey]!.text);
    if (amount == null || amount <= 0) {
      _showValidationError('Вкажіть суму більше 0');
      return false;
    }

    return true;
  }

  bool _validateGenericEntry() {
    final moneyKey = _moneyFieldKey;
    if (moneyKey != null) {
      final amount = _parsePositiveNumber(_controllers[moneyKey]!.text);
      if (amount == null || amount <= 0) {
        _showValidationError('Вкажіть суму більше 0');
        return false;
      }
    }

    for (final field in widget.fields) {
      if (_isNameOrCategoryField(field) && _controllers[field]!.text.trim().isEmpty) {
        _showValidationError('Заповніть поле "$field"');
        return false;
      }

      if (_isQuantityFieldName(field)) {
        final parsed = _parsePositiveNumber(_controllers[field]!.text);
        if (parsed == null || parsed <= 0) {
          _showValidationError('Перевірте значення поля "$field"');
          return false;
        }
      }

      if (_isDateFieldName(field) && _controllers[field]!.text.trim().isEmpty) {
        _showValidationError('Заповніть поле "$field"');
        return false;
      }
    }

    return true;
  }

  bool _validateEntry() {
    if (widget.isWarehouseLinked) {
      return _validateWarehouseEntry();
    }
    return _validateGenericEntry();
  }

  Map<String, dynamic>? _buildCartItemFromForm() {
    if (!_validateEntry()) return null;
    return _captureFormSnapshot();
  }

  String _cartChipLabel(Map<String, dynamic> item) {
    final parts = <String>[];
    final fields = Map<String, String>.from(item['fields'] as Map<String, dynamic>);

    for (final field in widget.fields) {
      final value = fields[field]?.trim() ?? '';
      if (value.isEmpty) continue;
      parts.add(_isMoneyFieldName(field) ? '$value ₴' : value);
    }

    final extraFields = item['extraFields'];
    if (extraFields is Map) {
      final warehouseItem = extraFields['Товар зі складу']?.toString().trim() ?? '';
      if (warehouseItem.isNotEmpty && !parts.contains(warehouseItem)) {
        parts.insert(0, warehouseItem);
      }

      final soldQuantity = extraFields['Продано (шт)']?.toString().trim() ?? '';
      if (soldQuantity.isNotEmpty) {
        parts.add('$soldQuantity шт');
      }
    }

    return parts.isEmpty ? 'Запис' : parts.join(' • ');
  }

  void _clearFieldsAfterAddToCart() {
    for (final field in widget.fields) {
      if (_shouldKeepAfterAddToCart(field)) continue;

      if (_isNameOrCategoryField(field) ||
          _isNoteFieldName(field) ||
          (!_isNumericField(field) && !_isDateFieldName(field))) {
        _controllers[field]!.clear();
      }
    }
  }

  void _handleAddToCart() {
    final item = _buildCartItemFromForm();
    if (item == null) return;

    setState(() {
      _cartItems.add(_cloneCartItem(item));
      _clearFieldsAfterAddToCart();
    });
  }

  List<String> _valuesFromCartItem(Map<String, dynamic> cartItem) {
    final fields = Map<String, String>.from(cartItem['fields'] as Map<String, dynamic>);
    return widget.fields.map((field) => fields[field] ?? '').toList();
  }

  Map<String, String>? _extraFieldsFromCartItem(Map<String, dynamic> cartItem) {
    final extraFields = cartItem['extraFields'];
    if (extraFields == null) return null;
    return Map<String, String>.from(extraFields as Map<String, dynamic>);
  }

  String _formatRecordDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
  }

  Future<void> _handleSave() async {
    if (_isSaving || widget.isSending) return;

    setState(() => _isSaving = true);

    try {
      final itemsToSave = _cartItems.map(_cloneCartItem).toList();

      final pendingItem = _buildCartItemFromForm();
      if (pendingItem != null) {
        itemsToSave.add(pendingItem);
      }

      if (itemsToSave.isEmpty) return;

      final baseTime = DateTime.now();

      for (var index = 0; index < itemsToSave.length; index++) {
        final cartItem = itemsToSave[index];
        final itemTime = itemsToSave.length > 1
            ? baseTime.add(Duration(seconds: index))
            : DateTime.now();
        final uniqueId = _formatRecordDateTime(itemTime);

        await widget.onSave(
          _valuesFromCartItem(cartItem),
          extraFields: _extraFieldsFromCartItem(cartItem),
          recordDateTime: uniqueId,
        );
      }

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildCartSection() {
    if (_cartItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(_cartItems.length, (index) {
          return InputChip(
            label: Text(_cartChipLabel(_cartItems[index])),
            onDeleted: () {
              setState(() => _cartItems.removeAt(index));
            },
          );
        }),
      ),
    );
  }

  Widget _buildWarehouseSection() {
    if (_isLoadingWarehouseItems) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          value: _warehouseTitles.contains(_selectedWarehouseTitle)
              ? _selectedWarehouseTitle
              : null,
          decoration: const InputDecoration(
            labelText: 'Оберіть склад',
            border: OutlineInputBorder(),
          ),
          hint: const Text('Оберіть склад'),
          isExpanded: true,
          items: _warehouseTitles
              .map(
                (title) => DropdownMenuItem<String?>(
                  value: title,
                  child: Text(title),
                ),
              )
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedWarehouseTitle = value;
              _selectedWarehouseItemId = null;
              _soldQuantityController.clear();
            });
          },
        ),
        if (_selectedWarehouseTitle != null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _itemsForSelectedWarehouse
                    .any((item) => item.dateTime == _selectedWarehouseItemId)
                ? _selectedWarehouseItemId
                : null,
            decoration: const InputDecoration(
              labelText: 'Оберіть товар',
              border: OutlineInputBorder(),
            ),
            hint: const Text('Оберіть товар'),
            isExpanded: true,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('— Оберіть товар —'),
              ),
              ..._itemsForSelectedWarehouse.map(
                (item) => DropdownMenuItem<String?>(
                  value: item.dateTime,
                  child: Text(
                    item.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedWarehouseItemId = value;
                if (value == null) {
                  _soldQuantityController.clear();
                }
              });
            },
          ),
        ],
        if (_selectedWarehouseItemId != null) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _soldQuantityController,
            decoration: const InputDecoration(
              labelText: 'Кількість',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildFieldInput(String field) {
    final isMoney = _isMoneyFieldName(field);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controllers[field],
        decoration: InputDecoration(
          labelText: field,
          border: const OutlineInputBorder(),
          prefixIcon: isMoney ? const Icon(Icons.payments_outlined) : null,
        ),
        keyboardType: _isNumericField(field) ? TextInputType.number : TextInputType.text,
        textCapitalization: TextCapitalization.sentences,
      ),
    );
  }

  Widget _buildSaveButtons() {
    final isBusy = widget.isSending || _isSaving || _isLoadingWarehouseItems;
    final greenStyle = ElevatedButton.styleFrom(
      backgroundColor: Colors.green,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );

    return Row(
      children: [
        SizedBox(
          width: 56,
          height: 56,
          child: ElevatedButton(
            style: greenStyle.copyWith(
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
              minimumSize: const WidgetStatePropertyAll(Size(56, 56)),
            ),
            onPressed: isBusy ? null : _handleAddToCart,
            child: const Icon(Icons.add),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            style: greenStyle.copyWith(
              padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 16)),
            ),
            icon: isBusy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.cloud_upload),
            label: Text(isBusy ? 'Відправка...' : 'Зберегти'),
            onPressed: isBusy ? null : _handleSave,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Новий запис: ${widget.title}",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildCartSection(),
            if (widget.isWarehouseLinked) _buildWarehouseSection(),
            ...widget.fields.map(_buildFieldInput),
            const SizedBox(height: 16),
            _buildSaveButtons(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
