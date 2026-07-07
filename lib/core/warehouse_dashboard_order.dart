import '../models/dashboard.dart';

/// Порядок складів для форм вибору: активні (як на головному екрані),
/// потім приховані — обидві групи зберігають порядок з App_Config.
List<Dashboard> orderWarehouseDashboardsForPicker(List<Dashboard> dashboards) {
  final active = <Dashboard>[];
  final hidden = <Dashboard>[];

  for (final dashboard in dashboards) {
    if (dashboard.type != Dashboard.typeWarehouse || dashboard.isArchived) {
      continue;
    }
    if (dashboard.isHidden) {
      hidden.add(dashboard);
    } else {
      active.add(dashboard);
    }
  }

  return [...active, ...hidden];
}
