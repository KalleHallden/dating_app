import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:provider/provider.dart';
import 'pages/auth_screen.dart';
import 'pages/signup_screen.dart';
import 'pages/call_page.dart';
import 'providers/signup_provider.dart';
import 'services/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseClient.initialize();
  runApp(
    ChangeNotifierProvider<SignupProvider>(
      create: (_) => SignupProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Listen to auth state changes
    SupabaseClient.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == supabase.AuthChangeEvent.signedIn ||
          event == supabase.AuthChangeEvent.signedOut ||
          event == supabase.AuthChangeEvent.tokenRefreshed) {
        setState(() {}); // Trigger rebuild to update initial screen
      }
    });
  }

  Future<Widget> _getInitialScreen() async {
    final client = SupabaseClient.instance.client;
    final session = client.auth.currentSession;
    final user = client.auth.currentUser;

    if (session == null || user == null) {
      return const AuthScreen();
    }

    final userId = user.id;
    final userData = await client
        .from('users')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (userData == null ||
        userData['name'] == null ||
        userData['age'] == null ||
        userData['gender'] == null ||
        userData['gender_preference'] == null ||
        userData['location'] == null ||
        userData['about_me'] == null) {
      return const SignupScreen();
    }

    return const CallPage();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dating App',
      theme: ThemeData(
        primaryColor: const Color(0xFF007AFF),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF007AFF),
          secondary: Color(0xFF34C759),
        ),
        scaffoldBackgroundColor: Colors.white,
        primarySwatch: const MaterialColor(
          0xFF007AFF,
          <int, Color>{
            50: Color(0xFFE6F0FF),
            100: Color(0xFFB3D1FF),
            200: Color(0xFF80B1FF),
            300: Color(0xFF4D92FF),
            400: Color(0xFF266EFF),
            500: Color(0xFF007AFF),
            600: Color(0xFF0073F0),
            700: Color(0xFF006AD1),
            800: Color(0xFF005AB2),
            900: Color(0xFF004680),
          },
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          selectedItemColor: const Color(0xFF007AFF),
          unselectedItemColor: Colors.grey[400],
        ),
      ),
      home: FutureBuilder<Widget>(
        future: _getInitialScreen(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return snapshot.data ?? const AuthScreen();
        },
      ),
    );
  }
}
