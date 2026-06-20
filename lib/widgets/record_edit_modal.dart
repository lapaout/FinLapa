import 'package:flutter/material.dart';

class RecordEditModal extends StatefulWidget {
  final List<String> headers;
  final List<String> rowData;
  final Function(List<String>) onSave;
  final Future<void> Function()? onDelete;

  const RecordEditModal({
    super.key,
    required this.headers,
    required this.rowData,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<RecordEditModal> createState() => _RecordEditModalState();
}

class _RecordEditModalState extends State<RecordEditModal> {
  final List<TextEditingController> _controllers = [];
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
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

  bool _isHiddenHeader(String headerName) {
    return headerName == 'ID товару (приховано)' || headerName == '_warehouseItemId';
  }

  bool _isReadOnlyHeader(String headerName) {
    return headerName == 'Товар зі складу' || headerName == '_warehouseItemName';
  }

  bool _isEditableWarehouseField(String headerName) {
    return headerName == 'Продано (шт)' || headerName == '_soldQuantity';
  }

  String _labelForHeader(String headerName) {
    switch (headerName) {
      case '_soldQuantity':
      case 'Продано (шт)':
        return 'Продано (шт)';
      case '_warehouseItemName':
      case 'Товар зі складу':
        return 'Товар зі складу';
      default:
        return headerName;
    }
  }

  Future<void> _confirmDelete() async {
    if (widget.onDelete == null || _isDeleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Дійсно видалити запис?'),
        content: const Text('Цю дію неможливо скасувати.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Редагування запису",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  ...List.generate(widget.headers.length - 1, (i) {
                    final headerIndex = i + 1;
                    final headerName = widget.headers[headerIndex];

                    if (_isHiddenHeader(headerName)) {
                      return const SizedBox.shrink();
                    }

                    if (headerName.startsWith('_') && !_isEditableWarehouseField(headerName)) {
                      if (!_isReadOnlyHeader(headerName)) {
                        return const SizedBox.shrink();
                      }
                    }

                    final headerLower = headerName.toLowerCase();
                    final labelText = _labelForHeader(headerName);
                    final readOnly = _isReadOnlyHeader(headerName);

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
                        readOnly: readOnly,
                        keyboardType: isNumeric
                            ? const TextInputType.numberWithOptions(decimal: true)
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: labelText,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: isMoney
                              ? const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '₴',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueAccent,
                                      ),
                                    ),
                                  ],
                                )
                              : const Icon(Icons.edit, color: Colors.blueAccent),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isDeleting
                              ? null
                              : () {
                                  List<String> newValues = [
                                    widget.rowData.isNotEmpty ? widget.rowData[0] : '',
                                  ];
                                  newValues.addAll(_controllers.map((c) => c.text.trim()));
                                  widget.onSave(newValues);
                                },
                          child: const Text(
                            'Зберегти зміни',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      if (widget.onDelete != null) ...[
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _isDeleting ? null : _confirmDelete,
                          icon: _isDeleting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.delete_outline, color: Colors.redAccent, size: 28),
                          tooltip: 'Видалити запис',
                        ),
                      ],
                    ],
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
