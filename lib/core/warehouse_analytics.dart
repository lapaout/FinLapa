import '../models/dashboard.dart';
import '../models/sheet_record.dart';

class LinkedIncomeRecord {
  final SheetRecord record;
  final List<String> headers;

  const LinkedIncomeRecord({
    required this.record,
    required this.headers,
  });

  Map<String, String> get fields {
    final map = <String, String>{};
    for (var i = 1; i < headers.length && i < record.values.length; i++) {
      map[headers[i]] = record.values[i];
    }
    return map;
  }
}

Map<String, String> recordFieldMap(
  SheetRecord record,
  List<String> dashboardFields,
) {
  final map = <String, String>{};
  for (var i = 0; i < dashboardFields.length; i++) {
    final valueIndex = i + 1;
    if (record.values.length > valueIndex) {
      map[dashboardFields[i]] = record.values[valueIndex];
    }
  }
  return map;
}

num parseWarehouseNum(String? value) {
  if (value == null || value.trim().isEmpty) return 0;
  final normalized = value.replaceAll(',', '.').replaceAll(RegExp(r'[^\d.-]'), '');
  return num.tryParse(normalized) ?? 0;
}

String normalizeWarehouseItemId(Object? value) {
  if (value == null) return '';

  final trimmed = value.toString().trim();
  if (trimmed.isEmpty) return '';

  final parsed = DateTime.tryParse(trimmed) ?? DateTime.tryParse('$trimmed:00');
  if (parsed != null) {
    return parsed.toString().substring(0, 16);
  }

  return trimmed;
}

num parseHardAmountValue(String raw) {
  final normalized =
      raw.replaceAll(' ', '').replaceAll(',', '.').replaceAll(RegExp(r'[^\d.-]'), '');
  return double.tryParse(normalized) ?? 0;
}

num parseSoldQuantity(Map<String, String> fields) {
  return parseWarehouseNum(fields['Продано (шт)'] ?? fields['_soldQuantity']);
}

String? parseWarehouseItemId(Map<String, String> fields) {
  final value = fields['ID товару (приховано)'] ?? fields['_warehouseItemId'];
  if (value == null || value.trim().isEmpty) return null;
  return value.trim();
}

/// Значення поля з рядка за назвою колонки (з опційним запасним ключем).
String? fieldValueFromRow(
  List<String> headers,
  List<String> row,
  String key, [
  String? fallbackKey,
]) {
  for (var i = 0; i < headers.length && i < row.length; i++) {
    if (headers[i] == key) {
      final value = row[i].trim();
      if (value.isNotEmpty) return value;
    }
  }
  if (fallbackKey != null) {
    for (var i = 0; i < headers.length && i < row.length; i++) {
      if (headers[i] == fallbackKey) {
        final value = row[i].trim();
        if (value.isNotEmpty) return value;
      }
    }
  }
  return null;
}

/// Назва складу з поля «Товар зі складу» формату `[Склад] Товар`.
String? warehouseTitleFromItemField(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final match = RegExp(r'^\[([^\]]+)\]').firstMatch(value.trim());
  return match?.group(1)?.trim();
}

/// Назва товару без префікса складу.
String? productNameFromItemField(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final trimmed = value.trim();
  final match = RegExp(r'^\[[^\]]+\]\s*(.+)$').firstMatch(trimmed);
  return match?.group(1)?.trim() ?? trimmed;
}

bool isWarehouseLinkedDisplayField(String header) {
  return header == 'Товар зі складу' ||
      header == '_warehouseItemName' ||
      header == 'Продано (шт)' ||
      header == '_soldQuantity';
}

num parseIncomeAmount(
  SheetRecord record,
  List<String> dashboardFields, {
  List<String>? headers,
}) {
  const amountKeywords = ['сум', 'amount', 'цін', 'варт'];

  if (headers != null) {
    for (var i = 1; i < headers.length && i < record.values.length; i++) {
      final keyLower = headers[i].toLowerCase();
      if (amountKeywords.any((word) => keyLower.contains(word))) {
        final parsed = parseHardAmountValue(record.values[i]);
        if (parsed > 0) {
          return parsed;
        }
      }
    }
  }

  final nativeAmount = record.amount;
  if (nativeAmount != null && nativeAmount > 0) {
    return nativeAmount;
  }

  if (record.values.length > 1) {
    final hardParsed = parseHardAmountValue(record.values[1]);
    if (hardParsed > 0) {
      return hardParsed;
    }
  }

  print('DEBUG RAW VALUES: ${record.values}');

  const extendedAmountKeywords = [...amountKeywords, 'грн'];

  final fields = recordFieldMap(record, dashboardFields);
  for (final entry in fields.entries) {
    if (entry.key.startsWith('_') || entry.key == 'ID товару (приховано)') {
      continue;
    }

    final keyLower = entry.key.toLowerCase();
    if (extendedAmountKeywords.any((word) => keyLower.contains(word))) {
      return parseWarehouseNum(entry.value);
    }
  }
  return 0;
}

Map<String, num> calculateWarehouseStats({
  required SheetRecord item,
  required Dashboard dashboard,
  required List<LinkedIncomeRecord> linkedIncomeRecords,
}) {
  final fields = recordFieldMap(item, dashboard.fields);
  final bought = parseWarehouseNum(fields['Кількість']);
  final spent = parseWarehouseNum(fields['Загальні витрати']);

  final itemId = normalizeWarehouseItemId(item.dateTime);

  final linkedSales = linkedIncomeRecords.where(
    (record) =>
        normalizeWarehouseItemId(parseWarehouseItemId(record.fields)) == itemId,
  );

  num sold = 0;
  num earned = 0;
  for (final sale in linkedSales) {
    sold += parseSoldQuantity(sale.fields);
    final incomeFields =
        sale.headers.length > 1 ? sale.headers.sublist(1) : const <String>[];
    earned += parseIncomeAmount(
      sale.record,
      incomeFields,
      headers: sale.headers,
    );
  }

  print(
    'DEBUG STATS: Item: ${fields['Назва']} | Sold: $sold | Earned: $earned',
  );

  final remaining = bought - sold;
  final costPerUnit = bought > 0 ? spent / bought : 0;

  return {
    'bought': bought,
    'spent': spent,
    'sold': sold,
    'earned': earned,
    'remaining': remaining,
    'costPerUnit': costPerUnit,
  };
}
