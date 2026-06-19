import 'module_type.dart';

/// Налаштування видимості модулів на головному екрані.
class ModuleSettings {
  final bool income;
  final bool expense;
  final bool warehouse;

  const ModuleSettings({
    required this.income,
    required this.expense,
    required this.warehouse,
  });

  factory ModuleSettings.defaults() {
    return ModuleSettings(
      income: ModuleType.income.defaultEnabled,
      expense: ModuleType.expense.defaultEnabled,
      warehouse: ModuleType.warehouse.defaultEnabled,
    );
  }

  bool isEnabled(ModuleType type) {
    return switch (type) {
      ModuleType.income => income,
      ModuleType.expense => expense,
      ModuleType.warehouse => warehouse,
    };
  }

  ModuleSettings copyWithEnabled(ModuleType type, bool enabled) {
    return switch (type) {
      ModuleType.income => copyWith(income: enabled),
      ModuleType.expense => copyWith(expense: enabled),
      ModuleType.warehouse => copyWith(warehouse: enabled),
    };
  }

  ModuleSettings copyWith({
    bool? income,
    bool? expense,
    bool? warehouse,
  }) {
    return ModuleSettings(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      warehouse: warehouse ?? this.warehouse,
    );
  }
}
