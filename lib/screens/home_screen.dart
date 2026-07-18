import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/repositories/settings_repository.dart';
import '../models/finlapa_spreadsheet.dart';
import '../widgets/settings_modal.dart';
import '../widgets/workspace_picker_sheet.dart';
import 'analytics_overview_screen.dart';
import 'tabs/expense_tab.dart';
import 'tabs/income_tab.dart';
import 'tabs/warehouse_tab.dart';

class HomeScreen extends StatefulWidget {
  final GoogleSignInAccount user;
  final GoogleSignIn googleSignIn;
  final FinLapaSpreadsheet activeWorkspace;
  final ValueChanged<FinLapaSpreadsheet> onWorkspaceChanged;
  final VoidCallback? onActiveWorkspaceDeleted;
  final Future<FinLapaSpreadsheet> Function(String name)? onCreateWorkspace;

  const HomeScreen({
    super.key,
    required this.user,
    required this.googleSignIn,
    required this.activeWorkspace,
    required this.onWorkspaceChanged,
    this.onActiveWorkspaceDeleted,
    this.onCreateWorkspace,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SettingsRepository _settingsRepository = SettingsRepository();

  int _currentIndex = 0;

  bool _showIncome = true;
  bool _showExpense = true;
  bool _showWarehouse = false;
  bool _showAnalytics = true;
  bool _isLoading = true;

  late FinLapaSpreadsheet _activeWorkspace;

  @override
  void initState() {
    super.initState();
    _activeWorkspace = widget.activeWorkspace;
    _loadSettings();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeWorkspace.id != widget.activeWorkspace.id) {
      _activeWorkspace = widget.activeWorkspace;
      _currentIndex = 0;
    }
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsRepository.getSettings();

    setState(() {
      _showIncome = settings.income;
      _showExpense = settings.expense;
      _showWarehouse = settings.warehouse;
      _showAnalytics = settings.analytics;
      _isLoading = false;
    });
  }

  void _openSettingsMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SettingsModal(
        settingsRepository: _settingsRepository,
        initialIncome: _showIncome,
        initialExpense: _showExpense,
        initialWarehouse: _showWarehouse,
        initialAnalytics: _showAnalytics,
        onSettingsChanged: _loadSettings,
      ),
    );
  }

  void _openWorkspacePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.85,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: WorkspacePickerSheet(
            user: widget.user,
            activeSpreadsheetId: _activeWorkspace.id,
            onCreate: widget.onCreateWorkspace,
            onActiveWorkspaceDeleted: widget.onActiveWorkspaceDeleted,
            onSelected: (workspace) {
              if (workspace.id == _activeWorkspace.id) return;
              widget.onWorkspaceChanged(workspace);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final workspaceKey = _activeWorkspace.id;
    final tabCount = (_showIncome ? 1 : 0) +
        (_showExpense ? 1 : 0) +
        (_showWarehouse ? 1 : 0) +
        (_showAnalytics ? 1 : 0);
    final safeIndex = _currentIndex >= tabCount ? 0 : _currentIndex;

    List<Widget> activeTabs = [];
    List<BottomNavigationBarItem> navItems = [];
    var tabIndex = 0;

    if (_showIncome) {
      activeTabs.add(IncomeTab(
        key: ValueKey('income-$workspaceKey'),
        user: widget.user,
        isActive: safeIndex == tabIndex,
      ));
      navItems.add(
        const BottomNavigationBarItem(icon: Icon(Icons.trending_up), label: 'Доходи'),
      );
      tabIndex++;
    }
    if (_showExpense) {
      activeTabs.add(ExpenseTab(
        key: ValueKey('expense-$workspaceKey'),
        user: widget.user,
        isActive: safeIndex == tabIndex,
      ));
      navItems.add(
        const BottomNavigationBarItem(icon: Icon(Icons.trending_down), label: 'Витрати'),
      );
      tabIndex++;
    }
    if (_showWarehouse) {
      activeTabs.add(WarehouseTab(
        key: ValueKey('warehouse-$workspaceKey'),
        user: widget.user,
        isActive: safeIndex == tabIndex,
      ));
      navItems.add(
        const BottomNavigationBarItem(icon: Icon(Icons.inventory_2), label: 'Склад'),
      );
      tabIndex++;
    }

    // Аналітика — четвертий головний екран (модуль, керований у налаштуваннях).
    if (_showAnalytics) {
      activeTabs.add(AnalyticsOverviewScreen(
        key: ValueKey('analytics-$workspaceKey'),
        user: widget.user,
        isActive: safeIndex == tabIndex,
      ));
      navItems.add(
        const BottomNavigationBarItem(
          icon: Icon(Icons.analytics_outlined),
          label: 'Аналітика',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _openWorkspacePicker,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _activeWorkspace.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 28),
            ],
          ),
        ),
        elevation: 2,
        actions: [
          GestureDetector(
            onTap: _openSettingsMenu,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CircleAvatar(
                radius: 18,
                backgroundImage:
                    widget.user.photoUrl != null ? NetworkImage(widget.user.photoUrl!) : null,
                child: widget.user.photoUrl == null ? const Icon(Icons.person) : null,
              ),
            ),
          ),
        ],
      ),
      body: activeTabs.isEmpty
          ? const Center(child: Text("Увімкніть модулі в налаштуваннях"))
          : IndexedStack(
              index: safeIndex,
              children: activeTabs,
            ),
      bottomNavigationBar: navItems.length > 1
          ? BottomNavigationBar(
              currentIndex: safeIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              type: BottomNavigationBarType.fixed,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
              items: navItems,
            )
          : null,
    );
  }
}
