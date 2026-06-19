import 'sheet_record.dart';

/// Повний набір даних аркуша: заголовки + записи.
class SheetData {
  final List<String> headers;
  final List<SheetRecord> records;

  const SheetData({
    required this.headers,
    required this.records,
  });

  factory SheetData.empty() {
    return const SheetData(headers: [], records: []);
  }

  bool get isEmpty => headers.isEmpty && records.isEmpty;

  /// Парсинг сирих рядків Google Sheets (перший рядок — заголовок).
  factory SheetData.fromSheetRows(List<List<String>> rows) {
    if (rows.isEmpty) return SheetData.empty();

    final headers = rows.first;
    final records = <SheetRecord>[];

    for (var i = 1; i < rows.length; i++) {
      records.add(
        SheetRecord.fromValues(
          values: rows[i],
          rowIndex: i + 1,
        ),
      );
    }

    return SheetData(headers: headers, records: records);
  }

  /// Парсинг кешованих рядків (перший елемент — заголовок).
  factory SheetData.fromCachedRows(List<List<String>> rows) {
    return SheetData.fromSheetRows(rows);
  }

  /// Конвертація назад у формат Google Sheets (заголовок + дані).
  List<List<String>> toSheetRows() {
    return [
      headers,
      ...records.map((record) => record.values),
    ];
  }
}
