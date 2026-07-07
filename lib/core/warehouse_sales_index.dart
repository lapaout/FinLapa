import '../models/dashboard.dart';
import '../models/sheet_record.dart';
import 'warehouse_analytics.dart';

typedef WarehouseStats = Map<String, num>;

/// Індекс продажів за ID товару — O(m) побудова, O(1) lookup на товар.
class WarehouseSalesIndex {
  WarehouseSalesIndex._(this._salesByItemId);

  final Map<String, List<LinkedIncomeRecord>> _salesByItemId;

  static final WarehouseSalesIndex empty = WarehouseSalesIndex._({});

  List<LinkedIncomeRecord> salesForItemId(String itemId) {
    if (itemId.isEmpty) return const [];
    return _salesByItemId[itemId] ?? const [];
  }

  factory WarehouseSalesIndex.build(List<LinkedIncomeRecord> linkedIncomeRecords) {
    final map = <String, List<LinkedIncomeRecord>>{};
    for (final record in linkedIncomeRecords) {
      final itemId = normalizeWarehouseItemId(parseWarehouseItemId(record.fields));
      if (itemId.isEmpty) continue;
      map.putIfAbsent(itemId, () => []).add(record);
    }
    return WarehouseSalesIndex._(map);
  }
}

/// Статистика однієї складської позиції через індекс — O(k), k = продажі товару.
WarehouseStats calculateWarehouseStatsIndexed({
  required SheetRecord item,
  required Dashboard dashboard,
  required WarehouseSalesIndex salesIndex,
}) {
  final fields = recordFieldMap(item, dashboard.fields);
  final bought = parseWarehouseNum(fields['Кількість']);
  final spent = parseWarehouseNum(fields['Загальні витрати']);
  final itemId = normalizeWarehouseItemId(item.dateTime);

  final linkedSales = salesIndex.salesForItemId(itemId);

  num sold = 0;
  num earned = 0;
  for (final sale in linkedSales) {
    sold += parseSoldQuantity(sale.fields);
    final incomeFields =
        sale.headers.length > 1 ? sale.headers.sublist(1) : const <String>[];
    earned += parseIncomeAmount(
      sale.record,
      incomeFields,
      headers: sale.headers,
    );
  }

  final remaining = bought - sold;
  final costPerUnit = bought > 0 ? spent / bought : 0;

  return {
    'bought': bought,
    'spent': spent,
    'sold': sold,
    'earned': earned,
    'remaining': remaining,
    'costPerUnit': costPerUnit,
  };
}

/// Агреговані показники дашборда + stats per itemId за один прохід O(n + m).
class WarehouseStatsCache {
  const WarehouseStatsCache({
    required this.totals,
    required this.statsByItemId,
    required this.salesIndex,
  });

  final WarehouseStats totals;
  final Map<String, WarehouseStats> statsByItemId;
  final WarehouseSalesIndex salesIndex;

  static final WarehouseStatsCache empty = WarehouseStatsCache(
    totals: {'remaining': 0, 'spent': 0, 'earned': 0},
    statsByItemId: {},
    salesIndex: WarehouseSalesIndex.empty,
  );

  WarehouseStats? statsFor(SheetRecord item) {
    final itemId = normalizeWarehouseItemId(item.dateTime);
    if (itemId.isEmpty) return null;
    return statsByItemId[itemId];
  }
}

WarehouseStatsCache buildWarehouseStatsCache({
  required List<SheetRecord> items,
  required Dashboard dashboard,
  required List<LinkedIncomeRecord> linkedIncomeRecords,
}) {
  if (items.isEmpty) {
    return WarehouseStatsCache.empty;
  }

  final salesIndex = WarehouseSalesIndex.build(linkedIncomeRecords);
  final statsByItemId = <String, WarehouseStats>{};

  num remaining = 0;
  num spent = 0;
  num earned = 0;

  for (final item in items) {
    final stats = calculateWarehouseStatsIndexed(
      item: item,
      dashboard: dashboard,
      salesIndex: salesIndex,
    );
    statsByItemId[normalizeWarehouseItemId(item.dateTime)] = stats;
    remaining += stats['remaining'] ?? 0;
    spent += stats['spent'] ?? 0;
    earned += stats['earned'] ?? 0;
  }

  return WarehouseStatsCache(
    totals: {'remaining': remaining, 'spent': spent, 'earned': earned},
    statsByItemId: statsByItemId,
    salesIndex: salesIndex,
  );
}

/// Legacy API — будує індекс на кожен виклик. Для списків використовуйте
/// [buildWarehouseStatsCache].
WarehouseStats calculateWarehouseStats({
  required SheetRecord item,
  required Dashboard dashboard,
  required List<LinkedIncomeRecord> linkedIncomeRecords,
}) {
  final salesIndex = WarehouseSalesIndex.build(linkedIncomeRecords);
  return calculateWarehouseStatsIndexed(
    item: item,
    dashboard: dashboard,
    salesIndex: salesIndex,
  );
}
