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
}
