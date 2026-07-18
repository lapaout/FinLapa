import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/ui_field_filter.dart';
import '../core/warehouse_analytics.dart';
import '../data/repositories/sheet_records_repository.dart';
import '../utils/ui_helpers.dart';
import 'record_edit_modal.dart';

class RecordsManager extends StatefulWidget {
  final GoogleSignInAccount user;
  final String sheetName;
  final Color color;
  final List<String> headers;
  final List<Map<String, dynamic>> records;
  final bool isOffline;
  final Function(int rowIndex, List<String> updatedRow) onRecordUpdated;
  final Function(int rowIndex)? onRecordDeleted;
  final bool hideDateFeatures;

  const RecordsManager({
    super.key,
    required this.user,
    required this.sheetName,
    required this.color,
    required this.headers,
    required this.records,
    required this.isOffline,
    required this.onRecordUpdated,
    this.onRecordDeleted,
    this.hideDateFeatures = false,
  });

  @override
  State<RecordsManager> createState() => _RecordsManagerState();
}

class _RecordsManagerState extends State<RecordsManager> {
  final SheetRecordsRepository _recordsRepository = SheetRecordsRepository();
  late final TextEditingController _searchController;

  String _searchQuery = '';
  bool _isUpdating = false;
  String _dateFilter = 'Всі';
  DateTimeRange? _customDateRange;
  final ValueNotifier<List<Map<String, dynamic>>> _filteredRecordsNotifier =
      ValueNotifier([]);
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredRecordsNotifier.value = _computeFilteredRecords();
  }

  @override
  void didUpdateWidget(covariant RecordsManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.records != widget.records) {
      _filteredRecordsNotifier.value = _computeFilteredRecords();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _filteredRecordsNotifier.dispose();
    super.dispose();
  }

  void _refreshFilteredRecords() {
    _filteredRecordsNotifier.value = _computeFilteredRecords();
  }

  void _onSearchChanged(String value) {
    _searchQuery = value.trim().toLowerCase();
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _refreshFilteredRecords();
    });
  }

  DateTime? _parseDateSafely(String dateStr) {
    DateTime? d = DateTime.tryParse(dateStr) ?? DateTime.tryParse('$dateStr:00');
    if (d != null) return d;

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

  bool _matchesDateFilter(List<String> rowData) {
    if (widget.hideDateFeatures || _dateFilter == 'Всі') return true;
    if (rowData.isEmpty) return false;

    final rowDate = _parseDateSafely(rowData[0]);
    if (rowDate == null) return false;

    final now = DateTime.now();
    if (_dateFilter == 'Сьогодні') {
      return rowDate.year == now.year &&
          rowDate.month == now.month &&
          rowDate.day == now.day;
    } else if (_dateFilter == 'Місяць') {
      return rowDate.year == now.year && rowDate.month == now.month;
    } else if (_dateFilter == 'Період' && _customDateRange != null) {
      final start = _customDateRange!.start.subtract(const Duration(seconds: 1));
      final end = _customDateRange!.end.add(const Duration(days: 1));
      return rowDate.isAfter(start) && rowDate.isBefore(end);
    }
    return true;
  }

  List<Map<String, dynamic>> _computeFilteredRecords() {
    if (_searchQuery.isEmpty && (widget.hideDateFeatures || _dateFilter == 'Всі')) {
      return List<Map<String, dynamic>>.from(widget.records);
    }

    return widget.records.where((item) {
      final rowData = item['row'] as List<String>;

      if (_searchQuery.isNotEmpty) {
        final combinedText = rowData.join(' ').toLowerCase();
        if (!combinedText.contains(_searchQuery)) return false;
      }

      return _matchesDateFilter(rowData);
    }).toList();
  }

  void _openEditModal(
    BuildContext context,
    Map<String, dynamic> item,
    int rowIndex,
    List<String> row,
  ) {
    if (widget.isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Редагування недоступне в офлайн режимі'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    showFinLapaBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => RecordEditModal(
        headers: widget.headers,
        rowData: row,
        onSave: (newValues) async {
          Navigator.pop(context);
          setState(() => _isUpdating = true);

          try {
            await _recordsRepository.updateRecord(
              user: widget.user,
              sheetTitle: widget.sheetName,
              rowIndex: rowIndex,
              values: newValues,
            );

            setState(() {
              item['row'] = newValues;
            });

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Запис оновлено!'),
                  backgroundColor: Colors.green,
                ),
              );
            }

            widget.onRecordUpdated(rowIndex, newValues);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Помилка: $e'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
          } finally {
            if (mounted) setState(() => _isUpdating = false);
          }
        },
        onDelete: () async {
          setState(() => _isUpdating = true);
          try {
            await _recordsRepository.deleteRecord(
              user: widget.user,
              sheetTitle: widget.sheetName,
              rowIndex: rowIndex,
            );

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Запис видалено'),
                  backgroundColor: Colors.green,
                ),
              );
            }

            widget.onRecordDeleted?.call(rowIndex);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('❌ Помилка: $e'),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
            rethrow;
          } finally {
            if (mounted) setState(() => _isUpdating = false);
          }
        },
      ),
    );
  }

  Future<void> _confirmAndDelete(
    BuildContext context,
    int rowIndex,
  ) async {
    if (widget.isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Видалення недоступне в офлайн режимі'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Видалити запис?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Видалити', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    if (!mounted) return;
    setState(() => _isUpdating = true);
    try {
      await _recordsRepository.deleteRecord(
        user: widget.user,
        sheetTitle: widget.sheetName,
        rowIndex: rowIndex,
      );

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('✅ Запис видалено'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onRecordDeleted?.call(rowIndex);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('❌ Помилка: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _selectCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: ColorScheme.light(primary: widget.color),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _dateFilter = 'Період';
        _customDateRange = picked;
      });
      _refreshFilteredRecords();
    }
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _dateFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: widget.color,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 13),
      side: BorderSide(color: widget.color.withValues(alpha: 0.4)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      onSelected: (bool selected) {
        if (selected) {
          setState(() {
            _dateFilter = label;
            _customDateRange = null;
          });
          _refreshFilteredRecords();
        }
      },
    );
  }

  Widget _buildRecordTile(Map<String, dynamic> item) {
    final rowIndex = item['rowIndex'] as int;
    final row = item['row'] as List<String>;

    final fieldWidgets = <Widget>[];
    final headerIndexes = widget.hideDateFeatures
        ? List.generate(widget.headers.length - 1, (i) => i + 1)
        : [1, 2, 3].where((i) => i < widget.headers.length).toList();

    for (final i in headerIndexes) {
      if (i < widget.headers.length && i < row.length) {
        final headerName = widget.headers[i];
        if (isHiddenUiField(headerName)) continue;
        if (isWarehouseLinkedDisplayField(headerName)) continue;

        String value = row[i];
        final headerLower = headerName.toLowerCase();

        final isMoney = headerLower.contains('сум') ||
            headerLower.contains('цін') ||
            headerLower.contains('варт');

        if (isMoney && value.isNotEmpty && value != '-') {
          value = '$value ₴';
        }

        fieldWidgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    '$headerName:',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: i == 1 || isMoney ? FontWeight.bold : FontWeight.w600,
                      fontSize: i == 1 || isMoney ? 16 : 15,
                      color: isMoney ? Colors.green.shade700 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return RepaintBoundary(
      child: Card(
        key: ValueKey('${rowIndex}_${row.join('_')}'),
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openEditModal(context, item, rowIndex, row),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWarehouseSaleInfo(row),
                      ...fieldWidgets,
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmAndDelete(context, rowIndex),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWarehouseSaleInfo(List<String> row) {
    final warehouseItemRaw = fieldValueFromRow(
      widget.headers,
      row,
      'Товар зі складу',
      '_warehouseItemName',
    );
    final soldQty = fieldValueFromRow(
      widget.headers,
      row,
      'Продано (шт)',
      '_soldQuantity',
    );
    final warehouseTitle = warehouseTitleFromItemField(warehouseItemRaw);
    final productName = productNameFromItemField(warehouseItemRaw);

    if (warehouseTitle == null || warehouseTitle.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Склад: $warehouseTitle',
            style: TextStyle(
              color: Colors.teal.shade700,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          if (productName != null && productName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Товар: $productName',
              style: TextStyle(
                color: Colors.teal.shade600,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
          if (soldQty != null && soldQty.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Продано: $soldQty шт.',
              style: TextStyle(
                color: Colors.teal.shade600,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.hideDateFeatures)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                _buildFilterChip('Всі'),
                const SizedBox(width: 6),
                _buildFilterChip('Сьогодні'),
                const SizedBox(width: 6),
                _buildFilterChip('Місяць'),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: Icon(
                    Icons.calendar_month,
                    size: 16,
                    color: _dateFilter == 'Період' ? Colors.white : widget.color,
                  ),
                  label: Text(
                    _customDateRange == null
                        ? 'Період'
                        : '${_customDateRange!.start.day}.${_customDateRange!.start.month} - '
                            '${_customDateRange!.end.day}.${_customDateRange!.end.month}',
                  ),
                  backgroundColor: _dateFilter == 'Період' ? widget.color : Colors.white,
                  labelStyle: TextStyle(
                    color: _dateFilter == 'Період' ? Colors.white : Colors.black87,
                    fontSize: 13,
                  ),
                  side: BorderSide(color: widget.color.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  onPressed: _selectCustomDateRange,
                ),
              ],
            ),
          ),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Пошук серед відфільтрованого...',
            prefixIcon: Icon(Icons.search, color: widget.color),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.color, width: 2),
            ),
          ),
          onChanged: _onSearchChanged,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Column(
            children: [
              if (_isUpdating)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(
                    child: CircularProgressIndicator(color: widget.color),
                  ),
                ),
              Expanded(
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: _filteredRecordsNotifier,
                  builder: (context, filteredRecords, _) {
                    if (filteredRecords.isEmpty) {
                      return const Center(
                        child: Text(
                          'Записів не знайдено за цими критеріями',
                          style: TextStyle(color: Colors.grey, fontSize: 15),
                        ),
                      );
                    }

                    return ListView.builder(
                      itemCount: filteredRecords.length,
                      scrollCacheExtent: const ScrollCacheExtent.pixels(500),
                      addAutomaticKeepAlives: false,
                      itemBuilder: (context, index) {
                        return _buildRecordTile(filteredRecords[index]);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
