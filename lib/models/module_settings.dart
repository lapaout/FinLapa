import 'module_type.dart';

/// Налаштування видимості модулів на головному екрані.
class ModuleSettings {
  final bool income;
  final bool expense;
  final bool warehouse;
  final bool analytics;

  const ModuleSettings({
    required this.income,
    required this.expense,
    required this.warehouse,
    required this.analytics,
  });

  factory ModuleSettings.defaults() {
    return ModuleSettings(
      income: ModuleType.income.defaultEnabled,
      expense: ModuleType.expense.defaultEnabled,
      warehouse: ModuleType.warehouse.defaultEnabled,
      analytics: ModuleType.analytics.defaultEnabled,
    );
  }

  bool isEnabled(ModuleType type) {
    return switch (type) {
      ModuleType.income => income,
      ModuleType.expense => expense,
      ModuleType.warehouse => warehouse,
      ModuleType.analytics => analytics,
    };
  }

  ModuleSettings copyWithEnabled(ModuleType type, bool enabled) {
    return switch (type) {
      ModuleType.income => copyWith(income: enabled),
      ModuleType.expense => copyWith(expense: enabled),
      ModuleType.warehouse => copyWith(warehouse: enabled),
      ModuleType.analytics => copyWith(analytics: enabled),
    };
  }

  ModuleSettings copyWith({
    bool? income,
    bool? expense,
    bool? warehouse,
    bool? analytics,
  }) {
    return ModuleSettings(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      warehouse: warehouse ?? this.warehouse,
      analytics: analytics ?? this.analytics,
    );
  }
}
