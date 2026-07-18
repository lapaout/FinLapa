import 'package:flutter/material.dart';

import '../models/dashboard.dart';

/// Тип дашборда для універсального таба [BaseDashboardTab].
enum DashboardType {
  income,
  expense,
  warehouse,
}

extension DashboardTypeX on DashboardType {
  String get sheetType {
    switch (this) {
      case DashboardType.income:
        return Dashboard.typeIncome;
      case DashboardType.expense:
        return Dashboard.typeExpense;
      case DashboardType.warehouse:
        return Dashboard.typeWarehouse;
    }
  }

  String get keyPrefix {
    switch (this) {
      case DashboardType.income:
        return 'income';
      case DashboardType.expense:
        return 'expense';
      case DashboardType.warehouse:
        return 'warehouse';
    }
  }

  String get emptyListMessage {
    switch (this) {
      case DashboardType.income:
        return "Немає джерел доходу.\nНатисніть 'Створити', щоб додати своє.";
      case DashboardType.expense:
        return "Немає джерел витрат.\nНатисніть 'Створити', щоб додати своє.";
      case DashboardType.warehouse:
        return "Немає складських дашбордів.\nНатисніть 'Створити', щоб додати свій.";
    }
  }

  String get searchHint {
    switch (this) {
      case DashboardType.income:
      case DashboardType.expense:
        return 'Пошук дашбордів...';
      case DashboardType.warehouse:
        return 'Пошук складів або товарів...';
    }
  }

  String get historyActionLabel {
    switch (this) {
      case DashboardType.income:
      case DashboardType.expense:
        return 'Історія';
      case DashboardType.warehouse:
        return 'Докладно';
    }
  }

  IconData get historyActionIcon {
    switch (this) {
      case DashboardType.income:
      case DashboardType.expense:
        return Icons.history;
      case DashboardType.warehouse:
        return Icons.inventory_2;
    }
  }

  bool get supportsWarehouseLink => this == DashboardType.income;

  bool get usesWarehouseProductSearch => this == DashboardType.warehouse;
}
