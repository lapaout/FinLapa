import '../models/dashboard.dart';
import '../models/sheet_record.dart';

List<String> extractWarehouseProductNames(
  Dashboard warehouse,
  List<SheetRecord> records,
) {
  final nameFieldIndex = warehouse.fields.indexOf('Назва');
  if (nameFieldIndex == -1) return const [];

  final valueIndex = nameFieldIndex + 1;
  final names = <String>[];

  for (final record in records) {
    if (record.values.length <= valueIndex) continue;
    final name = record.values[valueIndex].trim();
    if (name.isNotEmpty) {
      names.add(name);
    }
  }

  return names;
}
