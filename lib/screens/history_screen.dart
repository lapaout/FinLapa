import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/sheets_api.dart';

class HistoryScreen extends StatefulWidget {
  final GoogleSignInAccount user;
  final String dashboardTitle;
  final Color dashboardColor;

  const HistoryScreen({
    super.key, 
    required this.user, 
    required this.dashboardTitle,
    required this.dashboardColor,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  bool _isLoading = true;
  List<List<String>> _allData = [];
  List<List<String>> _filteredData = [];
  List<String> _headers = [];
  
  String _currentFilter = 'Всі';
  DateTimeRange? _customDateRange;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final data = await SheetsApi.readSheetData(user: widget.user, sheetName: widget.dashboardTitle);
      if (data.isNotEmpty) {
        _headers = data.first; // Перший рядок - це заголовки
        _allData = data.sublist(1).reversed.toList(); // Інші рядки - дані (перевертаємо, щоб нові були зверху)
        _filteredData = List.from(_allData);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Помилка: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Логіка фільтрації за датами
  void _applyFilter(String filter) {
    setState(() {
      _currentFilter = filter;
      _customDateRange = null; // Скидаємо кастомний період
      
      if (filter == 'Всі') {
        _filteredData = List.from(_allData);
        return;
      }

      final now = DateTime.now();
      _filteredData = _allData.where((row) {
        if (row.isEmpty) return false;
        // Наша дата завжди в першій колонці (формат: 2026-06-17 12:13)
        final dateStr = row[0]; 
        // Додаємо :00 щоб парсер точно зрозумів формат
        final rowDate = DateTime.tryParse("$dateStr:00"); 
        if (rowDate == null) return false;

        if (filter == 'Сьогодні') {
          return rowDate.year == now.year && rowDate.month == now.month && rowDate.day == now.day;
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
        data: ThemeData.light().copyWith(colorScheme: ColorScheme.light(primary: widget.dashboardColor)),
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
          // Перевіряємо, чи входить дата в обраний діапазон
          return rowDate.isAfter(picked.start.subtract(const Duration(days: 1))) && 
                 rowDate.isBefore(picked.end.add(const Duration(days: 1)));
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Історія: ${widget.dashboardTitle}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: widget.dashboardColor.withOpacity(0.1),
      ),
      body: Column(
        children: [
          // ПАНЕЛЬ ФІЛЬТРІВ
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
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
                    avatar: Icon(Icons.calendar_month, size: 18, color: _currentFilter == 'Період' ? Colors.white : widget.dashboardColor),
                    label: Text(_customDateRange == null ? 'Період' : '${_customDateRange!.start.day}.${_customDateRange!.start.month} - ${_customDateRange!.end.day}.${_customDateRange!.end.month}'),
                    backgroundColor: _currentFilter == 'Період' ? widget.dashboardColor : Colors.white,
                    labelStyle: TextStyle(color: _currentFilter == 'Період' ? Colors.white : Colors.black87),
                    side: BorderSide(color: widget.dashboardColor.withOpacity(0.5)),
                    onPressed: _selectCustomDateRange,
                  )
                ],
              ),
            ),
          ),

          // СПИСОК ЗАПИСІВ
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: widget.dashboardColor))
                : _allData.isEmpty
                    ? const Center(child: Text("Записів ще немає", style: TextStyle(color: Colors.grey, fontSize: 16)))
                    : _filteredData.isEmpty
                        ? const Center(child: Text("За обраний період записів не знайдено", style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredData.length,
                            itemBuilder: (context, index) {
                              final row = _filteredData[index];
                              return Card(
                                elevation: 1,
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Дата завжди перша
                                      Row(
                                        children: [
                                          Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                                          const SizedBox(width: 6),
                                          Text(row.isNotEmpty ? row[0] : 'Без дати', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                      const Divider(),
                                      // Виводимо всі інші поля, які користувач створив у конструкторі
                                      ...List.generate(_headers.length - 1, (i) {
                                        // +1 бо перша колонка це дата
                                        final colIndex = i + 1;
                                        final header = _headers[colIndex];
                                        final value = colIndex < row.length ? row[colIndex] : '-'; // Захист, якщо клітинка в таблиці порожня
                                        
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 4),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(flex: 2, child: Text("$header:", style: const TextStyle(color: Colors.black54, fontSize: 14))),
                                              Expanded(flex: 3, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                                            ],
                                          ),
                                        );
                                      })
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
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