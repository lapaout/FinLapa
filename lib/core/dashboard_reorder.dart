import '../models/dashboard.dart';

/// Чиста (без мережі/кешу) логіка злиття нового порядку дашбордів у
/// СВІЖИЙ список з хмари. Виділено з [DashboardRepository.reorderDashboards],
/// щоб покрити тестами найризикованішу частину read-before-write патерну:
/// якщо тут закрадеться помилка в індексах, вона мовчки перезапише
/// App_Config для ВСІХ дашбордів (не тільки тих, що переставляли).
///
/// [latestDashboards] — актуальний список з хмари (усі типи, включно з
/// архівними/прихованими). [type] — тип, який переставляють. [orderedActiveTitles] —
/// новий порядок активних (не архівних, не прихованих) дашбордів цього типу,
/// що прийшов з UI (drag-and-drop).
///
/// Дашборди інших типів та архівні/приховані записи лишаються на тих самих
/// позиціях у результуючому списку. Активні дашборди типу [type], яких UI не
/// знав (з'явилися в хмарі після останнього завантаження), не втрачаються —
/// дописуються в кінець свого блоку.
List<Dashboard> mergeReorderedDashboards({
  required List<Dashboard> latestDashboards,
  required String type,
  required List<String> orderedActiveTitles,
}) {
  bool isActiveOfType(Dashboard dashboard) =>
      dashboard.type == type && !dashboard.isArchived && !dashboard.isHidden;

  final activeOfType = latestDashboards.where(isActiveOfType).toList();
  final byTitle = {
    for (final dashboard in activeOfType) dashboard.title: dashboard,
  };

  final reordered = <Dashboard>[];
  final usedTitles = <String>{};
  for (final title in orderedActiveTitles) {
    final dashboard = byTitle[title];
    if (dashboard != null && usedTitles.add(title)) {
      reordered.add(dashboard);
    }
  }
  for (final dashboard in activeOfType) {
    if (!usedTitles.contains(dashboard.title)) {
      reordered.add(dashboard);
    }
  }

  final updatedDashboards = <Dashboard>[];
  var cursor = 0;
  for (final dashboard in latestDashboards) {
    if (isActiveOfType(dashboard)) {
      updatedDashboards.add(reordered[cursor]);
      cursor++;
    } else {
      updatedDashboards.add(dashboard);
    }
  }

  return updatedDashboards;
}
