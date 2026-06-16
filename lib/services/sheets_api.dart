import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';

class SheetsApi {
  
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

  // НОВА ФУНКЦІЯ: Читання даних з таблиці (ВИПРАВЛЕНА ТИПІЗАЦІЯ)
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
      
      // Чітко вказуємо Dart'у, що ми перетворюємо кожен рядок на список тексту (String)
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
}