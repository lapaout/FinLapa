import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/ui_field_filter.dart';
import '../core/warehouse_analytics.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/sheet_records_repository.dart';
import '../models/dashboard.dart';
import '../models/sheet_record.dart';

class DashboardOverviewScreen extends StatefulWidget {
  final GoogleSignInAccount user;
  final String dashboardTitle;
  final Color dashboardColor;
  final String dashboardType;
  final List<String> dashboardFields;

  const DashboardOverviewScreen({
    super.key,
    required this.user,
    required this.dashboardTitle,
    required this.dashboardColor,
    this.dashboardType = Dashboard.typeIncome,
    this.dashboardFields = const [],
  });

  bool get isWarehouse => dashboardType == Dashboard.typeWarehouse;

  @override
  State<DashboardOverviewScreen> createState() => _DashboardOverviewScreenState();
}

class _DashboardOverviewScreenState extends State<DashboardOverviewScreen> {
  final SheetRecordsRepository _recordsRepository = SheetRecordsRepository();
  final DashboardRepository _dashboardRepository = DashboardRepository();

  bool _isLoading = true;
  bool _isOffline = false;
  List<List<String>> _allData = [];
  List<SheetRecord> _records = [];
  List<LinkedIncomeRecord> _linkedIncomeRecords = [];
  List<String> _headers = [];

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

    setState(() {
      _isOffline = result.isOffline;
      _headers = headers;
      _records = result.data;
      _allData = SheetRecordsRepository.recordsToDisplayRows(result.data);
      _isLoading = false;
    });
  }

  Future<void> _loadLinkedIncomeRecords() async {
    final dashboardsResult = await _dashboardRepository.getDashboards(user: widget.user);
    final linkedIncomeDashboards = dashboardsResult.data
        .where(
          (dashboard) =>
              dashboard.type == Dashboard.typeIncome && dashboard.isWarehouseLinked,
        )
        .toList();

    final linkedRecords = <LinkedIncomeRecord>[];

    for (final dashboard in linkedIncomeDashboards) {
      final result = await _recordsRepository.getRecords(
        user: widget.user,
        sheetTitle: dashboard.title,
      );
      final headers = await _recordsRepository.getSheetHeaders(dashboard.title);

      for (final record in result.data) {
        linkedRecords.add(
          LinkedIncomeRecord(record: record, headers: headers),
        );
      }
    }

    if (!mounted) return;
    setState(() => _linkedIncomeRecords = linkedRecords);
  }

  num? _amountForRow(List<String> row) {
    final record = SheetRecord.fromValues(values: row);
    final nativeAmount = record.amount;
    if (nativeAmount != null && nativeAmount > 0) {
      return nativeAmount;
    }

    if (row.length > 1) {
      final normalized =
          row[1].replaceAll(' ', '').replaceAll(',', '.').replaceAll(RegExp(r'[^\d.-]'), '');
      final parsed = num.tryParse(normalized);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    return null;
  }

  num get _totalAmount {
    num total = 0;
    for (final row in _allData) {
      final amount = _amountForRow(row);
      if (amount != null) total += amount;
    }
    return total;
  }

  Map<String, num> get _warehouseTotals {
    num remaining = 0;
    num spent = 0;
    num earned = 0;
    for (final item in _records) {
      final stats = calculateWarehouseStats(
        item: item,
        dashboard: _warehouseDashboard,
        linkedIncomeRecords: _linkedIncomeRecords,
      );
      remaining += stats['remaining'] ?? 0;
      spent += stats['spent'] ?? 0;
      earned += stats['earned'] ?? 0;
    }
    return {'remaining': remaining, 'spent': spent, 'earned': earned};
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

  Widget _buildIncomeExpenseStats() {
    return Container(
      margin: const EdgeInsets.all(16),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Загальна сума',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_formatNumber(_totalAmount)} ₴',
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
          Container(
            width: 1,
            height: 48,
            color: Colors.white.withOpacity(0.3),
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Записів',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_allData.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
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

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.grey.withOpacity(0.2),
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

  Widget _buildWarehouseStats() {
    final totals = _warehouseTotals;
    final spent = totals['spent'] ?? 0;
    final earned = totals['earned'] ?? 0;
    final profit = earned - spent;

    return Container(
      margin: const EdgeInsets.all(16),
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
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined, color: widget.dashboardColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Позицій: ${_records.length}',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
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

  Widget _buildDataTable() {
    if (_allData.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            'Записів ще немає',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    final visibleIndexes = _headers.isNotEmpty
        ? List.generate(_headers.length, (i) => i)
            .where((i) => !isHiddenUiField(_headers[i]))
            .toList()
        : List.generate(
            _allData.map((r) => r.length).fold(0, (a, b) => a > b ? a : b),
            (i) => i,
          );

    final columns = visibleIndexes.map((i) {
      if (_headers.isNotEmpty && i < _headers.length) {
        return _headers[i];
      }
      return 'Колонка ${i + 1}';
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Таблиця',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    widget.dashboardColor.withOpacity(0.08),
                  ),
                  columns: columns
                      .map(
                        (header) => DataColumn(
                          label: Text(
                            header,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  rows: _allData.map((row) {
                    return DataRow(
                      cells: visibleIndexes.map((colIndex) {
                        final value = colIndex < row.length ? row[colIndex] : '';
                        return DataCell(
                          Text(
                            value.isEmpty ? '—' : value,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.dashboardTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: widget.dashboardColor.withOpacity(0.1),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: widget.dashboardColor))
          : Column(
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
                if (widget.isWarehouse)
                  _buildWarehouseStats()
                else
                  _buildIncomeExpenseStats(),
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildDataTable(),
                  ),
                ),
              ],
            ),
    );
  }
}
