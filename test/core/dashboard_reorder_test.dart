import 'package:finlapa/core/dashboard_reorder.dart';
import 'package:finlapa/models/dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

Dashboard _dashboard(
  String title, {
  String type = Dashboard.typeIncome,
  bool isArchived = false,
  bool isHidden = false,
}) {
  return Dashboard(
    title: title,
    iconCode: Dashboard.defaultIconCode,
    colorValue: Dashboard.defaultColorValue,
    fields: const ['Сума'],
    type: type,
    isArchived: isArchived,
    isHidden: isHidden,
  );
}

void main() {
  group('mergeReorderedDashboards', () {
    test('reorders active dashboards of the given type per UI order', () {
      final latest = [
        _dashboard('A'),
        _dashboard('B'),
        _dashboard('C'),
      ];

      final result = mergeReorderedDashboards(
        latestDashboards: latest,
        type: Dashboard.typeIncome,
        orderedActiveTitles: ['C', 'A', 'B'],
      );

      expect(result.map((d) => d.title).toList(), ['C', 'A', 'B']);
    });

    test('leaves other dashboard types untouched in their original slots', () {
      final latest = [
        _dashboard('Income A'),
        _dashboard('Expense X', type: Dashboard.typeExpense),
        _dashboard('Income B'),
        _dashboard('Warehouse Y', type: Dashboard.typeWarehouse),
      ];

      final result = mergeReorderedDashboards(
        latestDashboards: latest,
        type: Dashboard.typeIncome,
        orderedActiveTitles: ['Income B', 'Income A'],
      );

      expect(result.map((d) => d.title).toList(), [
        'Income B',
        'Expense X',
        'Income A',
        'Warehouse Y',
      ]);
    });

    test('leaves archived and hidden dashboards of the same type untouched', () {
      final latest = [
        _dashboard('A'),
        _dashboard('Archived', isArchived: true),
        _dashboard('B'),
        _dashboard('Hidden', isHidden: true),
      ];

      final result = mergeReorderedDashboards(
        latestDashboards: latest,
        type: Dashboard.typeIncome,
        orderedActiveTitles: ['B', 'A'],
      );

      expect(result.map((d) => d.title).toList(), [
        'B',
        'Archived',
        'A',
        'Hidden',
      ]);
    });

    test('appends active dashboards missing from the UI list instead of dropping them', () {
      // Сценарій: UI сформував drag-and-drop список ДО того, як з хмари
      // прилетів новий дашборд з іншого пристрою — його не можна втратити.
      final latest = [
        _dashboard('A'),
        _dashboard('B'),
        _dashboard('New from another device'),
      ];

      final result = mergeReorderedDashboards(
        latestDashboards: latest,
        type: Dashboard.typeIncome,
        orderedActiveTitles: ['B', 'A'],
      );

      expect(result.map((d) => d.title).toList(), [
        'B',
        'A',
        'New from another device',
      ]);
    });

    test('ignores titles from UI that no longer exist in the cloud list', () {
      final latest = [
        _dashboard('A'),
        _dashboard('B'),
      ];

      final result = mergeReorderedDashboards(
        latestDashboards: latest,
        type: Dashboard.typeIncome,
        orderedActiveTitles: ['Deleted elsewhere', 'B', 'A'],
      );

      expect(result.map((d) => d.title).toList(), ['B', 'A']);
    });

    test('ignores duplicate titles in the UI order', () {
      final latest = [
        _dashboard('A'),
        _dashboard('B'),
      ];

      final result = mergeReorderedDashboards(
        latestDashboards: latest,
        type: Dashboard.typeIncome,
        orderedActiveTitles: ['B', 'B', 'A'],
      );

      expect(result.map((d) => d.title).toList(), ['B', 'A']);
    });

    test('returns the list unchanged when there are no active dashboards of the type', () {
      final latest = [
        _dashboard('Expense X', type: Dashboard.typeExpense),
      ];

      final result = mergeReorderedDashboards(
        latestDashboards: latest,
        type: Dashboard.typeIncome,
        orderedActiveTitles: [],
      );

      expect(result.map((d) => d.title).toList(), ['Expense X']);
    });
  });
}
