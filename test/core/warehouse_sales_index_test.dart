import 'package:finlapa/core/warehouse_analytics.dart';
import 'package:finlapa/core/warehouse_sales_index.dart';
import 'package:finlapa/models/dashboard.dart';
import 'package:finlapa/models/sheet_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildWarehouseStatsCache matches legacy per-item calculation', () {
    const dashboard = Dashboard(
      title: 'Склад',
      iconCode: 0,
      colorValue: 0,
      fields: ['Назва', 'Кількість', 'Загальні витрати'],
      type: Dashboard.typeWarehouse,
    );

    final item = SheetRecord.fromValues(
      rowIndex: 2,
      values: ['2026-01-01 10:00:00', 'Товар A', '10', '100'],
    );

    final linked = [
      LinkedIncomeRecord(
        record: SheetRecord.fromValues(
          rowIndex: 2,
          values: [
            '2026-01-02 10:00:00',
            '500',
            '[Склад] Товар A',
            '3',
            '2026-01-01 10:00:00',
          ],
        ),
        headers: const [
          'Дата і час',
          'Сума',
          'Товар зі складу',
          'Продано (шт)',
          'ID товару (приховано)',
        ],
      ),
    ];

    final cache = buildWarehouseStatsCache(
      items: [item],
      dashboard: dashboard,
      linkedIncomeRecords: linked,
    );

    final legacy = calculateWarehouseStats(
      item: item,
      dashboard: dashboard,
      linkedIncomeRecords: linked,
    );

    expect(cache.statsFor(item), legacy);
    expect(cache.totals['remaining'], legacy['remaining']);
    expect(cache.totals['spent'], legacy['spent']);
    expect(cache.totals['earned'], legacy['earned']);
  });

  test('buildWarehouseStatsCache handles 1000 items and 5000 sales', () {
    const dashboard = Dashboard(
      title: 'Склад',
      iconCode: 0,
      colorValue: 0,
      fields: ['Назва', 'Кількість', 'Загальні витрати'],
      type: Dashboard.typeWarehouse,
    );

    String itemTimestamp(int index) {
      final dt = DateTime(2026, 1, 1).add(Duration(seconds: index));
      String pad(int v) => v.toString().padLeft(2, '0');
      return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} '
          '${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
    }

    final items = List.generate(1000, (index) {
      final timestamp = itemTimestamp(index);
      return SheetRecord.fromValues(
        rowIndex: index + 2,
        values: [timestamp, 'Товар $index', '100', '1000'],
      );
    });

    final linked = List.generate(5000, (index) {
      final item = items[index % items.length];
      final itemId = item.values.first;
      return LinkedIncomeRecord(
        record: SheetRecord.fromValues(
          rowIndex: index + 2,
          values: [
            '2026-02-${(index % 28 + 1).toString().padLeft(2, '0')} 10:00:00',
            '100',
            '[Склад] ${item.values[1]}',
            '1',
            itemId,
          ],
        ),
        headers: const [
          'Дата і час',
          'Сума',
          'Товар зі складу',
          'Продано (шт)',
          'ID товару (приховано)',
        ],
      );
    });

    final stopwatch = Stopwatch()..start();
    final cache = buildWarehouseStatsCache(
      items: items,
      dashboard: dashboard,
      linkedIncomeRecords: linked,
    );
    stopwatch.stop();

    expect(cache.statsByItemId.length, 1000);

    final totalSold = cache.statsByItemId.values.fold<num>(
      0,
      (sum, stats) => sum + (stats['sold'] ?? 0),
    );
    expect(totalSold, 5000);
    expect(stopwatch.elapsedMilliseconds, lessThan(3000));
  });
}
