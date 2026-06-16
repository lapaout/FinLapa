import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const FinLapaApp());
}

class FinLapaApp extends StatelessWidget {
  const FinLapaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinLapa',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = false;
  GoogleSignInAccount? _currentUser;

  // Запитуємо доступ до створення файлів на Диску та редагування Таблиць
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/drive.file',
      'https://www.googleapis.com/auth/spreadsheets',
    ],
  );

  @override
  void initState() {
    super.initState();
    _googleSignIn.onCurrentUserChanged.listen((account) {
      setState(() => _currentUser = account);
    });
    _googleSignIn.signInSilently(); // Пробуємо увійти автоматично, якщо вже входили
  }

  Future<void> _handleSignIn() async {
    try {
      await _googleSignIn.signIn();
    } catch (error) {
      _showSnackBar('❌ Помилка входу: $error');
    }
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ГОЛОВНА АВТОМАТИКА: Відправка даних
  Future<void> _sendData(String sheetName, String activity, String type, double amount) async {
    if (_currentUser == null) {
      _showSnackBar('🔒 Спочатку увійдіть у Google Акаунт!');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authHeaders = await _currentUser!.authHeaders;
      final token = authHeaders['Authorization'];

      // 1. Шукаємо або створюємо файл FinLapa_Data
      final spreadsheetId = await _getOrCreateSpreadsheet(token!);
      
      // 2. Пробуємо записати рядок
      bool success = await _appendRow(token, spreadsheetId, sheetName, activity, type, amount);
      
      // 3. Якщо аркуша немає — створюємо його і пишемо знову
      if (!success) {
        await _createSheetWithHeaders(token, spreadsheetId, sheetName);
        await _appendRow(token, spreadsheetId, sheetName, activity, type, amount);
      }

      _showSnackBar('✅ Записано на аркуш "$sheetName"!');
    } catch (e) {
      _showSnackBar('❌ Помилка API: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String> _getOrCreateSpreadsheet(String token) async {
    final searchUrl = Uri.parse('https://www.googleapis.com/drive/v3/files?q=name="FinLapa_Data" and mimeType="application/vnd.google-apps.spreadsheet"');
    final response = await http.get(searchUrl, headers: {'Authorization': token});
    final files = jsonDecode(response.body)['files'];

    if (files != null && files.isNotEmpty) {
      return files[0]['id'];
    }

    final createResponse = await http.post(
      Uri.parse('https://sheets.googleapis.com/v4/spreadsheets'),
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({'properties': {'title': 'FinLapa_Data'}}),
    );
    return jsonDecode(createResponse.body)['spreadsheetId'];
  }

  Future<bool> _appendRow(String token, String docId, String sheetName, String activity, String type, double amount) async {
    final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName!A1:append?valueInputOption=USER_ENTERED');
    final response = await http.post(
      url,
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'values': [[DateTime.now().toString().substring(0, 16), activity, type, amount]]
      }),
    );
    return response.statusCode == 200;
  }

  Future<void> _createSheetWithHeaders(String token, String docId, String sheetName) async {
    final url = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId:batchUpdate');
    await http.post(
      url,
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'requests': [{'addSheet': {'properties': {'title': sheetName}}}]
      }),
    );

    final headerUrl = Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$docId/values/$sheetName!A1:D1?valueInputOption=USER_ENTERED');
    await http.put(
      headerUrl,
      headers: {'Authorization': token, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'values': [['Дата і час', 'Діяльність', 'Тип операції', 'Сума']]
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FinLapa: Автопілот', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Блок авторизації
                    if (user != null) ...[
                      Text('Вхід виконано: ${user.email}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      ElevatedButton(onPressed: () => _googleSignIn.signOut(), child: const Text('Вийти з акаунта')),
                    ] else ...[
                      ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Увійти через Google'),
                        onPressed: _handleSignIn,
                      ),
                    ],
                    const Divider(height: 40),

                    // Кнопки бізнесу
                    const Text("Проєкт: Paper-Master", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                      icon: const Icon(Icons.add),
                      label: const Text('Продаж: 3D Друк (1500)'),
                      onPressed: () => _sendData('Paper-Master', '3D Друк / Фігурки', 'Продаж', 1500.0),
                    ),
                    
                    const SizedBox(height: 30),
                    
                    const Text("Проєкт: Pokemon TCG", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                      icon: const Icon(Icons.remove),
                      label: const Text('Витрата: Сингли (450)'),
                      onPressed: () => _sendData('Pokemon TCG', 'Купівля синглів', 'Витрата', 450.0),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}