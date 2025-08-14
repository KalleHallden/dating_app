import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoFadeController;
  late AnimationController _textPopController;
  late Animation<double> _logoFadeAnimation;
  late Animation<double> _textScaleAnimation;
  late Animation<double> _textFadeAnimation;

  @override
  void initState() {
    super.initState();

    // Logo fade-in animation
    _logoFadeController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _logoFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoFadeController,
      curve: Curves.easeIn,
    ));

    // Text pop-up animation
    _textPopController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _textScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textPopController,
      curve: Curves.elasticOut,
    ));

    _textFadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _textPopController,
      curve: Curves.easeIn,
    ));

    // Start animations sequence
    _startAnimationSequence();
  }

  void _startAnimationSequence() async {
    // Start logo fade-in
    await _logoFadeController.forward();

    // Small delay before text appears
    await Future.delayed(const Duration(milliseconds: 300));

    // Start text pop-up
    await _textPopController.forward();

    // Wait a bit before navigating away
    await Future.delayed(const Duration(seconds: 2));

    // Navigate to next screen
    if (mounted) {
      _navigateToNextScreen();
    }
  }

  void _navigateToNextScreen() {
    // This will be called from main.dart
    // We'll pass a callback for navigation
  }

  @override
  void dispose() {
    _logoFadeController.dispose();
    _textPopController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo with fade-in animation
            FadeTransition(
              opacity: _logoFadeAnimation,
              child: Image.asset(
                'assets/icon/hq_foreground.png',
                width: 200,
                height: 200,
              ),
            ),
            const SizedBox(height: 40),
            // Text with pop-up animation
            AnimatedBuilder(
              animation: _textPopController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _textScaleAnimation.value,
                  child: FadeTransition(
                    opacity: _textFadeAnimation,
                    child: Text(
                      'Welcome to ...',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF985021),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
