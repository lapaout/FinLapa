import 'package:flutter/material.dart';

import '../models/dashboard.dart';

class DashboardManageModal extends StatefulWidget {
  final Dashboard dashboard;
  final VoidCallback onArchive;
  final VoidCallback onDeleteForever;
  final Future<void> Function(bool isWarehouseLinked, List<String> fields)?
      onWarehouseLinkedChanged;

  const DashboardManageModal({
    super.key,
    required this.dashboard,
    required this.onArchive,
    required this.onDeleteForever,
    this.onWarehouseLinkedChanged,
  });

  @override
  State<DashboardManageModal> createState() => _DashboardManageModalState();
}

class _DashboardManageModalState extends State<DashboardManageModal> {
  late bool _isWarehouseLinked;
  bool _isSavingWarehouseLink = false;

  @override
  void initState() {
    super.initState();
    _isWarehouseLinked = widget.dashboard.isWarehouseLinked;
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

  Future<void> _onWarehouseLinkedChanged(bool value) async {
    if (widget.onWarehouseLinkedChanged == null || _isSavingWarehouseLink) return;

    var fields = List<String>.from(widget.dashboard.fields);
    if (value) {
      fields = _ensureMoneyField(fields);
    }

    setState(() {
      _isWarehouseLinked = value;
      _isSavingWarehouseLink = true;
    });

    try {
      await widget.onWarehouseLinkedChanged!(value, fields);
    } catch (_) {
      if (mounted) {
        setState(() => _isWarehouseLinked = !value);
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingWarehouseLink = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showWarehouseToggle =
        widget.dashboard.type == Dashboard.typeIncome &&
        widget.onWarehouseLinkedChanged != null;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.dashboard.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Управління дашбордом',
            style: TextStyle(color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (showWarehouseToggle)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.inventory_2_outlined,
                color: _isWarehouseLinked ? Colors.teal : Colors.grey,
              ),
              title: const Text('Режим продажу зі складу'),
              subtitle: const Text('Доступ до товарів з усіх складів'),
              value: _isWarehouseLinked,
              onChanged: _isSavingWarehouseLink ? null : _onWarehouseLinkedChanged,
            ),
          if (showWarehouseToggle) const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.archive_outlined, color: Colors.orange),
            title: const Text('В архів'),
            subtitle: const Text('Приховати з основного списку'),
            onTap: () {
              Navigator.pop(context);
              widget.onArchive();
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
            title: const Text('Видалити назавжди'),
            subtitle: const Text('Безповоротно видалить таблицю і всі записи'),
            onTap: () {
              Navigator.pop(context);
              widget.onDeleteForever();
            },
          ),
        ],
      ),
    );
  }
}
