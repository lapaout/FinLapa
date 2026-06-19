import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'screens/home_screen.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const FinLapaApp());
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
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: [
    'https://www.googleapis.com/auth/drive.file', 
    'https://www.googleapis.com/auth/spreadsheets'
  ]);
  GoogleSignInAccount? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    _googleSignIn.onCurrentUserChanged.listen((account) {
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
    return HomeScreen(user: _user!, googleSignIn: _googleSignIn);
  }
}

class WelcomeScreen extends StatelessWidget {
  final GoogleSignIn googleSignIn;
  const WelcomeScreen({super.key, required this.googleSignIn});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.analytics_outlined, size: 90, color: Colors.blueAccent),
            const SizedBox(height: 16),
            const Text('FinLapa', textAlign: TextAlign.center, style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 1)),
            const Text('Автономна система обліку', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black54)),
            const SizedBox(height: 60),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
              icon: const Icon(Icons.login),
              label: const Text('Увійти через Google', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              onPressed: () => googleSignIn.signIn(),
            ),
          ],
        ),
      ),
    );
  }
}