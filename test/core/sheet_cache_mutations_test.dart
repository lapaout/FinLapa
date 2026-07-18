import 'package:finlapa/core/sheet_cache_mutations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SheetCacheMutations.appendRow', () {
    test('creates header row when cache is empty', () {
      final result = SheetCacheMutations.appendRow(
        [],
        ['150', 'Зарплата'],
        columns: ['Сума', 'Категорія'],
      );

      expect(result, [
        ['Дата і час', 'Сума', 'Категорія'],
        ['150', 'Зарплата'],
      ]);
    });

    test('falls back to generic column names when columns not provided', () {
      final result = SheetCacheMutations.appendRow(
        [],
        ['2026-06-18 10:00', '150', 'Зарплата'],
      );

      expect(result.first, ['Дата і час', 'Поле 1', 'Поле 2']);
    });

    test('appends to the end without touching existing rows', () {
      final existing = [
        ['Дата і час', 'Сума'],
        ['2026-06-18 10:00', '100'],
      ];

      final result = SheetCacheMutations.appendRow(existing, ['2026-06-19 10:00', '200']);

      expect(result.length, 3);
      expect(result[0], existing[0]);
      expect(result[1], existing[1]);
      expect(result[2], ['2026-06-19 10:00', '200']);
    });

    test('does not mutate the original list', () {
      final existing = [
        ['Дата і час', 'Сума'],
      ];

      SheetCacheMutations.appendRow(existing, ['2026-06-19 10:00', '200']);

      expect(existing.length, 1);
    });
  });

  group('SheetCacheMutations.deleteRow', () {
    final rows = [
      ['Дата і час', 'Сума'],
      ['2026-06-18 10:00', '100'],
      ['2026-06-19 10:00', '200'],
      ['2026-06-20 10:00', '300'],
    ];

    test('removes the correct data row for a 1-based Google Sheets rowIndex', () {
      // rowIndex=3 -> третій рядок таблиці (1=заголовок, 2=перший запис, 3=другий).
      final result = SheetCacheMutations.deleteRow(rows, 3);

      expect(result.length, 3);
      expect(result, [
        ['Дата і час', 'Сума'],
        ['2026-06-18 10:00', '100'],
        ['2026-06-20 10:00', '300'],
      ]);
    });

    test('ignores rowIndex pointing at the header row', () {
      final result = SheetCacheMutations.deleteRow(rows, 1);
      expect(result, rows);
    });

    test('ignores out-of-range rowIndex', () {
      final result = SheetCacheMutations.deleteRow(rows, 99);
      expect(result, rows);
    });

    test('returns input unchanged when cache is empty', () {
      final result = SheetCacheMutations.deleteRow([], 2);
      expect(result, isEmpty);
    });

    test('does not mutate the original list', () {
      final copy = rows.map((row) => List<String>.from(row)).toList();
      SheetCacheMutations.deleteRow(copy, 2);
      expect(copy.length, 4);
    });
  });

  group('SheetCacheMutations.patchRow', () {
    final rows = [
      ['Дата і час', 'Сума'],
      ['2026-06-18 10:00', '100'],
      ['2026-06-19 10:00', '200'],
    ];

    test('replaces the correct data row for a 1-based rowIndex', () {
      final result = SheetCacheMutations.patchRow(rows, 2, ['2026-06-18 10:00', '999']);

      expect(result[1], ['2026-06-18 10:00', '999']);
      expect(result[2], rows[2]);
    });

    test('ignores rowIndex pointing at the header row', () {
      final result = SheetCacheMutations.patchRow(rows, 1, ['x', 'y']);
      expect(result, rows);
    });

    test('ignores out-of-range rowIndex', () {
      final result = SheetCacheMutations.patchRow(rows, 99, ['x', 'y']);
      expect(result, rows);
    });

    test('does not mutate the original list', () {
      final copy = rows.map((row) => List<String>.from(row)).toList();
      SheetCacheMutations.patchRow(copy, 2, ['x', 'y']);
      expect(copy[1], rows[1]);
    });
  });
}
