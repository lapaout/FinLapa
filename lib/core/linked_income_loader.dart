import 'package:google_sign_in/google_sign_in.dart';

import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/sheet_records_repository.dart';
import '../models/dashboard.dart';
import 'warehouse_analytics.dart';

/// Паралельно завантажує записи з усіх income-дашбордів, прив'язаних до складу.
///
/// 1. Конфіг — спочатку локальний кеш, потім мережа (якщо кеш порожній).
/// 2. Записи кожного дашборда — [Future.wait] (паралельно, не N+1 sequential).
Future<List<LinkedIncomeRecord>> loadLinkedIncomeRecords({
  required GoogleSignInAccount user,
  required DashboardRepository dashboardRepository,
  required SheetRecordsRepository recordsRepository,
}) async {
  var dashboards = await dashboardRepository.getCachedDashboards();
  dashboards = dashboards
      .where(
        (dashboard) =>
            dashboard.type == Dashboard.typeIncome && dashboard.isWarehouseLinked,
      )
      .toList();

  if (dashboards.isEmpty) {
    final dashboardsResult = await dashboardRepository.getDashboards(user: user);
    dashboards = dashboardsResult.data
        .where(
          (dashboard) =>
              dashboard.type == Dashboard.typeIncome && dashboard.isWarehouseLinked,
        )
        .toList();
  }

  if (dashboards.isEmpty) return const [];

  final batches = await Future.wait(
    dashboards.map((dashboard) async {
      final result = await recordsRepository.getRecords(
        user: user,
        sheetTitle: dashboard.title,
      );
      final headers = await recordsRepository.getSheetHeaders(dashboard.title);
      return (records: result.data, headers: headers);
    }),
  );

  final linkedRecords = <LinkedIncomeRecord>[];
  for (final batch in batches) {
    for (final record in batch.records) {
      linkedRecords.add(
        LinkedIncomeRecord(record: record, headers: batch.headers),
      );
    }
  }

  return linkedRecords;
}
