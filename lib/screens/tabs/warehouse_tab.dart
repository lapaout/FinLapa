import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/dashboard_search_filter.dart';
import '../../core/network_exception.dart';
import '../../core/warehouse_picker_data.dart';
import '../../core/warehouse_product_names.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/sheet_records_repository.dart';
import '../../models/dashboard.dart';
import '../../widgets/dashboard_search_bar.dart';
import '../../widgets/dashboard_manage_modal.dart';
import '../../widgets/delete_dashboard_dialog.dart';
import '../../widgets/module_builder_modal.dart';
import '../../widgets/data_entry_modal.dart';
import '../history_screen.dart';
import '../dashboard_overview_screen.dart';
import 'edit_tab.dart';

class WarehouseTab extends StatefulWidget {
  final GoogleSignInAccount user;
  final bool isActive;

  const WarehouseTab({
    super.key,
    required this.user,
    this.isActive = false,
  });

  @override
  State<WarehouseTab> createState() => _WarehouseTabState();
}

class _WarehouseTabState extends State<WarehouseTab> with AutomaticKeepAliveClientMixin {
  final DashboardRepository _dashboardRepository = DashboardRepository();
  final SheetRecordsRepository _recordsRepository = SheetRecordsRepository();

  List<Dashboard> _dashboards = [];
  Map<String, List<String>> _warehouseProductNames = {};
  bool _isSending = false;
  bool _isLoading = false;
  bool _isOffline = false;
  bool _hasLoadedOnce = false;
  String _searchQuery = '';
  late final TextEditingController _searchController;

  @override
  bool get wantKeepAlive => _hasLoadedOnce;

  bool get _isSearchActive => DashboardSearchFilter.isActive(_searchQuery);

  bool get _canReorder => !_isSearchActive && !_isOffline;

  List<Dashboard> get _incomeDashboards =>
      _dashboards.where((dashboard) => dashboard.type == Dashboard.typeIncome).toList();

  List<Dashboard> get _expenseDashboards =>
      _dashboards.where((dashboard) => dashboard.type == Dashboard.typeExpense).toList();

  List<Dashboard> get _activeDashboards => _dashboards
      .where(
        (dashboard) =>
            dashboard.type == Dashboard.typeWarehouse &&
            !dashboard.isArchived &&
            !dashboard.isHidden,
      )
      .toList();

  List<Dashboard> get _hiddenDashboards => _dashboards
      .where(
        (dashboard) =>
            dashboard.type == Dashboard.typeWarehouse &&
            !dashboard.isArchived &&
            dashboard.isHidden,
      )
      .toList();

  List<Dashboard> get _archivedDashboards => _dashboards
      .where((dashboard) => dashboard.type == Dashboard.typeWarehouse && dashboard.isArchived)
      .toList();

  List<Dashboard> get _filteredActiveDashboards => DashboardSearchFilter.filterWarehouses(
        dashboards: _activeDashboards,
        query: _searchQuery,
        productNamesByWarehouse: _warehouseProductNames,
      );

  List<Dashboard> get _filteredHiddenDashboards => DashboardSearchFilter.filterWarehouses(
        dashboards: _hiddenDashboards,
        query: _searchQuery,
        productNamesByWarehouse: _warehouseProductNames,
      );

