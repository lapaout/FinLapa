import 'package:flutter/material.dart';

class DataEntryModal extends StatefulWidget {
  final String title;
  final List<String> fields;
  final Function(List<String> values) onSave;
  final bool isSending;

  const DataEntryModal({
    super.key, 
    required this.title, 
    required this.fields, 
    required this.onSave,
    required this.isSending,
  });

  @override
  State<DataEntryModal> createState() => _DataEntryModalState();
}

class _DataEntryModalState extends State<DataEntryModal> {
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (var field in widget.fields) field: TextEditingController()
    };
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
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
            Text("Новий запис: ${widget.title}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            
            ...widget.fields.map((field) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _controllers[field],
                decoration: InputDecoration(labelText: field, border: const OutlineInputBorder()),
                keyboardType: field.toLowerCase().contains("сум") || 
                              field.toLowerCase().contains("цін") || 
                              field.toLowerCase().contains("к-сть") || 
                              field.toLowerCase().contains("кількість")
                    ? TextInputType.number : TextInputType.text,
              ),
            )),
            
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16), 
                backgroundColor: Colors.green, 
                foregroundColor: Colors.white
              ),
              icon: widget.isSending 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.cloud_upload),
              label: Text(widget.isSending ? "Відправка..." : "Зберегти в Таблицю"),
              onPressed: widget.isSending ? null : () {
                List<String> valuesToSave = widget.fields.map((f) => _controllers[f]!.text).toList();
                widget.onSave(valuesToSave);
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}