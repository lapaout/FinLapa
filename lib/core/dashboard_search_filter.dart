import '../models/dashboard.dart';

class DashboardSearchFilter {
  static String normalize(String query) => query.trim().toLowerCase();

  static bool isActive(String query) => normalize(query).isNotEmpty;

  static bool matchesTitle(Dashboard dashboard, String query) {
    final normalized = normalize(query);
    if (normalized.isEmpty) return true;
    return dashboard.title.toLowerCase().contains(normalized);
  }

  static List<Dashboard> filterByTitle(
    List<Dashboard> dashboards,
    String query,
  ) {
    if (!isActive(query)) return dashboards;
    return dashboards.where((dashboard) => matchesTitle(dashboard, query)).toList();
  }

  static bool matchesWarehouse({
    required Dashboard dashboard,
    required String query,
    required Map<String, List<String>> productNamesByWarehouse,
  }) {
    final normalized = normalize(query);
    if (normalized.isEmpty) return true;
    if (dashboard.title.toLowerCase().contains(normalized)) return true;

    final productNames = productNamesByWarehouse[dashboard.title] ?? const [];
    return productNames.any((name) => name.toLowerCase().contains(normalized));
  }

  static List<Dashboard> filterWarehouses({
    required List<Dashboard> dashboards,
    required String query,
    required Map<String, List<String>> productNamesByWarehouse,
  }) {
    if (!isActive(query)) return dashboards;
    return dashboards
        .where(
          (dashboard) => matchesWarehouse(
            dashboard: dashboard,
            query: query,
            productNamesByWarehouse: productNamesByWarehouse,
          ),
        )
        .toList();
  }
}
