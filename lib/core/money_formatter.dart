/// Спільне форматування грошей та чисел для UI.
class MoneyFormatter {
  MoneyFormatter._();

  /// Форматує число з пробілами тисяч; дробова частина — лише якщо потрібна.
  /// Напр.: `15 000`, `1 234.56`.
  static String formatNumber(num value) {
    final isWhole = value == value.truncateToDouble();
    final str = isWhole ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

    final parts = str.split('.');
    final intPart = parts[0];
    final isNegative = intPart.startsWith('-');
    final digits = isNegative ? intPart.substring(1) : intPart;

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }

    final grouped = (isNegative ? '-' : '') + buffer.toString();
    return parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
  }

  /// Форматує суму з пробілами тисяч, напр. `15 000 ₴`.
  static String formatMoney(num value) {
    final rounded = value.round();
    final isNegative = rounded < 0;
    final digits = rounded.abs().toString();

    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }

    return '${isNegative ? '-' : ''}${buffer.toString()} ₴';
  }

  /// Форматує кількість штук з пробілами тисяч, напр. `1 250 шт`.
  static String formatUnits(num value) {
    final rounded = value.round();
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return '${rounded < 0 ? '-' : ''}${buffer.toString()} шт';
  }

  /// Короткий формат для осі Y графіка: `15k`, `1.2M`.
  static String shortNumber(num value) {
    final abs = value.abs();
    if (abs >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(abs >= 10000000 ? 0 : 1)}M';
    }
    if (abs >= 1000) {
      return '${(value / 1000).toStringAsFixed(abs >= 10000 ? 0 : 1)}k';
    }
    return value.toStringAsFixed(0);
  }
}
