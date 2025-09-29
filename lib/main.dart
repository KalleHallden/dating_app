import 'package:kora/pages/home_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart'; // Import app_links

import 'pages/welcome_screen.dart';
import 'pages/signup_screen.dart';
import 'pages/call_page.dart';
import 'pages/splash_screen.dart';
import 'providers/signup_provider.dart';
import 'services/supabase_client.dart';
import 'services/online_status_service.dart';
import 'services/call_notification_service.dart';
import 'services/ban_detection_service.dart';
import 'widgets/call_notification.dart';

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ensure Supabase is initialized with the correct redirect URL and authFlowType
  await SupabaseClient.initialize();

  // Initialize services
  await OnlineStatusService().initialize();

  // Initialize the global call notification service
  await CallNotificationService().initialize();

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

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  supabase.Session? _session; // Use a nullable Session object
  bool _isCheckingAuth = true; // Add loading state
  bool _showSplash = true; // Add splash screen state

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Show splash screen for a minimum duration
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showSplash = false;
        });
      }
    });

    // Initialize session listener from Supabase
    SupabaseClient.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      print(
          'Auth Event: $event, Session: ${session?.accessToken != null ? 'Present' : 'Null'}');

      // Update online status based on auth state
      if (event == supabase.AuthChangeEvent.signedIn && session != null) {
        OnlineStatusService().initialize();
        // Re-initialize call notification service for new user
        CallNotificationService().reinitialize();
        // Initialize ban detection service
        BanDetectionService().initialize(onBanned: () {
          // Show banned message and navigate to welcome screen when user gets banned
          if (navigatorKey.currentContext != null) {
            // Show the ban message
            ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
              const SnackBar(
                content: Text('Your account has been suspended due to multiple reports. Please contact support if you believe this is an error.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 6),
              ),
            );

            // Navigate to welcome screen (login screen)
            Navigator.of(navigatorKey.currentContext!).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const WelcomeScreen()),
              (route) => false,
            );
          }
        });
      } else if (event == supabase.AuthChangeEvent.signedOut) {
        OnlineStatusService().dispose();
        BanDetectionService().dispose();
        // No need to dispose CallNotificationService - it handles auth changes internally

        // Force navigation to welcome screen on sign out
        if (mounted && navigatorKey.currentContext != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.of(navigatorKey.currentContext!).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const WelcomeScreen()),
              (route) => false,
            );
          });
        }
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

    // Initialize services if user is authenticated
    final session = SupabaseClient.instance.client.auth.currentSession;
    if (session != null) {
      OnlineStatusService().initialize();
      BanDetectionService().initialize(onBanned: () {
        // Show banned message and navigate to welcome screen when user gets banned
        if (navigatorKey.currentContext != null) {
          // Show the ban message
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            const SnackBar(
              content: Text('Your account has been suspended due to multiple reports. Please contact support if you believe this is an error.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 6),
            ),
          );

          // Navigate to welcome screen (login screen)
          Navigator.of(navigatorKey.currentContext!).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const WelcomeScreen()),
            (route) => false,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-initialize call notification service when app resumes
      // This ensures subscriptions are re-established
      print('App resumed - re-initializing call notification service');
      CallNotificationService().reinitialize();
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
    final appLinks = AppLinks();

    // Listen for incoming links when the app is already open
    appLinks.uriLinkStream.listen((Uri uri) {
      _handleDeepLink(uri.toString());
    }, onError: (err) {
      print('Error receiving deep link: $err');
    });

    // Get the initial link if the app was launched by a deep link
    appLinks.getInitialLink().then((Uri? uri) {
      if (uri != null) {
        _handleDeepLink(uri.toString());
      }
    });
  }

  // Function to handle banned users
  Future<void> _handleBannedUser() async {
    try {
      // Clear any local state
      OnlineStatusService().dispose();
      BanDetectionService().dispose();

      // Sign out the user
      await SupabaseClient.instance.client.auth.signOut();

      // Don't navigate here, let the auth state change handle it
      // The signOut above will trigger the auth state listener which will rebuild the app
    } catch (e) {
      print('Error handling banned user: $e');
    }
  }

  // Function to process the deep link
  Future<void> _handleDeepLink(String? uri) async {
    if (uri != null) {
      print('Received deep link: $uri');
      try {
        // Corrected type from AuthResponse to AuthSessionUrlResponse
        final supabase.AuthSessionUrlResponse response =
            await SupabaseClient.instance.client.auth.getSessionFromUrl(
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
      print('DEBUG: No session or user. Navigating to WelcomeScreen.');
      return const WelcomeScreen();
    }

    // Case 2: User exists but phone is not confirmed (for phone auth)
    // Note: For phone auth, we don't need to check emailConfirmedAt
    // The user is automatically verified when they enter the OTP

    // Case 3: User exists, email confirmed. Now check user profile data.
    final userId = currentUser.id;
    try {
      final userData = await client
          .from('users')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      // Check if user is banned first
      if (userData != null && userData['banned'] == true) {
        print('DEBUG: User is banned. Logging out and navigating to WelcomeScreen.');
        await _handleBannedUser();
        return const WelcomeScreen();
      }

      if (userData == null ||
          userData['name'] == null ||
          userData['date_of_birth'] == null ||
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
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // Add the navigator key here
      theme: ThemeData(
        primaryColor: const Color(0xFF985021), // Brown color
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF985021), // Brown color
          secondary: Color(0xFF34C759), // Keeping green for success states
        ),
        scaffoldBackgroundColor: Colors.white,
        primarySwatch: MaterialColor(
          0xFF985021, // Brown color
          <int, Color>{
            50: const Color(0xFFF3E8E1),
            100: const Color(0xFFE1C5B5),
            200: const Color(0xFFCD9E84),
            300: const Color(0xFFB97753),
            400: const Color(0xFFAA5A2E),
            500: const Color(0xFF985021), // Main brown
            600: const Color(0xFF8A481D),
            700: const Color(0xFF793E19),
            800: const Color(0xFF693514),
            900: const Color(0xFF4B250D),
          },
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          selectedItemColor: const Color(0xFF985021), // Brown color
          unselectedItemColor: Colors.grey[400],
        ),
      ),
      // Use a builder to wrap the entire app navigation with CallNotificationOverlay
      builder: (context, child) {
        // Only wrap with CallNotificationOverlay if user is authenticated
        if (_session != null && _session?.user != null) {
          print('Main: Wrapping app with CallNotificationOverlay');
          return CallNotificationOverlay(
            navigatorKey: navigatorKey, // Pass the navigator key
            child: child ?? const SizedBox.shrink(),
          );
        }
        return child ?? const SizedBox.shrink();
      },
      home: _showSplash
          ? const SplashScreen()
          : _isCheckingAuth
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
                      return WelcomeScreen();
                    }

                    return snapshot.data ?? const WelcomeScreen();
                  },
                ),
    );
  }
}
