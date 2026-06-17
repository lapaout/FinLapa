import 'package:flutter/material.dart';

class RecordEditModal extends StatefulWidget {
  final List<String> headers;
  final List<String> rowData;
  final Function(List<String> newValues) onSave;

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
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    // Створюємо контролери для кожного поля і заповнюємо їх існуючими даними
    _controllers = widget.rowData.map((value) => TextEditingController(text: value)).toList();
    
    // Якщо в таблиці з'явилися нові стовпці, а в старому записі їх немає — додаємо порожні
    while (_controllers.length < widget.headers.length) {
      _controllers.add(TextEditingController(text: ""));
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24, right: 24, top: 24
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Редагування запису", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            // Генеруємо поля вводу для кожного стовпця таблиці
            ...List.generate(widget.headers.length, (index) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: TextField(
                  controller: _controllers[index],
                  decoration: InputDecoration(
                    labelText: widget.headers[index], 
                    border: const OutlineInputBorder()
                  ),
                ),
              );
            }),
            
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.blueGrey,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                // Збираємо нові значення з усіх полів
                List<String> newValues = _controllers.map((c) => c.text).toList();
                widget.onSave(newValues);
              },
              child: const Text("Зберегти зміни"),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}