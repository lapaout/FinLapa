/// Конфігурація динамічного dashboard (рядок у App_Config).
class Dashboard {
  static const int defaultIconCode = 57933;
  static const int defaultColorValue = 4284901072;

  final String title;
  final int iconCode;
  final int colorValue;
  final List<String> fields;

  const Dashboard({
    required this.title,
    required this.iconCode,
    required this.colorValue,
    required this.fields,
  });

  /// Парсинг з формату SharedPreferences / App_Config map.
  factory Dashboard.fromMap(Map<String, dynamic> map) {
    return Dashboard(
      title: map['title']?.toString() ?? '',
      iconCode: _parseInt(map['icon'], defaultIconCode),
      colorValue: _parseInt(map['color'], defaultColorValue),
      fields: _parseFields(map['fields']),
    );
  }

  /// Парсинг рядка Google Sheets App_Config (без заголовка).
  factory Dashboard.fromSheetRow(List<String> row) {
    if (row.length < 4) {
      throw FormatException('Некоректний рядок конфігурації dashboard: $row');
    }

    return Dashboard(
      title: row[0],
      iconCode: int.tryParse(row[1]) ?? defaultIconCode,
      colorValue: int.tryParse(row[2]) ?? defaultColorValue,
      fields: row[3].split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'icon': iconCode,
      'color': colorValue,
      'fields': List<String>.from(fields),
    };
  }

  /// Рядок для запису в Google Sheets App_Config.
  List<String> toSheetRow() {
    return [
      title,
      iconCode.toString(),
      colorValue.toString(),
      fields.join(','),
    ];
  }

  static const List<String> appConfigHeader = [
    'Title',
    'IconCode',
    'ColorValue',
    'Fields',
  ];

  /// Парсинг сирих рядків аркуша App_Config (перший рядок — заголовок).
  static List<Dashboard> listFromSheetRows(List<List<String>> rows) {
    if (rows.isEmpty || rows.length <= 1) return [];

    final dashboards = <Dashboard>[];
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 4) continue;

      dashboards.add(
        Dashboard(
          title: row[0],
          iconCode: int.tryParse(row[1]) ?? defaultIconCode,
          colorValue: int.tryParse(row[2]) ?? defaultColorValue,
          fields: row[3]
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
        ),
      );
    }
    return dashboards;
  }

  /// Формує повний набір рядків для запису в App_Config.
  static List<List<String>> sheetRowsFromList(List<Dashboard> dashboards) {
    return [
      appConfigHeader,
      ...dashboards.map((dashboard) => dashboard.toSheetRow()),
    ];
  }

  Dashboard copyWith({
    String? title,
    int? iconCode,
    int? colorValue,
    List<String>? fields,
  }) {
    return Dashboard(
      title: title ?? this.title,
      iconCode: iconCode ?? this.iconCode,
      colorValue: colorValue ?? this.colorValue,
      fields: fields ?? this.fields,
    );
  }

  static int _parseInt(Object? value, int fallback) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<String> _parseFields(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }
}
