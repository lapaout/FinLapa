import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';

class SheetsApi {
  
  // --- НОВІ ФУНКЦІЇ ДЛЯ ХМАРНОГО КОНФІГУ (APP_CONFIG) ---

  // Читання конфігурації (БЕЗПЕЧНА ВЕРСІЯ З ПЕРЕВІРКОЮ МЕРЕЖІ)
  static Future<List<Map<String, dynamic>>> readAppConfig({required GoogleSignInAccount user}) async {
    try {
      final data = await readSheetData(user: user, sheetName: 'App_Config');
      if (data.isEmpty || data.length <= 1) return [];

      List<Map<String, dynamic>> loadedDashboards = [];
      for (var i = 1; i < data.length; i++) {
        final row = data[i];
        if (row.length < 4) continue;
        
        loadedDashboards.add({
          'title': row[0],
          'icon': int.tryParse(row[1]) ?? 57933,
          'color': int.tryParse(row[2]) ?? 4284901072,
          'fields': row[3].split(',').map((e) => e.trim()).toList(),
        });
      }
      return loadedDashboards;
    } catch (e) {
      final errorStr = e.toString();
      
      // КРИТИЧНЕ ВИПРАВЛЕННЯ: Якщо помилка викликана відсутністю інтернету,
      // ми ОБОВ'ЯЗКОВО прокидаємо її далі (rethrow), щоб додаток увімкнув офлайн-режим!
      if (errorStr.contains('SocketException') || 
          errorStr.contains('ClientException') || 
          errorStr.contains('Failed host lookup')) {
        rethrow; 
      }
      
      // Якщо це просто помилка 404 (аркуша App_Config ще немає в Google), повертаємо порожній список
      print("Аркуш конфігурації ще не створено користувачем: $e");
      return [];
    }
  }

  // Запис (перезапис) конфігурації
  static Future<void> saveAppConfig({required GoogleSignInAccount user, required List<Map<String, dynamic>> dashboards}) async {
    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);

    List<List<String>> rowsToSave = [
      ['Title', 'IconCode', 'ColorValue', 'Fields']
    ];

    for (var d in dashboards) {
      rowsToSave.add([
        d['title'].toString(),
        d['icon'].toString(),
        d['color'].toString(),
        (d['fields'] as List).join(','), // Перетворюємо список полів у рядок через кому
      ]);
    }

    // Пробуємо повністю перезаписати дані
    bool success = await _overwriteSheetData(token, docId, 'App_Config', rowsToSave);
    
