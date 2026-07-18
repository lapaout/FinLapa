import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/history_date_filter.dart';
import '../core/warehouse_analytics.dart';
import '../core/warehouse_sales_index.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/sheet_records_repository.dart';
import '../models/dashboard.dart';
import '../widgets/history_record_card.dart';

/// Період, за який рахується аналітика.
enum AnalyticsPeriod {
  today('Сьогодні'),
  week('Тиждень'),
  month('Місяць'),
  year('Рік'),
  all('Весь час');

  const AnalyticsPeriod(this.label);
  final String label;
}

/// Область статусів дашбордів, що потрапляють у розрахунок.
///
/// [onlyActive]   — лише активні (не приховані, не архівні).
/// [activeHidden] — активні + приховані (архівні ігноруються).
/// [all]          — активні + приховані + архівні.
enum AnalyticsScope {
  onlyActive('Активні'),
  activeHidden('Активні + приховані'),
  all('Всі');

  const AnalyticsScope(this.label);
  final String label;
}

/// Одна транзакція, зведена з реального запису дашборда (read-only).
class _Transaction {
  const _Transaction({
    required this.date,
    required this.amount,
    required this.dashboardTitle,
    required this.isIncome,
  });

  final DateTime? date;
  final num amount;
  final String dashboardTitle;
  final bool isIncome;
}

/// Поточний стан одного складу (розраховується «на льоту», read-only).
class _WarehouseStat {
  const _WarehouseStat({
    required this.title,
    required this.color,
    required this.isArchived,
    required this.isHidden,
    required this.frozen,
    required this.remainingUnits,
    required this.soldUnits,
    required this.boughtUnits,
  });

  final String title;
  final Color color;
  final bool isArchived;
  final bool isHidden;

  /// Гроші, витрачені на наявний залишок товару (залишок × собівартість).
  final num frozen;
  final num remainingUnits;
  final num soldUnits;
  final num boughtUnits;
}

/// Стовпчик графіка динаміки (один період на осі X).
class _ChartBucket {
  const _ChartBucket({
    required this.label,
    required this.income,
    required this.expense,
  });

  final String label;
  final num income;
  final num expense;
}

/// Сегмент кругової діаграми (розподіл по джерелах/категоріях).
class _BreakdownSlice {
  const _BreakdownSlice({
    required this.title,
    required this.amount,
    required this.color,
  });

  final String title;
  final num amount;
  final Color color;
}

/// Часова вісь графіка: підписи стовпчиків + функція індексації дати.
class _TimeAxis {
  const _TimeAxis(this.labels, this.indexOf);

  final List<String> labels;
  final int Function(DateTime date) indexOf;
}

/// Повний результат розрахунку аналітики під поточні фільтри.
class _AnalyticsData {
  const _AnalyticsData({
    required this.totalIncome,
    required this.totalExpense,
    required this.warehouseFrozen,
    required this.buckets,
    required this.incomeBreakdown,
    required this.expenseBreakdown,
    required this.warehouses,
  });

  final num totalIncome;
  final num totalExpense;
  final num warehouseFrozen;
  final List<_ChartBucket> buckets;
  final List<_BreakdownSlice> incomeBreakdown;
  final List<_BreakdownSlice> expenseBreakdown;
  final List<_WarehouseStat> warehouses;

  /// Чистий прибуток = Дохід − Витрати − Склад (витрачено на товар).
  num get netProfit => totalIncome - totalExpense - warehouseFrozen;

  static const empty = _AnalyticsData(
    totalIncome: 0,
    totalExpense: 0,
    warehouseFrozen: 0,
    buckets: [],
    incomeBreakdown: [],
    expenseBreakdown: [],
    warehouses: [],
  );
}

/// Четвертий головний екран — «Аналітика» (Financial Analytics).
///
/// Агрегує дані з локального кешу (записи, завантажені іншими модулями
/// через [DashboardRepository] та [SheetRecordsRepository]) і показує
/// загальну фінансову картину: зведені показники, динаміку прибутку,
/// розподіл по категоріях та поточний стан складів.
///
/// Екран не ініціює мережеві запити до Google Sheets. При переході на
/// вкладку перечитує локальний кеш; зміна фільтрів лише викликає
/// [_calculateAnalytics] у пам'яті.
class AnalyticsOverviewScreen extends StatefulWidget {
  final GoogleSignInAccount user;
  final bool isActive;

