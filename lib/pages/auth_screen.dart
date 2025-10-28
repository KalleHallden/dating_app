import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/signup_provider.dart';
import 'signup_screen.dart';
import 'call_page.dart';
import '../services/supabase_client.dart'; // Import SupabaseClient

class AuthScreen extends StatefulWidget {
  final String? initialMessage; // Optional message to display
  const AuthScreen({this.initialMessage, super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialMessage != null) {
      _errorMessage = widget.initialMessage;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter email and password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = SupabaseClient.instance.client;
      final response = await client.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        emailRedirectTo:
            'io.supabase.flutterquickstart://login-callback/', // Important for deep linking
      );

      // If email confirmation is enabled, a session won't be immediately available.
      // Supabase will send a verification email.
      if (response.user != null && response.user!.emailConfirmedAt == null) {
        setState(() {
          _errorMessage =
              'Registration successful! Please check your email to confirm your account.';
        });
        // Do NOT navigate immediately to SignupScreen or CallPage here.
        // User needs to confirm email first.
      } else if (response.user != null) {
        // If email confirmation is NOT required, or if user is automatically signed in
        // (e.g., via magic link if configured for it and the user is on the same device)
        // or if there's an immediate session for some other reason.
        // This part is less common for a direct email/password sign-up without confirmation.
        // But if a session *is* immediately established, proceed.
        if (mounted) {
          // Check if user has completed profile data
          final user = SupabaseClient.instance.client.auth.currentUser;
          if (user != null) {
            final userData = await client
                .from('users')
                .select()
                .eq('user_id', user.id)
                .maybeSingle();

            if (userData == null ||
                userData['name'] == null ||
                userData['date_of_birth'] == null ||
                userData['gender'] == null ||
                userData['gender_preference'] == null ||
                userData['location'] == null ||
                userData['about_me'] == null) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const SignupScreen()),
              );
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const CallPage()),
              );
            }
          }
        }
      } else {
        // This case generally implies a problem if response.user is null but no AuthException was thrown.
        throw Exception('Sign-up failed unexpectedly.');
      }
    } on supabase.AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signIn() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter email and password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = SupabaseClient.instance.client;
      final response = await client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (response.user == null) {
        throw Exception('Sign-in failed: No user found.');
      }

      if (mounted) {
        // Check if user has completed profile data
        final user = SupabaseClient.instance.client.auth.currentUser;
        if (user != null) {
          final userData = await client
              .from('users')
              .select()
              .eq('user_id', user.id)
              .maybeSingle();

          if (userData == null ||
              userData['name'] == null ||
              userData['date_of_birth'] == null ||
              userData['gender'] == null ||
              userData['gender_preference'] == null ||
              userData['location'] == null ||
              userData['about_me'] == null) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const SignupScreen()),
            );
          } else {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const CallPage()),
            );
          }
        }
      }
    } on supabase.AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Authentication')), // Changed title
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _signUp,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Sign Up'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isLoading ? null : _signIn,
              child: const Text('Already have an account? Sign In'),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  children: [
                    const TextSpan(
                      text: 'By tapping Sign In or Create Account, you agree to our ',
                    ),
                    TextSpan(
                      text: 'Terms of Service',
                      style: const TextStyle(
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _launchUrl('https://kalletech.com/terms-of-service/'),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: const TextStyle(
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _launchUrl('https://kalletech.com/privacy-policy/'),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
