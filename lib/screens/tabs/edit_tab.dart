import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../services/sheets_api.dart';
import '../../services/prefs_service.dart';
import '../../widgets/module_edit_modal.dart';
import '../../widgets/record_edit_modal.dart';

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
  List<List<String>> _recentData = [];
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
    try {
      // Пробуємо завантажити свіжі дані
      final data = await SheetsApi.readSheetData(user: widget.user, sheetName: _title);
      
      if (data.isNotEmpty && mounted) {
        List<Map<String, dynamic>> rowsToCache = data.map((row) => {'row': row}).toList();
        await PrefsService.saveCustomDashboards('cache_rows_$_title', rowsToCache);

        setState(() {
          _headers = data.first;
          _recentData = data.length > 1 ? data.sublist(1).reversed.take(20).toList() : [];
        });
      }
    } catch (e) {
      final errorStr = e.toString();
      
      // ПЕРЕВІРКА: Це дійсно немає інтернету?
      if (errorStr.contains('SocketException') || errorStr.contains('Failed host lookup') || errorStr.contains('ClientException')) {
        print("Справжній офлайн в EditTab: $e");
        if (!mounted) return;
        setState(() => _isOffline = true);
        
        final cachedData = await PrefsService.getCustomDashboards('cache_rows_$_title');
        if (cachedData.isNotEmpty && mounted) {
          List<List<String>> parsedData = cachedData.map<List<String>>((item) {
            final dynamicList = item['row'] as List<dynamic>? ?? [];
            return dynamicList.map((e) => e.toString()).toList();
          }).toList();

          setState(() {
            _headers = parsedData.isNotEmpty ? parsedData.first : [];
            _recentData = parsedData.length > 1 ? parsedData.sublist(1).reversed.take(20).toList() : [];
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Офлайн: Показано записи з кешу'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)));
        } else if (mounted) {
          setState(() { _headers = []; _recentData = []; });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Немає інтернету. Ця вкладка ще не кешувалася.'), backgroundColor: Colors.redAccent));
        }
      } else {
        // ІНТЕРНЕТ Є! Просто таблиця ще порожня (не створена в Гуглі)
        print("Таблиця порожня: $e");
        if (!mounted) return;
        setState(() {
          _isOffline = false; // Примусово кажемо, що ми ОНЛАЙН
          _headers = [];
          _recentData = [];
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
     appBar: AppBar(
        title: Text('Мої фінанси', style: const TextStyle(fontWeight: FontWeight.bold)), // Або твоя назва
        backgroundColor: _color.withOpacity(0.1),
        actions: [
          // Якщо ми в офлайні — показуємо червону хмаринку
          if (_isOffline)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Icon(Icons.cloud_off, color: Colors.redAccent),
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _color))
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // --- СЕКЦІЯ 1: Редагування модуля ---
                const Text(
                  "Редагування модуля",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _color,
                      child: Icon(_icon, color: Colors.white),
                    ),
                    title: Text(_title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text("Змінити назву, колір, значок або додати поля"),
                    trailing: const Icon(Icons.settings_suggest, color: Colors.blueGrey),
                    onTap: () {
                      // ЗАХИСТ ВІД ОФЛАЙН РЕДАГУВАННЯ
                      if (_isOffline) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Редагування недоступне в офлайн режимі'), backgroundColor: Colors.redAccent)
                        );
                        return;
                      }

                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                        builder: (context) => ModuleEditModal(
                          initialDashboard: widget.dashboard,
                          onSave: (newName, newFields, newIcon, newColor) async {
                            final loaded = await PrefsService.getCustomDashboards('income_cache');
                            final index = loaded.indexWhere((d) => d['title'] == widget.dashboard['title']);
                            
                            if (index != -1) {
                              loaded[index]['title'] = newName; 
                              loaded[index]['fields'] = newFields;
                              loaded[index]['icon'] = newIcon;
                              loaded[index]['color'] = newColor;
                              
                              try {
                                await SheetsApi.saveAppConfig(user: widget.user, dashboards: loaded);
                                await PrefsService.saveCustomDashboards('income_cache', loaded); // Оновлюємо кеш!
                                
                                setState(() {
                                  _title = newName;
                                  _color = Color(newColor);
                                  _icon = IconData(newIcon, fontFamily: 'MaterialIcons');
                                });

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Налаштування збережено!'), backgroundColor: Colors.green));
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Помилка збереження.'), backgroundColor: Colors.redAccent));
                                }
                              }
                            }
                            
                            if (context.mounted) Navigator.pop(context);
                          },
                        ),
                      ); // <-- Ось тут була загублена дужка з крапкою з комою!
                    },
                  ),
                ),

                const SizedBox(height: 30),

                // --- СЕКЦІЯ 2: Останні записи ---
                const Text(
                  "Останні записи",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                
                if (_recentData.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: Text("Немає записів для відображення", style: TextStyle(color: Colors.grey))),
                  )
                else
                  ...List.generate(_recentData.length, (index) {
                    final row = _recentData[index];
                    final dateStr = row.isNotEmpty ? row[0] : 'Без дати';
                    final mainValue = row.length > 1 ? row[1] : '...'; 

                    List<String> extraFields = [];
                    for (int i = 2; i < row.length && i < 4; i++) { 
                      if (i < _headers.length) {
                        extraFields.add("${_headers[i]}: ${row[i]}");
                      }
                    }

                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: ListTile(
                          title: Text(mainValue, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (extraFields.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  extraFields.join(' • '), 
                                  style: const TextStyle(color: Colors.black87, fontSize: 14)
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Text(
                                    dateStr, 
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12)
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_note, color: Colors.blueGrey, size: 28),
                            onPressed: () {
                              // ЗАХИСТ ВІД ОФЛАЙН РЕДАГУВАННЯ
                              if (_isOffline) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Редагування записів недоступне без інтернету'), backgroundColor: Colors.redAccent)
                                );
                                return;
                              }
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                                builder: (context) => RecordEditModal(
                                  headers: _headers,
                                  rowData: row,
                                  onSave: (newValues) {
                                    print("Нові значення для таблиці: $newValues");
                                    Navigator.pop(context);
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}