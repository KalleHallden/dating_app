import 'package:kora/pages/call_page.dart';
import 'package:kora/pages/tutorial_call_page.dart';
import 'package:flutter/material.dart';
import '../widgets/tutorial_spotlight.dart';
import '../services/tutorial_service.dart';
import '../services/tutorial_manager.dart';

class TalkPage extends StatefulWidget {
  final bool showTutorial;

  const TalkPage({super.key, this.showTutorial = false});

  @override
  State<TalkPage> createState() => _TalkPageState();
}

class _TalkPageState extends State<TalkPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Key for the button to be targeted by tutorial
  final GlobalKey _startButtonKey = GlobalKey();
  bool _showTutorialOverlay = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Show tutorial after build completes if requested
    if (widget.showTutorial) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _showTutorialOverlay = true;
        });
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Stack(
              children: [
                // Subtle top accent
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: screenHeight * 0.35,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF985021).withValues(alpha: 0.03),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),

                // Main content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),

                      // Logo
                      Hero(
                        tag: 'app_logo',
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/icon/app_icon.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Simple tagline
                      Text(
                        'Start a conversation',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[900],
                          letterSpacing: -0.5,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        'Connect with someone new through\nan authentic voice conversation',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w400,
                        ),
                      ),

                      const Spacer(flex: 3),

                      // Main action button with pulse
                      ScaleTransition(
                        key: _startButtonKey, // Key for tutorial targeting
                        scale: _pulseAnimation,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF985021)
                                    .withValues(alpha: 0.3),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Material(
                            color: const Color(0xFF985021),
                            borderRadius: BorderRadius.circular(28),
                            child: InkWell(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const CallPage()),
                                );
                              },
                              borderRadius: BorderRadius.circular(28),
                              child: Container(
                                height: 56,
                                alignment: Alignment.center,
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.mic_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Find someone to talk to',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 80),

                      // Minimalist info text
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'You\'ll be matched randomly',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),

                      const Spacer(flex: 2),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tutorial overlay
          if (_showTutorialOverlay)
            TutorialSpotlight(
              targetKey: _startButtonKey,
              title: 'Find Someone to Talk To',
              description:
                  'Tap this button to be matched with someone new for an authentic voice conversation!',
              currentStep: 1,
              totalSteps: 9,
              onNext: () async {
                // Start the tutorial flow - navigate to tutorial call page
                TutorialManager().startTutorial();
                TutorialManager().nextStep(); // Move to searching step

                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TutorialCallPage(),
                    ),
                  ).then((_) {
                    // When returning from tutorial, mark it as completed
                    TutorialService().setTutorialCompleted();
                    setState(() {
                      _showTutorialOverlay = false;
                    });
                  });
                }
              },
              onSkip: () async {
                await TutorialService().setTutorialCompleted();
                TutorialManager().skipTutorial();
                setState(() {
                  _showTutorialOverlay = false;
                });
              },
            ),
        ],
      ),
    );
  }
}
