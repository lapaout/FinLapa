/// Конфігурація динамічного dashboard (рядок у App_Config).
class Dashboard {
  static const int defaultIconCode = 57933;
  static const int defaultColorValue = 4284901072;
  static const String typeIncome = 'income';
  static const String typeExpense = 'expense';
  static const String typeWarehouse = 'warehouse';

  static const List<String> warehouseRequiredFields = [
    'Назва',
    'Кількість',
    'Загальні витрати',
  ];

  final String title;
  final int iconCode;
  final int colorValue;
  final List<String> fields;
  final bool isArchived;
  final bool isHidden;
  final String type;
  final bool isWarehouseLinked;

  const Dashboard({
    required this.title,
    required this.iconCode,
    required this.colorValue,
    required this.fields,
    this.isArchived = false,
    this.isHidden = false,
    this.type = typeIncome,
    this.isWarehouseLinked = false,
  });

  factory Dashboard.fromMap(Map<String, dynamic> map) {
    return Dashboard(
      title: map['title']?.toString() ?? '',
      iconCode: _parseInt(map['icon'], defaultIconCode),
      colorValue: _parseInt(map['color'], defaultColorValue),
      fields: _parseFields(map['fields']),
      isArchived: _parseBool(map['isArchived']),
      isHidden: _parseBool(map['isHidden']),
      type: _parseType(map['type']),
      isWarehouseLinked: _parseBool(map['isWarehouseLinked']),
    );
  }

  factory Dashboard.fromJson(Map<String, dynamic> json) => Dashboard.fromMap(json);

  factory Dashboard.fromSheetRow(List<String> row) {
    if (row.length < 4) {
      throw FormatException('Некоректний рядок конфігурації dashboard: $row');
    }

    return Dashboard(
      title: row[0],
      iconCode: int.tryParse(row[1]) ?? defaultIconCode,
      colorValue: int.tryParse(row[2]) ?? defaultColorValue,
      fields: row[3].split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      isArchived: row.length >= 5 ? _parseArchivedCell(row[4]) : false,
      type: row.length >= 6 ? _parseType(row[5]) : typeIncome,
      isWarehouseLinked: row.length >= 7 ? _parseLinkedCell(row[6]) : false,
      isHidden: row.length >= 8 ? _parseArchivedCell(row[7]) : false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'icon': iconCode,
      'color': colorValue,
      'fields': List<String>.from(fields),
      'isArchived': isArchived,
      'isHidden': isHidden,
      'type': type,
      'isWarehouseLinked': isWarehouseLinked,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  List<String> toSheetRow() {
    return [
      title,
      iconCode.toString(),
      colorValue.toString(),
      fields.join(','),
      isArchived ? '1' : '0',
      type,
      isWarehouseLinked ? '1' : '0',
      isHidden ? '1' : '0',
    ];
  }

  static const List<String> appConfigHeader = [
    'Title',
    'IconCode',
    'ColorValue',
    'Fields',
    'IsArchived',
    'Type',
    'IsWarehouseLinked',
    'IsHidden',
  ];

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
          isArchived: row.length >= 5 ? _parseArchivedCell(row[4]) : false,
          type: row.length >= 6 ? _parseType(row[5]) : typeIncome,
          isWarehouseLinked: row.length >= 7 ? _parseLinkedCell(row[6]) : false,
          isHidden: row.length >= 8 ? _parseArchivedCell(row[7]) : false,
        ),
      );
    }
    return dashboards;
  }

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
    bool? isArchived,
    bool? isHidden,
    String? type,
    bool? isWarehouseLinked,
  }) {
    return Dashboard(
      title: title ?? this.title,
      iconCode: iconCode ?? this.iconCode,
      colorValue: colorValue ?? this.colorValue,
      fields: fields ?? this.fields,
      isArchived: isArchived ?? this.isArchived,
      isHidden: isHidden ?? this.isHidden,
      type: type ?? this.type,
      isWarehouseLinked: isWarehouseLinked ?? this.isWarehouseLinked,
    );
  }

  static String _parseType(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == typeExpense) return typeExpense;
    if (normalized == typeWarehouse) return typeWarehouse;
    return typeIncome;
  }

  static List<String> buildWarehouseFields(List<String> customFields) {
    final custom = customFields
        .where((field) => !warehouseRequiredFields.contains(field))
        .toList();
    return [...warehouseRequiredFields, ...custom];
  }

  static bool _parseBool(Object? value) {
    if (value is bool) return value;
    if (value == null) return false;
    final normalized = value.toString().toLowerCase();
    return normalized == 'true' || normalized == '1';
  }

  static bool _parseArchivedCell(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized == '1' || normalized == 'true';
  }

  static bool _parseLinkedCell(String value) => _parseArchivedCell(value);

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
