import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/data_result.dart';
import '../../core/network_exception.dart';
import '../../core/sheet_cache_mutations.dart';
import '../../models/sheet_data.dart';
import '../../models/sheet_record.dart';
import '../sources/local_cache_data_source.dart';
import '../sources/sheets_api.dart';

/// Керує записами аркуша Google Sheets: мережа + локальний кеш.
class SheetRecordsRepository {
  SheetRecordsRepository({
    LocalCacheDataSource? cache,
  }) : _cache = cache ?? LocalCacheDataSource();

  final LocalCacheDataSource _cache;

  Future<DataResult<List<SheetRecord>>> getRecords({
    required GoogleSignInAccount user,
    required String sheetTitle,
  }) async {
    final sheetResult = await _fetchSheetData(user: user, sheetTitle: sheetTitle);
    return sheetResult.map((data) => data.records);
  }

  /// Лише локальний кеш записів аркуша — без мережевих запитів.
  Future<List<SheetRecord>> getCachedRecords({required String sheetTitle}) async {
    final sheetData = await _cache.getSheetData(sheetTitle);
    return sheetData.records;
  }

  /// Спочатку локальний кеш; якщо порожній і є [user] — завантажує з мережі та кешує.
  Future<List<SheetRecord>> getRecordsPreferCache({
    required String sheetTitle,
    GoogleSignInAccount? user,
  }) async {
    final cached = await getCachedRecords(sheetTitle: sheetTitle);
    if (cached.isNotEmpty || user == null) {
      return cached;
    }

    final result = await getRecords(user: user, sheetTitle: sheetTitle);
    return result.data;
  }

  /// Заголовки аркуша з локального кешу (актуальні після [getRecords]).
  Future<List<String>> getSheetHeaders(String sheetTitle) async {
    return (await _cache.getSheetData(sheetTitle)).headers;
  }

  Future<DataResult<SheetData>> _fetchSheetData({
    required GoogleSignInAccount user,
    required String sheetTitle,
  }) async {
    try {
      final rows = await SheetsApi.readSheetData(
        user: user,
        sheetName: sheetTitle,
      );
      await _cache.saveSheetRows(sheetTitle, rows);
      final sheetData = SheetData.fromSheetRows(rows);
      return DataResult.network(sheetData);
    } catch (error, stackTrace) {
      debugPrint('NETWORK ERROR [SheetRecordsRepository]: $error');
      debugPrint('NETWORK ERROR [SheetRecordsRepository] stack: $stackTrace');

      if (isNetworkError(error)) {
        final cached = await _cache.getSheetData(sheetTitle);
        debugPrint(
          'NETWORK ERROR [SheetRecordsRepository]: offline fallback, '
          'cache records=${cached.records.length}',
        );
        return DataResult.cache(cached, error: classifyError(error));
      }

      debugPrint(
        'NETWORK ERROR [SheetRecordsRepository]: non-network error, '
        'returning empty sheet',
      );
      await _cache.saveSheetRows(sheetTitle, []);
      return DataResult.network(SheetData.empty());
    }
  }

  /// Додає запис. [values] — значення полів без колонки «Дата і час».
  /// [columns] — назви полів для нового аркуша (якщо аркуш ще не існує).
  Future<void> appendRecord({
    required GoogleSignInAccount user,
    required String sheetTitle,
    required List<String> values,
    List<String>? columns,
    String? recordDateTime,
  }) async {
    try {
      List<String> resolvedColumns;

      if (columns != null && columns.isNotEmpty) {
        resolvedColumns = columns;
      } else {
        final existingRows = await _cache.getSheetRows(sheetTitle);
        resolvedColumns = existingRows.isNotEmpty && existingRows.first.length > 1
            ? existingRows.first.sublist(1)
            : List.generate(values.length, (i) => 'Поле ${i + 1}');
      }

      final recordDate =
          recordDateTime ?? DateTime.now().toString().substring(0, 16);

      await SheetsApi.sendDynamicData(
        user: user,
        sheetName: sheetTitle,
        columns: resolvedColumns,
        values: values,
        recordDateTime: recordDateTime,
      );

      await _appendCachedRow(
        sheetTitle,
        [recordDate, ...values.map((e) => e.toString())],
        columns: resolvedColumns,
      );
      debugPrint('NETWORK OK [appendRecord]: appended to "$sheetTitle"');
    } catch (error, stackTrace) {
      debugPrint('NETWORK ERROR [SheetRecordsRepository]: $error');
      debugPrint('NETWORK ERROR [SheetRecordsRepository] stack: $stackTrace');
      rethrow;
    }
  }

