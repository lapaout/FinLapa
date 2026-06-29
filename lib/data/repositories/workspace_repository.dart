import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../models/finlapa_spreadsheet.dart';
import '../sources/local_cache_data_source.dart';
import '../sources/sheets_api.dart';

/// Керує multi-workspace: папка FinLapa, активна таблиця, onboarding.
class WorkspaceRepository {
  WorkspaceRepository({
    LocalCacheDataSource? cache,
  }) : _cache = cache ?? LocalCacheDataSource();

  final LocalCacheDataSource _cache;

  /// Відновлює сесію або автоматично обирає єдину таблицю в FinLapa.
  Future<FinLapaSpreadsheet?> resolveInitialWorkspace({
    required GoogleSignInAccount user,
  }) async {
    final restored = await tryRestoreSession(user: user);
    if (restored != null) {
      return restored;
    }

    try {
      final tables = await listWorkspaces(user: user);
      if (tables.length == 1) {
        await activateWorkspace(workspace: tables.first);
        return tables.first;
      }
    } catch (error) {
      debugPrint('WorkspaceRepository.resolveInitialWorkspace: $error');
    }

    return null;
  }

  Future<FinLapaSpreadsheet?> tryRestoreSession({
    required GoogleSignInAccount user,
  }) async {
    final activeId = await _cache.getActiveSpreadsheetId();
    if (activeId == null || activeId.isEmpty) {
      return null;
    }

    var activeName = await _cache.getActiveSpreadsheetName();
    if (activeName == null || activeName.isEmpty) {
      activeName = 'Таблиця';
    }

    try {
      final isValid = await SheetsApi.isSpreadsheetInFinLapaFolder(
        user: user,
        spreadsheetId: activeId,
      );

      if (!isValid) {
        await _cache.clearActiveWorkspace();
        return null;
      }

      final driveName = await SheetsApi.getSpreadsheetName(
        user: user,
        spreadsheetId: activeId,
      );
      if (driveName != null && driveName.isNotEmpty) {
        activeName = driveName;
      }
    } catch (error) {
      debugPrint(
        'WorkspaceRepository.tryRestoreSession: remote validation failed, '
        'using cached session: $error',
      );
    }

    final resolvedName = activeName ?? 'Таблиця';
    await _cache.setActiveWorkspace(id: activeId, name: resolvedName);
    return FinLapaSpreadsheet(id: activeId, name: resolvedName);
  }

  Future<List<FinLapaSpreadsheet>> listWorkspaces({
    required GoogleSignInAccount user,
  }) {
    return SheetsApi.listSpreadsheetsInFinLapaFolder(user: user);
  }

  Future<FinLapaSpreadsheet> createWorkspace({
    required GoogleSignInAccount user,
    required String name,
  }) async {
    await _cache.clearWorkspaceDataCaches();
    final spreadsheet = await SheetsApi.createSpreadsheetInFinLapaFolder(
      user: user,
      title: name,
    );
    await _cache.setActiveWorkspace(
      id: spreadsheet.id,
      name: spreadsheet.name,
    );
    return spreadsheet;
  }

  Future<void> activateWorkspace({
    required FinLapaSpreadsheet workspace,
  }) async {
    await _cache.clearWorkspaceDataCaches();
    await _cache.setActiveWorkspace(
      id: workspace.id,
      name: workspace.name,
    );
  }

  Future<bool> deleteWorkspace({
    required GoogleSignInAccount user,
    required FinLapaSpreadsheet workspace,
  }) async {
    await SheetsApi.deleteSpreadsheetInFinLapaFolder(
      user: user,
      spreadsheetId: workspace.id,
    );

    final activeId = await _cache.getActiveSpreadsheetId();
    final wasActive = activeId == workspace.id;

    if (wasActive) {
      await _cache.clearWorkspaceDataCaches();
      await _cache.clearActiveWorkspace();
    }

    return wasActive;
  }

  Future<void> clearSessionOnLogout() async {
    await _cache.clearWorkspaceDataCaches();
    await _cache.clearActiveWorkspace();
    SheetsApi.clearFolderCache();
  }

  Future<String?> readCachedWorkspaceId() => _cache.getActiveSpreadsheetId();

  Future<String?> readCachedWorkspaceName() => _cache.getActiveSpreadsheetName();
}
