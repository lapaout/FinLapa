/// Модулі додатку, що відображаються на головному екрані.
enum ModuleType {
  income('mod_income', true),
  expense('mod_expense', true),
  warehouse('mod_warehouse', false),
  analytics('mod_analytics', true);

  const ModuleType(this.prefsKey, this.defaultEnabled);

  /// Ключ у SharedPreferences (mod_income, mod_expense, mod_warehouse).
  final String prefsKey;

  /// Увімкнений за замовчуванням для нових користувачів.
  final bool defaultEnabled;
}
