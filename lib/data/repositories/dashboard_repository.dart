import 'package:google_sign_in/google_sign_in.dart';

import '../../core/data_result.dart';
import '../../core/network_exception.dart';
import '../../models/dashboard.dart';
import '../sources/local_cache_data_source.dart';
import '../sources/sheets_api.dart';

/// Керує конфігурацією dashboard: мережа Google Sheets + локальний кеш.
class DashboardRepository {
  DashboardRepository({
    LocalCacheDataSource? cache,
  }) : _cache = cache ?? LocalCacheDataSource();

  final LocalCacheDataSource _cache;

  Future<DataResult<List<Dashboard>>> getDashboards({
    required GoogleSignInAccount user,
  }) async {
    try {
      final rows = await SheetsApi.readSheetData(
        user: user,
        sheetName: SheetsApi.appConfigSheetName,
      );
      final dashboards = Dashboard.listFromSheetRows(rows);
      await _cache.saveDashboards(dashboards);
      return DataResult.network(dashboards);
    } catch (error, stackTrace) {
      print('NETWORK ERROR [getDashboards]: $error');
      print('NETWORK ERROR [getDashboards] stack: $stackTrace');

      if (isNetworkError(error)) {
        final cached = await _cache.getDashboards();
        print(
          'NETWORK ERROR [getDashboards]: offline fallback, '
          'cache size=${cached.length}',
        );
        return DataResult.cache(cached, error: classifyError(error));
      }

      // Як legacy readAppConfig: помилка API / відсутній App_Config → порожній список.
      print(
        'NETWORK ERROR [getDashboards]: non-network error, returning empty list',
      );
      await _cache.saveDashboards([]);
      return DataResult.network([]);
    }
  }

  /// Зберігає конфігурацію в Google Sheets і локальний кеш.
  ///
  /// При помилках, не пов'язаних з мережею, оновлює кеш оптимістично
  /// (Google міг зберегти дані, але відповісти некоректно).
  Future<void> saveDashboards({
    required GoogleSignInAccount user,
    required List<Dashboard> dashboards,
  }) async {
    try {
      await SheetsApi.writeAppConfig(user: user, dashboards: dashboards);
      print('NETWORK OK [saveDashboards]: saved ${dashboards.length} dashboards');
    } catch (error, stackTrace) {
      print('NETWORK ERROR [saveDashboards]: $error');
      print('NETWORK ERROR [saveDashboards] stack: $stackTrace');

      if (isNetworkError(error)) {
        print('NETWORK ERROR [saveDashboards]: rethrowing network error');
        rethrow;
      }

      print(
        'NETWORK ERROR [saveDashboards]: non-network error, '
        'updating cache optimistically',
      );
    }

    await _cache.saveDashboards(dashboards);
  }

  /// Перейменовує dashboard: Google Sheets → App_Config → міграція кешу записів.
  Future<void> renameDashboard({
    required GoogleSignInAccount user,
    required String oldTitle,
    required Dashboard updatedDashboard,
  }) async {
    final newTitle = updatedDashboard.title;
    final dashboardsResult = await getDashboards(user: user);
    final dashboards = List<Dashboard>.from(dashboardsResult.data);
    final index = dashboards.indexWhere((dashboard) => dashboard.title == oldTitle);

    if (index == -1) {
      throw Exception('Dashboard "$oldTitle" не знайдено в конфігурації');
    }

    try {
      if (oldTitle != newTitle) {
        await SheetsApi.renameSheet(
          user: user,
          oldTitle: oldTitle,
          newTitle: newTitle,
        );
      }

      dashboards[index] = updatedDashboard;
      await saveDashboards(user: user, dashboards: dashboards);

      if (oldTitle != newTitle) {
        await _cache.migrateSheetCache(oldTitle, newTitle);
      }

      print('NETWORK OK [renameDashboard]: "$oldTitle" → "$newTitle"');
    } catch (error, stackTrace) {
      print('NETWORK ERROR [renameDashboard]: $error');
      print('NETWORK ERROR [renameDashboard] stack: $stackTrace');
      rethrow;
    }
  }

  /// Повністю видаляє dashboard: аркуш Google Sheets, App_Config і локальний кеш.
  Future<void> deleteDashboard({
    required GoogleSignInAccount user,
    required String title,
  }) async {
    try {
      await SheetsApi.deleteSheet(user: user, sheetName: title);

      final dashboardsResult = await getDashboards(user: user);
      final dashboards = dashboardsResult.data
          .where((dashboard) => dashboard.title != title)
          .toList();

      await saveDashboards(user: user, dashboards: dashboards);
      await _cache.deleteSheetCache(title);

      print('NETWORK OK [deleteDashboard]: deleted "$title"');
    } catch (error, stackTrace) {
      print('NETWORK ERROR [deleteDashboard]: $error');
      print('NETWORK ERROR [deleteDashboard] stack: $stackTrace');
      rethrow;
    }
  }
}
