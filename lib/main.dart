import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'data/sources/google_api_auth.dart';
import 'screens/authenticated_shell.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'widgets/google_web_sign_in_button.dart';

void main() {  runApp(const FinLapaApp());
}

class FinLapaApp extends StatelessWidget {
  const FinLapaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FinLapa',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent), useMaterial3: true),
      
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('uk', 'UA'),
        Locale('en', 'US'),
      ],
      locale: const Locale('uk', 'UA'),

      home: const AppRoot(),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: GoogleApiAuth.platformClientId,
    scopes: GoogleApiAuth.apiScopes,
  );

  GoogleSignInAccount? _user;
  bool _isLoading = true;
  @override
  void initState() {
    super.initState();
    GoogleApiAuth.bind(_googleSignIn);

    _googleSignIn.onCurrentUserChanged.listen((account) async {
      if (account != null) {
        try {
          await GoogleApiAuth.ensureScopesGranted();
        } catch (error) {
          debugPrint('GoogleApiAuth: scope request failed: $error');
        }
      }

      if (mounted) {
        setState(() {
          _user = account;
          _isLoading = false;
        });
      }
    });
    // Фікс: примусово вимикаємо завантаження, якщо тихий вхід не вдався
    _googleSignIn.signInSilently().then((account) {
      if (account == null && mounted) {
        setState(() { _isLoading = false; });
      }
    }).catchError((error) {
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_user == null) return WelcomeScreen(googleSignIn: _googleSignIn);
    return AuthenticatedShell(user: _user!, googleSignIn: _googleSignIn);
  }
}

class WelcomeScreen extends StatelessWidget {
  final GoogleSignIn googleSignIn;
  const WelcomeScreen({super.key, required this.googleSignIn});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: SizedBox(
                    width: 140,
                    height: 140,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/Icon_phone.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'FinLapa',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const Text(
                  'Система обліку',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 60),
                if (kIsWeb)
                  buildGoogleWebSignInButton()
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.login),
                    label: const Text(
                      'Увійти через Google',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => googleSignIn.signIn(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}