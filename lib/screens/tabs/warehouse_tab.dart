import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/network_exception.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/sheet_records_repository.dart';
import '../../models/dashboard.dart';
import '../../widgets/dashboard_manage_modal.dart';
import '../../widgets/delete_dashboard_dialog.dart';
import '../../widgets/module_builder_modal.dart';
import '../../widgets/data_entry_modal.dart';
import '../history_screen.dart';
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
  bool _isSending = false;
  bool _isLoading = false;
  bool _isOffline = false;
  bool _hasLoadedOnce = false;

  @override
  bool get wantKeepAlive => _hasLoadedOnce;

  List<Dashboard> get _incomeDashboards =>
      _dashboards.where((dashboard) => dashboard.type == Dashboard.typeIncome).toList();

  List<Dashboard> get _expenseDashboards =>
      _dashboards.where((dashboard) => dashboard.type == Dashboard.typeExpense).toList();

  List<Dashboard> get _activeDashboards => _dashboards
      .where((dashboard) => dashboard.type == Dashboard.typeWarehouse && !dashboard.isArchived)
      .toList();

  List<Dashboard> get _archivedDashboards => _dashboards
      .where((dashboard) => dashboard.type == Dashboard.typeWarehouse && dashboard.isArchived)
      .toList();

  List<Dashboard> _mergeWarehouseDashboards({
    required List<Dashboard> activeWarehouse,
    required List<Dashboard> archivedWarehouse,
  }) {
    return [
      ..._incomeDashboards,
      ..._expenseDashboards,
      ...activeWarehouse,
      ...archivedWarehouse,
    ];
  }

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _loadDashboards();
    }
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

  Future<void> _saveDashboards(List<Dashboard> dashboards) async {
    await _dashboardRepository.saveDashboards(
      user: widget.user,
      dashboards: dashboards,
    );
    if (!mounted) return;
    setState(() {
      _dashboards = dashboards;
      _isOffline = false;
    });
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
          final updatedDashboards = [..._dashboards, newDashboard];

          try {
            await _saveDashboards(updatedDashboards);
            if (context.mounted) Navigator.pop(context);
          } catch (error) {
            if (isNetworkError(error)) {
              if (mounted) {
                setState(() => _isOffline = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ Немає зв\'язку з інтернетом.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
              }
            } else {
              if (!mounted) return;
              setState(() {
                _dashboards = updatedDashboards;
                _isOffline = false;
              });
              if (context.mounted) Navigator.pop(context);
            }
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
        onDeleteForever: () => _confirmDeleteDashboard(dashboard),
      ),
    );
  }

  Future<void> _archiveDashboard(Dashboard dashboard) async {
    final updated = _dashboards
        .map(
          (item) => item.title == dashboard.title && item.type == Dashboard.typeWarehouse
              ? item.copyWith(isArchived: true)
              : item,
        )
        .toList();

    try {
      await _saveDashboards(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📦 "${dashboard.title}" переміщено в архів'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (error) {
      if (mounted && isNetworkError(error)) {
        setState(() => _isOffline = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Немає зв\'язку з інтернетом.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteDashboard(Dashboard dashboard) async {
    final confirmed = await showDeleteDashboardDialog(
      context,
      dashboardTitle: dashboard.title,
    );

    if (!confirmed || !mounted) return;

    try {
      await _dashboardRepository.deleteDashboard(
        user: widget.user,
        title: dashboard.title,
      );
      if (!mounted) return;
      setState(() {
        _dashboards = _dashboards
            .where((item) => item.title != dashboard.title)
            .toList();
        _isOffline = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🗑 "${dashboard.title}" видалено назавжди'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (error) {
      if (mounted) {
        if (isNetworkError(error)) setState(() => _isOffline = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Помилка: $error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _onReorderActiveDashboards(int oldIndex, int newIndex) async {
    if (_isOffline) return;

    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    final active = List<Dashboard>.from(_activeDashboards);
    final item = active.removeAt(oldIndex);
    active.insert(newIndex, item);

    final updated = _mergeWarehouseDashboards(
      activeWarehouse: active,
      archivedWarehouse: _archivedDashboards,
    );

    setState(() => _dashboards = updated);

    try {
      await _dashboardRepository.saveDashboards(
        user: widget.user,
        dashboards: updated,
      );
      if (!mounted) return;
      setState(() => _isOffline = false);
    } catch (error) {
      if (mounted && isNetworkError(error)) {
        setState(() => _isOffline = true);
        await _loadDashboards();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Немає зв\'язку з інтернетом. Порядок не збережено.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _restoreDashboard(Dashboard dashboard) async {
    final updated = _dashboards
        .map(
          (item) => item.title == dashboard.title && item.type == Dashboard.typeWarehouse
              ? item.copyWith(isArchived: false)
              : item,
        )
        .toList();

    try {
      await _saveDashboards(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${dashboard.title}" відновлено'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (mounted && isNetworkError(error)) {
        setState(() => _isOffline = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Немає зв\'язку з інтернетом.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
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
        onSave: (valuesToSave, {extraFields}) async {
          Navigator.pop(context);
          setState(() => _isSending = true);

          try {
            await _recordsRepository.appendRecord(
              user: widget.user,
              sheetTitle: title,
              columns: fields,
              values: valuesToSave,
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
            if (mounted) setState(() => _isSending = false);
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
            Row(
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
              ],
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
              if (_activeDashboards.isEmpty)
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
        if (_activeDashboards.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverReorderableList(
              itemCount: _activeDashboards.length,
              onReorder: _isOffline ? (_, __) {} : _onReorderActiveDashboards,
              itemBuilder: (context, index) {
                final dashboard = _activeDashboards[index];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey('warehouse-active-${dashboard.title}'),
                  index: index,
                  enabled: !_isOffline,
                  child: _buildActiveDashboardCard(dashboard),
                );
              },
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