  List<Dashboard> _mergeWarehouseDashboards({
    required List<Dashboard> activeWarehouse,
    required List<Dashboard> hiddenWarehouse,
    required List<Dashboard> archivedWarehouse,
  }) {
    return [
      ..._incomeDashboards,
      ..._expenseDashboards,
      ...activeWarehouse,
      ...hiddenWarehouse,
      ...archivedWarehouse,
    ];
  }

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    if (widget.isActive) {
      _loadDashboards();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WarehouseTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive && !_hasLoadedOnce) {
      _loadDashboards();
    }
  }

  Future<void> _loadDashboards() async {
    setState(() {
      _isLoading = true;
      _isOffline = false;
    });

    final result = await _dashboardRepository.getDashboards(user: widget.user);

    if (!mounted) return;

    setState(() {
      _dashboards = result.data;
      _isOffline = result.isOffline;
      _isLoading = false;
      _hasLoadedOnce = true;
    });
    updateKeepAlive();
    await _loadWarehouseProductNames();

    if (result.isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Офлайн режим. Показані збережені дані.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _loadWarehouseProductNames() async {
    final warehouses = await resolveWarehouseDashboardsForPicker(
      dashboardRepository: _dashboardRepository,
      user: widget.user,
    );

    if (warehouses.isEmpty) {
      if (!mounted) return;
      setState(() => _warehouseProductNames = {});
      return;
    }

    final entries = await Future.wait(
      warehouses.map((warehouse) async {
        final records = await _recordsRepository.getRecordsPreferCache(
          sheetTitle: warehouse.title,
          user: widget.user,
        );
        return MapEntry(
          warehouse.title,
          extractWarehouseProductNames(warehouse, records),
        );
      }),
    );

    if (!mounted) return;
    setState(() => _warehouseProductNames = Map.fromEntries(entries));
  }

  void _openModuleBuilder() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => ModuleBuilderModal(
        dashboardType: Dashboard.typeWarehouse,
        onSave: (moduleName, fields, iconCode, colorValue, _) async {
          final newDashboard = Dashboard(
            title: moduleName,
            fields: fields,
            iconCode: iconCode,
            colorValue: colorValue,
            type: Dashboard.typeWarehouse,
          );

          try {
            // Read-Before-Write: репозиторій сам читає свіжий список з хмари.
            final latest = await _dashboardRepository.createDashboard(
              user: widget.user,
              dashboard: newDashboard,
            );
            if (!mounted) return;
            setState(() {
              _dashboards = latest;
              _isOffline = false;
            });
            if (context.mounted) Navigator.pop(context);
          } catch (error) {
            if (!mounted) return;
            setState(() => _isOffline = isNetworkError(error));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isNetworkError(error)
                      ? '❌ Немає зв\'язку. Зміна дашбордів потребує стабільного інтернету.'
                      : '❌ Помилка збереження: $error',
                ),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        },
      ),
    );
  }

  void _openDashboardManage(Dashboard dashboard) {
    if (_isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Недоступно в офлайн режимі'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DashboardManageModal(
        dashboard: dashboard,
        onArchive: () => _archiveDashboard(dashboard),
        onToggleHidden: () => _toggleDashboardHidden(dashboard),
        onDeleteForever: () => _confirmDeleteDashboard(dashboard),
      ),
    );
  }

  Future<void> _toggleDashboardHidden(Dashboard dashboard) async {
    final hide = !dashboard.isHidden;

    try {
      final latest = await _dashboardRepository.updateDashboard(
        user: widget.user,
        oldTitle: dashboard.title,
        updatedDashboard: dashboard.copyWith(isHidden: hide),
      );
      if (!mounted) return;
      setState(() {
        _dashboards = latest;
        _isOffline = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hide
                ? '👁 "${dashboard.title}" приховано'
                : '✅ "${dashboard.title}" показано',
          ),
          backgroundColor: hide ? Colors.blueGrey : Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isOffline = isNetworkError(error));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNetworkError(error)
                ? '❌ Немає зв\'язку. Зміна дашбордів потребує стабільного інтернету.'
                : '❌ Помилка: $error',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _archiveDashboard(Dashboard dashboard) async {
    try {
      // Read-Before-Write: оновлюємо запис у свіжому хмарному списку.
      final latest = await _dashboardRepository.updateDashboard(
        user: widget.user,
        oldTitle: dashboard.title,
        updatedDashboard: dashboard.copyWith(isArchived: true),
      );
      if (!mounted) return;
      setState(() {
        _dashboards = latest;
        _isOffline = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📦 "${dashboard.title}" переміщено в архів'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isOffline = isNetworkError(error));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNetworkError(error)
                ? '❌ Немає зв\'язку. Зміна дашбордів потребує стабільного інтернету.'
                : '❌ Помилка: $error',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _confirmDeleteDashboard(Dashboard dashboard) async {
    final confirmed = await showDeleteDashboardDialog(
      context,
      dashboardTitle: dashboard.title,
    );

    if (!confirmed || !mounted) return;

    try {
      // Read-Before-Write: репозиторій повертає свіжий список без видаленого.
      final latest = await _dashboardRepository.deleteDashboard(
        user: widget.user,
        title: dashboard.title,
      );
      if (!mounted) return;
      setState(() {
        _dashboards = latest;
        _isOffline = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🗑 "${dashboard.title}" видалено назавжди'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isOffline = isNetworkError(error));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNetworkError(error)
                ? '❌ Немає зв\'язку. Видалення дашборда потребує стабільного інтернету.'
                : '❌ Помилка: $error',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _onReorderActiveDashboards(int oldIndex, int newIndex) async {
    if (_isOffline) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    // Знімок поточного (кешованого) стану для відкату при помилці.
    final previousDashboards = List<Dashboard>.from(_dashboards);

    final active = List<Dashboard>.from(_activeDashboards);
    final item = active.removeAt(oldIndex);
    active.insert(newIndex, item);

    // Оптимістично показуємо новий порядок одразу.
    setState(() {
      _dashboards = _mergeWarehouseDashboards(
        activeWarehouse: active,
        hiddenWarehouse: _hiddenDashboards,
        archivedWarehouse: _archivedDashboards,
      );
    });

    try {
      // Read-Before-Write: репозиторій застосовує порядок до свіжого хмарного списку.
      final latest = await _dashboardRepository.reorderDashboards(
        user: widget.user,
        type: Dashboard.typeWarehouse,
        orderedActiveTitles: active.map((dashboard) => dashboard.title).toList(),
      );
      if (!mounted) return;
      setState(() {
        _dashboards = latest;
        _isOffline = false;
      });
    } catch (error) {
      if (!mounted) return;
      // Відкочуємо візуальний порядок до кешованого (до перетягування).
      setState(() {
        _dashboards = previousDashboards;
        _isOffline = isNetworkError(error);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNetworkError(error)
                ? '❌ Потрібен інтернет. Порядок не збережено.'
                : '❌ Помилка збереження порядку: $error',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _restoreDashboard(Dashboard dashboard) async {
    try {
      // Read-Before-Write: оновлюємо запис у свіжому хмарному списку.
      final latest = await _dashboardRepository.updateDashboard(
        user: widget.user,
        oldTitle: dashboard.title,
        updatedDashboard: dashboard.copyWith(isArchived: false),
      );
      if (!mounted) return;
      setState(() {
        _dashboards = latest;
        _isOffline = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ "${dashboard.title}" відновлено'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isOffline = isNetworkError(error));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNetworkError(error)
                ? '❌ Немає зв\'язку. Зміна дашбордів потребує стабільного інтернету.'
                : '❌ Помилка: $error',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _openDashboardOverview(Dashboard dashboard) {
    final colorData = Color(dashboard.colorValue);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DashboardOverviewScreen(
          user: widget.user,
          dashboardTitle: dashboard.title,
          dashboardColor: colorData,
          dashboardType: dashboard.type,
          dashboardFields: dashboard.fields,
        ),
      ),
    );
  }

  void _openDataEntryForm(Dashboard dashboard) {
    final title = dashboard.title;
    final fields = List<String>.from(dashboard.fields);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DataEntryModal(
        title: title,
        fields: fields,
        isSending: _isSending,
        onSave: (valuesToSave, {extraFields, recordDateTime}) async {
          setState(() => _isSending = true);

          try {
            await _recordsRepository.appendRecord(
              user: widget.user,
              sheetTitle: title,
              columns: fields,
              values: valuesToSave,
              recordDateTime: recordDateTime,
            );

            setState(() => _isOffline = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Записано в "$title"'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (error) {
            if (isNetworkError(error)) {
              setState(() => _isOffline = true);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ Немає інтернету. Запис скасовано.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            } else {
              setState(() => _isOffline = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ Записано в "$title"'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            }
          } finally {
            if (mounted) {
              setState(() => _isSending = false);
              _loadWarehouseProductNames();
            }
          }
        },
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveDashboardCard(Dashboard dashboard) {
    final iconData = IconData(
      dashboard.iconCode,
      fontFamily: 'MaterialIcons',
    );
    final colorData = Color(dashboard.colorValue);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _openDashboardOverview(dashboard),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: colorData.withOpacity(0.1),
                      child: Icon(iconData, color: colorData, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        dashboard.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 22),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  Icons.add_circle,
                  "Додати",
                  colorData,
                  () => _openDataEntryForm(dashboard),
                ),
                _buildActionButton(Icons.inventory_2, "Докладно", Colors.blueGrey, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HistoryScreen(
                        user: widget.user,
                        dashboardTitle: dashboard.title,
                        dashboardColor: colorData,
                        dashboardType: dashboard.type,
                        dashboardFields: dashboard.fields,
                      ),
                    ),
                  );
                }),
                _buildActionButton(Icons.edit_document, "Редагувати", Colors.blueGrey, () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditTab(
                        user: widget.user,
                        dashboard: dashboard.toMap(),
                      ),
                    ),
                  );
                  _loadDashboards();
                }),
                _buildActionButton(
                  Icons.settings,
                  "Налаштування",
                  Colors.blueGrey,
                  () => _openDashboardManage(dashboard),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchivedDashboardCard(Dashboard dashboard) {
    final iconData = IconData(
      dashboard.iconCode,
      fontFamily: 'MaterialIcons',
    );
    final colorData = Color(dashboard.colorValue);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorData.withOpacity(0.1),
          child: Icon(iconData, color: colorData, size: 20),
        ),
        title: Text(
          dashboard.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('В архіві'),
        trailing: TextButton.icon(
          onPressed: _isOffline ? null : () => _restoreDashboard(dashboard),
          icon: const Icon(Icons.unarchive_outlined, size: 18),
          label: const Text('Відновити'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_hasLoadedOnce && !widget.isActive) {
      return const SizedBox.shrink();
    }
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_isSending) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Запис у Google..."),
          ],
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              DashboardSearchBar(
                controller: _searchController,
                hintText: 'Пошук складів або товарів...',
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
              const SizedBox(height: 12),
              if (_isOffline)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off, color: Colors.redAccent),
                      SizedBox(width: 10),
                      Text(
                        "Офлайн режим (тільки читання)",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isSearchActive &&
                  _filteredActiveDashboards.isEmpty &&
                  _filteredHiddenDashboards.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 24.0),
                  child: Text(
                    'Нічого не знайдено.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              else if (!_isSearchActive && _activeDashboards.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 24.0),
                  child: Text(
                    "Немає складських дашбордів.\nНатисніть 'Створити', щоб додати свій.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
            ]),
          ),
        ),
        if (_filteredActiveDashboards.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _canReorder
                ? SliverReorderableList(
                    itemCount: _filteredActiveDashboards.length,
                    onReorder: _onReorderActiveDashboards,
                    itemBuilder: (context, index) {
                      final dashboard = _filteredActiveDashboards[index];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey('warehouse-active-${dashboard.title}'),
                        index: index,
                        enabled: true,
                        child: _buildActiveDashboardCard(dashboard),
                      );
                    },
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final dashboard = _filteredActiveDashboards[index];
                        return _buildActiveDashboardCard(dashboard);
                      },
                      childCount: _filteredActiveDashboards.length,
                    ),
                  ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 10),
              InkWell(
                onTap: _openModuleBuilder,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 2),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline, color: Colors.blueAccent, size: 26),
                      SizedBox(width: 12),
                      Text(
                        "Створити новий дашборд",
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_filteredHiddenDashboards.isNotEmpty) ...[
                const SizedBox(height: 20),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Icon(Icons.visibility_off_outlined, color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Приховані дашборди (${_filteredHiddenDashboards.length})',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  children: _filteredHiddenDashboards
                      .map(
                        (dashboard) => KeyedSubtree(
                          key: ValueKey('warehouse-hidden-${dashboard.title}'),
                          child: _buildActiveDashboardCard(dashboard),
                        ),
                      )
                      .toList(),
                ),
              ],
              if (_archivedDashboards.isNotEmpty) ...[
                const SizedBox(height: 20),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Row(
                    children: [
                      Icon(Icons.archive_outlined, color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Архів (${_archivedDashboards.length})',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                  children: _archivedDashboards
                      .map(
                        (dashboard) => KeyedSubtree(
                          key: ValueKey('warehouse-archived-${dashboard.title}'),
                          child: _buildArchivedDashboardCard(dashboard),
                        ),
                      )
                      .toList(),
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }
}
