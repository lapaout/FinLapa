import 'package:finlapa/core/warehouse_dashboard_order.dart';
import 'package:finlapa/core/warehouse_picker_data.dart';
import 'package:finlapa/models/dashboard.dart';
import 'package:finlapa/models/sheet_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orderWarehouseDashboardsForPicker keeps App_Config order', () {
    final dashboards = <Dashboard>[
      Dashboard(
        title: 'Income',
        iconCode: Dashboard.defaultIconCode,
        colorValue: Dashboard.defaultColorValue,
        fields: const ['Сума'],
        type: Dashboard.typeIncome,
      ),
      Dashboard(
        title: 'Warehouse B',
        iconCode: Dashboard.defaultIconCode,
        colorValue: Dashboard.defaultColorValue,
        fields: const ['Назва'],
        type: Dashboard.typeWarehouse,
      ),
      Dashboard(
        title: 'Warehouse A',
        iconCode: Dashboard.defaultIconCode,
        colorValue: Dashboard.defaultColorValue,
        fields: const ['Назва'],
        type: Dashboard.typeWarehouse,
      ),
      Dashboard(
        title: 'Hidden WH',
        iconCode: Dashboard.defaultIconCode,
        colorValue: Dashboard.defaultColorValue,
        fields: const ['Назва'],
        type: Dashboard.typeWarehouse,
        isHidden: true,
      ),
    ];

    final ordered = orderWarehouseDashboardsForPicker(dashboards);

    expect(ordered.map((d) => d.title).toList(), [
      'Warehouse B',
      'Warehouse A',
      'Hidden WH',
    ]);
  });

  test('warehousePickerItemsFromRecords extracts product names', () {
    const warehouse = Dashboard(
      title: 'Склад 1',
      iconCode: Dashboard.defaultIconCode,
      colorValue: Dashboard.defaultColorValue,
      fields: ['Назва', 'Кількість'],
      type: Dashboard.typeWarehouse,
    );

    final items = warehousePickerItemsFromRecords(
      warehouse: warehouse,
      records: [
        SheetRecord(
          rowIndex: 2,
          values: ['2026-01-01 10:00', 'Товар А', '5'],
        ),
        SheetRecord(
          rowIndex: 3,
          values: ['2026-01-02 11:00', '', '1'],
        ),
      ],
    );

    expect(items.length, 1);
    expect(items.first.name, 'Товар А');
    expect(items.first.dashboardTitle, 'Склад 1');
  });
}
