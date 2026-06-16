import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static Future<bool> getModuleState(String moduleKey, {bool defaultState = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(moduleKey) ?? defaultState;
  }

  static Future<void> setModuleState(String moduleKey, bool isEnabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(moduleKey, isEnabled);
  }

  // НОВІ МЕТОДИ ДЛЯ ДИНАМІЧНИХ ДАШБОРДІВ
  // Зберігаємо список створених карток (назва + масив полів)
  static Future<void> saveCustomDashboards(String category, List<Map<String, dynamic>> dashboards) async {
    final prefs = await SharedPreferences.getInstance();
    final String jsonString = jsonEncode(dashboards);
    await prefs.setString('dashboards_$category', jsonString);
  }

  static Future<List<Map<String, dynamic>>> getCustomDashboards(String category) async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonString = prefs.getString('dashboards_$category');
    if (jsonString == null) return [];
    
    // Декодуємо JSON назад у список
    List<dynamic> decodedList = jsonDecode(jsonString);
    return decodedList.map((item) => Map<String, dynamic>.from(item)).toList();
  }
}