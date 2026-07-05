import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../models/dashboard.dart';
import '../../models/finlapa_spreadsheet.dart';
import 'google_api_auth.dart';
import 'local_cache_data_source.dart';

/// HTTP-клієнт для Google Sheets / Drive. Без логіки кешу та парсингу доменних моделей.
class SheetsApi {
  static const String appConfigSheetName = 'App_Config';
  static const String finLapaFolderName = 'FinLapa';

  static final LocalCacheDataSource _localCache = LocalCacheDataSource();
  static String? _cachedFinLapaFolderId;

  /// Скидає кеш ID папки FinLapa (logout / зміна акаунта).
  static void clearFolderCache() {
    _cachedFinLapaFolderId = null;
  }

  static Future<List<List<String>>> readSheetData({
    required GoogleSignInAccount user,
    required String sheetName,
  }) async {
    final authHeaders = await _authHeaders(user);
    final docId = await _requireActiveSpreadsheetId();

    final url = _valuesUrl(docId, sheetName);
    final response = await http.get(url, headers: authHeaders);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final values = data['values'] as List<dynamic>?;
      if (values == null) return [];

      return values.map<List<String>>((row) {
        return (row as List<dynamic>).map<String>((e) => e.toString()).toList();
      }).toList();
    }

    if (_isMissingSheetResponse(response.statusCode, response.body)) {
      return [];
    }