    // Якщо аркуша App_Config ще немає в таблиці
    if (!success) {
      await _createSheetWithHeaders(token, docId, 'App_Config', rowsToSave[0]);
      await _overwriteSheetData(token, docId, 'App_Config', rowsToSave);
    }
  }

  // --- НОВА ФУНКЦІЯ: ПЕРЕЙМЕНУВАННЯ АРКУША В GOOGLE ТАБЛИЦІ ---
  static Future<void> renameSheet({
    required GoogleSignInAccount user,
    required String oldTitle,
    required String newTitle,
  }) async {
    if (oldTitle == newTitle) return; // Немає сенсу робити запит, якщо назва не змінилася

    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);

    // 1. Завантажуємо метадані всієї таблиці, щоб знайти sheetId потрібного аркуша
    final metaUrl = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId');
    final metaRes = await http.get(metaUrl, headers: {'Authorization': token});

    if (metaRes.statusCode != 200) throw Exception("Не вдалося отримати метадані таблиці");
    final metaData = jsonDecode(metaRes.body);

    int? targetSheetId;

    // Шукаємо наш аркуш за старою назвою
    for (var sheet in metaData['sheets']) {
      if (sheet['properties']['title'] == oldTitle) {
        targetSheetId = sheet['properties']['sheetId'];
        break;
      }
    }

    // Якщо такого аркуша немає (він порожній і ще не створився) — просто виходимо
    if (targetSheetId == null) return; 

    // 2. Відправляємо запит batchUpdate на перейменування
    final updateUrl = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId:batchUpdate');
    final updateBody = {
      "requests": [
        {
          "updateSheetProperties": {
            "properties": {
              "sheetId": targetSheetId,
              "title": newTitle
            },
            "fields": "title" // Вказуємо, що міняємо тільки назву
          }
        }
      ]
    };

    final updateRes = await http.post(
      updateUrl,
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode(updateBody),
    );

    if (updateRes.statusCode != 200) {
      throw Exception("Помилка при перейменуванні аркуша");
    }
  }

  // --- СТАРІ ПЕРЕВІРЕНІ ФУНКЦІЇ ---

  // Стара функція для витрат/складу (поки залишаємо)
  static Future<void> sendTransaction({required GoogleSignInAccount user, required String sheetName, required String activity, required String type, required double amount}) async {
    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);
    
    bool success = await _appendDynamicRow(token, docId, sheetName, [DateTime.now().toString().substring(0, 16), activity, type, amount]);
    if (!success) {
      await _createSheetWithHeaders(token, docId, sheetName, ['Дата і час', 'Діяльність', 'Тип операції', 'Сума']);
      await _appendDynamicRow(token, docId, sheetName, [DateTime.now().toString().substring(0, 16), activity, type, amount]);
    }
  }

  // Динамічний запис (Конструктор)
  static Future<void> sendDynamicData({required GoogleSignInAccount user, required String sheetName, required List<String> columns, required List<dynamic> values}) async {
    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);
    
    List<String> finalHeaders = ['Дата і час', ...columns];
    List<dynamic> finalValues = [DateTime.now().toString().substring(0, 16), ...values];

    bool success = await _appendDynamicRow(token, docId, sheetName, finalValues);
    if (!success) {
      await _createSheetWithHeaders(token, docId, sheetName, finalHeaders);
      await _appendDynamicRow(token, docId, sheetName, finalValues);
    }
  }

  // Читання даних з таблиці
  static Future<List<List<String>>> readSheetData({required GoogleSignInAccount user, required String sheetName}) async {
    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);

    final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName');
    final response = await http.get(url, headers: {'Authorization': token});

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final values = data['values'] as List<dynamic>?;
      if (values == null) return [];
      
      return values.map<List<String>>((row) {
        return (row as List<dynamic>).map<String>((e) => e.toString()).toList();
      }).toList();
      
    } else {
      throw Exception('Не вдалося завантажити дані. Можливо, таблиця ще порожня.');
    }
  }

  // --- Внутрішні методи API ---
  static Future<String> _getOrCreateSpreadsheet(String token) async {
    final searchUrl = Uri.parse('https://www.googleapis.com/drive/v3/files?q=name="FinLapa_Data" and mimeType="application/vnd.google-apps.spreadsheet"');
    final response = await http.get(searchUrl, headers: {'Authorization': token});
    final files = jsonDecode(response.body)['files'];
    if (files != null && files.isNotEmpty) return files[0]['id'];

    final createResponse = await http.post(
      Uri.parse('https://sheets.googleapis.com/v4/spreadsheets'),
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'properties': {'title': 'FinLapa_Data'}}),
    );
    return jsonDecode(createResponse.body)['spreadsheetId'];
  }

  static Future<bool> _appendDynamicRow(String token, String docId, String sheetName, List<dynamic> rowData) async {
    final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName!A1:append?valueInputOption=USER_ENTERED');
    final response = await http.post(url, headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'values': [rowData]}),
    );
    return response.statusCode == 200;
  }

  static Future<void> _createSheetWithHeaders(String token, String docId, String sheetName, List<String> headers) async {
    final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId:batchUpdate');
    await http.post(url, headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'requests': [{'addSheet': {'properties': {'title': sheetName}}}]}),
    );
    final headerUrl = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName!A1:Z1?valueInputOption=USER_ENTERED');
    await http.put(headerUrl, headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'values': [headers]}),
    );
  }

  static Future<bool> _overwriteSheetData(String token, String docId, String sheetName, List<List<dynamic>> rows) async {
    final clearUrl = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName:clear');
    await http.post(clearUrl, headers: {'Authorization': token});

    final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName!A1?valueInputOption=USER_ENTERED');
    final response = await http.put(url, headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'values': rows}),
    );
    return response.statusCode == 200;
  }
// --- ФУНКЦІЯ РЕДАГУВАННЯ КОНКРЕТНОГО РЯДКА ЗА ЙОГО ІНДЕКСОМ ---
  static Future<void> updateRowData({
    required GoogleSignInAccount user,
    required String sheetName,
    required int rowIndex, // Номер рядка в Google Sheets (починаючи з 1)
    required List<dynamic> newValues,
  }) async {
    final authHeaders = await user.authHeaders;
    final token = authHeaders['Authorization']!;
    final docId = await _getOrCreateSpreadsheet(token);

    // Формуємо діапазон, наприклад: "Продажі!A45:Z45"
    // Юзер вводить дані з датою, тому DateTime ми теж туди передамо
    final range = '$sheetName!A$rowIndex';

    final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$range?valueInputOption=USER_ENTERED');
    
    final response = await http.put(
      url,
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'values': [newValues]}),
    );

    if (response.statusCode != 200) {
      throw Exception('Не вдалося оновити рядок в Google Таблиці: ${response.body}');
    }
  }

}