import 'package:google_sign_in/google_sign_in.dart';

import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/sheet_records_repository.dart';
import '../models/dashboard.dart';
import '../models/sheet_record.dart';

class WarehousePickerItem {
  final String dateTime;
  final String name;
  final String dashboardTitle;

  const WarehousePickerItem({
    required this.dateTime,
    required this.name,
    required this.dashboardTitle,
  });
}

class WarehousePickerData {
  final List<String> orderedWarehouseTitles;
  final List<WarehousePickerItem> items;

  const WarehousePickerData({
    required this.orderedWarehouseTitles,
    required this.items,
  });

  static const empty = WarehousePickerData(
    orderedWarehouseTitles: [],
    items: [],
  );
}

List<WarehousePickerItem> warehousePickerItemsFromRecords({
  required Dashboard warehouse,
  required List<SheetRecord> records,
}) {
  final nameFieldIndex = warehouse.fields.indexOf('Назва');
  if (nameFieldIndex == -1) return const [];

  final valueIndex = nameFieldIndex + 1;
  final items = <WarehousePickerItem>[];

  for (final record in records) {
    final dateTime = record.dateTime;
    if (dateTime == null || dateTime.isEmpty) continue;
    if (record.values.length <= valueIndex) continue;

    final name = record.values[valueIndex].trim();
    if (name.isEmpty) continue;

    items.add(
      WarehousePickerItem(
        dateTime: dateTime.trim(),
        name: name,
        dashboardTitle: warehouse.title,
      ),
    );
  }

  return items;
}

Future<List<Dashboard>> resolveWarehouseDashboardsForPicker({
  required DashboardRepository dashboardRepository,
  GoogleSignInAccount? user,
}) async {
  var orderedWarehouses = await dashboardRepository.getCachedWarehouseDashboards();
  if (orderedWarehouses.isEmpty && user != null) {
    await dashboardRepository.getDashboards(user: user);
    orderedWarehouses = await dashboardRepository.getCachedWarehouseDashboards();
  }
  return orderedWarehouses;
}

/// Повний список складів (порядок App_Config) + товари з кешу всіх складів.
Future<WarehousePickerData> loadWarehousePickerData({
  required DashboardRepository dashboardRepository,
  required SheetRecordsRepository recordsRepository,
  GoogleSignInAccount? user,
}) async {
  final orderedWarehouses = await resolveWarehouseDashboardsForPicker(
    dashboardRepository: dashboardRepository,
    user: user,
  );
  final orderedTitles = orderedWarehouses.map((dashboard) => dashboard.title).toList();

  if (orderedWarehouses.isEmpty) {
    return WarehousePickerData.empty;
  }

  final itemBatches = await Future.wait(
    orderedWarehouses.map((warehouse) async {
      final records = await recordsRepository.getRecordsPreferCache(
        sheetTitle: warehouse.title,
        user: user,
      );
      return warehousePickerItemsFromRecords(
        warehouse: warehouse,
        records: records,
      );
    }),
  );

  return WarehousePickerData(
    orderedWarehouseTitles: List<String>.from(orderedTitles),
    items: itemBatches.expand((items) => items).toList(),
  );
}
