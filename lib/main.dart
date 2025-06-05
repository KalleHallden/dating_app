import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:provider/provider.dart';
import 'package:uni_links/uni_links.dart'; // Import uni_links
import 'pages/auth_screen.dart';
import 'pages/signup_screen.dart';
import 'pages/call_page.dart';
import 'providers/signup_provider.dart';
import 'services/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ensure Supabase is initialized with the correct redirect URL and authFlowType
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
  supabase.Session? _session; // Use a nullable Session object

  @override
  void initState() {
    super.initState();
    // Initialize session listener from Supabase
    SupabaseClient.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (mounted) {
        setState(() {
          _session = session;
        });
      }
      print('Auth Event: $event, Session: ${session?.accessToken != null ? 'Present' : 'Null'}');
    });

    // Also get initial session on startup
    _getInitialSession();

    // Set up deep link listener for Supabase
    _setupDeepLinkListener();
  }

  Future<void> _getInitialSession() async {
    final session = SupabaseClient.instance.client.auth.currentSession;
    if (mounted) {
      setState(() {
        _session = session;
      });
    }
  }

  // Deep link listener function
  void _setupDeepLinkListener() {
    // Listen for incoming links when the app is already open
    linkStream.listen((String? uri) {
      _handleDeepLink(uri);
    }, onError: (err) {
      print('Error receiving deep link: $err');
    });

    // Get the initial link if the app was launched by a deep link
    getInitialLink().then((String? uri) {
      _handleDeepLink(uri);
    });
  }

  // Function to process the deep link
  Future<void> _handleDeepLink(String? uri) async {
    if (uri != null) {
      print('Received deep link: $uri');
      try {
        // Corrected type from AuthResponse to AuthSessionUrlResponse
        final supabase.AuthSessionUrlResponse response = await SupabaseClient.instance.client.auth.getSessionFromUrl(
          Uri.parse(uri),
        );

        if (response.session != null) {
          print('Supabase session recovered from deep link!');
          // The onAuthStateChange listener will pick this up and trigger a rebuild
          // No need to manually navigate here, the _getInitialScreen will handle it
        } else {
          print('No session in deep link response.');
          // Optionally show an error or redirect to AuthScreen if session couldn't be recovered
        }
      } catch (e) {
        print('Error processing deep link with Supabase: $e');
        // Optionally show an error to the user
      }
    }
  }

  Future<Widget> _getInitialScreen() async {
    final client = SupabaseClient.instance.client;
    final session = _session; // Use the state variable
    final user = client.auth.currentUser;

    // If a session exists but the user object is null (e.g., user deleted on server)
    // or if the session is invalid, explicitly sign out to clear cache.
    if (session != null && user == null) {
      print('DEBUG: Session exists but user is null or invalid. Attempting signOut to clear cache.');
      try {
        await client.auth.signOut();
        // After signOut, session and user should be null, which will correctly
        // lead to the AuthScreen.
        return const AuthScreen(initialMessage: 'Session cleared. Please sign in.');
      } catch (e) {
        print('Error during signOut: $e');
        // Fallback to AuthScreen if signOut fails
        return const AuthScreen(initialMessage: 'Error clearing session. Please sign in.');
      }
    }

    // Case 1: No session or user found
    if (session == null || user == null) {
      print('DEBUG: No session or user. Navigating to AuthScreen.');
      return const AuthScreen(
          initialMessage:
              'Auth session missing! Please sign in or complete email confirmation.');
    }

    // Case 2: User exists but email is not confirmed
    if (user.emailConfirmedAt == null) {
      print('DEBUG: User email not confirmed. Navigating to AuthScreen.');
      return const AuthScreen(
          initialMessage:
              'Please check your email to confirm your account. Then sign in.');
    }

    // Case 3: User exists, email confirmed. Now check user profile data.
    final userId = user.id;
    try {
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
        print('DEBUG: User profile incomplete. Navigating to SignupScreen.');
        return const SignupScreen();
      }
    } catch (e) {
      print('Error fetching user data: $e');
      return const AuthScreen(
          initialMessage: 'Failed to load user data. Please try again.');
    }

    // Case 4: User exists, email confirmed, profile complete. Go to CallPage.
    print('DEBUG: User profile complete. Navigating to CallPage.');
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
        // Depend on _session directly, which is updated by the listener
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

