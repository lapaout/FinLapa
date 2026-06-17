import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../services/sheets_api.dart';
import '../../services/prefs_service.dart';
import '../../widgets/module_edit_modal.dart';
import '../../widgets/records_manager.dart'; // Наш новий модуль!

class EditTab extends StatefulWidget {
  final GoogleSignInAccount user;
  final Map<String, dynamic> dashboard;

  const EditTab({
    super.key,
    required this.user,
    required this.dashboard,
  });

  @override
  State<EditTab> createState() => _EditTabState();
}

class _EditTabState extends State<EditTab> {
  bool _isLoading = true;
  bool _isOffline = false;
  List<Map<String, dynamic>> _recentRecords = []; // Тепер зберігаємо з номерами рядків
  List<String> _headers = [];

  late String _title;
  late Color _color;
  late IconData _icon;

  @override
  void initState() {
    super.initState();
    _title = widget.dashboard['title'] ?? 'Без назви';
    _color = Color(widget.dashboard['color'] ?? Colors.green.value);
    _icon = IconData(widget.dashboard['icon'] ?? Icons.dashboard.codePoint, fontFamily: 'MaterialIcons');
    
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final data = await SheetsApi.readSheetData(user: widget.user, sheetName: _title);
      
      if (data.isNotEmpty && mounted) {
        // Зберігаємо в кеш для офлайну
        List<Map<String, dynamic>> rowsToCache = data.map((row) => {'row': row}).toList();
        await PrefsService.saveCustomDashboards('cache_rows_$_title', rowsToCache);

        _parseDataWithIndexes(data);
        setState(() => _isOffline = false);
      }
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('SocketException') || errorStr.contains('Failed host lookup')) {
        if (!mounted) return;
        setState(() => _isOffline = true);
        
        final cachedData = await PrefsService.getCustomDashboards('cache_rows_$_title');
        if (cachedData.isNotEmpty && mounted) {
          List<List<String>> parsedData = cachedData.map<List<String>>((item) {
            final dynamicList = item['row'] as List<dynamic>? ?? [];
            return dynamicList.map((e) => e.toString()).toList();
          }).toList();

          _parseDataWithIndexes(parsedData);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Офлайн: Показано записи з кешу'), backgroundColor: Colors.orange));
        } else if (mounted) {
          setState(() { _headers = []; _recentRecords = []; });
        }
      } else {
        if (!mounted) return;
        setState(() { _isOffline = false; _headers = []; _recentRecords = []; });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Призначаємо кожному запису номер рядка (Рядок 1 - це заголовки, дані починаються з 2)
  void _parseDataWithIndexes(List<List<String>> data) {
    if (data.isEmpty) return;
    _headers = data.first;
    
    List<Map<String, dynamic>> recordsWithIndex = [];
    for (int i = 1; i < data.length; i++) {
      recordsWithIndex.add({
        'rowIndex': i + 1, // i=1 -> рядок 2 в Екселі
        'row': data[i],
      });
    }
    
    // Перевертаємо, щоб нові були зверху
    setState(() {
      _recentRecords = recordsWithIndex.reversed.toList();
    });
  }

  // Ця функція миттєво замінює текст на екрані і в кеші
  void _updateLocalRecord(int rowIndex, List<String> updatedRow) async {
    setState(() {
      final index = _recentRecords.indexWhere((r) => r['rowIndex'] == rowIndex);
      if (index != -1) {
        _recentRecords[index]['row'] = updatedRow;
      }
    });

    // Оновлюємо локальний кеш, щоб при наступному вході без інтернету була актуальна інфа
    final cachedData = await PrefsService.getCustomDashboards('cache_rows_$_title');
    if (cachedData.isNotEmpty) {
      // Шукаємо в кеші запис із такою ж датою і оновлюємо його
      final cacheIndex = cachedData.indexWhere((item) {
         final rowList = item['row'] as List<dynamic>? ?? [];
         return rowList.isNotEmpty && rowList[0].toString() == updatedRow[0];
      });
      if (cacheIndex != -1) {
        cachedData[cacheIndex]['row'] = updatedRow;
        await PrefsService.saveCustomDashboards('cache_rows_$_title', cachedData);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Редагування: $_title', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: _color.withOpacity(0.1),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _color))
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                if (_isOffline)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    color: Colors.redAccent.withOpacity(0.1),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off, color: Colors.redAccent, size: 20),
                        SizedBox(width: 8),
                        Text("Офлайн режим (тільки читання)", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),

                // --- СЕКЦІЯ 1: Редагування модуля ---
                const Text("Налаштування модуля", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 10),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: _color, child: Icon(_icon, color: Colors.white)),
                    title: Text(_title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("Змінити назву, колір, значок або поля"),
                    trailing: const Icon(Icons.settings_suggest, color: Colors.blueGrey),
                    onTap: () {
                      if (_isOffline) return;
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (context) => ModuleEditModal(
                          initialDashboard: widget.dashboard,
                          onSave: (newName, newFields, newIcon, newColor) async {
                            final oldName = widget.dashboard['title']; 
                            final loaded = await PrefsService.getCustomDashboards('income_cache');
                            final index = loaded.indexWhere((d) => d['title'] == oldName);
                            
                            if (index != -1) {
                              loaded[index]['title'] = newName; 
                              loaded[index]['fields'] = newFields;
                              loaded[index]['icon'] = newIcon;
                              loaded[index]['color'] = newColor;
                              
                              try {
                                await SheetsApi.renameSheet(user: widget.user, oldTitle: oldName, newTitle: newName);
                                await SheetsApi.saveAppConfig(user: widget.user, dashboards: loaded);
                                await PrefsService.saveCustomDashboards('income_cache', loaded); 
                                
                                setState(() {
                                  _title = newName;
                                  _color = Color(newColor);
                                  _icon = IconData(newIcon, fontFamily: 'MaterialIcons');
                                });
                              } catch (e) {
                                print(e);
                              }
                            }
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 30),

                // --- СЕКЦІЯ 2: НАШ НОВИЙ МОДУЛЬ ПОШУКУ ТА РЕДАГУВАННЯ ЗАПИСІВ ---
                const Text("База записів", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 10),
                
                RecordsManager(
                  user: widget.user,
                  sheetName: _title,
                  color: _color,
                  headers: _headers,
                  records: _recentRecords,
                  isOffline: _isOffline,
                  onRecordUpdated: _updateLocalRecord, // <--- ЗМІНИТИ ЦЕЙ РЯДОК
                ),
              ],
            ),
    );
  }
}