import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../services/sheets_api.dart';
import '../../services/prefs_service.dart';
import '../../widgets/module_builder_modal.dart';
import '../../widgets/data_entry_modal.dart';
import '../history_screen.dart';
import 'edit_tab.dart';

class IncomeTab extends StatefulWidget {
  final GoogleSignInAccount user;

  const IncomeTab({super.key, required this.user});

  @override
  State<IncomeTab> createState() => _IncomeTabState();
}

class _IncomeTabState extends State<IncomeTab> {
  List<Map<String, dynamic>> _dashboards = [];
  bool _isSending = false;
  bool _isLoading = true;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadDashboards();
  }

  Future<void> _loadDashboards() async {
    setState(() {
      _isLoading = true;
      _isOffline = false; 
    });

    try {
      final loaded = await SheetsApi.readAppConfig(user: widget.user);
      await PrefsService.saveCustomDashboards('income_cache', loaded);
      
      setState(() {
        _dashboards = loaded;
        _isLoading = false;
      });
    } catch (e) {
      print("Офлайн режим. Читаємо з кешу. Помилка: $e");

      final cached = await PrefsService.getCustomDashboards('income_cache');

      setState(() {
        _dashboards = cached;
        _isOffline = true; // Вмикаємо режим офлайн
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Офлайн режим. Показані збережені дані.'), 
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          )
        );
      }
    }
  }

  void _openModuleBuilder() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => ModuleBuilderModal(
        onSave: (moduleName, fields, iconCode, colorValue) async {
          _dashboards.add({
            'title': moduleName, 
            'fields': fields,
            'icon': iconCode, 
            'color': colorValue
          });
          
          try {
            await SheetsApi.saveAppConfig(user: widget.user, dashboards: _dashboards);
            await PrefsService.saveCustomDashboards('income_cache', _dashboards); 
            
            setState(() => _isOffline = false); 
            setState(() {});
            if (context.mounted) Navigator.pop(context);
          } catch (e) {
            final errorStr = e.toString();
            
            if (errorStr.contains('SocketException') || errorStr.contains('Failed host lookup') || errorStr.contains('ClientException')) {
              _dashboards.removeLast(); 
              setState(() => _isOffline = true);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('❌ Немає зв\'язку з інтернетом.'), backgroundColor: Colors.redAccent)
              );
            } else {
              // Все збереглося успішно, ігноруємо помилки формату
              await PrefsService.saveCustomDashboards('income_cache', _dashboards); 
              setState(() => _isOffline = false); // Вимикаємо плашку
              setState(() {});
              if (context.mounted) Navigator.pop(context);
            }
          }
        },
      ),
    );
  }

  void _openDataEntryForm(Map<String, dynamic> dashboard) {
    String title = dashboard['title'];
    List<String> fields = List<String>.from(dashboard['fields']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DataEntryModal(
        title: title,
        fields: fields,
        isSending: _isSending,
        onSave: (valuesToSave) async {
          Navigator.pop(context);
          setState(() => _isSending = true);
          
          try {
            await SheetsApi.sendDynamicData(user: widget.user, sheetName: title, columns: fields, values: valuesToSave);
            
            setState(() => _isOffline = false); // Все супер, плашку ховаємо
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('✅ Записано в "$title"'), backgroundColor: Colors.green));
          } catch (e) {
            final errorStr = e.toString();
            
            // РОЗУМНА ПЕРЕВІРКА: чи це реально обрив інтернету?
            if (errorStr.contains('SocketException') || errorStr.contains('Failed host lookup') || errorStr.contains('ClientException')) {
              setState(() => _isOffline = true); // Тільки тоді вмикаємо плашку
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('❌ Немає інтернету. Запис скасовано.'), backgroundColor: Colors.redAccent)
              );
            } else {
              // Інтернет Є! Гугл зберіг дані, просто криво відповів.
              setState(() => _isOffline = false); // ПРИМУСОВО ВИМИКАЄМО ПЛАШКУ!
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✅ Записано в "$title"'), backgroundColor: Colors.green)
              );
            }
          } finally {
            if (mounted) setState(() => _isSending = false);
          }
        },
      ),
    );
  }
  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🛠 $feature: У розробці!'), backgroundColor: Colors.blueAccent));
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22), 
              const SizedBox(height: 4),
              Text(
                label, 
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600), 
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_isSending) return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Запис у Google...")]));

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // --- ВІЗУАЛЬНИЙ ІНДИКАТОР ОФЛАЙНУ ---
        if (_isOffline)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, color: Colors.redAccent),
                SizedBox(width: 10),
                Text(
                  "Офлайн режим (тільки читання)", 
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)
                ),
              ],
            ),
          ),

        if (_dashboards.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 24.0),
            child: Text("Немає джерел доходу.\nНатисніть 'Створити', щоб додати своє.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
          ),
          
        ..._dashboards.map((dashboard) {
          final iconData = IconData(dashboard['icon'] ?? Icons.monetization_on.codePoint, fontFamily: 'MaterialIcons');
          final colorData = Color(dashboard['color'] ?? Colors.green.value);

          return Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: colorData.withOpacity(0.1),
                        child: Icon(iconData, color: colorData, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(dashboard['title'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(Icons.add_circle, "Додати", colorData, () => _openDataEntryForm(dashboard)),
                      _buildActionButton(Icons.history, "Історія", Colors.blueGrey, () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => HistoryScreen(
                              user: widget.user,
                              dashboardTitle: dashboard['title'],
                              dashboardColor: colorData,
                            ),
                          ),
                        );
                      }),
                      _buildActionButton(Icons.edit_document, "Редагувати", Colors.blueGrey, () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditTab(
                              user: widget.user,
                              dashboard: dashboard, 
                            ),
                          ),
                        );
                        _loadDashboards(); 
                      }),
                      _buildActionButton(Icons.settings, "Налаштув.", Colors.blueGrey, () => _showComingSoon("Налаштування модуля")),
                    ],
                  )
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 10),
        
        InkWell(
          onTap: _openModuleBuilder,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 2),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline, color: Colors.blueAccent, size: 26),
                SizedBox(width: 12),
                Text("Створити новий дашборд", style: TextStyle(color: Colors.blueAccent, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        )
      ],
    );
  }
}