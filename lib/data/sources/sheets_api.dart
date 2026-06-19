import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../models/dashboard.dart';
import 'local_cache_data_source.dart';

/// HTTP-клієнт для Google Sheets / Drive. Без логіки кешу та парсингу доменних моделей.
class SheetsApi {
  static const String appConfigSheetName = 'App_Config';
  static const String spreadsheetName = 'FinLapa_Data';

  static final LocalCacheDataSource _localCache = LocalCacheDataSource();

  static Future<List<List<String>>> readSheetData({
    required GoogleSignInAccount user,
    required String sheetName,
  }) async {
    final authHeaders = await _authHeaders(user);
    final docId = await _getOrCreateSpreadsheet(authHeaders);

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
    final docId = await _getOrCreateSpreadsheet(authHeaders);

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
    final docId = await _getOrCreateSpreadsheet(authHeaders);

    final metaUrl = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId',
    );
    final metaRes = await http.get(metaUrl, headers: authHeaders);

    if (metaRes.statusCode != 200) {
      throw Exception(
        'Не вдалося отримати метадані таблиці (${metaRes.statusCode}): ${metaRes.body}',
      );
    }

    final metaData = jsonDecode(metaRes.body);
    int? targetSheetId;

    for (final sheet in metaData['sheets']) {
      if (sheet['properties']['title'] == oldTitle) {
        targetSheetId = sheet['properties']['sheetId'];
        break;
      }
    }

    if (targetSheetId == null) return;

    final updateUrl = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId:batchUpdate',
    );
    final updateBody = {
      'requests': [
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
    };

    final updateRes = await http.post(
      updateUrl,
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(updateBody),
    );

    if (updateRes.statusCode != 200) {
      throw Exception(
        'Помилка при перейменуванні аркуша (${updateRes.statusCode}): ${updateRes.body}',
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
    final docId = await _getOrCreateSpreadsheet(authHeaders);

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
  }) async {
    final authHeaders = await _authHeaders(user);
    final docId = await _getOrCreateSpreadsheet(authHeaders);

    final headers = ['Дата і час', ...columns];
    final row = [DateTime.now().toString().substring(0, 16), ...values];

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
    final docId = await _getOrCreateSpreadsheet(authHeaders);

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
    final headers = await user.authHeaders;

    final authorization = headers['Authorization'];
    if (authorization == null || authorization.isEmpty) {
      throw Exception(
        'Authorization token is missing. Sign out and sign in again.',
      );
    }

    return Map<String, String>.from(headers);
  }

  static Future<String> _getOrCreateSpreadsheet(
    Map<String, String> authHeaders,
  ) async {
    final cachedDocId = await _localCache.getSpreadsheetDocId();
    if (cachedDocId != null && cachedDocId.isNotEmpty) {
      return cachedDocId;
    }

    final existingDocId = await _findSpreadsheetOnDrive(authHeaders);
    if (existingDocId != null) {
      await _localCache.saveSpreadsheetDocId(existingDocId);
      return existingDocId;
    }

    final newDocId = await _createSpreadsheet(authHeaders);
    await _localCache.saveSpreadsheetDocId(newDocId);
    return newDocId;
  }

  /// Шукає існуючий файл FinLapa_Data на Google Drive (не в кошику).
  static Future<String?> _findSpreadsheetOnDrive(
    Map<String, String> authHeaders,
  ) async {
    final query =
        "name = '$spreadsheetName' and trashed = false and mimeType = 'application/vnd.google-apps.spreadsheet'";
    final searchUrl = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files',
      {
        'q': query,
        'fields': 'files(id,name)',
        'orderBy': 'createdTime',
        'pageSize': '10',
      },
    );

    final response = await http.get(searchUrl, headers: authHeaders);

    if (response.statusCode != 200) {
      throw Exception(
        'Drive search failed (${response.statusCode}): ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final files = body['files'] as List<dynamic>?;
    if (files == null || files.isEmpty) {
      return null;
    }

    if (files.length > 1) {
      print(
        'SheetsApi: знайдено ${files.length} файлів "$spreadsheetName", '
        'використовуємо найстаріший (${files[0]['id']})',
      );
    }

    return files[0]['id'] as String;
  }

  /// Створює нову Google-таблицю FinLapa_Data.
  static Future<String> _createSpreadsheet(
    Map<String, String> authHeaders,
  ) async {
    final createResponse = await http.post(
      Uri.parse('https://sheets.googleapis.com/v4/spreadsheets'),
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'properties': {'title': spreadsheetName}}),
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
