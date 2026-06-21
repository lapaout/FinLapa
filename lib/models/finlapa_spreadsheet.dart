/// Google Sheets файл у папці FinLapa на Drive (один workspace).
class FinLapaSpreadsheet {
  final String id;
  final String name;

  const FinLapaSpreadsheet({
    required this.id,
    required this.name,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinLapaSpreadsheet && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
