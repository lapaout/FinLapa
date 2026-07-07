import 'package:finlapa/core/history_date_filter.dart';
import 'package:finlapa/models/sheet_record.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HistoryDateFilter', () {
    final reference = DateTime(2026, 6, 18, 12);

    test('parseDateSafely supports ISO and dotted formats', () {
      expect(
        HistoryDateFilter.parseDateSafely('2026-06-18 12:30'),
        DateTime(2026, 6, 18, 12, 30),
      );
      expect(
        HistoryDateFilter.parseDateSafely('18.06.2026'),
        DateTime(2026, 6, 18),
      );
    });

    test('filterRecords returns all rows for filter Всі', () {
      final records = [
        SheetRecord.fromValues(values: ['2026-06-18 10:00', '100']),
        SheetRecord.fromValues(values: ['2026-05-01 10:00', '200']),
      ];

      final filtered = HistoryDateFilter.filterRecords(
        records: records,
        filter: 'Всі',
      );

      expect(filtered.length, 2);
    });

    test('filterRecords applies Сьогодні filter', () {
      final records = [
        SheetRecord.fromValues(values: ['2026-06-18 10:00', '100']),
        SheetRecord.fromValues(values: ['2026-05-01 10:00', '200']),
      ];

      final filtered = HistoryDateFilter.filterRecords(
        records: records,
        filter: 'Сьогодні',
        now: reference,
      );

      expect(filtered.length, 1);
      expect(filtered.first.values[1], '100');
    });

    test('filterRecords applies custom period', () {
      final records = [
        SheetRecord.fromValues(values: ['2026-06-10 10:00', '100']),
        SheetRecord.fromValues(values: ['2026-06-20 10:00', '200']),
      ];

      final filtered = HistoryDateFilter.filterRecords(
        records: records,
        filter: 'Період',
        customRange: DateTimeRange(
          start: DateTime(2026, 6, 15),
          end: DateTime(2026, 6, 25),
        ),
        now: reference,
      );

      expect(filtered.length, 1);
      expect(filtered.first.values[1], '200');
    });
  });
}
