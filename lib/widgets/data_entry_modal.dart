import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
  final void Function(List<String> values, {Map<String, String>? extraFields}) onSave;
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
  List<_WarehousePickerItem> _warehouseItems = [];
  String? _selectedWarehouseTitle;
  String? _selectedWarehouseItemId;

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

  bool _isMoneyFieldName(String field) {
    final normalized = field.toLowerCase();
    return normalized.contains('сум') ||
        normalized.contains('amount') ||
        normalized.contains('цін') ||
        normalized.contains('варт');
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
              dateTime: normalizeWarehouseItemId(dateTime),
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
        if (widget.isWarehouseLinked && _warehouseTitles.isNotEmpty) {
          _selectedWarehouseTitle = _warehouseTitles.first;
        }
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
    final normalized = field.toLowerCase();
    return normalized.contains('сум') ||
        normalized.contains('цін') ||
        normalized.contains('к-сть') ||
        normalized.contains('кількість');
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

  void _handleSave() {
    if (widget.isWarehouseLinked) {
      if (_selectedWarehouseItemId == null) {
        _showValidationError('Оберіть товар зі складу!');
        return;
      }

      final quantity = _parsePositiveNumber(_soldQuantityController.text);
      if (quantity == null || quantity <= 0) {
        _showValidationError('Вкажіть кількість більше 0');
        return;
      }

      final moneyFieldKey = _moneyFieldKey;
      if (moneyFieldKey == null) {
        _showValidationError('Вкажіть суму більше 0');
        return;
      }

      final amount = _parsePositiveNumber(_controllers[moneyFieldKey]!.text);
      if (amount == null || amount <= 0) {
        _showValidationError('Вкажіть суму більше 0');
        return;
      }
    }

    final valuesToSave =
        widget.fields.map((field) => _controllers[field]!.text.trim()).toList();

    Map<String, String>? extraFields;
    if (widget.isWarehouseLinked) {
      final selectedItem = _itemsForSelectedWarehouse.firstWhere(
        (item) => item.dateTime == _selectedWarehouseItemId,
      );
      extraFields = {
        'ID товару (приховано)': _selectedWarehouseItemId!,
        'Продано (шт)': _soldQuantityController.text.trim(),
        'Товар зі складу': '[$_selectedWarehouseTitle] ${selectedItem.name}',
      };
    }

    widget.onSave(valuesToSave, extraFields: extraFields);
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
            value: _selectedWarehouseItemId,
            decoration: const InputDecoration(
              labelText: 'Оберіть товар',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('— Оберіть товар —'),
              ),
              ..._itemsForSelectedWarehouse.map(
                (item) => DropdownMenuItem<String?>(
                  value: item.dateTime,
                  child: Text(item.name),
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
      ),
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
            if (widget.isWarehouseLinked) _buildWarehouseSection(),
            ...widget.fields.map(_buildFieldInput),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              icon: widget.isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(widget.isSending ? "Відправка..." : "Зберегти в Таблицю"),
              onPressed: widget.isSending || _isLoadingWarehouseItems ? null : _handleSave,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
