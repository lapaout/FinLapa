/// Один запис з Google Sheets (рядок даних, без заголовка).
class SheetRecord {
  /// 1-based індекс рядка в Google Sheets (дані починаються з рядка 2).
  final int? rowIndex;
  final List<String> values;

  const SheetRecord({
    required this.values,
    this.rowIndex,
  });

  /// Дата і час з першої колонки (формат запису FinLapa).
  String? get dateTime => values.isNotEmpty ? values.first : null;

  /// Сума з другого стовпця, якщо перше поле даних — типова «Сума» доходу.
  num? get amount {
    if (values.length < 2) return null;
    final normalized =
        values[1].trim().replaceAll(',', '.').replaceAll(RegExp(r'[^\d.-]'), '');
    final parsed = num.tryParse(normalized);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  factory SheetRecord.fromValues({
    required List<String> values,
    int? rowIndex,
  }) {
    return SheetRecord(
      values: values.map((e) => e.toString()).toList(),
      rowIndex: rowIndex,
    );
  }

  /// Парсинг з кешу SharedPreferences: {'row': [...]}.
  factory SheetRecord.fromCacheMap(Map<String, dynamic> map, {int? rowIndex}) {
    final dynamicList = map['row'] as List<dynamic>? ?? [];
    return SheetRecord(
      values: dynamicList.map((e) => e.toString()).toList(),
      rowIndex: rowIndex,
    );
  }

  Map<String, dynamic> toCacheMap() {
    return {'row': List<String>.from(values)};
  }

  SheetRecord copyWith({
    int? rowIndex,
    List<String>? values,
  }) {
    return SheetRecord(
      rowIndex: rowIndex ?? this.rowIndex,
      values: values ?? this.values,
    );
  }
}
