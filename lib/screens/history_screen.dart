import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/history_date_filter.dart';
import '../core/linked_income_loader.dart';
import '../core/warehouse_analytics.dart';
import '../core/warehouse_sales_index.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/sheet_records_repository.dart';
import '../models/dashboard.dart';
import '../models/sheet_record.dart';
import '../widgets/history_record_card.dart';
import '../widgets/warehouse_item_card.dart';

class HistoryScreen extends StatefulWidget {
  final GoogleSignInAccount user;
  final String dashboardTitle;
  final Color dashboardColor;
  final String dashboardType;
  final List<String> dashboardFields;

  const HistoryScreen({
    super.key,
    required this.user,
    required this.dashboardTitle,
    required this.dashboardColor,
    this.dashboardType = Dashboard.typeIncome,
    this.dashboardFields = const [],
  });

  bool get isWarehouse => dashboardType == Dashboard.typeWarehouse;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SheetRecordsRepository _recordsRepository = SheetRecordsRepository();
  final DashboardRepository _dashboardRepository = DashboardRepository();

  bool _isLoading = true;
  bool _isOffline = false;
  List<SheetRecord> _records = [];
  List<SheetRecord> _filteredRecords = [];
  List<LinkedIncomeRecord> _linkedIncomeRecords = [];
  List<String> _headers = [];

  WarehouseStatsCache _warehouseStatsCache = WarehouseStatsCache.empty;
  num _totalAmountCache = 0;

  String _currentFilter = 'Всі';
  DateTimeRange? _customDateRange;

  Dashboard get _warehouseDashboard => Dashboard(
        title: widget.dashboardTitle,
        fields: widget.dashboardFields,
        iconCode: Dashboard.defaultIconCode,
        colorValue: widget.dashboardColor.value,
        type: Dashboard.typeWarehouse,
      );

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _records = [];
    _filteredRecords = [];
    _linkedIncomeRecords = [];
    _headers = [];
    _warehouseStatsCache = WarehouseStatsCache.empty;
    super.dispose();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    if (widget.isWarehouse) {
      await _loadLinkedIncomeRecords();
    }

    final result = await _recordsRepository.getRecords(
      user: widget.user,
      sheetTitle: widget.dashboardTitle,
    );

    if (!mounted) return;

    final headers = await _recordsRepository.getSheetHeaders(widget.dashboardTitle);

    final warehouseStatsCache = widget.isWarehouse
        ? buildWarehouseStatsCache(
            items: result.data,
            dashboard: _warehouseDashboard,
            linkedIncomeRecords: _linkedIncomeRecords,
          )
        : WarehouseStatsCache.empty;

    setState(() {
      _isOffline = result.isOffline;
      _headers = headers;
      _records = result.data;
      _warehouseStatsCache = warehouseStatsCache;
      _recomputeFilteredRecords();
      _isLoading = false;
    });

    if (!mounted) return;

