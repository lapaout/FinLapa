/// Базовий клас помилок додатку.
sealed class AppException implements Exception {
  final String message;
  const AppException(this.message);

  @override
  String toString() => message;
}

/// Відсутність мережевого з'єднання або таймаут.
class NetworkException extends AppException {
  const NetworkException([super.message = 'Немає з\'єднання з інтернетом']);
}

/// Помилка авторизації Google.
class AuthException extends AppException {
  const AuthException([super.message = 'Помилка авторизації']);
}

/// Аркуш або таблиця не знайдена (новий користувач, порожня таблиця).
class SheetNotFoundException extends AppException {
  const SheetNotFoundException([super.message = 'Таблицю або аркуш не знайдено']);
}

/// Локальний кеш відсутній (офлайн без попереднього завантаження).
class NoCacheException extends AppException {
  const NoCacheException([super.message = 'Немає збережених даних для офлайн-режиму']);
}

/// Невідома або неочікувана помилка API.
class ApiException extends AppException {
  const ApiException(super.message);
}

/// Класифікує довільну помилку в типізований [AppException].
AppException classifyError(Object error) {
  if (error is AppException) return error;

  final message = error.toString();

  if (_isNetworkErrorMessage(message)) {
    return NetworkException(message);
  }

  if (message.contains('401') || message.contains('403')) {
    return AuthException(message);
  }

  if (message.contains('404') ||
      message.contains('порожня') ||
      message.contains('не знайден')) {
    return SheetNotFoundException(message);
  }

  return ApiException(message);
}

/// Перевіряє, чи помилка пов'язана з відсутністю мережі.
bool isNetworkError(Object error) {
  if (error is NetworkException) return true;
  return _isNetworkErrorMessage(error.toString());
}

bool _isNetworkErrorMessage(String message) {
  return message.contains('SocketException') ||
      message.contains('ClientException') ||
      message.contains('Failed host lookup') ||
      message.contains('Network is unreachable') ||
      message.contains('Connection refused') ||
      message.contains('Connection timed out');
}
