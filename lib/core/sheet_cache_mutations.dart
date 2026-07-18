/// Чисті (без I/O) трансформації рядків кешу аркуша Google Sheets.
///
/// Виділено з [SheetRecordsRepository] окремо, щоб покрити тестами найризикованішу
/// частину офлайн-кешування записів — локальне оновлення кешу без мережевого
/// підтвердження (append/delete/patch), яке з'явилось після відмови від
/// патерну "запис → повне перечитування".
///
/// Рядки завжди у форматі Google Sheets: [0] — заголовок, [1..] — дані.
/// [rowIndex] всюди 1-based, як індекс рядка в Google Sheets (дані з рядка 2).
class SheetCacheMutations {
  SheetCacheMutations._();

  /// Додає [row] в кінець [existingRows]. Якщо кеш порожній — створює
  /// заголовок ('Дата і час' + [columns]) і перший рядок даних.
  static List<List<String>> appendRow(
    List<List<String>> existingRows,
    List<String> row, {
    List<String>? columns,
  }) {
    final newRow = row.map((e) => e.toString()).toList();

    if (existingRows.isEmpty) {
      final resolvedColumns = columns ??
          List.generate(
            newRow.length > 1 ? newRow.length - 1 : 0,
            (i) => 'Поле ${i + 1}',
          );
      return [
        ['Дата і час', ...resolvedColumns],
        newRow,
      ];
    }

    return [...existingRows, newRow];
  }

  /// Видаляє рядок даних за 1-based [rowIndex]. Індекси за межами діапазону
  /// даних (заголовок або non-existent рядок) ігноруються — повертає [rows]
  /// без змін.
  static List<List<String>> deleteRow(List<List<String>> rows, int rowIndex) {
    final dataRowIndex = rowIndex - 1;
    if (rows.isEmpty || dataRowIndex < 1 || dataRowIndex >= rows.length) {
      return rows;
    }

    final updated = List<List<String>>.from(rows);
    updated.removeAt(dataRowIndex);
    return updated;
  }

  /// Замінює рядок даних за 1-based [rowIndex] на [values]. Індекси за межами
  /// діапазону даних ігноруються — повертає [rows] без змін.
  static List<List<String>> patchRow(
    List<List<String>> rows,
    int rowIndex,
    List<String> values,
  ) {
    final dataRowIndex = rowIndex - 1;
    if (rows.isEmpty || dataRowIndex < 1 || dataRowIndex >= rows.length) {
      return rows;
    }

    final updated = List<List<String>>.from(rows);
    updated[dataRowIndex] = List<String>.from(values);
    return updated;
  }
}
