import 'package:amplify_app/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:provider/provider.dart';
import 'package:uni_links/uni_links.dart'; // Import uni_links
import 'pages/auth_screen.dart';
import 'pages/signup_screen.dart';
import 'pages/call_page.dart';
import 'providers/signup_provider.dart';
import 'services/supabase_client.dart';
import 'services/online_status_service.dart';

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
  bool _isCheckingAuth = true; // Add loading state

  @override
  void initState() {
    super.initState();
    // Initialize session listener from Supabase
    SupabaseClient.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      print('Auth Event: $event, Session: ${session?.accessToken != null ? 'Present' : 'Null'}');
      
      // Update online status based on auth state
      if (event == supabase.AuthChangeEvent.signedIn && session != null) {
        OnlineStatusService().initialize();
      } else if (event == supabase.AuthChangeEvent.signedOut) {
        OnlineStatusService().dispose();
      }
      
      if (mounted) {
        setState(() {
          _session = session;
          // If we receive a SIGNED_OUT event, ensure session is null
          if (event == supabase.AuthChangeEvent.signedOut) {
            _session = null;
          }
        });
      }
    });

    // Also get initial session on startup
    _getInitialSession();

    // Set up deep link listener for Supabase
    _setupDeepLinkListener();
    
    // Initialize online status service if user is authenticated
    final session = SupabaseClient.instance.client.auth.currentSession;
    if (session != null) {
      OnlineStatusService().initialize();
    }
  }

  Future<void> _getInitialSession() async {
    try {
      final session = SupabaseClient.instance.client.auth.currentSession;
      if (mounted) {
        setState(() {
          _session = session;
          _isCheckingAuth = false;
        });
      }
    } catch (e) {
      print('Error getting initial session: $e');
      if (mounted) {
        setState(() {
          _session = null;
          _isCheckingAuth = false;
        });
      }
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
    
    // CRITICAL: Always check the current session/user state fresh
    // Don't rely on the state variable during initial screen determination
    final currentSession = client.auth.currentSession;
    final currentUser = client.auth.currentUser;

    // Case 1: No session or user found - definitely need to authenticate
    if (currentSession == null || currentUser == null) {
      print('DEBUG: No session or user. Navigating to AuthScreen.');
      return const AuthScreen();
    }

    // Case 2: User exists but email is not confirmed
    if (currentUser.emailConfirmedAt == null) {
      print('DEBUG: User email not confirmed. Navigating to AuthScreen.');
      return const AuthScreen(
          initialMessage:
              'Please check your email to confirm your account. Then sign in.');
    }

    // Case 3: User exists, email confirmed. Now check user profile data.
    final userId = currentUser.id;
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
      // If we can't fetch user data, assume they need to complete signup
      return const SignupScreen();
    }

    // Case 4: User exists, email confirmed, profile complete. Go to HomePage.
    print('DEBUG: User profile complete. Navigating to HomePage.');
    return const HomePage();
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
      home: _isCheckingAuth 
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : FutureBuilder<Widget>(
              // Re-evaluate the initial screen whenever session changes
              future: _getInitialScreen(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return AuthScreen(
                    initialMessage: 'Error: ${snapshot.error}',
                  );
                }
                return snapshot.data ?? const AuthScreen();
              },
            ),
    );
  }
}
