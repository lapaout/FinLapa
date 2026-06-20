import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
        final dateStr = row[0];
        final rowDate = DateTime.tryParse("$dateStr:00");
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
          final rowDate = DateTime.tryParse("${row[0]}:00");
          if (rowDate == null) return false;
          return rowDate.isAfter(picked.start.subtract(const Duration(days: 1))) &&
              rowDate.isBefore(picked.end.add(const Duration(days: 1)));
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
    return header.startsWith('_') ||
        header == 'ID товару (приховано)' ||
        header == 'Продано (шт)' ||
        header == 'Товар зі складу';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isWarehouse
              ? 'Склад: ${widget.dashboardTitle}'
              : 'Історія: ${widget.dashboardTitle}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
