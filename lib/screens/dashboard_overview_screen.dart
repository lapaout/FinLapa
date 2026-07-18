import 'dart:math' show max;

import 'package:finlapa/core/money_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/linked_income_loader.dart';
import '../core/ui_field_filter.dart';
import '../core/warehouse_analytics.dart';
import '../core/warehouse_sales_index.dart';
import '../data/repositories/dashboard_repository.dart';
import '../data/repositories/sheet_records_repository.dart';
import '../models/dashboard.dart';
import '../models/sheet_record.dart';
import '../widgets/offline_banner.dart';
import '../widgets/stats_widgets.dart';

class _OverviewTableColumn {
  const _OverviewTableColumn({
    required this.label,
    required this.isElastic,
    required this.valueAt,
  });

  final String label;
  final bool isElastic;
  final String Function(List<String> row, int rowIndex) valueAt;
}

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

  WarehouseStatsCache _warehouseStatsCache = WarehouseStatsCache.empty;
  num _totalAmountCache = 0;

  Dashboard get _warehouseDashboard => Dashboard(
        title: widget.dashboardTitle,
        fields: widget.dashboardFields,
        iconCode: Dashboard.defaultIconCode,
        colorValue: widget.dashboardColor.toARGB32(),
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
    _allData = [];
    _linkedIncomeRecords = [];
    _headers = [];
    _warehouseStatsCache = WarehouseStatsCache.empty;
    super.dispose();
  }

  /// [showLoader] — false для pull-to-refresh: стара таблиця лишається на
  /// екрані, поки триває мережевий запит (спінер показує сам RefreshIndicator).
  Future<void> _fetchData({bool showLoader = true}) async {
    if (showLoader) setState(() => _isLoading = true);

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

    final allData = SheetRecordsRepository.recordsToDisplayRows(result.data);

    setState(() {
      _isOffline = result.isOffline;
      _headers = headers;
      _records = result.data;
      _allData = allData;
      _warehouseStatsCache = warehouseStatsCache;
      _totalAmountCache = _computeTotalAmount(allData);
      _isLoading = false;
    });
  }

  /// Ручне оновлення (pull-to-refresh) — лише читання з хмари, без жодного
  /// впливу на запис даних: appendRecord/deleteRecord/updateRecord завжди
  /// пишуть у Google Sheets синхронно, до оновлення кешу. Немає відкладених
  /// "чернеток", які це оновлення могло би перезаписати чи загубити.
  Future<void> _handleRefresh() => _fetchData(showLoader: false);

  Future<void> _loadLinkedIncomeRecords() async {
    final linkedRecords = await loadLinkedIncomeRecords(
      user: widget.user,
      dashboardRepository: _dashboardRepository,
      recordsRepository: _recordsRepository,
    );

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

  num _computeTotalAmount(List<List<String>> rows) {
    num total = 0;
    for (final row in rows) {
      final amount = _amountForRow(row);
      if (amount != null) total += amount;
    }
    return total;
  }

  SheetRecord? _recordForTableIndex(int displayIndex) {
    if (_records.isEmpty) return null;
    final recordIndex = _records.length - 1 - displayIndex;
    if (recordIndex < 0 || recordIndex >= _records.length) return null;
    return _records[recordIndex];
  }

  WarehouseStats _statsForRecord(SheetRecord item) {
    return _warehouseStatsCache.statsFor(item) ??
        calculateWarehouseStatsIndexed(
          item: item,
          dashboard: _warehouseDashboard,
          salesIndex: _warehouseStatsCache.salesIndex,
        );
  }

  String _headerLabelAt(int columnIndex) {
    if (_headers.isNotEmpty && columnIndex < _headers.length) {
      return _headers[columnIndex];
    }
    return 'Колонка ${columnIndex + 1}';
  }

  bool _isElasticTextColumn(String header) {
    final normalized = header.toLowerCase();
    return normalized.contains('назв') ||
        normalized.contains('товар') ||
        normalized.contains('нотат') ||
        normalized.contains('note') ||
        normalized.contains('комент') ||
        normalized.contains('опис') ||
        normalized.contains('категор');
  }

  List<_OverviewTableColumn> _buildTableColumns() {
    final visibleIndexes = _visibleColumnIndexes();
    final columns = <_OverviewTableColumn>[];

    for (final columnIndex in visibleIndexes) {
      final header = _headerLabelAt(columnIndex);
      columns.add(
        _OverviewTableColumn(
          label: header,
          isElastic: _isElasticTextColumn(header),
          valueAt: (row, _) => columnIndex < row.length ? row[columnIndex] : '',
        ),
      );

      if (widget.isWarehouse && header == 'Кількість') {
        columns.add(
          _OverviewTableColumn(
            label: 'Залишок',
            isElastic: false,
            valueAt: (row, rowIndex) {
              final record = _recordForTableIndex(rowIndex);
              if (record == null) return '—';
              final remaining = _statsForRecord(record)['remaining'] ?? 0;
              return remaining.toString();
            },
          ),
        );
      }
    }

    return columns;
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
            Color.alphaBlend(Colors.black.withValues(alpha: 0.15), widget.dashboardColor),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: widget.dashboardColor.withValues(alpha: 0.35),
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
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${MoneyFormatter.formatNumber(_totalAmountCache)} ₴',
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
            color: Colors.white.withValues(alpha: 0.3),
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Записів',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
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

  Widget _buildWarehouseStats() {
    final totals = _warehouseStatsCache.totals;
    final spent = totals['spent'] ?? 0;
    final earned = totals['earned'] ?? 0;
    final profit = earned - spent;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.dashboardColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
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
                  child: WarehouseStatItem(
                    icon: Icons.inventory_2_rounded,
                    label: 'Залишок',
                    value: '${MoneyFormatter.formatNumber(totals['remaining'] ?? 0)} шт.',
                    color: widget.dashboardColor,
                  ),
                ),
                const WarehouseStatDivider(),
                Expanded(
                  child: WarehouseStatItem(
                    icon: Icons.trending_down_rounded,
                    label: 'Витрачено',
                    value: '${MoneyFormatter.formatNumber(spent)} ₴',
                    color: Colors.redAccent,
                  ),
                ),
                const WarehouseStatDivider(),
                Expanded(
                  child: WarehouseStatItem(
                    icon: Icons.trending_up_rounded,
                    label: 'Зароблено',
                    value: '${MoneyFormatter.formatNumber(earned)} ₴',
                    color: Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ),
          WarehouseProfitBar(profit: profit),
        ],
      ),
    );
  }

  static const double _cellHorizontalPadding = 16;
  static const double _compactColumnMinWidth = 56;
  static const double _compactColumnSafetyBuffer = 20;
  static const double _elasticColumnMinWidth = 160;
  static const int _elasticFullTextTapMinLength = 25;
  static const double _fullTextDialogMaxWidth = 480;

  List<int> _visibleColumnIndexes() {
    if (_headers.isNotEmpty) {
      return List.generate(_headers.length, (i) => i)
          .where((i) => !isHiddenUiField(_headers[i]))
          .toList();
    }

    final columnCount = _allData.fold<int>(
      0,
      (maxColumns, row) => row.length > maxColumns ? row.length : maxColumns,
    );
    return List.generate(columnCount, (i) => i);
  }

  double _measureTextWidth(String text, {bool bold = false}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text.isEmpty ? '—' : text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout();
    return painter.size.width;
  }

  Map<int, double> _computeFixedColumnWidths(List<_OverviewTableColumn> columns) {
    final widths = <int, double>{};

    for (var columnIndex = 0; columnIndex < columns.length; columnIndex++) {
      final column = columns[columnIndex];
      if (column.isElastic) continue;

      var maxContentWidth = _measureTextWidth(column.label, bold: true);
      for (var rowIndex = 0; rowIndex < _allData.length; rowIndex++) {
        final display = column.valueAt(_allData[rowIndex], rowIndex).trim();
        maxContentWidth = max(
          maxContentWidth,
          _measureTextWidth(display.isEmpty ? '—' : display),
        );
      }

      widths[columnIndex] = max(
        maxContentWidth + _cellHorizontalPadding + _compactColumnSafetyBuffer,
        _compactColumnMinWidth,
      );
    }

    return widths;
  }

  double _resolveTableWidth({
    required double viewportWidth,
    required List<_OverviewTableColumn> columns,
    required Map<int, double> fixedColumnWidths,
  }) {
    final fixedTotal = fixedColumnWidths.values.fold<double>(0, (sum, width) => sum + width);
    final elasticCount = columns.where((column) => column.isElastic).length;
    final elasticReserve = elasticCount > 0 ? _elasticColumnMinWidth : 0.0;
    return max(viewportWidth, fixedTotal + elasticReserve);
  }

  void _showFullTextPopup(String text) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _fullTextDialogMaxWidth),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              text,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableCell({
    required String text,
    required bool isHeader,
    required bool isElastic,
    double? fixedWidth,
  }) {
    final displayText = text.isEmpty ? '—' : text;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(
        alignment: isElastic ? Alignment.centerLeft : Alignment.center,
        child: Text(
          displayText,
          maxLines: isElastic ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          textAlign: isElastic ? TextAlign.left : TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );

    final isTappable = isElastic &&
        !isHeader &&
        text.trim().length > _elasticFullTextTapMinLength;

    final cellBody = isTappable
        ? GestureDetector(
            onTap: () => _showFullTextPopup(text.trim()),
            behavior: HitTestBehavior.opaque,
            child: content,
          )
        : content;

    if (isElastic) {
      return Expanded(child: cellBody);
    }

    return SizedBox(width: fixedWidth, child: cellBody);
  }

  Widget _buildTableHeaderRow(
    List<_OverviewTableColumn> columns,
    Map<int, double> fixedColumnWidths,
  ) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      color: widget.dashboardColor.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var columnIndex = 0; columnIndex < columns.length; columnIndex++)
            _buildTableCell(
              text: columns[columnIndex].label,
              isHeader: true,
              isElastic: columns[columnIndex].isElastic,
              fixedWidth: fixedColumnWidths[columnIndex],
            ),
        ],
      ),
    );
  }

  Widget _buildTableDataRow(
    List<String> row,
    int rowIndex,
    List<_OverviewTableColumn> columns,
    Map<int, double> fixedColumnWidths,
  ) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var columnIndex = 0; columnIndex < columns.length; columnIndex++)
            _buildTableCell(
              text: columns[columnIndex].valueAt(row, rowIndex).trim(),
              isHeader: false,
              isElastic: columns[columnIndex].isElastic,
              fixedWidth: fixedColumnWidths[columnIndex],
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyDataTable() {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: const Center(
              child: Text(
                'Записів ще немає',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    if (_allData.isEmpty) {
      return _buildEmptyDataTable();
    }

    final columns = _buildTableColumns();
    final fixedColumnWidths = _computeFixedColumnWidths(columns);

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
          Expanded(
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = _resolveTableWidth(
                    viewportWidth: constraints.maxWidth,
                    columns: columns,
                    fixedColumnWidths: fixedColumnWidths,
                  );

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      height: constraints.maxHeight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTableHeaderRow(columns, fixedColumnWidths),
                          Expanded(
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _allData.length,
                              scrollCacheExtent: const ScrollCacheExtent.pixels(500),
                              addAutomaticKeepAlives: false,
                              itemBuilder: (context, index) {
                                return RepaintBoundary(
                                  child: _buildTableDataRow(
                                    _allData[index],
                                    index,
                                    columns,
                                    fixedColumnWidths,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
        backgroundColor: widget.dashboardColor.withValues(alpha: 0.1),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: widget.dashboardColor))
          : Column(
              children: [
                if (_isOffline) const OfflineBanner(compact: true),
                if (widget.isWarehouse)
                  _buildWarehouseStats()
                else
                  _buildIncomeExpenseStats(),
                Expanded(
                  child: RefreshIndicator(
                    color: widget.dashboardColor,
                    onRefresh: _handleRefresh,
                    child: _buildDataTable(),
                  ),
                ),
              ],
            ),
    );
  }
}
