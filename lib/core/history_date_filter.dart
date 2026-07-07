import 'package:flutter/material.dart';

import '../models/sheet_record.dart';

/// Парсинг дат і фільтрація записів історії (income/expense).
class HistoryDateFilter {
  HistoryDateFilter._();

  static DateTime? parseDateSafely(String dateStr) {
    final parsed = DateTime.tryParse(dateStr) ?? DateTime.tryParse('$dateStr:00');
    if (parsed != null) return parsed;

    try {
      final cleanDate = dateStr.split(' ')[0];
      final parts = cleanDate.split(RegExp(r'[\.\-\/]'));
      if (parts.length >= 3) {
        var day = int.parse(parts[0]);
        var month = int.parse(parts[1]);
        var year = int.parse(parts[2]);
        if (year < 100) year += 2000;
        return DateTime(year, month, day);
      }
    } catch (_) {}

    return null;
  }

  static bool matchesFilter({
    required List<String> row,
    required String filter,
    DateTimeRange? customRange,
    DateTime? now,
  }) {
    if (filter == 'Всі') return true;
    if (row.isEmpty) return false;

    final rowDate = parseDateSafely(row[0]);
    if (rowDate == null) return false;

    final reference = now ?? DateTime.now();

    if (filter == 'Сьогодні') {
      return rowDate.year == reference.year &&
          rowDate.month == reference.month &&
          rowDate.day == reference.day;
    }
    if (filter == 'Тиждень') {
      return reference.difference(rowDate).inDays <= 7;
    }
    if (filter == 'Місяць') {
      return rowDate.year == reference.year && rowDate.month == reference.month;
    }
    if (filter == 'Період' && customRange != null) {
      final start = customRange.start.subtract(const Duration(seconds: 1));
      final end = customRange.end.add(const Duration(days: 1));
      return rowDate.isAfter(start) && rowDate.isBefore(end);
    }
    return true;
  }

  static List<SheetRecord> filterRecords({
    required List<SheetRecord> records,
    required String filter,
    DateTimeRange? customRange,
    DateTime? now,
  }) {
    if (filter == 'Всі') {
      return List<SheetRecord>.from(records);
    }

    return records.where((record) {
      return matchesFilter(
        row: record.values,
        filter: filter,
        customRange: customRange,
        now: now,
      );
    }).toList();
  }
}
