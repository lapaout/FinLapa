import 'package:flutter/material.dart';

class RecordEditModal extends StatefulWidget {
  final List<String> headers;
  final List<String> rowData;
  final Function(List<String>) onSave;

  const RecordEditModal({
    super.key,
    required this.headers,
    required this.rowData,
    required this.onSave,
  });

  @override
  State<RecordEditModal> createState() => _RecordEditModalState();
}

class _RecordEditModalState extends State<RecordEditModal> {
  final List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    // ПОЧИНАЄМО З 1 (Пропускаємо дату, вона під нульовим індексом)
    for (int i = 1; i < widget.headers.length; i++) {
      String initialValue = i < widget.rowData.length ? widget.rowData[i] : '';
      _controllers.add(TextEditingController(text: initialValue));
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Center(
          // ТУТ БУЛА ПОМИЛКА - РЯДОК ВИДАЛЕНО
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min, // А ось тут йому саме місце
                children: [
                  const Text("Редагування запису", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  
                  // Створюємо поля, але генеруємо на 1 менше (бо відкинули дату)
                  ...List.generate(widget.headers.length - 1, (i) {
                    final headerIndex = i + 1; // Справжній індекс в таблиці
                    final headerName = widget.headers[headerIndex];
                    final headerLower = headerName.toLowerCase();

                    // РОЗУМНА ПЕРЕВІРКА: чи це цифри/гроші?
                    final isNumeric = headerLower.contains('сум') || 
                                      headerLower.contains('цін') || 
                                      headerLower.contains('варт') || 
                                      headerLower.contains('кільк');
                                      
                    final isMoney = headerLower.contains('сум') || 
                                    headerLower.contains('цін') || 
                                    headerLower.contains('варт');
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: TextFormField(
                        controller: _controllers[i], 
                        keyboardType: isNumeric ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: headerName,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          // ЯКЩО ГРОШІ — СТАВИМО ГРИВНЮ
                          prefixIcon: isMoney 
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('₴', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                                  ],
                                )
                              : const Icon(Icons.edit, color: Colors.blueAccent),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        // 1. Повертаємо дату на її законне перше місце
                        List<String> newValues = [
                          widget.rowData.isNotEmpty ? widget.rowData[0] : ''
                        ];
                        
                        // 2. Додаємо всі інші відредаговані значення
                        newValues.addAll(_controllers.map((c) => c.text.trim()));

                        // 3. Відправляємо повний рядок на збереження
                        widget.onSave(newValues);
                      },
                      child: const Text('Зберегти зміни', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}