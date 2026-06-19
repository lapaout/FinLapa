import 'package:google_sign_in/google_sign_in.dart';

import '../core/network_exception.dart';
import '../data/sources/sheets_api.dart' as remote;
import '../models/dashboard.dart';

/// Фасад для зворотної сумісності з екранами, що ще не мігровані на repositories.
///
/// Новий код для dashboard-конфігурації використовує [DashboardRepository].
class SheetsApi {
  static Future<List<List<String>>> readSheetData({
    required GoogleSignInAccount user,
    required String sheetName,
  }) {
    return remote.SheetsApi.readSheetData(user: user, sheetName: sheetName);
  }

  static Future<void> renameSheet({
    required GoogleSignInAccount user,
    required String oldTitle,
    required String newTitle,
  }) {
    return remote.SheetsApi.renameSheet(
      user: user,
      oldTitle: oldTitle,
      newTitle: newTitle,
    );
  }

  static Future<void> sendTransaction({
    required GoogleSignInAccount user,
    required String sheetName,
    required String activity,
    required String type,
    required double amount,
  }) {
    return remote.SheetsApi.sendTransaction(
      user: user,
      sheetName: sheetName,
      activity: activity,
      type: type,
      amount: amount,
    );
  }

  static Future<void> sendDynamicData({
    required GoogleSignInAccount user,
    required String sheetName,
    required List<String> columns,
    required List<dynamic> values,
  }) {
    return remote.SheetsApi.sendDynamicData(
      user: user,
      sheetName: sheetName,
      columns: columns,
      values: values,
    );
  }

  static Future<void> updateRowData({
    required GoogleSignInAccount user,
    required String sheetName,
    required int rowIndex,
    required List<dynamic> newValues,
  }) {
    return remote.SheetsApi.updateRowData(
      user: user,
      sheetName: sheetName,
      rowIndex: rowIndex,
      newValues: newValues,
    );
  }

  /// @deprecated Використовуйте [DashboardRepository.getDashboards].
  static Future<List<Map<String, dynamic>>> readAppConfig({
    required GoogleSignInAccount user,
  }) async {
    try {
      final rows = await readSheetData(
        user: user,
        sheetName: remote.SheetsApi.appConfigSheetName,
      );
      return Dashboard.listFromSheetRows(rows).map((d) => d.toMap()).toList();
    } catch (error) {
      if (isNetworkError(error)) rethrow;
      return [];
    }
  }

  /// @deprecated Використовуйте [DashboardRepository.saveDashboards].
  static Future<void> saveAppConfig({
    required GoogleSignInAccount user,
    required List<Map<String, dynamic>> dashboards,
  }) async {
    final models = dashboards.map(Dashboard.fromMap).toList();
    await remote.SheetsApi.writeAppConfig(user: user, dashboards: models);
  }
}
