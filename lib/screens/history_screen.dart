import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/ui_field_filter.dart';
import '../core/warehouse_analytics.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/sheet_records_repository.dart';
import '../models/dashboard.dart';
import '../models/sheet_record.dart';
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
  List<List<String>> _allData = [];
  List<List<String>> _filteredData = [];
  List<SheetRecord> _records = [];
  List<LinkedIncomeRecord> _linkedIncomeRecords = [];
  List<String> _headers = [];

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
      _filteredData = List.from(_allData);
      _isLoading = false;
    });

    if (result.isOffline) {
      if (_allData.isNotEmpty) {
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

  DateTime? _parseDateSafely(String dateStr) {
    DateTime? parsed = DateTime.tryParse(dateStr) ?? DateTime.tryParse('$dateStr:00');
    if (parsed != null) return parsed;

    try {
      final cleanDate = dateStr.split(' ')[0];
      final parts = cleanDate.split(RegExp(r'[\.\-\/]'));
      if (parts.length >= 3) {
        int day = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int year = int.parse(parts[2]);
        if (year < 100) year += 2000;

        return DateTime(year, month, day);
      }
    } catch (_) {}

    return null;
  }

  void _applyFilter(String filter) {
    setState(() {
      _currentFilter = filter;
      _customDateRange = null;

      if (filter == 'Всі') {
        _filteredData = List.from(_allData);
        return;
      }

      final now = DateTime.now();
      _filteredData = _allData.where((row) {
        if (row.isEmpty) return false;
        final rowDate = _parseDateSafely(row[0]);
        if (rowDate == null) return false;

        if (filter == 'Сьогодні') {
          return rowDate.year == now.year &&
              rowDate.month == now.month &&
              rowDate.day == now.day;
        } else if (filter == 'Тиждень') {
          return now.difference(rowDate).inDays <= 7;
        } else if (filter == 'Місяць') {
          return rowDate.year == now.year && rowDate.month == now.month;
        }
        return true;
      }).toList();
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
        _filteredData = _allData.where((row) {
          if (row.isEmpty) return false;
          final rowDate = _parseDateSafely(row[0]);
          if (rowDate == null) return false;

          final start = picked.start.subtract(const Duration(seconds: 1));
          final end = picked.end.add(const Duration(days: 1));

          return rowDate.isAfter(start) && rowDate.isBefore(end);
        }).toList();
      });
    }
  }

  Map<String, String> _fieldsForRow(List<String> row) {
    final map = <String, String>{};
    for (var i = 1; i < _headers.length && i < row.length; i++) {
      map[_headers[i]] = row[i];
    }
    return map;
  }

  bool _isAmountHeader(String header) {
    final normalized = header.toLowerCase();
    return normalized.contains('сум') || normalized.contains('amount');
  }

  bool _isHiddenHistoryHeader(String header) {
    if (isHiddenUiField(header)) return true;
    return header == 'Продано (шт)' || header == 'Товар зі складу';
  }

  String? _warehouseField(Map<String, String> fields, String newKey, String oldKey) {
    final newValue = fields[newKey]?.trim();
    if (newValue != null && newValue.isNotEmpty) {
      return newValue;
    }
    return fields[oldKey]?.trim();
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

  /// Загальна сума записів у поточному фільтрі (Доходи/Витрати).
  num get _totalAmount {
    num total = 0;
    for (final row in _filteredData) {
      final amount = _amountForRow(row);
      if (amount != null) total += amount;
    }
    return total;
  }

  /// Сумарна статистика для всього складського дашборда.
  /// Переюзовує існуючу логіку [calculateWarehouseStats] для кожної позиції,
  /// нічого в ній не змінюючи.
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

  Widget _buildRecordCard(List<String> row) {
    final fields = _fieldsForRow(row);
    final warehouseItemName =
        _warehouseField(fields, 'Товар зі складу', '_warehouseItemName');
    final soldQuantity = _warehouseField(fields, 'Продано (шт)', '_soldQuantity');
    final hasWarehouseSale = warehouseItemName != null &&
        warehouseItemName.isNotEmpty &&
        soldQuantity != null &&
        soldQuantity.isNotEmpty;
    final displayAmount = _amountForRow(row);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  row.isNotEmpty ? row[0] : 'Без дати',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Divider(),
            if (hasWarehouseSale)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '📦 Товар: $warehouseItemName | Продано: $soldQuantity шт.',
                  style: TextStyle(
                    color: Colors.teal.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            if (displayAmount != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '💰 Сума: $displayAmount ₴',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ...List.generate(_headers.length - 1, (i) {
              final colIndex = i + 1;
              final header = _headers.length > colIndex ? _headers[colIndex] : 'Поле';
              final value = colIndex < row.length ? row[colIndex].trim() : '-';

              if (_isHiddenHistoryHeader(header)) {
                return const SizedBox.shrink();
              }

              if (value.isEmpty || value == '-') {
                return const SizedBox.shrink();
              }

              if (_isAmountHeader(header)) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        "$header:",
                        style: const TextStyle(color: Colors.black54, fontSize: 14),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        value,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildWarehouseInventoryList() {
    if (_records.isEmpty) {
      return const Center(
        child: Text(
          "Товарів ще немає",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _records.length,
      itemBuilder: (context, index) {
        return WarehouseItemCard(
          item: _records[index],
          dashboard: _warehouseDashboard,
          linkedIncomeRecords: _linkedIncomeRecords,
          accentColor: widget.dashboardColor,
        );
      },
    );
  }

  Widget _buildTransactionHistoryList() {
    if (_allData.isEmpty) {
      return const Center(
        child: Text(
          "Записів ще немає",
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    if (_filteredData.isEmpty) {
      return const Center(
        child: Text(
          "За обраний період записів не знайдено",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredData.length,
      itemBuilder: (context, index) => _buildRecordCard(_filteredData[index]),
    );
  }

  /// Плашка "Загальна сума" для звичайних дашбордів (Доходи / Витрати).
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
        ],
      ),
    );
  }

  /// Сумарна плашка для всього складського дашборда (3 показники + прибуток).
  Widget _buildWarehouseStatsBanner() {
    final totals = _warehouseTotals;
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

  /// Смужка "Прибуток" = Зароблено − Витрачено з кольоровою індикацією.
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
                    "Офлайн режим (тільки читання)",
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

          if (!widget.isWarehouse && !_isLoading && _allData.isNotEmpty)
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
                            : '${_customDateRange!.start.day}.${_customDateRange!.start.month} - ${_customDateRange!.end.day}.${_customDateRange!.end.month}',
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