  const AnalyticsOverviewScreen({
    super.key,
    required this.user,
    this.isActive = false,
  });

  @override
  State<AnalyticsOverviewScreen> createState() =>
      _AnalyticsOverviewScreenState();
}

class _AnalyticsOverviewScreenState extends State<AnalyticsOverviewScreen>
    with AutomaticKeepAliveClientMixin {
  static const Color _incomeColor = Color(0xFF2E9E5B);
  static const Color _expenseColor = Color(0xFFE5484D);
  static const Color _warehouseColor = Color(0xFF2563EB);

  static const List<String> _weekdayLabels = [
    'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд',
  ];
  static const List<String> _monthsShort = [
    'Січ', 'Лют', 'Бер', 'Кві', 'Тра', 'Чер',
    'Лип', 'Сер', 'Вер', 'Жов', 'Лис', 'Гру',
  ];
  static const List<String> _dayPartLabels = [
    '00', '04', '08', '12', '16', '20',
  ];

  final DashboardRepository _dashboardRepository = DashboardRepository();
  final SheetRecordsRepository _recordsRepository = SheetRecordsRepository();

  // Фільтри.
  AnalyticsPeriod _period = AnalyticsPeriod.month;
  DateTimeRange? _customRange;
  AnalyticsScope _scope = AnalyticsScope.onlyActive;

  // Реальні дані.
  Map<String, Dashboard> _dashboardsByTitle = {};
  List<_Transaction> _transactions = [];
  List<_WarehouseStat> _warehousesAll = [];
  DateTime? _earliestDate;

  bool _isLoading = false;
  bool _isOffline = false;
  bool _hasLoadedOnce = false;
  String? _loadError;

  _AnalyticsData _data = _AnalyticsData.empty;

  @override
  bool get wantKeepAlive => _hasLoadedOnce;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _loadData();
    }
  }

  @override
  void didUpdateWidget(covariant AnalyticsOverviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // При кожному переході на вкладку — перечитати локальний кеш і
    // перерахувати аналітику (дані могли змінитися в інших модулях).
    if (widget.isActive && !oldWidget.isActive) {
      _loadData();
    }
  }

  // ---------------------------------------------------------------------------
  // Завантаження з локального кешу (без мережі)
  // ---------------------------------------------------------------------------

  /// Завантажує аналітику з локального кешу (без мережевих запитів).
  Future<void> _loadData() async {
    final isInitialLoad = !_hasLoadedOnce;
    if (isInitialLoad) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final dashboards = await _dashboardRepository.getCachedDashboards();

      // Грошові потоки: доходи та витрати.
      final cashflowDashboards = dashboards
          .where(
            (dashboard) =>
                dashboard.type == Dashboard.typeIncome ||
                dashboard.type == Dashboard.typeExpense,
          )
          .toList();

      // Склади.
      final warehouseDashboards = dashboards
          .where((dashboard) => dashboard.type == Dashboard.typeWarehouse)
          .toList();

      // Записи доходів, прив'язані до складів (для обчислення продажів) — лише кеш.
      final linkedIncomeRecords = await _loadLinkedIncomeFromCache();

      // 1. Транзакції доходів/витрат (лише кеш).
      final transactions = <_Transaction>[];
      DateTime? earliest;
      for (final dashboard in cashflowDashboards) {
        final records = await _recordsRepository.getCachedRecords(
          sheetTitle: dashboard.title,
        );

        final isIncome = dashboard.type == Dashboard.typeIncome;
        for (final record in records) {
          final row = record.values;
          if (row.isEmpty) continue;

          final amount = HistoryRecordCard.amountForRow(row);
          if (amount == null || amount <= 0) continue;

          final date = HistoryDateFilter.parseDateSafely(row.first);
          if (date != null &&
              (earliest == null || date.isBefore(earliest))) {
            earliest = date;
          }

          transactions.add(
            _Transaction(
              date: date,
              amount: amount,
              dashboardTitle: dashboard.title,
              isIncome: isIncome,
            ),
          );
        }
      }

      // 2. Поточний стан складів (витрачено на товар, залишки, продажі).
      final salesIndex = WarehouseSalesIndex.build(linkedIncomeRecords);
      final warehouses = <_WarehouseStat>[];
      for (final dashboard in warehouseDashboards) {
        final records = await _recordsRepository.getCachedRecords(
          sheetTitle: dashboard.title,
        );

        num frozen = 0;
        num remaining = 0;
        num sold = 0;
        num bought = 0;
        for (final item in records) {
          final stats = calculateWarehouseStatsIndexed(
            item: item,
            dashboard: dashboard,
            salesIndex: salesIndex,
          );
          final itemRemaining = stats['remaining'] ?? 0;
          final costPerUnit = stats['costPerUnit'] ?? 0;
          frozen += (itemRemaining > 0 ? itemRemaining : 0) * costPerUnit;
          remaining += itemRemaining;
          sold += stats['sold'] ?? 0;
          bought += stats['bought'] ?? 0;
        }

        warehouses.add(
          _WarehouseStat(
            title: dashboard.title,
            color: Color(dashboard.colorValue),
            isArchived: dashboard.isArchived,
            isHidden: dashboard.isHidden,
            frozen: frozen,
            remainingUnits: remaining,
            soldUnits: sold,
            boughtUnits: bought,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _dashboardsByTitle = {for (final d in cashflowDashboards) d.title: d};
        _transactions = transactions;
        _warehousesAll = warehouses;
        _earliestDate = earliest;
        _isOffline = false;
        _isLoading = false;
        _hasLoadedOnce = true;
        _data = _calculateAnalytics();
      });
      updateKeepAlive();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasLoadedOnce = true;
        _loadError = error.toString();
      });
    }
  }

  /// Записи income-дашбордів, прив'язаних до складу — тільки з локального кешу.
  Future<List<LinkedIncomeRecord>> _loadLinkedIncomeFromCache() async {
    final dashboards = (await _dashboardRepository.getCachedDashboards())
        .where(
          (dashboard) =>
              dashboard.type == Dashboard.typeIncome &&
              dashboard.isWarehouseLinked,
        )
        .toList();

    final linkedRecords = <LinkedIncomeRecord>[];
    for (final dashboard in dashboards) {
      final records = await _recordsRepository.getCachedRecords(
        sheetTitle: dashboard.title,
      );
      final headers = await _recordsRepository.getSheetHeaders(dashboard.title);
      for (final record in records) {
        linkedRecords.add(
          LinkedIncomeRecord(record: record, headers: headers),
        );
      }
    }
    return linkedRecords;
  }

  // ---------------------------------------------------------------------------
  // Розрахунок аналітики
  // ---------------------------------------------------------------------------

  /// Перераховує всі показники під поточні фільтри.
  ///
  /// Доходи/витрати враховують фільтр періоду та статусів. Склади (витрачено
  /// на товар) залежать лише від фільтра статусів — це поточний стан, не
  /// прив'язаний до дати.
  _AnalyticsData _calculateAnalytics() {
    final (start, end) = _activeRange();

    final visible = _transactions.where((txn) {
      final dashboard = _dashboardsByTitle[txn.dashboardTitle];
      if (dashboard == null) return false;
      if (!_scopeAllows(dashboard.isArchived, dashboard.isHidden)) {
        return false;
      }
      return _inRange(txn.date, start, end);
    }).toList();

    num totalIncome = 0;
    num totalExpense = 0;
    final incomeByTitle = <String, num>{};
    final expenseByTitle = <String, num>{};

    for (final txn in visible) {
      if (txn.isIncome) {
        totalIncome += txn.amount;
        incomeByTitle.update(
          txn.dashboardTitle,
          (value) => value + txn.amount,
          ifAbsent: () => txn.amount,
        );
      } else {
        totalExpense += txn.amount;
        expenseByTitle.update(
          txn.dashboardTitle,
          (value) => value + txn.amount,
          ifAbsent: () => txn.amount,
        );
      }
    }

    // Склади фільтруються лише за статусом (поточний стан, без періоду).
    final warehouses = _warehousesAll
        .where((w) => _scopeAllows(w.isArchived, w.isHidden))
        .toList();
    final warehouseFrozen =
        warehouses.fold<num>(0, (sum, w) => sum + w.frozen);

    return _AnalyticsData(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      warehouseFrozen: warehouseFrozen,
      buckets: _buildBuckets(visible, start, end),
      incomeBreakdown: _buildBreakdown(incomeByTitle),
      expenseBreakdown: _buildBreakdown(expenseByTitle),
      warehouses: warehouses,
    );
  }

  bool _scopeAllows(bool isArchived, bool isHidden) {
    switch (_scope) {
      case AnalyticsScope.onlyActive:
        return !isArchived && !isHidden;
      case AnalyticsScope.activeHidden:
        return !isArchived;
      case AnalyticsScope.all:
        return true;
    }
  }

  /// Активний діапазон дат [start, end] під поточний період/довільний вибір.
  (DateTime, DateTime) _activeRange() {
    final now = DateTime.now();

    final customRange = _customRange;
    if (customRange != null) {
      final start = DateTime(
        customRange.start.year,
        customRange.start.month,
        customRange.start.day,
      );
      final end = DateTime(
        customRange.end.year,
        customRange.end.month,
        customRange.end.day,
        23,
        59,
        59,
      );
      return (start, end);
    }

    switch (_period) {
      case AnalyticsPeriod.today:
        return (DateTime(now.year, now.month, now.day), now);
      case AnalyticsPeriod.week:
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return (monday, now);
      case AnalyticsPeriod.month:
        return (DateTime(now.year, now.month, 1), now);
      case AnalyticsPeriod.year:
        return (DateTime(now.year, 1, 1), now);
      case AnalyticsPeriod.all:
        return (_earliestDate ?? DateTime(2000), now);
    }
  }

  bool _inRange(DateTime? date, DateTime start, DateTime end) {
    if (date == null) {
      // Записи без розпізнаної дати враховуємо лише у режимі «Весь час».
      return _customRange == null && _period == AnalyticsPeriod.all;
    }
    return !date.isBefore(start) && !date.isAfter(end);
  }

  /// Групує транзакції у стовпчики графіка залежно від часової осі.
  List<_ChartBucket> _buildBuckets(
    List<_Transaction> transactions,
    DateTime start,
    DateTime end,
  ) {
    final axis = _buildTimeAxis(start, end);
    if (axis.labels.isEmpty) return const [];

    final income = List<num>.filled(axis.labels.length, 0);
    final expense = List<num>.filled(axis.labels.length, 0);

    for (final txn in transactions) {
      final date = txn.date;
      if (date == null) continue;
      final index = axis.indexOf(date);
      if (index < 0 || index >= axis.labels.length) continue;
      if (txn.isIncome) {
        income[index] += txn.amount;
      } else {
        expense[index] += txn.amount;
      }
    }

    return [
      for (var i = 0; i < axis.labels.length; i++)
        _ChartBucket(
          label: axis.labels[i],
          income: income[i],
          expense: expense[i],
        ),
    ];
  }

  _TimeAxis _buildTimeAxis(DateTime start, DateTime end) {
    if (_customRange != null) {
      return _adaptiveAxis(start, end);
    }

    switch (_period) {
      case AnalyticsPeriod.today:
        return _TimeAxis(
          _dayPartLabels,
          (date) => (date.hour ~/ 4).clamp(0, _dayPartLabels.length - 1),
        );
      case AnalyticsPeriod.week:
        return _TimeAxis(_weekdayLabels, (date) => date.weekday - 1);
      case AnalyticsPeriod.month:
        final daysInMonth = DateTime(start.year, start.month + 1, 0).day;
        final weeks = ((daysInMonth - 1) ~/ 7) + 1;
        return _TimeAxis(
          [for (var i = 0; i < weeks; i++) 'Т${i + 1}'],
          (date) => (date.day - 1) ~/ 7,
        );
      case AnalyticsPeriod.year:
        return _TimeAxis(_monthsShort, (date) => date.month - 1);
      case AnalyticsPeriod.all:
        final minYear = start.year;
        final maxYear = end.year;
        return _TimeAxis(
          [for (var y = minYear; y <= maxYear; y++) '$y'],
          (date) => date.year - minYear,
        );
    }
  }

  /// Адаптивна вісь для довільного проміжку: гранулярність за довжиною.
  _TimeAxis _adaptiveAxis(DateTime start, DateTime end) {
    final startDay = DateTime(start.year, start.month, start.day);
    final spanDays = math.max(0, end.difference(startDay).inDays);

    if (spanDays <= 1) {
      return _TimeAxis(
        _dayPartLabels,
        (date) => (date.hour ~/ 4).clamp(0, _dayPartLabels.length - 1),
      );
    }

    if (spanDays <= 8) {
      final days = spanDays + 1;
      return _TimeAxis(
        [
          for (var i = 0; i < days; i++)
            _shortDate(startDay.add(Duration(days: i))),
        ],
        (date) => DateTime(date.year, date.month, date.day)
            .difference(startDay)
            .inDays,
      );
    }

    if (spanDays <= 45) {
      final weeks = (spanDays ~/ 7) + 1;
      return _TimeAxis(
        [
          for (var i = 0; i < weeks; i++)
            _shortDate(startDay.add(Duration(days: i * 7))),
        ],
        (date) =>
            DateTime(date.year, date.month, date.day)
                .difference(startDay)
                .inDays ~/
            7,
      );
    }

    if (spanDays <= 366) {
      final startMonth = DateTime(start.year, start.month);
      final months = _monthDiff(end, startMonth) + 1;
      return _TimeAxis(
        [
          for (var i = 0; i < months; i++)
            _monthsShort[DateTime(startMonth.year, startMonth.month + i)
                .month -
                1],
        ],
        (date) => _monthDiff(date, startMonth),
      );
    }

    final startYear = start.year;
    return _TimeAxis(
      [for (var y = startYear; y <= end.year; y++) '$y'],
      (date) => date.year - startYear,
    );
  }

  int _monthDiff(DateTime date, DateTime base) {
    return (date.year - base.year) * 12 + (date.month - base.month);
  }

  String _shortDate(DateTime date) => '${date.day}.${date.month}';

  List<_BreakdownSlice> _buildBreakdown(Map<String, num> byTitle) {
    final slices = byTitle.entries
        .where((entry) => entry.value > 0)
        .map(
          (entry) => _BreakdownSlice(
            title: entry.key,
            amount: entry.value,
            color: _colorForDashboard(entry.key),
          ),
        )
        .toList();
    slices.sort((a, b) => b.amount.compareTo(a.amount));
    return slices;
  }

  Color _colorForDashboard(String title) {
    final dashboard = _dashboardsByTitle[title];
    if (dashboard == null) return Colors.grey;
    return Color(dashboard.colorValue);
  }

  // ---------------------------------------------------------------------------
  // Обробники фільтрів
  // ---------------------------------------------------------------------------

  void _onPeriodChanged(AnalyticsPeriod period) {
    setState(() {
      _period = period;
      _customRange = null; // Вибір пресету скидає довільний проміжок.
      _data = _calculateAnalytics();
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customRange,
    );

    if (picked == null) return;
    setState(() {
      _customRange = picked; // Довільний проміжок скидає пресет періоду.
      _data = _calculateAnalytics();
    });
  }

  void _clearCustomRange() {
    setState(() {
      _customRange = null;
      _data = _calculateAnalytics();
    });
  }

  void _onScopeChanged(AnalyticsScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _data = _calculateAnalytics();
    });
  }

  // ---------------------------------------------------------------------------
  // Форматування
  // ---------------------------------------------------------------------------

  /// Форматує суму з пробілами тисяч, напр. `15 000 ₴`.
  String _formatMoney(num value) {
    final rounded = value.round();
    final isNegative = rounded < 0;
    final digits = rounded.abs().toString();

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }

    return '${isNegative ? '-' : ''}${buffer.toString()} ₴';
  }

  /// Форматує кількість штук з пробілами тисяч, напр. `1 250 шт`.
  String _formatUnits(num value) {
    final rounded = value.round();
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return '${rounded < 0 ? '-' : ''}${buffer.toString()} шт';
  }

  /// Короткий формат для осі Y графіка: `15k`, `1.2M`.
  String _shortNumber(num value) {
    final abs = value.abs();
    if (abs >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(abs >= 10000000 ? 0 : 1)}M';
    }
    if (abs >= 1000) {
      return '${(value / 1000).toStringAsFixed(abs >= 10000 ? 0 : 1)}k';
    }
    return value.toStringAsFixed(0);
  }

  String _percent(num part, num total) {
    if (total <= 0) return '0';
    return (part / total * 100).toStringAsFixed(0);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_hasLoadedOnce && !widget.isActive) {
      return const SizedBox.shrink();
    }

    if (_isLoading && _transactions.isEmpty && _loadError == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null && _transactions.isEmpty) {
      return _buildErrorState();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isOffline) _buildOfflineBanner(),
          _buildFiltersPanel(),
          const SizedBox(height: 20),
          _buildSummaryCards(),
          const SizedBox(height: 20),
          _buildDynamicsChartCard(),
          const SizedBox(height: 20),
          _buildBreakdownCard(
            title: 'Структура доходів',
            icon: Icons.trending_up_rounded,
            accent: _incomeColor,
            slices: _data.incomeBreakdown,
            emptyLabel: 'Немає доходів за обраний період',
          ),
          const SizedBox(height: 16),
          _buildBreakdownCard(
            title: 'Структура витрат',
            icon: Icons.trending_down_rounded,
            accent: _expenseColor,
            slices: _data.expenseBreakdown,
            emptyLabel: 'Немає витрат за обраний період',
          ),
          const SizedBox(height: 16),
          _buildWarehouseCard(),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            const Text(
              'Не вдалося завантажити аналітику',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _loadError ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Спробувати ще раз'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Офлайн: показано збережені дані з кешу',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 1. Панель фільтрів ---------------------------------------------------------

  Widget _buildFiltersPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildFilterLabel(
                  Icons.calendar_today_rounded,
                  'Період',
                ),
              ),
              _buildCustomRangeButton(),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AnalyticsPeriod>(
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              style: _segmentStyle(),
              segments: [
                for (final period in AnalyticsPeriod.values)
                  ButtonSegment<AnalyticsPeriod>(
                    value: period,
                    label: Text(
                      period.label,
                      style: const TextStyle(fontSize: 11),
                      maxLines: 1,
                    ),
                  ),
              ],
              selected: _customRange != null
                  ? <AnalyticsPeriod>{}
                  : {_period},
              onSelectionChanged: (selection) {
                if (selection.isEmpty) return;
                _onPeriodChanged(selection.first);
              },
            ),
          ),
          if (_customRange != null) _buildCustomRangeChip(),
          const SizedBox(height: 18),
          _buildFilterLabel(Icons.layers_rounded, 'Статус дашбордів'),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<AnalyticsScope>(
              showSelectedIcon: false,
              style: _segmentStyle(),
              segments: [
                for (final scope in AnalyticsScope.values)
                  ButtonSegment<AnalyticsScope>(
                    value: scope,
                    label: Text(
                      scope.label,
                      style: const TextStyle(fontSize: 10.5),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  ),
              ],
              selected: {_scope},
              onSelectionChanged: (selection) =>
                  _onScopeChanged(selection.first),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomRangeButton() {
    final isActive = _customRange != null;
    return TextButton.icon(
      onPressed: _pickCustomRange,
      style: TextButton.styleFrom(
        foregroundColor: isActive
            ? Theme.of(context).colorScheme.primary
            : Colors.grey.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.date_range_rounded, size: 18),
      label: const Text('Свій період', style: TextStyle(fontSize: 12.5)),
    );
  }

  Widget _buildCustomRangeChip() {
    final range = _customRange!;
    final text =
        '${_shortDate(range.start)}.${range.start.year} — '
        '${_shortDate(range.end)}.${range.end.year}';

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(
            Icons.event_available_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Довільний період: $text',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          InkWell(
            onTap: _clearCustomRange,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 16, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterLabel(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade700),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade800,
          ),
        ),
      ],
    );
  }

  ButtonStyle _segmentStyle() {
    return SegmentedButton.styleFrom(
      selectedBackgroundColor: Theme.of(context).colorScheme.primary,
      selectedForegroundColor: Colors.white,
      foregroundColor: Colors.grey.shade700,
      side: BorderSide(color: Colors.grey.shade300),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      visualDensity: VisualDensity.compact,
    );
  }

  // 2. Зведені показники -------------------------------------------------------

  Widget _buildSummaryCards() {
    final profit = _data.netProfit;
    final profitColor = profit >= 0 ? _incomeColor : _expenseColor;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _buildSummaryCard(
              label: 'Дохід',
              value: _data.totalIncome,
              color: _incomeColor,
              icon: Icons.arrow_downward_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildSummaryCard(
              label: 'Витрати',
              value: _data.totalExpense,
              color: _expenseColor,
              icon: Icons.arrow_upward_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildSummaryCard(
              label: 'Склад',
              value: _data.warehouseFrozen,
              color: _warehouseColor,
              icon: Icons.inventory_2_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildSummaryCard(
              label: 'Прибуток',
              value: profit,
              color: profitColor,
              icon: profit >= 0
                  ? Icons.savings_rounded
                  : Icons.warning_amber_rounded,
              showSign: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String label,
    required num value,
    required Color color,
    required IconData icon,
    bool showSign = false,
  }) {
    final sign = showSign && value > 0 ? '+' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$sign${_formatMoney(value)}',
              maxLines: 1,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 3. Головний графік ---------------------------------------------------------

  Widget _buildDynamicsChartCard() {
    final buckets = _data.buckets;
    final maxValue = buckets.fold<num>(0, (currentMax, bucket) {
      final localMax = math.max(bucket.income, bucket.expense);
      return math.max(currentMax, localMax);
    });
    final maxY = maxValue <= 0 ? 100.0 : (maxValue * 1.2).toDouble();
    final interval = maxY / 4;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            Icons.bar_chart_rounded,
            'Динаміка прибутку',
            Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          _buildChartLegend(),
          const SizedBox(height: 16),
          SizedBox(
            height: 230,
            child: (buckets.isEmpty || maxValue <= 0)
                ? _buildEmptyChart('Немає даних за обраний період')
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: maxY,
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => Colors.blueGrey.shade800,
                          getTooltipItem: (group, _, rod, _) {
                            return BarTooltipItem(
                              _formatMoney(rod.toY),
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            interval: interval,
                            getTitlesWidget: (value, meta) {
                              if (value > maxY) return const SizedBox.shrink();
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  _shortNumber(value),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 26,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= buckets.length) {
                                return const SizedBox.shrink();
                              }
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  buckets[index].label,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: interval,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey.shade200,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: [
                        for (var i = 0; i < buckets.length; i++)
                          BarChartGroupData(
                            x: i,
                            barsSpace: 4,
                            barRods: [
                              _buildRod(buckets[i].income, _incomeColor),
                              _buildRod(buckets[i].expense, _expenseColor),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  BarChartRodData _buildRod(num value, Color color) {
    return BarChartRodData(
      toY: value.toDouble(),
      color: color,
      width: 9,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    );
  }

  Widget _buildChartLegend() {
    return Row(
      children: [
        _buildLegendDot(_incomeColor, 'Дохід'),
        const SizedBox(width: 16),
        _buildLegendDot(_expenseColor, 'Витрати'),
      ],
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _buildEmptyChart(String message) {
    return Center(
      child: Text(
        message,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
      ),
    );
  }

  // 4. Розподіл по категоріях (клікабельні) ------------------------------------

  Widget _buildBreakdownCard({
    required String title,
    required IconData icon,
    required Color accent,
    required List<_BreakdownSlice> slices,
    required String emptyLabel,
    VoidCallback? onTap,
  }) {
    final total = slices.fold<num>(0, (sum, slice) => sum + slice.amount);
    final hasData = slices.isNotEmpty && total > 0;

    // Показуємо не більше 4 категорій на головному екрані; решта — у деталях.
    final visibleSlices = hasData ? slices.take(4).toList() : const <_BreakdownSlice>[];
    final hiddenCount = hasData ? slices.length - visibleSlices.length : 0;

    final content = Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon,
            title,
            accent,
            trailing: hasData ? _buildDetailsHint() : null,
          ),
          const SizedBox(height: 16),
          if (!hasData)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  emptyLabel,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
              ),
            )
          else
            Row(
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 34,
                      sections: [
                        for (final slice in slices)
                          PieChartSectionData(
                            value: slice.amount.toDouble(),
                            color: slice.color,
                            radius: 26,
                            title: '${_percent(slice.amount, total)}%',
                            titleStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final slice in visibleSlices)
                        _buildBreakdownRow(slice, total),
                      if (hiddenCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.more_horiz_rounded,
                                size: 18,
                                color: Colors.grey.shade500,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Ще $hiddenCount — натисніть для деталей',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );

    if (!hasData) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () => _showBreakdownSheet(title, icon, accent, slices),
        borderRadius: BorderRadius.circular(18),
        child: content,
      ),
    );
  }

  Widget _buildDetailsHint() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Деталі',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey.shade500),
      ],
    );
  }

  Widget _buildBreakdownRow(_BreakdownSlice slice, num total) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: slice.color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              slice.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_percent(slice.amount, total)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  /// Детальний перелік усіх категорій структури у нижньому листі.
  void _showBreakdownSheet(
    String title,
    IconData icon,
    Color accent,
    List<_BreakdownSlice> slices,
  ) {
    final total = slices.fold<num>(0, (sum, slice) => sum + slice.amount);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Icon(icon, color: accent, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        _formatMoney(total),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    itemCount: slices.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: Colors.grey.shade100,
                    ),
                    itemBuilder: (context, index) {
                      final slice = slices[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: slice.color,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                slice.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  _formatMoney(slice.amount),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${_percent(slice.amount, total)}%',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 5. Стан складів (поточний, не залежить від періоду) ------------------------

  /// Компактна картка «Стан складів» — виглядає як картки структури доходів/
  /// витрат (PieChart + легенда). Детальний розклад з прогрес-барами
  /// відкривається по тапу у [_showWarehouseSheet].
  ///
  /// Секція завжди показує поточний стан і не залежить від фільтра періоду —
  /// реагує лише на фільтр статусів (склади вже відфільтровані у
  /// [_calculateAnalytics]).
  Widget _buildWarehouseCard() {
    final warehouses = _data.warehouses;

    // Пиріг за грошима, витраченими на наявний залишок. Якщо собівартість
    // ніде не задана — резервно розподіляємо за кількістю залишку (штуками).
    final useMoney = warehouses.any((w) => w.frozen > 0);
    final slices = <_BreakdownSlice>[];
    for (final warehouse in warehouses) {
      final remaining =
          warehouse.remainingUnits < 0 ? 0 : warehouse.remainingUnits;
      final amount = useMoney ? warehouse.frozen : remaining;
      if (amount <= 0) continue;
      slices.add(
        _BreakdownSlice(
          title: warehouse.title,
          amount: amount,
          color: warehouse.color,
        ),
      );
    }
    slices.sort((a, b) => b.amount.compareTo(a.amount));

    return _buildBreakdownCard(
      title: 'Стан складів',
      icon: Icons.warehouse_rounded,
      accent: _warehouseColor,
      slices: slices,
      emptyLabel: warehouses.isEmpty
          ? 'Немає складів за обраним фільтром статусів'
          : 'Немає залишків на складах',
      onTap: warehouses.isEmpty ? null : _showWarehouseSheet,
    );
  }

  /// Детальний розклад складів з прогрес-барами (яскраве — наявний залишок,
  /// напівпрозоре — продано). Відкривається по тапу на компактну картку.
  void _showWarehouseSheet() {
    final warehouses = _data.warehouses;
    if (warehouses.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warehouse_rounded,
                        color: _warehouseColor,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Стан складів',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Поточний стан на цей момент (не залежить від періоду)',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _buildWarehouseLegend(),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    itemCount: warehouses.length,
                    separatorBuilder: (_, _) => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                    itemBuilder: (context, index) =>
                        _buildWarehouseStateRow(warehouses[index]),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWarehouseLegend() {
    return Row(
      children: [
        _buildLegendDot(_warehouseColor, 'Залишок'),
        const SizedBox(width: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.25),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Продано',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWarehouseStateRow(_WarehouseStat warehouse) {
    final bought = warehouse.boughtUnits;
    final remaining = warehouse.remainingUnits < 0 ? 0 : warehouse.remainingUnits;
    final fraction = bought > 0 ? (remaining / bought).clamp(0.0, 1.0) : 0.0;
    final percent = (fraction * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: warehouse.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                warehouse.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: warehouse.color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final fullWidth = constraints.maxWidth;
            return ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                children: [
                  Container(
                    height: 12,
                    width: fullWidth,
                    color: warehouse.color.withOpacity(0.15),
                  ),
                  Container(
                    height: 12,
                    width: fullWidth * fraction,
                    color: warehouse.color,
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildWarehouseMetric(
                'Залишок',
                _formatUnits(warehouse.remainingUnits),
                warehouse.color,
              ),
            ),
            Expanded(
              child: _buildWarehouseMetric(
                'Продано',
                _formatUnits(warehouse.soldUnits),
                Colors.grey.shade600,
              ),
            ),
            Expanded(
              child: _buildWarehouseMetric(
                'Витрачено',
                _formatMoney(warehouse.frozen),
                _warehouseColor,
                alignEnd: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWarehouseMetric(
    String label,
    String value,
    Color color, {
    bool alignEnd = false,
  }) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  // Спільні елементи -----------------------------------------------------------

  Widget _buildSectionHeader(
    IconData icon,
    String title,
    Color color, {
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.grey.withOpacity(0.15)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
