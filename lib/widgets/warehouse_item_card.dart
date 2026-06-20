import 'package:flutter/material.dart';

import '../core/warehouse_analytics.dart';
import '../models/dashboard.dart';
import '../models/sheet_record.dart';

class WarehouseItemCard extends StatelessWidget {
  final SheetRecord item;
  final Dashboard dashboard;
  final List<LinkedIncomeRecord> linkedIncomeRecords;
  final Color accentColor;

  const WarehouseItemCard({
    super.key,
    required this.item,
    required this.dashboard,
    required this.linkedIncomeRecords,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final stats = calculateWarehouseStats(
      item: item,
      dashboard: dashboard,
      linkedIncomeRecords: linkedIncomeRecords,
    );
    final fields = recordFieldMap(item, dashboard.fields);
    final name = fields['Назва']?.trim().isNotEmpty == true
        ? fields['Назва']!.trim()
        : 'Без назви';

    final bought = stats['bought']!;
    final spent = stats['spent']!;
    final sold = stats['sold']!;
    final earned = stats['earned']!;
    final remaining = stats['remaining']!;
    final costPerUnit = stats['costPerUnit']!;

    final remainingColor = remaining <= 0 ? Colors.redAccent : Colors.green.shade700;
    final financeColor = earned >= spent ? Colors.green.shade700 : Colors.black87;

    final customFields = dashboard.fields.where(
      (field) =>
          !Dashboard.warehouseRequiredFields.contains(field) && field != 'Назва',
    );

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Залишок: $remaining шт. (з $bought)',
              style: TextStyle(
                color: remainingColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Витрачено: ${spent.toStringAsFixed(2)} ₴ | Зароблено: ${earned.toStringAsFixed(2)} ₴',
              style: TextStyle(
                color: financeColor,
                fontSize: 13,
                fontWeight: earned >= spent ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (sold > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Продано: $sold шт.',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ),
            const SizedBox(height: 6),
            Text(
              'Собівартість 1 шт: ${costPerUnit.toStringAsFixed(2)} ₴',
              style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
            ),
            if (customFields.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              ...customFields.map((field) {
                final value = fields[field];
                if (value == null || value.trim().isEmpty) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '$field: $value',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
