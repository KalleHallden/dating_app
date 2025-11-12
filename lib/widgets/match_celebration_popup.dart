import 'package:flutter/material.dart';
import 'dart:math' as math;

class MatchCelebrationPopup extends StatefulWidget {
  final String currentUserName;
  final String matchedUserName;
  final String? currentUserProfilePicture;
  final String? matchedUserProfilePicture;
  final VoidCallback onDismiss;

  const MatchCelebrationPopup({
    super.key,
    required this.currentUserName,
    required this.matchedUserName,
    this.currentUserProfilePicture,
    this.matchedUserProfilePicture,
    required this.onDismiss,
  });

  @override
  State<MatchCelebrationPopup> createState() => _MatchCelebrationPopupState();
}

class _MatchCelebrationPopupState extends State<MatchCelebrationPopup>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _scaleController.forward();
    _fadeController.forward();

    // Auto-dismiss after 60 seconds
    Future.delayed(const Duration(seconds: 60), () {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF985021).withValues(alpha: 0.95),
              const Color(0xFFD4773C).withValues(alpha: 0.95),
            ],
          ),
        ),
        child: Stack(
          children: [
            // Animated hearts background
            ...List.generate(20, (index) => _buildFloatingHeart(index)),

            // Main content
            SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 1),

                  // "It's a Match!" text
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: const Text(
                      "It's a Match!",
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Subtitle
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      "You and ${widget.matchedUserName} liked each other!",
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const SizedBox(height: 60),

                  // Profile pictures
                  ScaleTransition(
                    scale: _scaleAnimation,
                    child: SizedBox(
                      height: 200,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Current user picture (left)
                          Positioned(
                            left: MediaQuery.of(context).size.width * 0.2,
                            child: _buildProfilePicture(
                              widget.currentUserProfilePicture,
                              widget.currentUserName,
                              true,
                            ),
                          ),

                          // Matched user picture (right)
                          Positioned(
                            right: MediaQuery.of(context).size.width * 0.2,
                            child: _buildProfilePicture(
                              widget.matchedUserProfilePicture,
                              widget.matchedUserName,
                              false,
                            ),
                          ),

                          // App logo in the middle
                          Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: ClipOval(
                                  child: Image.asset(
                                    'assets/icon/app_icon.png',
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(flex: 1),

                  // Action button
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: widget.onDismiss,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF985021),
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: const Text(
                            'Return to Call',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilePicture(String? imageUrl, String name, bool isLeft) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: imageUrl != null && imageUrl.isNotEmpty
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildPlaceholder(name);
                },
              )
            : _buildPlaceholder(name),
      ),
    );
  }

  Widget _buildPlaceholder(String name) {
    return Container(
      color: Colors.grey[300],
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingHeart(int index) {
    final random = math.Random(index);
    final startX = random.nextDouble();
    final duration = 3 + random.nextDouble() * 4;
    final size = 20.0 + random.nextDouble() * 30;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: (duration * 1000).toInt()),
      builder: (context, value, child) {
        return Positioned(
          left: MediaQuery.of(context).size.width * startX,
          bottom: -50 + (MediaQuery.of(context).size.height * value),
          child: Opacity(
            opacity: (1 - value) * 0.6,
            child: Icon(
              Icons.favorite,
              color: Colors.white,
              size: size,
            ),
          ),
        );
      },
      onEnd: () {
        if (mounted) {
          setState(() {}); // Restart animation
        }
      },
    );
  }
}
