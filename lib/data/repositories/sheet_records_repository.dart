import 'package:google_sign_in/google_sign_in.dart';

import '../../core/data_result.dart';
import '../../core/network_exception.dart';
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
      print('NETWORK ERROR [SheetRecordsRepository]: $error');
      print('NETWORK ERROR [SheetRecordsRepository] stack: $stackTrace');

      if (isNetworkError(error)) {
        final cached = await _cache.getSheetData(sheetTitle);
        print(
          'NETWORK ERROR [SheetRecordsRepository]: offline fallback, '
          'cache records=${cached.records.length}',
        );
        return DataResult.cache(cached, error: classifyError(error));
      }

      print(
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
  }) async {
    try {
      List<String> resolvedColumns;

      if (columns != null && columns.isNotEmpty) {
        resolvedColumns = columns;
      } else {
        final existingRows = await SheetsApi.readSheetData(
          user: user,
          sheetName: sheetTitle,
        );
        resolvedColumns = existingRows.isNotEmpty && existingRows.first.length > 1
            ? existingRows.first.sublist(1)
            : List.generate(values.length, (i) => 'Поле ${i + 1}');
      }

      await SheetsApi.sendDynamicData(
        user: user,
        sheetName: sheetTitle,
        columns: resolvedColumns,
        values: values,
      );

      final rows = await SheetsApi.readSheetData(
        user: user,
        sheetName: sheetTitle,
      );
      await _cache.saveSheetRows(sheetTitle, rows);
      print('NETWORK OK [appendRecord]: appended to "$sheetTitle"');
    } catch (error, stackTrace) {
      print('NETWORK ERROR [SheetRecordsRepository]: $error');
      print('NETWORK ERROR [SheetRecordsRepository] stack: $stackTrace');
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
      print('NETWORK OK [updateRecord]: row $rowIndex in "$sheetTitle"');
    } catch (error, stackTrace) {
      print('NETWORK ERROR [SheetRecordsRepository]: $error');
      print('NETWORK ERROR [SheetRecordsRepository] stack: $stackTrace');
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

      final rows = await SheetsApi.readSheetData(
        user: user,
        sheetName: sheetTitle,
      );
      await _cache.saveSheetRows(sheetTitle, rows);
      print('NETWORK OK [deleteRecord]: row $rowIndex in "$sheetTitle"');
    } catch (error, stackTrace) {
      print('NETWORK ERROR [SheetRecordsRepository]: $error');
      print('NETWORK ERROR [SheetRecordsRepository] stack: $stackTrace');
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

  Future<void> _patchCachedRow(
    String sheetTitle,
    int rowIndex,
    List<String> values,
  ) async {
    final rows = await _cache.getSheetRows(sheetTitle);
    if (rows.isEmpty) return;

    final dataRowIndex = rowIndex - 1;
    if (dataRowIndex < 1 || dataRowIndex >= rows.length) return;

    rows[dataRowIndex] = values;
    await _cache.saveSheetRows(sheetTitle, rows);
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
