import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../models/dashboard.dart';

/// HTTP-клієнт для Google Sheets / Drive. Без логіки кешу та парсингу доменних моделей.
class SheetsApi {
  static const String appConfigSheetName = 'App_Config';
  static const String spreadsheetName = 'FinLapa_Data';

  static Future<List<List<String>>> readSheetData({
    required GoogleSignInAccount user,
    required String sheetName,
  }) async {
    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);

    final url = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName',
    );
        final response = await http.get(url, headers: {'Authorization': token});

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final values = data['values'] as List<dynamic>?;
      if (values == null) return [];

      return values.map<List<String>>((row) {
        return (row as List<dynamic>).map<String>((e) => e.toString()).toList();
      }).toList();
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
    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);

    final success = await _overwriteSheetData(token, docId, sheetName, rows);

    if (!success) {
      final headers = createHeaders ?? (rows.isNotEmpty ? rows.first : ['']);
      await _createSheetWithHeaders(token, docId, sheetName, headers);
      await _overwriteSheetData(token, docId, sheetName, rows);
    }
  }

  static Future<void> renameSheet({
    required GoogleSignInAccount user,
    required String oldTitle,
    required String newTitle,
  }) async {
    if (oldTitle == newTitle) return;

    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);

    final metaUrl = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId',
    );
    final metaRes = await http.get(metaUrl, headers: {'Authorization': token});

    if (metaRes.statusCode != 200) {
      throw Exception('Не вдалося отримати метадані таблиці');
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
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode(updateBody),
    );

    if (updateRes.statusCode != 200) {
      throw Exception('Помилка при перейменуванні аркуша');
    }
  }

  static Future<void> sendTransaction({
    required GoogleSignInAccount user,
    required String sheetName,
    required String activity,
    required String type,
    required double amount,
  }) async {
    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);

    final row = [
      DateTime.now().toString().substring(0, 16),
      activity,
      type,
      amount,
    ];

    var success = await _appendDynamicRow(token, docId, sheetName, row);
    if (!success) {
      await _createSheetWithHeaders(
        token,
        docId,
        sheetName,
        ['Дата і час', 'Діяльність', 'Тип операції', 'Сума'],
      );
      await _appendDynamicRow(token, docId, sheetName, row);
    }
  }

  static Future<void> sendDynamicData({
    required GoogleSignInAccount user,
    required String sheetName,
    required List<String> columns,
    required List<dynamic> values,
  }) async {
    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);

    final headers = ['Дата і час', ...columns];
    final row = [DateTime.now().toString().substring(0, 16), ...values];

    var success = await _appendDynamicRow(token, docId, sheetName, row);
    if (!success) {
      await _createSheetWithHeaders(token, docId, sheetName, headers);
      await _appendDynamicRow(token, docId, sheetName, row);
    }
  }

  static Future<void> updateRowData({
    required GoogleSignInAccount user,
    required String sheetName,
    required int rowIndex,
    required List<dynamic> newValues,
  }) async {
    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);

    final range = '$sheetName!A$rowIndex';
    final url = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$range?valueInputOption=USER_ENTERED',
    );

    final response = await http.put(
      url,
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'values': [newValues]}),
    );

        if (response.statusCode != 200) {
      throw Exception(
        'Помилка оновлення рядка (${response.statusCode}): ${response.body}',
      );
    }
  }

  static Future<String> _getOrCreateSpreadsheet(String token) async {
    final searchUrl = Uri.parse(
      'https://www.googleapis.com/drive/v3/files?q=name="$spreadsheetName" and mimeType="application/vnd.google-apps.spreadsheet"',
    );
    final response = await http.get(
      searchUrl,
      headers: {'Authorization': token},
    );
    final files = jsonDecode(response.body)['files'];
    if (files != null && files.isNotEmpty) return files[0]['id'];

    final createResponse = await http.post(
      Uri.parse('https://sheets.googleapis.com/v4/spreadsheets'),
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'properties': {'title': spreadsheetName}}),
    );
    return jsonDecode(createResponse.body)['spreadsheetId'];
  }

  static Future<bool> _appendDynamicRow(
    String token,
    String docId,
    String sheetName,
    List<dynamic> rowData,
  ) async {
    final url = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName!A1:append?valueInputOption=USER_ENTERED',
    );
    final response = await http.post(
      url,
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'values': [rowData]}),
    );
    return response.statusCode == 200;
  }

  static Future<void> _createSheetWithHeaders(
    String token,
    String docId,
    String sheetName,
    List<String> headers,
  ) async {
    final url = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId:batchUpdate',
    );
    await http.post(
      url,
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'requests': [
          {'addSheet': {'properties': {'title': sheetName}}},
        ],
      }),
    );

    final headerUrl = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName!A1:Z1?valueInputOption=USER_ENTERED',
    );
    await http.put(
      headerUrl,
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'values': [headers]}),
    );
  }

  static Future<bool> _overwriteSheetData(
    String token,
    String docId,
    String sheetName,
    List<List<dynamic>> rows,
  ) async {
    final clearUrl = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName:clear',
    );
    await http.post(clearUrl, headers: {'Authorization': token});

    final url = Uri.parse(
      'https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName!A1?valueInputOption=USER_ENTERED',
    );
    final response = await http.put(
      url,
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'values': rows}),
    );
    return response.statusCode == 200;
  }
}
