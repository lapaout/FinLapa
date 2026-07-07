import 'package:flutter/material.dart';

import '../core/ui_field_filter.dart';
import '../models/sheet_record.dart';

/// Картка одного запису в [HistoryScreen] (income/expense).
class HistoryRecordCard extends StatelessWidget {
  final List<String> headers;
  final List<String> row;

  const HistoryRecordCard({
    super.key,
    required this.headers,
    required this.row,
  });

  static Map<String, String> fieldsForRow(List<String> headers, List<String> row) {
    final map = <String, String>{};
    for (var i = 1; i < headers.length && i < row.length; i++) {
      map[headers[i]] = row[i];
    }
    return map;
  }

  static bool isAmountHeader(String header) {
    final normalized = header.toLowerCase();
    return normalized.contains('сум') || normalized.contains('amount');
  }

  static bool isHiddenHistoryHeader(String header) {
    if (isHiddenUiField(header)) return true;
    return header == 'Продано (шт)' || header == 'Товар зі складу';
  }

  static String? warehouseField(Map<String, String> fields, String newKey, String oldKey) {
    final newValue = fields[newKey]?.trim();
    if (newValue != null && newValue.isNotEmpty) {
      return newValue;
    }
    return fields[oldKey]?.trim();
  }

  static num? amountForRow(List<String> row) {
    final record = SheetRecord.fromValues(values: row);
    final nativeAmount = record.amount;
    if (nativeAmount != null && nativeAmount > 0) {
      return nativeAmount;
    }

    if (row.length > 1) {
      final normalized =
          row[1].replaceAll(' ', '').replaceAll(',', '.').replaceAll(RegExp(r'[^\d.-]'), '');
      final parsed = num.tryParse(normalized);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    return null;
  }

  static num totalAmountForRows(List<List<String>> rows) {
    num total = 0;
    for (final row in rows) {
      final amount = amountForRow(row);
      if (amount != null) total += amount;
    }
    return total;
  }

  static num totalAmountForRecords(List<SheetRecord> records) {
    return totalAmountForRows(records.map((record) => record.values).toList());
  }

  @override
  Widget build(BuildContext context) {
    final fields = fieldsForRow(headers, row);
    final warehouseItemName = warehouseField(fields, 'Товар зі складу', '_warehouseItemName');
    final soldQuantity = warehouseField(fields, 'Продано (шт)', '_soldQuantity');
    final hasWarehouseSale = warehouseItemName != null &&
        warehouseItemName.isNotEmpty &&
        soldQuantity != null &&
        soldQuantity.isNotEmpty;
    final displayAmount = amountForRow(row);

    return RepaintBoundary(
      child: Card(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    row.isNotEmpty ? row[0] : 'Без дати',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Divider(),
              if (hasWarehouseSale)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '📦 Товар: $warehouseItemName | Продано: $soldQuantity шт.',
                    style: TextStyle(
                      color: Colors.teal.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              if (displayAmount != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '💰 Сума: $displayAmount ₴',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ...List.generate(headers.length - 1, (i) {
                final colIndex = i + 1;
                final header = headers.length > colIndex ? headers[colIndex] : 'Поле';
                final value = colIndex < row.length ? row[colIndex].trim() : '-';

                if (isHiddenHistoryHeader(header)) {
                  return const SizedBox.shrink();
                }

                if (value.isEmpty || value == '-') {
                  return const SizedBox.shrink();
                }

                if (isAmountHeader(header)) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          '$header:',
                          style: const TextStyle(color: Colors.black54, fontSize: 14),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
