import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../data/repositories/sheet_records_repository.dart';
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

  String _searchQuery = '';
  bool _isUpdating = false;
  
  // Нові змінні для розумної фільтрації за датами
  String _dateFilter = 'Всі';
  DateTimeRange? _customDateRange;
// РОЗУМНИЙ ПАРСЕР ДАТ (Захист від ручного редагування в Екселі)
  DateTime? _parseDateSafely(String dateStr) {
    // 1. Спочатку пробуємо наш стандартний машинний формат (2026-06-18 12:30)
    DateTime? d = DateTime.tryParse(dateStr) ?? DateTime.tryParse("$dateStr:00");
    if (d != null) return d;

    // 2. Якщо ти відредагував дату руками в Google Sheets (наприклад: 14.06.2026)
    try {
      final cleanDate = dateStr.split(' ')[0]; // Відрізаємо час, якщо він є
      final parts = cleanDate.split(RegExp(r'[\.\-\/]')); // Ділимо по крапках або рисках
      if (parts.length >= 3) {
        int day = int.parse(parts[0]);
        int month = int.parse(parts[1]);
        int year = int.parse(parts[2]);
        if (year < 100) year += 2000; // Якщо раптом ввів 14.06.26
        
        return DateTime(year, month, day);
      }
    } catch (e) {
      // Якщо в комірці взагалі написана якась нісенітниця, ігноруємо
    }
    
    return null; // Якщо дату неможливо розпізнати
  }
  // Метод для відкриття календаря (вибір кастомного періоду)
  Future<void> _selectCustomDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(colorScheme: ColorScheme.light(primary: widget.color)),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        _dateFilter = 'Період';
        _customDateRange = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // КОМБІНОВАНИЙ РОЗУМНИЙ ФІЛЬТР (Пошук + Календар)
    // КОМБІНОВАНИЙ РОЗУМНИЙ ФІЛЬТР (Пошук + Календар)
    final filteredRecords = widget.records.where((item) {
      final rowData = item['row'] as List<String>;
      
      // 1. Фільтрація за текстом у пошуку
      final combinedText = rowData.join(' ').toLowerCase();
      final matchesText = combinedText.contains(_searchQuery.toLowerCase());
      if (!matchesText) return false;

      // 2. Фільтрація за обраною датою
      if (widget.hideDateFeatures || _dateFilter == 'Всі') return true;
      if (rowData.isEmpty) return false;

      final dateStr = rowData[0]; 
      
      // ВИКОРИСТОВУЄМО НАШ НОВИЙ БРОНЕЖИЛЕТ ДЛЯ ДАТ
      final rowDate = _parseDateSafely(dateStr); 
      if (rowDate == null) return false;

      final now = DateTime.now();
      if (_dateFilter == 'Сьогодні') {
        return rowDate.year == now.year && rowDate.month == now.month && rowDate.day == now.day;
      } else if (_dateFilter == 'Місяць') {
        return rowDate.year == now.year && rowDate.month == now.month;
      } else if (_dateFilter == 'Період' && _customDateRange != null) {
        
        // ВИПРАВЛЕНИЙ БАГ ДІАПАЗОНУ (18 по 18)
        final start = _customDateRange!.start.subtract(const Duration(seconds: 1)); // Починаємо з 23:59:59 попереднього дня
        final end = _customDateRange!.end.add(const Duration(days: 1)); // Захоплюємо весь останній день до 00:00 наступного
        
        return rowDate.isAfter(start) && rowDate.isBefore(end);
      }
      return true;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- ПАНЕЛЬ КЛІК КЛУБІВ (ФІЛЬТРИ ДАТ) ---
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
                  avatar: Icon(Icons.calendar_month, size: 16, color: _dateFilter == 'Період' ? Colors.white : widget.color),
                  label: Text(_customDateRange == null ? 'Період' : '${_customDateRange!.start.day}.${_customDateRange!.start.month} - ${_customDateRange!.end.day}.${_customDateRange!.end.month}'),
                  backgroundColor: _dateFilter == 'Період' ? widget.color : Colors.white,
                  labelStyle: TextStyle(color: _dateFilter == 'Період' ? Colors.white : Colors.black87, fontSize: 13),
                  side: BorderSide(color: widget.color.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  onPressed: _selectCustomDateRange,
                ),
              ],
            ),
          ),

        // --- ПОЛЕ ПОШУКУ ---
        TextField(
          decoration: InputDecoration(
            hintText: 'Пошук серед відфільтрованого...',
            prefixIcon: Icon(Icons.search, color: widget.color),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: widget.color, width: 2)),
          ),
          onChanged: (val) => setState(() => _searchQuery = val),
        ),
        const SizedBox(height: 16),

        if (_isUpdating)
          Center(child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircularProgressIndicator(color: widget.color),
          )),

        // --- СПИСОК ЗАПИСІВ ---
        if (filteredRecords.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24.0),
            child: Center(child: Text("Записів не знайдено за цими критеріями", style: TextStyle(color: Colors.grey, fontSize: 15))),
          )
        else
          ...filteredRecords.map((item) {
            final rowIndex = item['rowIndex'] as int;
            final row = item['row'] as List<String>;
            final dateStr = row.isNotEmpty ? row[0] : 'Без дати';

            List<Widget> fieldWidgets = [];
            final headerIndexes = widget.hideDateFeatures
                ? List.generate(widget.headers.length - 1, (i) => i + 1)
                : [1, 2, 3].where((i) => i < widget.headers.length).toList();

            for (final i in headerIndexes) {
              if (i < widget.headers.length && i < row.length) {
                final headerName = widget.headers[i];
                if (headerName.startsWith('_')) continue;

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
                        Expanded(flex: 2, child: Text("$headerName:", style: const TextStyle(color: Colors.black54, fontSize: 14, fontWeight: FontWeight.w500))),
                        Expanded(
                          flex: 3,
                          child: Text(
                            value,
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

            return Card(
              key: ValueKey('${rowIndex}_${row.join('_')}'),
              elevation: 1,
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...fieldWidgets,
                          if (!widget.hideDateFeatures) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                                const SizedBox(width: 4),
                                Text(dateStr, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_note, color: Colors.blueGrey, size: 28),
                      onPressed: () {
                        if (widget.isOffline) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Редагування недоступне в офлайн режимі'), backgroundColor: Colors.redAccent));
                          return;
                        }

                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✅ Запис оновлено!'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }

                                widget.onRecordUpdated(rowIndex, newValues);
                              } catch (e) {
                                if (mounted) {
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

                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✅ Запис видалено'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }

                                widget.onRecordDeleted?.call(rowIndex);
                              } catch (e) {
                                if (mounted) {
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
                      },
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _dateFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: widget.color,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontSize: 13),
      side: BorderSide(color: widget.color.withOpacity(0.4)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      onSelected: (bool selected) {
        if (selected) {
          setState(() {
            _dateFilter = label;
            _customDateRange = null; // Скидаємо кастомні дати, якщо обрали швидкий фільтр
          });
        }
      },
    );
  }
}