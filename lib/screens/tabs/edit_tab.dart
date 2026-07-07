import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/network_exception.dart';
import '../../data/repositories/dashboard_repository.dart';
import '../../data/repositories/sheet_records_repository.dart';
import '../../models/dashboard.dart';
import '../../models/sheet_data.dart';
import '../../widgets/module_edit_modal.dart';
import '../../widgets/records_manager.dart';

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
  final SheetRecordsRepository _recordsRepository = SheetRecordsRepository();
  final DashboardRepository _dashboardRepository = DashboardRepository();

  bool _isLoading = true;
  bool _isOffline = false;
  List<Map<String, dynamic>> _recentRecords = [];
  List<String> _headers = [];

  late String _title;
  late Color _color;
  late IconData _icon;
  late bool _isWarehouse;

  @override
  void initState() {
    super.initState();
    final dashboard = Dashboard.fromMap(widget.dashboard);
    _isWarehouse = dashboard.type == Dashboard.typeWarehouse;
    _title = widget.dashboard['title'] ?? 'Без назви';
    _color = Color(widget.dashboard['color'] ?? Colors.green.value);
    _icon = IconData(
      widget.dashboard['icon'] ?? Icons.dashboard.codePoint,
      fontFamily: 'MaterialIcons',
    );

    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);

    final result = await _recordsRepository.getRecords(
      user: widget.user,
      sheetTitle: _title,
    );

    if (!mounted) return;

    final headers = await _recordsRepository.getSheetHeaders(_title);
    final sheetData = SheetData(
      headers: headers,
      records: result.data,
    );

    setState(() {
      _isOffline = result.isOffline;
      _headers = headers;
      _recentRecords = SheetRecordsRepository.recordsToUiMaps(sheetData);
      _isLoading = false;
    });

    if (result.isOffline && _recentRecords.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Офлайн: Показано записи з кешу'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _updateLocalRecord(int rowIndex, List<String> updatedRow) {
    setState(() {
      final index = _recentRecords.indexWhere((r) => r['rowIndex'] == rowIndex);
      if (index != -1) {
        _recentRecords[index]['row'] = updatedRow;
      }
    });
  }

  Future<void> _saveDashboardConfig({
    required String oldName,
    required String newName,
    required List<String> newFields,
    required int newIcon,
    required int newColor,
  }) async {
    final current = Dashboard.fromMap(widget.dashboard);
    final updatedDashboard = current.copyWith(
      title: newName,
      fields: newFields,
      iconCode: newIcon,
      colorValue: newColor,
    );

    await _dashboardRepository.renameDashboard(
      user: widget.user,
      oldTitle: oldName,
      updatedDashboard: updatedDashboard,
    );

    setState(() {
      _title = newName;
      _color = Color(newColor);
      _icon = IconData(newIcon, fontFamily: 'MaterialIcons');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Редагування: $_title',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: _color.withOpacity(0.1),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _color))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isOffline)
                  Container(
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Налаштування модуля',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _color,
                            child: Icon(_icon, color: Colors.white),
                          ),
                          title: Text(
                            _title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text('Змінити назву, колір, значок або поля'),
                          trailing: const Icon(Icons.settings_suggest, color: Colors.blueGrey),
                          onTap: () {
                            if (_isOffline) return;
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                              ),
                              builder: (context) => ModuleEditModal(
                                initialDashboard: widget.dashboard,
                                onSave: (newName, newFields, newIcon, newColor) async {
                                  final oldName = widget.dashboard['title'];

                                  try {
                                    await _saveDashboardConfig(
                                      oldName: oldName,
                                      newName: newName,
                                      newFields: newFields,
                                      newIcon: newIcon,
                                      newColor: newColor,
                                    );
                                    if (context.mounted) Navigator.pop(context);
                                  } catch (error) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          isNetworkError(error)
                                              ? '❌ Немає зв\'язку. Зміна налаштувань дашборда потребує стабільного інтернету.'
                                              : '❌ Помилка збереження: $error',
                                        ),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'База записів',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: RecordsManager(
                      user: widget.user,
                      sheetName: _title,
                      color: _color,
                      headers: _headers,
                      records: _recentRecords,
                      isOffline: _isOffline,
                      hideDateFeatures: _isWarehouse,
                      onRecordUpdated: _updateLocalRecord,
                      onRecordDeleted: (_) => _fetchData(),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