  /// Оновлює рядок за 1-based індексом Google Sheets. [values] — повний рядок з датою.
  Future<void> updateRecord({
    required GoogleSignInAccount user,
    required String sheetTitle,
    required int rowIndex,
    required List<String> values,
  }) async {
    try {
      await SheetsApi.updateRowData(
        user: user,
        sheetName: sheetTitle,
        rowIndex: rowIndex,
        newValues: values,
      );
      await _patchCachedRow(sheetTitle, rowIndex, values);
      debugPrint('NETWORK OK [updateRecord]: row $rowIndex in "$sheetTitle"');
    } catch (error, stackTrace) {
      debugPrint('NETWORK ERROR [SheetRecordsRepository]: $error');
      debugPrint('NETWORK ERROR [SheetRecordsRepository] stack: $stackTrace');
      rethrow;
    }
  }

  /// Фізично видаляє рядок з Google Sheets та оновлює локальний кеш.
  Future<void> deleteRecord({
    required GoogleSignInAccount user,
    required String sheetTitle,
    required int rowIndex,
  }) async {
    try {
      await SheetsApi.deleteRow(
        user: user,
        sheetName: sheetTitle,
        rowIndex: rowIndex,
      );

      await _deleteCachedRow(sheetTitle, rowIndex);
      debugPrint('NETWORK OK [deleteRecord]: row $rowIndex in "$sheetTitle"');
    } catch (error, stackTrace) {
      debugPrint('NETWORK ERROR [SheetRecordsRepository]: $error');
      debugPrint('NETWORK ERROR [SheetRecordsRepository] stack: $stackTrace');
      rethrow;
    }
  }

  /// Оновлює один рядок у локальному кеші (для синхронізації UI після edit).
  Future<void> patchCachedRow({
    required String sheetTitle,
    required int rowIndex,
    required List<String> values,
  }) async {
    await _patchCachedRow(sheetTitle, rowIndex, values);
  }

  Future<void> _appendCachedRow(
    String sheetTitle,
    List<String> row, {
    List<String>? columns,
  }) async {
    final rows = await _cache.getSheetRows(sheetTitle);
    final updated = SheetCacheMutations.appendRow(rows, row, columns: columns);
    await _cache.saveSheetRows(sheetTitle, updated);
  }

  Future<void> _deleteCachedRow(String sheetTitle, int rowIndex) async {
    final rows = await _cache.getSheetRows(sheetTitle);
    final updated = SheetCacheMutations.deleteRow(rows, rowIndex);
    await _cache.saveSheetRows(sheetTitle, updated);
  }

  Future<void> _patchCachedRow(
    String sheetTitle,
    int rowIndex,
    List<String> values,
  ) async {
    final rows = await _cache.getSheetRows(sheetTitle);
    final updated = SheetCacheMutations.patchRow(rows, rowIndex, values);
    await _cache.saveSheetRows(sheetTitle, updated);
  }

  /// Конвертує [SheetData] у формат UI EditTab / RecordsManager.
  static List<Map<String, dynamic>> recordsToUiMaps(SheetData sheetData) {
    return sheetData.records
        .map(
          (record) => {
            'rowIndex': record.rowIndex,
            'row': List<String>.from(record.values),
          },
        )
        .toList()
        .reversed
        .toList();
  }

  /// Конвертує записи у рядки значень для HistoryScreen (без заголовка, нові зверху).
  static List<List<String>> recordsToDisplayRows(List<SheetRecord> records) {
    return records.map((record) => record.values).toList().reversed.toList();
  }
}
