import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// OAuth scopes для Google Sheets та Drive (папка FinLapa).
class GoogleApiAuth {
  GoogleApiAuth._();

  static const String webClientId =
      '348506371188-dah5gjuuo7q4tnpjnf70b54akdtpghd3.apps.googleusercontent.com';

  static const List<String> apiScopes = [
    'https://www.googleapis.com/auth/spreadsheets',
    'https://www.googleapis.com/auth/drive.file',
  ];

  static String? get platformClientId => kIsWeb ? webClientId : null;
  static GoogleSignIn? _googleSignIn;

  static void bind(GoogleSignIn googleSignIn) {
    _googleSignIn = googleSignIn;
  }

  /// Примусово відкликає доступ (Android) і скидає кеш старих scopes.
  static Future<void> disconnect() async {
    final googleSignIn = _googleSignIn;
    if (googleSignIn == null) return;

    try {
      await googleSignIn.disconnect();
    } catch (error) {
      debugPrint('GoogleApiAuth: disconnect failed: $error');
      try {
        await googleSignIn.signOut();
      } catch (signOutError) {
        debugPrint('GoogleApiAuth: signOut fallback failed: $signOutError');
      }
    }
  }

  /// На Web GIS спочатку автентифікує користувача, а scopes потрібно запросити окремо.
  static Future<void> ensureScopesGranted() async {
    final googleSignIn = _googleSignIn;
    if (googleSignIn == null || googleSignIn.currentUser == null) {
      return;
    }

    if (await googleSignIn.canAccessScopes(apiScopes)) {
      return;
    }

    final granted = await googleSignIn.requestScopes(apiScopes);
    if (!granted) {
      throw Exception(
        'Потрібен доступ до Google Sheets і Google Drive. '
        'Надайте дозволи в діалозі Google.',
      );
    }
  }

  /// Повертає актуальні Authorization-заголовки для REST-запитів Google API.
  static Future<Map<String, String>> buildHeaders(
    GoogleSignInAccount user,
  ) async {
    try {
      await ensureScopesGranted();
    } catch (error) {
      debugPrint('GoogleApiAuth: ensureScopesGranted skipped: $error');
    }

    final headers = await user.authHeaders;
    final authorization = headers['Authorization'];
    if (authorization == null ||
        authorization.isEmpty ||
        authorization == 'Bearer null') {
      throw Exception(
        'Токен доступу відсутній. Вийдіть і увійдіть знову через Google.',
      );
    }

    return Map<String, String>.from(headers);
  }
}
