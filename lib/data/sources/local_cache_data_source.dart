import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/dashboard.dart';
import '../../models/module_settings.dart';
import '../../models/module_type.dart';
import '../../models/sheet_data.dart';

/// Локальне сховище даних поверх SharedPreferences.
///
/// Використовує стабільні ключі SharedPreferences для зворотної сумісності
/// з попередніми версіями додатку.
class LocalCacheDataSource {
  static const String dashboardsCategory = 'income_cache';
  static const String activeSpreadsheetIdKey = 'activeSpreadsheetId';
  static const String activeSpreadsheetNameKey = 'activeSpreadsheetName';
  /// Legacy key — читається лише для міграції з попередніх версій.
  static const String spreadsheetDocIdKey = 'spreadsheet_doc_id';

  static String sheetRowsCategory(String sheetTitle) => 'cache_rows_$sheetTitle';

  /// Ключ SharedPreferences для списку dashboard (legacy: dashboards_income_cache).
  static String _dashboardsPrefsKey(String category) => 'dashboards_$category';

  // --- Dashboards (App_Config cache) ---

  Future<void> saveDashboards(
    List<Dashboard> dashboards, {
    String category = dashboardsCategory,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(dashboards.map((d) => d.toMap()).toList());
    await prefs.setString(_dashboardsPrefsKey(category), jsonString);
  }

  Future<List<Dashboard>> getDashboards({
    String category = dashboardsCategory,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_dashboardsPrefsKey(category));
    if (jsonString == null) return [];

    final decodedList = jsonDecode(jsonString) as List<dynamic>;
    return decodedList
        .map((item) => Dashboard.fromMap(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> clearDashboards({
    String category = dashboardsCategory,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dashboardsPrefsKey(category));
  }

  // --- Sheet rows cache ---

  Future<void> saveSheetRows(
    String sheetTitle,
    List<List<String>> rows,
  ) async {
    final cacheEntries = rows.map((row) => {'row': row}).toList();
    await _saveJsonList(sheetRowsCategory(sheetTitle), cacheEntries);
  }

  Future<void> saveSheetData(String sheetTitle, SheetData data) async {
    await saveSheetRows(sheetTitle, data.toSheetRows());
  }

  Future<List<List<String>>> getSheetRows(String sheetTitle) async {
    final cachedMaps = await _getJsonList(sheetRowsCategory(sheetTitle));
    return cachedMaps.map((item) {
      final dynamicList = item['row'] as List<dynamic>? ?? [];
      return dynamicList.map((e) => e.toString()).toList();
    }).toList();
  }

  Future<SheetData> getSheetData(String sheetTitle) async {
    final rows = await getSheetRows(sheetTitle);
    return SheetData.fromCachedRows(rows);
  }

  Future<void> deleteSheetCache(String sheetTitle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dashboardsPrefsKey(sheetRowsCategory(sheetTitle)));
  }

  /// Переносить кеш записів при перейменуванні dashboard.
  Future<void> migrateSheetCache(String oldTitle, String newTitle) async {
    if (oldTitle == newTitle) return;

    final rows = await getSheetRows(oldTitle);
    if (rows.isEmpty) {
      await deleteSheetCache(oldTitle);
      return;
    }

    await saveSheetRows(newTitle, rows);
    await deleteSheetCache(oldTitle);
  }

  // --- Module settings ---

  Future<ModuleSettings> getModuleSettings() async {
    final prefs = await SharedPreferences.getInstance();

    return ModuleSettings(
      income: prefs.getBool(ModuleType.income.prefsKey) ??
          ModuleType.income.defaultEnabled,
      expense: prefs.getBool(ModuleType.expense.prefsKey) ??
          ModuleType.expense.defaultEnabled,
      warehouse: prefs.getBool(ModuleType.warehouse.prefsKey) ??
          ModuleType.warehouse.defaultEnabled,
      analytics: prefs.getBool(ModuleType.analytics.prefsKey) ??
          ModuleType.analytics.defaultEnabled,
    );
  }

  Future<void> saveModuleSettings(ModuleSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ModuleType.income.prefsKey, settings.income);
    await prefs.setBool(ModuleType.expense.prefsKey, settings.expense);
    await prefs.setBool(ModuleType.warehouse.prefsKey, settings.warehouse);
    await prefs.setBool(ModuleType.analytics.prefsKey, settings.analytics);
  }

  Future<void> setModuleEnabled(ModuleType type, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(type.prefsKey, enabled);
  }

  Future<bool> isModuleEnabled(ModuleType type) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(type.prefsKey) ?? type.defaultEnabled;
  }

  // --- Active workspace (multi-spreadsheet) ---

  /// Кеш активного workspace у пам'яті протягом сесії (усуває reload диска).
  static String? _sessionActiveSpreadsheetId;
  static String? _sessionActiveSpreadsheetName;
  static bool _sessionWorkspaceLoaded = false;

  Future<void> _ensureSessionWorkspaceLoaded() async {
    if (_sessionWorkspaceLoaded) return;

    final prefs = await SharedPreferences.getInstance();
    var activeId = prefs.getString(activeSpreadsheetIdKey);
    if (activeId == null || activeId.isEmpty) {
      activeId = prefs.getString(spreadsheetDocIdKey);
    }

    _sessionActiveSpreadsheetId = activeId;
    _sessionActiveSpreadsheetName = prefs.getString(activeSpreadsheetNameKey);
    _sessionWorkspaceLoaded = true;
  }

  Future<String?> getActiveSpreadsheetId() async {
    await _ensureSessionWorkspaceLoaded();
    return _sessionActiveSpreadsheetId;
  }

  Future<String?> getActiveSpreadsheetName() async {
    await _ensureSessionWorkspaceLoaded();
    return _sessionActiveSpreadsheetName;
  }

  Future<void> setActiveWorkspace({
    required String id,
    required String name,
  }) async {
    _sessionActiveSpreadsheetId = id;
    _sessionActiveSpreadsheetName = name;
    _sessionWorkspaceLoaded = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(activeSpreadsheetIdKey, id);
    await prefs.setString(activeSpreadsheetNameKey, name);
    await prefs.setString(spreadsheetDocIdKey, id);
  }

  Future<void> clearActiveWorkspace() async {
    _sessionActiveSpreadsheetId = null;
    _sessionActiveSpreadsheetName = null;
    _sessionWorkspaceLoaded = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(activeSpreadsheetIdKey);
    await prefs.remove(activeSpreadsheetNameKey);
    await prefs.remove(spreadsheetDocIdKey);
  }

  /// Очищає кеш дашбордів і записів поточного workspace (при перемиканні таблиць).
  Future<void> clearWorkspaceDataCaches() async {
    final prefs = await SharedPreferences.getInstance();
    final keysToRemove = prefs.getKeys().where((key) {
      return key.startsWith('dashboards_');
    }).toList();

    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }

  /// Legacy alias — використовується SheetsApi для зворотної сумісності.
  Future<String?> getSpreadsheetDocId() => getActiveSpreadsheetId();

  Future<void> saveSpreadsheetDocId(String docId) async {
    _sessionActiveSpreadsheetId = docId;
    _sessionWorkspaceLoaded = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(spreadsheetDocIdKey, docId);
    await prefs.setString(activeSpreadsheetIdKey, docId);
  }

  Future<void> clearSpreadsheetDocId() => clearActiveWorkspace();

  // --- Internal helpers ---

  Future<void> _saveJsonList(
    String category,
    List<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(items);
    await prefs.setString(_dashboardsPrefsKey(category), jsonString);
  }

  Future<List<Map<String, dynamic>>> _getJsonList(String category) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_dashboardsPrefsKey(category));
    if (jsonString == null) return [];

    final decodedList = jsonDecode(jsonString) as List<dynamic>;
    return decodedList
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }
}