    if (result.isOffline) {
      if (_records.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Офлайн: Показано записи з кешу'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Немає інтернету. Ця вкладка ще не кешувалася.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _loadLinkedIncomeRecords() async {
    final linkedRecords = await loadLinkedIncomeRecords(
      user: widget.user,
      dashboardRepository: _dashboardRepository,
      recordsRepository: _recordsRepository,
    );

    if (!mounted) return;
    setState(() => _linkedIncomeRecords = linkedRecords);
  }

  void _recomputeFilteredRecords() {
    _filteredRecords = HistoryDateFilter.filterRecords(
      records: _records,
      filter: _currentFilter,
      customRange: _customDateRange,
    );
    _totalAmountCache = HistoryRecordCard.totalAmountForRecords(_filteredRecords);
  }

  void _applyFilter(String filter) {
    setState(() {
      _currentFilter = filter;
      _customDateRange = null;
      _recomputeFilteredRecords();
    });
  }

  Future<void> _selectCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: ColorScheme.light(primary: widget.dashboardColor),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _currentFilter = 'Період';
        _customDateRange = picked;
        _recomputeFilteredRecords();
      });
    }
  }

  WarehouseStats _statsForItem(SheetRecord item) {
    return _warehouseStatsCache.statsFor(item) ??
        calculateWarehouseStatsIndexed(
          item: item,
          dashboard: _warehouseDashboard,
          salesIndex: _warehouseStatsCache.salesIndex,
        );
  }

  String _formatNumber(num value) {
    final isWhole = value == value.truncateToDouble();
    final str = isWhole ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

    final parts = str.split('.');
    final intPart = parts[0];
    final isNegative = intPart.startsWith('-');
    final digits = isNegative ? intPart.substring(1) : intPart;

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }

    final grouped = (isNegative ? '-' : '') + buffer.toString();
    return parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
  }

  Widget _buildWarehouseInventoryList() {
    if (_records.isEmpty) {
      return const Center(
        child: Text(
          'Товарів ще немає',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _records.length,
      addAutomaticKeepAlives: false,
      cacheExtent: 500,
      itemBuilder: (context, index) {
        final item = _records[index];
        return RepaintBoundary(
          child: WarehouseItemCard(
            item: item,
            dashboard: _warehouseDashboard,
            stats: _statsForItem(item),
            accentColor: widget.dashboardColor,
          ),
        );
      },
    );
  }

  Widget _buildTransactionHistoryList() {
    if (_records.isEmpty) {
      return const Center(
        child: Text(
          'Записів ще немає',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    if (_filteredRecords.isEmpty) {
      return const Center(
        child: Text(
          'За обраний період записів не знайдено',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredRecords.length,
      addAutomaticKeepAlives: false,
      cacheExtent: 500,
      itemBuilder: (context, index) {
        final record = _filteredRecords[index];
        return HistoryRecordCard(
          key: ValueKey(record.rowIndex ?? index),
          headers: _headers,
          row: record.values,
        );
      },
    );
  }

  Widget _buildTotalAmountBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.dashboardColor,
            Color.alphaBlend(Colors.black.withOpacity(0.15), widget.dashboardColor),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: widget.dashboardColor.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Загальна сума',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_formatNumber(_totalAmountCache)} ₴',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarehouseStatsBanner() {
    final totals = _warehouseStatsCache.totals;
    final spent = totals['spent'] ?? 0;
    final earned = totals['earned'] ?? 0;
    final profit = earned - spent;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.dashboardColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _buildWarehouseStatItem(
                    icon: Icons.inventory_2_rounded,
                    label: 'Залишок',
                    value: '${_formatNumber(totals['remaining'] ?? 0)} шт.',
                    color: widget.dashboardColor,
                  ),
                ),
                _buildStatDivider(),
                Expanded(
                  child: _buildWarehouseStatItem(
                    icon: Icons.trending_down_rounded,
                    label: 'Витрачено',
                    value: '${_formatNumber(spent)} ₴',
                    color: Colors.redAccent,
                  ),
                ),
                _buildStatDivider(),
                Expanded(
                  child: _buildWarehouseStatItem(
                    icon: Icons.trending_up_rounded,
                    label: 'Зароблено',
                    value: '${_formatNumber(earned)} ₴',
                    color: Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ),
          _buildProfitBar(profit),
        ],
      ),
    );
  }

  Widget _buildProfitBar(num profit) {
    final Color profitColor;
    final IconData profitIcon;
    if (profit > 0) {
      profitColor = Colors.green.shade600;
      profitIcon = Icons.arrow_upward_rounded;
    } else if (profit < 0) {
      profitColor = Colors.redAccent;
      profitIcon = Icons.arrow_downward_rounded;
    } else {
      profitColor = Colors.grey.shade600;
      profitIcon = Icons.remove_rounded;
    }

    final sign = profit > 0 ? '+' : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: profitColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: profitColor.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(profitIcon, color: profitColor, size: 20),
          const SizedBox(width: 8),
          Text(
            'Прибуток',
            style: TextStyle(
              color: profitColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '$sign${_formatNumber(profit)} ₴',
                maxLines: 1,
                style: TextStyle(
                  color: profitColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.grey.withOpacity(0.2),
    );
  }

  Widget _buildWarehouseStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isWarehouse
              ? 'Склад: ${widget.dashboardTitle}'
              : 'Історія: ${widget.dashboardTitle}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: widget.dashboardColor.withOpacity(0.1),
      ),
      body: Column(
        children: [
          if (_isOffline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: Colors.redAccent.withOpacity(0.1),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, color: Colors.redAccent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Офлайн режим (тільки читання)',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          if (widget.isWarehouse && !_isLoading && _records.isNotEmpty)
            _buildWarehouseStatsBanner(),
          if (!widget.isWarehouse && !_isLoading && _records.isNotEmpty)
            _buildTotalAmountBanner(),
          if (!widget.isWarehouse)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('Всі'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Сьогодні'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Тиждень'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Місяць'),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: Icon(
                        Icons.calendar_month,
                        size: 18,
                        color: _currentFilter == 'Період'
                            ? Colors.white
                            : widget.dashboardColor,
                      ),
                      label: Text(
                        _customDateRange == null
                            ? 'Період'
                            : '${_customDateRange!.start.day}.${_customDateRange!.start.month} - '
                                '${_customDateRange!.end.day}.${_customDateRange!.end.month}',
                      ),
                      backgroundColor:
                          _currentFilter == 'Період' ? widget.dashboardColor : Colors.white,
                      labelStyle: TextStyle(
                        color: _currentFilter == 'Період' ? Colors.white : Colors.black87,
                      ),
                      side: BorderSide(color: widget.dashboardColor.withOpacity(0.5)),
                      onPressed: _selectCustomDateRange,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: widget.dashboardColor))
                : widget.isWarehouse
                    ? _buildWarehouseInventoryList()
                    : _buildTransactionHistoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _currentFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: widget.dashboardColor,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
      side: BorderSide(color: widget.dashboardColor.withOpacity(0.5)),
      onSelected: (_) => _applyFilter(label),
    );
  }
}
