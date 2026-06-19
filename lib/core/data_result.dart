import 'data_source_type.dart';

/// Обгортка результату операції з даними та метаданими про джерело.
class DataResult<T> {
  final T data;
  final DataSourceType source;
  final Object? error;

  const DataResult({
    required this.data,
    required this.source,
    this.error,
  });

  bool get isFromCache => source == DataSourceType.cache;
  bool get isFromNetwork => source == DataSourceType.network;
  bool get isOffline => isFromCache;
  bool get hasError => error != null;

  factory DataResult.network(T data) {
    return DataResult(
      data: data,
      source: DataSourceType.network,
    );
  }

  factory DataResult.cache(T data, {Object? error}) {
    return DataResult(
      data: data,
      source: DataSourceType.cache,
      error: error,
    );
  }

  DataResult<R> map<R>(R Function(T data) transform) {
    return DataResult<R>(
      data: transform(data),
      source: source,
      error: error,
    );
  }
}