    throw Exception(
      'Помилка Google Sheets (${response.statusCode}): ${response.body}',
    );
  }

  static Future<void> writeAppConfig({
    required GoogleSignInAccount user,
    required List<Dashboard> dashboards,
  }) async {
    final rows = Dashboard.sheetRowsFromList(dashboards);
    await overwriteSheetData(
      user: user,
      sheetName: appConfigSheetName,
      rows: rows,
      createHeaders: Dashboard.appConfigHeader,
    );
  }

  static Future<void> overwriteSheetData({
    required GoogleSignInAccount user,
    required String sheetName,
    required List<List<String>> rows,
    List<String>? createHeaders,
  }) async {
    final authHeaders = await _authHeaders(user);
    final docId = await _requireActiveSpreadsheetId();

    var success = await _overwriteSheetData(
      authHeaders,
      docId,
      sheetName,
      rows,
    );

    if (!success) {
      final headers = createHeaders ?? (rows.isNotEmpty ? rows.first : ['']);
      await _createSheetWithHeaders(authHeaders, docId, sheetName, headers);
      success = await _overwriteSheetData(
        authHeaders,
        docId,
        sheetName,
        rows,
      );
    }

    if (!success) {
      throw Exception('Не вдалося записати дані в аркуш "$sheetName"');
    }
  }

  static Future<void> renameSheet({
    required GoogleSignInAccount user,
    required String oldTitle,
    required String newTitle,
  }) async {
    if (oldTitle == newTitle) return;

    final authHeaders = await _authHeaders(user);
    final docId = await _requireActiveSpreadsheetId();
    final targetSheetId = await _findSheetIdByTitle(
      authHeaders: authHeaders,
      docId: docId,
      sheetTitle: oldTitle,
    );

    if (targetSheetId == null) return;

    await _batchUpdate(
      authHeaders: authHeaders,
      docId: docId,
      requests: [
        {
          'updateSheetProperties': {
            'properties': {
              'sheetId': targetSheetId,
              'title': newTitle,
            },
            'fields': 'title',
          },
        },
      ],
      errorMessage: 'Помилка при перейменуванні аркуша',
    );
  }

  /// Видаляє один рядок за 1-based індексом Google Sheets.
  static Future<void> deleteRow({
    required GoogleSignInAccount user,
    required String sheetName,
    required int rowIndex,
  }) async {
    final authHeaders = await _authHeaders(user);
    final docId = await _requireActiveSpreadsheetId();
    final sheetId = await _findSheetIdByTitle(
      authHeaders: authHeaders,
      docId: docId,
      sheetTitle: sheetName,
    );

    if (sheetId == null) {
      throw Exception('Аркуш "$sheetName" не знайдено');
    }

    await _batchUpdate(
      authHeaders: authHeaders,
      docId: docId,
      requests: [
        {
          'deleteDimension': {
            'range': {
              'sheetId': sheetId,
              'dimension': 'ROWS',
              'startIndex': rowIndex - 1,
              'endIndex': rowIndex,
            },
          },
        },
      ],
      errorMessage: 'Не вдалося видалити рядок $rowIndex в "$sheetName"',
    );
  }

  /// Повністю видаляє аркуш з Google-таблиці.
  static Future<void> deleteSheet({
    required GoogleSignInAccount user,
    required String sheetName,
  }) async {
    final authHeaders = await _authHeaders(user);
    final docId = await _requireActiveSpreadsheetId();
    final sheetId = await _findSheetIdByTitle(
      authHeaders: authHeaders,
      docId: docId,
      sheetTitle: sheetName,
    );

    if (sheetId == null) return;

    await _batchUpdate(
      authHeaders: authHeaders,
      docId: docId,
      requests: [
        {
          'deleteSheet': {
            'sheetId': sheetId,
          },
        },
      ],
      errorMessage: 'Не вдалося видалити аркуш "$sheetName"',
    );
  }

  static Future<int?> _findSheetIdByTitle({
    required Map<String, String> authHeaders,
    required String docId,
    required String sheetTitle,
  }) async {
    final metaUrl = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId',
    );
    final metaRes = await http.get(metaUrl, headers: authHeaders);

    if (metaRes.statusCode != 200) {
      throw Exception(
        'Не вдалося отримати метадані таблиці (${metaRes.statusCode}): ${metaRes.body}',
      );
    }

    final metaData = jsonDecode(metaRes.body) as Map<String, dynamic>;
    final sheets = metaData['sheets'] as List<dynamic>? ?? [];

    for (final sheet in sheets) {
      if (sheet['properties']['title'] == sheetTitle) {
        return sheet['properties']['sheetId'] as int;
      }
    }

    return null;
  }

  static Future<void> _batchUpdate({
    required Map<String, String> authHeaders,
    required String docId,
    required List<Map<String, dynamic>> requests,
    required String errorMessage,
  }) async {
    final updateUrl = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId:batchUpdate',
    );
    final updateRes = await http.post(
      updateUrl,
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'requests': requests}),
    );

    if (updateRes.statusCode != 200) {
      throw Exception(
        '$errorMessage (${updateRes.statusCode}): ${updateRes.body}',
      );
    }
  }

  static Future<void> sendTransaction({
    required GoogleSignInAccount user,
    required String sheetName,
    required String activity,
    required String type,
    required double amount,
  }) async {
    final authHeaders = await _authHeaders(user);
    final docId = await _requireActiveSpreadsheetId();

    final row = [
      DateTime.now().toString().substring(0, 16),
      activity,
      type,
      amount,
    ];

    var success = await _appendDynamicRow(authHeaders, docId, sheetName, row);
    if (!success) {
      await _createSheetWithHeaders(
        authHeaders,
        docId,
        sheetName,
        ['Дата і час', 'Діяльність', 'Тип операції', 'Сума'],
      );
      success = await _appendDynamicRow(authHeaders, docId, sheetName, row);
    }

    if (!success) {
      throw Exception('Не вдалося записати транзакцію в "$sheetName"');
    }
  }

  static Future<void> sendDynamicData({
    required GoogleSignInAccount user,
    required String sheetName,
    required List<String> columns,
    required List<dynamic> values,
    String? recordDateTime,
  }) async {
    final authHeaders = await _authHeaders(user);
    final docId = await _requireActiveSpreadsheetId();

    final headers = ['Дата і час', ...columns];
    final row = [
      recordDateTime ?? DateTime.now().toString().substring(0, 16),
      ...values,
    ];

    var success = await _appendDynamicRow(authHeaders, docId, sheetName, row);
    if (!success) {
      await _createSheetWithHeaders(authHeaders, docId, sheetName, headers);
      success = await _appendDynamicRow(authHeaders, docId, sheetName, row);
    }

    if (!success) {
      throw Exception('Не вдалося записати дані в "$sheetName"');
    }
  }

  static Future<void> updateRowData({
    required GoogleSignInAccount user,
    required String sheetName,
    required int rowIndex,
    required List<dynamic> newValues,
  }) async {
    final authHeaders = await _authHeaders(user);
    final docId = await _requireActiveSpreadsheetId();

    final range = _sheetRange(sheetName, 'A$rowIndex');
    final url = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$range?valueInputOption=USER_ENTERED',
    );

    final response = await http.put(
      url,
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'values': [newValues]}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Помилка оновлення рядка (${response.statusCode}): ${response.body}',
      );
    }
  }

  static Future<Map<String, String>> _authHeaders(
    GoogleSignInAccount user,
  ) async {
    return GoogleApiAuth.buildHeaders(user);
  }

  /// Знаходить або створює папку FinLapa в корені Google Drive.
  static Future<String> ensureFinLapaFolder(
    Map<String, String> authHeaders,
  ) async {
    if (_cachedFinLapaFolderId != null && _cachedFinLapaFolderId!.isNotEmpty) {
      return _cachedFinLapaFolderId!;
    }

    final query =
        "name = '$finLapaFolderName' and mimeType = 'application/vnd.google-apps.folder' "
        "and trashed = false and 'root' in parents";
    final searchUrl = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files',
      {
        'q': query,
        'fields': 'files(id,name)',
        'pageSize': '1',
      },
    );

    final response = await http.get(searchUrl, headers: authHeaders);
    if (response.statusCode != 200) {
      throw Exception(
        'Пошук папки FinLapa не вдався (${response.statusCode}): ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final files = body['files'] as List<dynamic>? ?? [];
    if (files.isNotEmpty) {
      _cachedFinLapaFolderId = files.first['id'] as String;
      return _cachedFinLapaFolderId!;
    }

    final createUrl = Uri.parse('https://www.googleapis.com/drive/v3/files');
    final createResponse = await http.post(
      createUrl,
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': finLapaFolderName,
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );

    if (createResponse.statusCode != 200) {
      throw Exception(
        'Створення папки FinLapa не вдалося (${createResponse.statusCode}): ${createResponse.body}',
      );
    }

    final createBody = jsonDecode(createResponse.body) as Map<String, dynamic>;
    final folderId = createBody['id'] as String?;
    if (folderId == null || folderId.isEmpty) {
      throw Exception('Drive API не повернув id нової папки FinLapa');
    }

    _cachedFinLapaFolderId = folderId;
    return folderId;
  }

  /// Усі Google Sheets всередині папки FinLapa.
  static Future<List<FinLapaSpreadsheet>> listSpreadsheetsInFinLapaFolder({
    required GoogleSignInAccount user,
  }) async {
    final authHeaders = await _authHeaders(user);
    final folderId = await ensureFinLapaFolder(authHeaders);

    final query =
        "'$folderId' in parents and trashed = false "
        "and mimeType = 'application/vnd.google-apps.spreadsheet'";
    final searchUrl = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files',
      {
        'q': query,
        'fields': 'files(id,name,createdTime)',
        'orderBy': 'name',
        'pageSize': '100',
      },
    );

    final response = await http.get(searchUrl, headers: authHeaders);
    if (response.statusCode != 200) {
      throw Exception(
        'Пошук таблиць у FinLapa не вдався (${response.statusCode}): ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final files = body['files'] as List<dynamic>? ?? [];

    return files
        .map(
          (file) => FinLapaSpreadsheet(
            id: file['id'] as String,
            name: file['name'] as String? ?? 'Без назви',
          ),
        )
        .toList();
  }

  /// Створює нову таблицю в папці FinLapa та ініціалізує App_Config.
  static Future<FinLapaSpreadsheet> createSpreadsheetInFinLapaFolder({
    required GoogleSignInAccount user,
    required String title,
  }) async {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw Exception('Назва таблиці не може бути порожньою');
    }

    final authHeaders = await _authHeaders(user);
    final folderId = await ensureFinLapaFolder(authHeaders);
    final docId = await _createSpreadsheetFile(authHeaders, trimmedTitle);

    await _moveFileToFolder(
      authHeaders: authHeaders,
      fileId: docId,
      folderId: folderId,
    );

    await _localCache.setActiveWorkspace(id: docId, name: trimmedTitle);
    await initializeAppConfig(user: user);

    return FinLapaSpreadsheet(id: docId, name: trimmedTitle);
  }

  /// Базова структура App_Config для нової таблиці.
  static Future<void> initializeAppConfig({
    required GoogleSignInAccount user,
  }) async {
    await writeAppConfig(user: user, dashboards: const []);
  }

  /// Видаляє таблицю на Google Drive (ID береться зі списку FinLapa).
  static Future<void> deleteSpreadsheetInFinLapaFolder({
    required GoogleSignInAccount user,
    required String spreadsheetId,
  }) async {
    final authHeaders = await _authHeaders(user);
    final url = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files/$spreadsheetId',
    );
    final response = await http.delete(url, headers: authHeaders);

    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception(
        'Не вдалося видалити таблицю (${response.statusCode}): ${response.body}. '
        'Переконайтеся, що додаток має доступ drive.file і увійдіть знову.',
      );
    }
  }

  /// Перевіряє, що файл існує і належить папці FinLapa.
  static Future<bool> isSpreadsheetInFinLapaFolder({
    required GoogleSignInAccount user,
    required String spreadsheetId,
  }) async {
    final authHeaders = await _authHeaders(user);
    final folderId = await ensureFinLapaFolder(authHeaders);

    final query =
        "id = '$spreadsheetId' and '$folderId' in parents and trashed = false "
        "and mimeType = 'application/vnd.google-apps.spreadsheet'";
    final searchUrl = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files',
      {
        'q': query,
        'fields': 'files(id,name)',
        'pageSize': '1',
      },
    );

    final response = await http.get(searchUrl, headers: authHeaders);
    if (response.statusCode != 200) {
      return false;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final files = body['files'] as List<dynamic>? ?? [];
    return files.isNotEmpty;
  }

  /// Отримує назву таблиці лише якщо вона в папці FinLapa.
  static Future<String?> getSpreadsheetName({
    required GoogleSignInAccount user,
    required String spreadsheetId,
  }) async {
    final authHeaders = await _authHeaders(user);
    final folderId = await ensureFinLapaFolder(authHeaders);

    final query =
        "id = '$spreadsheetId' and '$folderId' in parents and trashed = false "
        "and mimeType = 'application/vnd.google-apps.spreadsheet'";
    final searchUrl = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files',
      {
        'q': query,
        'fields': 'files(name)',
        'pageSize': '1',
      },
    );

    final response = await http.get(searchUrl, headers: authHeaders);
    if (response.statusCode != 200) {
      return null;
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final files = body['files'] as List<dynamic>? ?? [];
    if (files.isEmpty) {
      return null;
    }

    return files.first['name'] as String?;
  }

  static Future<String> _requireActiveSpreadsheetId() async {
    final activeId = await _localCache.getActiveSpreadsheetId();
    if (activeId != null && activeId.isNotEmpty) {
      return activeId;
    }

    throw Exception(
      'Активна таблиця не обрана. Оберіть або створіть таблицю у FinLapa.',
    );
  }

  static Future<String> _createSpreadsheetFile(
    Map<String, String> authHeaders,
    String title,
  ) async {
    final createResponse = await http.post(
      Uri.parse('https://sheets.googleapis.com/v4/spreadsheets'),
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'properties': {'title': title}}),
    );

    if (createResponse.statusCode != 200) {
      throw Exception(
        'Create spreadsheet failed (${createResponse.statusCode}): ${createResponse.body}',
      );
    }

    final createBody = jsonDecode(createResponse.body) as Map<String, dynamic>;
    final docId = createBody['spreadsheetId'] as String?;
    if (docId == null || docId.isEmpty) {
      throw Exception(
        'Create spreadsheet returned no spreadsheetId: ${createResponse.body}',
      );
    }

    return docId;
  }

  static Future<void> _moveFileToFolder({
    required Map<String, String> authHeaders,
    required String fileId,
    required String folderId,
  }) async {
    final url = Uri.parse(
      'https://www.googleapis.com/drive/v3/files/$fileId'
      '?addParents=$folderId&fields=id,parents',
    );
    final response = await http.patch(url, headers: authHeaders);

    if (response.statusCode != 200) {
      throw Exception(
        'Не вдалося перемістити таблицю в папку FinLapa '
        '(${response.statusCode}): ${response.body}',
      );
    }
  }

  static Uri _valuesUrl(String docId, String range) {
    return Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/${_sheetRange(range)}',
    );
  }

  /// Формує A1-діапазон з URL-кодуванням для Google Sheets API.
  static String _sheetRange(String sheetName, [String? cellRange]) {
    final needsQuotes = !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(sheetName);
    final safeSheetName = needsQuotes
        ? "'${sheetName.replaceAll("'", "''")}'"
        : sheetName;
    final range = cellRange != null ? '$safeSheetName!$cellRange' : safeSheetName;
    return Uri.encodeComponent(range);
  }

  static bool _isMissingSheetResponse(int statusCode, String body) {
    if (statusCode == 404) return true;
    if (statusCode != 400) return false;

    return body.contains('Unable to parse range') ||
        body.contains('Requested entity was not found');
  }

  static Future<bool> _appendDynamicRow(
    Map<String, String> authHeaders,
    String docId,
    String sheetName,
    List<dynamic> rowData,
  ) async {
    final range = _sheetRange(sheetName, 'A1');
    final url = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$range:append?valueInputOption=USER_ENTERED',
    );
    final response = await http.post(
      url,
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'values': [rowData]}),
    );
    return response.statusCode == 200;
  }

  static Future<void> _createSheetWithHeaders(
    Map<String, String> authHeaders,
    String docId,
    String sheetName,
    List<String> headers,
  ) async {
    final url = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId:batchUpdate',
    );
    final createRes = await http.post(
      url,
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'requests': [
          {'addSheet': {'properties': {'title': sheetName}}},
        ],
      }),
    );

    if (createRes.statusCode != 200) {
      throw Exception(
        'Не вдалося створити аркуш "$sheetName" (${createRes.statusCode}): ${createRes.body}',
      );
    }

    final headerRange = _sheetRange(sheetName, 'A1:Z1');
    final headerUrl = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$headerRange?valueInputOption=USER_ENTERED',
    );
    final headerRes = await http.put(
      headerUrl,
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'values': [headers]}),
    );

    if (headerRes.statusCode != 200) {
      throw Exception(
        'Не вдалося записати заголовки аркуша "$sheetName" (${headerRes.statusCode}): ${headerRes.body}',
      );
    }
  }

  static Future<bool> _overwriteSheetData(
    Map<String, String> authHeaders,
    String docId,
    String sheetName,
    List<List<dynamic>> rows,
  ) async {
    final clearRange = _sheetRange(sheetName);
    final clearUrl = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$clearRange:clear',
    );
    final clearRes = await http.post(clearUrl, headers: authHeaders);

    // Аркуш може ще не існувати — clear поверне 400, але put/create відновить.
    if (clearRes.statusCode != 200 && clearRes.statusCode != 400) {
      print(
        'SheetsApi: clear warning for "$sheetName" '
        '(${clearRes.statusCode}): ${clearRes.body}',
      );
    }

    final writeRange = _sheetRange(sheetName, 'A1');
    final url = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$writeRange?valueInputOption=USER_ENTERED',
    );
    final response = await http.put(
      url,
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'values': rows}),
    );

    if (response.statusCode != 200) {
      print(
        'SheetsApi: overwrite failed for "$sheetName" '
        '(${response.statusCode}): ${response.body}',
      );
    }

    return response.statusCode == 200;
  }
}
