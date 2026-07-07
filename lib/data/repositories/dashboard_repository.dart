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

  /// Лише локальний кеш App_Config — без мережевих запитів.
  Future<List<Dashboard>> getCachedDashboards() async {
    return _cache.getDashboards();
  }

  /// Зберігає новий ПОРЯДОК дашбордів за патерном Read-Before-Write (online-first).
  ///
  /// [orderedActiveTitles] — новий порядок НЕархівних дашбордів типу [type],
  /// що прийшов з UI. Решта записів (інші типи, архівні) лишаються на своїх
  /// місцях — ми не будуємо список з застарілого локального стану.
  ///
  /// 1. Примусово читає АКТУАЛЬНИЙ список з хмари (offline → throw).
  /// 2. Переставляє активні дашборди цього типу у свіжому списку згідно з UI,
  ///    зберігаючи позиції записів, яких UI не знав (нові/інші в хмарі).
  /// 3. Лише після успішного запису оновлює локальний кеш.
  Future<List<Dashboard>> reorderDashboards({
    required GoogleSignInAccount user,
    required String type,
    required List<String> orderedActiveTitles,
  }) async {
    // 1. Свіжі дані з хмари (offline → throw, кеш не чіпаємо).
    final latestDashboards = await _readLatestDashboardsOnline(user: user);

    // Активні дашборди цього типу зі СВІЖОГО хмарного списку.
    final activeOfType = latestDashboards
        .where(
          (dashboard) =>
              dashboard.type == type && !dashboard.isArchived && !dashboard.isHidden,
        )
        .toList();
    final byTitle = {
      for (final dashboard in activeOfType) dashboard.title: dashboard,
    };

    // 2. Новий порядок: спершу за списком з UI (лише ті, що ще існують у хмарі),
    //    потім будь-які активні цього типу, яких UI не знав — щоб не загубити їх.
    final reordered = <Dashboard>[];
    final usedTitles = <String>{};
    for (final title in orderedActiveTitles) {
      final dashboard = byTitle[title];
      if (dashboard != null && usedTitles.add(title)) {
        reordered.add(dashboard);
      }
    }
    for (final dashboard in activeOfType) {
      if (!usedTitles.contains(dashboard.title)) {
        reordered.add(dashboard);
      }
    }

    // Повертаємо переставлені активні дашборди на ТІ САМІ позиції-слоти,
    // не чіпаючи інші типи та архівні записи зі свіжого списку.
    final updatedDashboards = <Dashboard>[];
    var cursor = 0;
    for (final dashboard in latestDashboards) {
      if (dashboard.type == type && !dashboard.isArchived && !dashboard.isHidden) {
        updatedDashboards.add(reordered[cursor]);
        cursor++;
      } else {
        updatedDashboards.add(dashboard);
      }
    }

    await SheetsApi.writeAppConfig(user: user, dashboards: updatedDashboards);

    // 3. Тільки після успіху — оновлюємо локальний кеш.
    await _cache.saveDashboards(updatedDashboards);
    print(
      'NETWORK OK [reorderDashboards]: type=$type, '
      'active=${reordered.length}, total=${updatedDashboards.length}',
    );
    return updatedDashboards;
  }

  /// Примусове ОНЛАЙН-читання App_Config БЕЗ фолбеку на локальний кеш.
  ///
  /// Це база для патерну "Read-Before-Write" у мутаціях: ми ніколи не
  /// будуємо запис у хмару на основі застарілого локального стану.
  /// Будь-яка мережева помилка кидається наверх — операцію треба перервати,
  /// бо без свіжих даних можна затерти чужі дашборди.
  Future<List<Dashboard>> _readLatestDashboardsOnline({
    required GoogleSignInAccount user,
  }) async {
    final rows = await SheetsApi.readSheetData(
      user: user,
      sheetName: SheetsApi.appConfigSheetName,
    );
    final dashboards = Dashboard.listFromSheetRows(rows);
    print(
      'NETWORK OK [readLatestOnline]: fetched ${dashboards.length} dashboards from cloud',
    );
    return dashboards;
  }

  /// Створює новий dashboard за патерном Read-Before-Write (online-first).
  ///
  /// 1. Примусово читає АКТУАЛЬНИЙ список з хмари (кидає виняток при offline).
  /// 2. Додає новий dashboard саме до свіжого списку і пише його в хмару.
  /// 3. Лише після успішного запису оновлює локальний кеш.
  Future<List<Dashboard>> createDashboard({
    required GoogleSignInAccount user,
    required Dashboard dashboard,
  }) async {
    // 1. Свіжі дані з хмари (offline → throw, кеш не чіпаємо).
    final latestDashboards = await _readLatestDashboardsOnline(user: user);

    // 2. Застосовуємо зміну до СВІЖОГО списку та пишемо в хмару.
    final updatedDashboards = [...latestDashboards, dashboard];
    await SheetsApi.writeAppConfig(user: user, dashboards: updatedDashboards);

    // 3. Тільки після успіху — оновлюємо локальний кеш.
    await _cache.saveDashboards(updatedDashboards);
    print(
      'NETWORK OK [createDashboard]: added "${dashboard.title}", '
      'total=${updatedDashboards.length}',
    );
    return updatedDashboards;
  }

  /// Оновлює існуючий dashboard за патерном Read-Before-Write (online-first).
  ///
  /// Підтримує перейменування (фізичного аркуша + міграцію кешу записів) та
  /// зміну будь-яких полів/іконки/кольору/прапора isArchived.
  Future<List<Dashboard>> updateDashboard({
    required GoogleSignInAccount user,
    required String oldTitle,
    required Dashboard updatedDashboard,
  }) async {
    final newTitle = updatedDashboard.title;

    // 1. Свіжі дані з хмари (offline → throw, кеш не чіпаємо).
    final latestDashboards = await _readLatestDashboardsOnline(user: user);
    final index =
        latestDashboards.indexWhere((dashboard) => dashboard.title == oldTitle);
    if (index == -1) {
      throw Exception(
        'Dashboard "$oldTitle" не знайдено в актуальній конфігурації',
      );
    }

    // Перейменування фізичного аркуша робимо до запису конфігу,
    // щоб App_Config і аркуш лишались консистентними при збої.
    if (oldTitle != newTitle) {
      await SheetsApi.renameSheet(
        user: user,
        oldTitle: oldTitle,
        newTitle: newTitle,
      );
    }

    // 2. Застосовуємо зміну до СВІЖОГО списку та пишемо в хмару.
    final updatedDashboards = List<Dashboard>.from(latestDashboards);
    updatedDashboards[index] = updatedDashboard;
    await SheetsApi.writeAppConfig(user: user, dashboards: updatedDashboards);

    // 3. Тільки після успіху — кеш конфігу + міграція кешу записів.
    await _cache.saveDashboards(updatedDashboards);
    if (oldTitle != newTitle) {
      await _cache.migrateSheetCache(oldTitle, newTitle);
    }
    print('NETWORK OK [updateDashboard]: "$oldTitle" → "$newTitle"');
    return updatedDashboards;
  }

  /// Зворотно-сумісний аліас для [updateDashboard] (перейменування/редагування).
  Future<void> renameDashboard({
    required GoogleSignInAccount user,
    required String oldTitle,
    required Dashboard updatedDashboard,
  }) async {
    await updateDashboard(
      user: user,
      oldTitle: oldTitle,
      updatedDashboard: updatedDashboard,
    );
  }

  /// Повністю видаляє dashboard за патерном Read-Before-Write (online-first).
  ///
  /// 1. Примусово читає АКТУАЛЬНИЙ список з хмари (кидає виняток при offline).
  /// 2. Видаляє фізичний аркуш і прибирає запис саме зі свіжого списку.
  /// 3. Лише після успіху оновлює локальний кеш.
  Future<List<Dashboard>> deleteDashboard({
    required GoogleSignInAccount user,
    required String title,
  }) async {
    // 1. Свіжі дані з хмари (offline → throw, кеш не чіпаємо).
    final latestDashboards = await _readLatestDashboardsOnline(user: user);

    // Видаляємо фізичний аркуш до запису конфігу.
    await SheetsApi.deleteSheet(user: user, sheetName: title);

    // 2. Прибираємо запис зі СВІЖОГО списку та пишемо в хмару.
    final updatedDashboards =
        latestDashboards.where((dashboard) => dashboard.title != title).toList();
    await SheetsApi.writeAppConfig(user: user, dashboards: updatedDashboards);

    // 3. Тільки після успіху — кеш конфігу + кеш записів аркуша.
    await _cache.saveDashboards(updatedDashboards);
    await _cache.deleteSheetCache(title);
    print(
      'NETWORK OK [deleteDashboard]: deleted "$title", '
      'remaining=${updatedDashboards.length}',
    );
    return updatedDashboards;
  }
}
