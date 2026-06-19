import '../../models/module_settings.dart';
import '../../models/module_type.dart';
import '../sources/local_cache_data_source.dart';

/// Керує локальними налаштуваннями модулів (видимість вкладок).
class SettingsRepository {
  SettingsRepository({
    LocalCacheDataSource? cache,
  }) : _cache = cache ?? LocalCacheDataSource();

  final LocalCacheDataSource _cache;

  Future<ModuleSettings> getSettings() {
    return _cache.getModuleSettings();
  }

  Future<void> saveSettings(ModuleSettings settings) {
    return _cache.saveModuleSettings(settings);
  }

  Future<void> setModuleEnabled(ModuleType type, bool enabled) {
    return _cache.setModuleEnabled(type, enabled);
  }

  Future<bool> isModuleEnabled(ModuleType type) {
    return _cache.isModuleEnabled(type);
  }
}
