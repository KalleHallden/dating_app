// lib/widgets/tutorial_spotlight.dart
import 'package:flutter/material.dart';

class TutorialSpotlight extends StatefulWidget {
  final GlobalKey targetKey;
  final String title;
  final String description;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool showSkip;
  final int currentStep;
  final int totalSteps;

  const TutorialSpotlight({
    super.key,
    required this.targetKey,
    required this.title,
    required this.description,
    required this.onNext,
    required this.onSkip,
    this.showSkip = true,
    this.currentStep = 1,
    this.totalSteps = 1,
  });

  @override
  State<TutorialSpotlight> createState() => _TutorialSpotlightState();
}

class _TutorialSpotlightState extends State<TutorialSpotlight>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  Rect? _targetRect;

  @override
  void initState() {
    super.initState();

    // Separate controller for one-time fade in
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Separate controller for continuous pulse
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Fade in once and stay at 1.0
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeOut,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeOutBack,
      ),
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    // Start fade in animation once
    _fadeController.forward();

    // Start continuous pulse animation - repeat indefinitely
    _pulseController.repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateTargetRect();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _calculateTargetRect() {
    final RenderBox? renderBox =
        widget.targetKey.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox != null) {
      final size = renderBox.size;
      final position = renderBox.localToGlobal(Offset.zero);

      setState(() {
        _targetRect = Rect.fromLTWH(
          position.dx,
          position.dy,
          size.width,
          size.height,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_targetRect == null) {
      return const SizedBox.shrink();
    }

    final screenSize = MediaQuery.of(context).size;

    // Determine if target is in top half of screen - if so, position tooltip below
    final isTargetInTopHalf = _targetRect!.top < screenSize.height / 2;

    // Calculate popup position - leave more space for arrow
    // For step 2 (searching), use less spacing since there's no arrow
    final double arrowSpacing = widget.currentStep == 2 ? 20 : 100;
    final double popupTopPosition = isTargetInTopHalf ? _targetRect!.bottom + arrowSpacing : 0;
    final double popupBottomPosition = isTargetInTopHalf ? 0 : screenSize.height - _targetRect!.top + arrowSpacing;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Arrow pointing from popup area to target (skip for step 2 - searching)
            if (widget.currentStep != 2)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: ArrowPainter(
                          targetRect: _targetRect!,
                          isTargetInTopHalf: isTargetInTopHalf,
                          popupTopPosition: popupTopPosition,
                          popupBottomPosition: popupBottomPosition,
                          screenHeight: screenSize.height,
                          currentStep: widget.currentStep,
                          animationValue: _pulseAnimation.value,
                        ),
                      );
                    },
                  ),
                ),
              ),

            // Tooltip - positioned with extra space for arrow
            Positioned(
              left: 24,
              right: 24,
              top: isTargetInTopHalf ? popupTopPosition : null,
              bottom: isTargetInTopHalf ? null : popupBottomPosition,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Progress indicator with X button
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: List.generate(
                                widget.totalSteps,
                                (index) => Expanded(
                                  child: Container(
                                    height: 3,
                                    margin: const EdgeInsets.symmetric(horizontal: 2),
                                    decoration: BoxDecoration(
                                      color: index < widget.currentStep
                                          ? const Color(0xFF985021)
                                          : Colors.grey.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${widget.currentStep}/${widget.totalSteps}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.showSkip) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: widget.onSkip,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  size: 20,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Title
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[900],
                          letterSpacing: -0.5,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Description
                      Text(
                        widget.description,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Colors.grey[700],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Next button
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton(
                          onPressed: widget.onNext,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF985021),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            widget.currentStep == widget.totalSteps
                                ? 'Got it!'
                                : 'Next',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ArrowPainter extends CustomPainter {
  final Rect targetRect;
  final bool isTargetInTopHalf;
  final double popupTopPosition;
  final double popupBottomPosition;
  final double screenHeight;
  final int currentStep;
  final double animationValue;

  ArrowPainter({
    required this.targetRect,
    required this.isTargetInTopHalf,
    required this.popupTopPosition,
    required this.popupBottomPosition,
    required this.screenHeight,
    required this.currentStep,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Use brown for steps 1-2, white for rest
    final arrowColor = currentStep <= 2 ? const Color(0xFF985021) : Colors.white;

    // Smooth breathing animation with easing
    // Opacity fades between 0.4 and 0.9 for a gentle pulse
    final opacity = 0.4 + (animationValue * 0.5);

    final fillPaint = Paint()
      ..color = arrowColor.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    // Fixed size for cleaner look
    final double triangleSize = 11.0;
    final double spacing = 5.0;

    // Animate position to create movement toward target
    // Move 8 pixels toward target during animation
    final double movementOffset = animationValue * 8.0;

    if (isTargetInTopHalf) {
      // Target is at top, popup is below
      // Position double triangles between popup and target, pointing UP
      final arrowX = targetRect.center.dx;
      // Position in the middle of the gap between target and popup
      final gapMiddleY = targetRect.bottom + ((popupTopPosition - targetRect.bottom) / 2);

      // Apply movement - move UP toward target as animation progresses
      final animatedY = gapMiddleY + movementOffset;

      // First triangle (closer to target)
      final triangle1Path = Path();
      triangle1Path.moveTo(arrowX, animatedY - spacing - triangleSize * 2); // top point
      triangle1Path.lineTo(arrowX - triangleSize, animatedY - spacing - triangleSize); // bottom left
      triangle1Path.lineTo(arrowX + triangleSize, animatedY - spacing - triangleSize); // bottom right
      triangle1Path.close();
      canvas.drawPath(triangle1Path, fillPaint);

      // Second triangle (further from target)
      final triangle2Path = Path();
      triangle2Path.moveTo(arrowX, animatedY - spacing); // top point
      triangle2Path.lineTo(arrowX - triangleSize, animatedY - spacing + triangleSize); // bottom left
      triangle2Path.lineTo(arrowX + triangleSize, animatedY - spacing + triangleSize); // bottom right
      triangle2Path.close();
      canvas.drawPath(triangle2Path, fillPaint);
    } else {
      // Target is at bottom, popup is above
      // Position double triangles between popup and target, pointing DOWN
      final arrowX = targetRect.center.dx;
      // Position in the middle of the gap between popup and target
      final gapMiddleY = targetRect.top - ((targetRect.top - (screenHeight - popupBottomPosition)) / 2);

      // Apply movement - move DOWN toward target as animation progresses
      final animatedY = gapMiddleY - movementOffset;

      // First triangle (closer to target)
      final triangle1Path = Path();
      triangle1Path.moveTo(arrowX, animatedY + spacing + triangleSize * 2); // bottom point
      triangle1Path.lineTo(arrowX - triangleSize, animatedY + spacing + triangleSize); // top left
      triangle1Path.lineTo(arrowX + triangleSize, animatedY + spacing + triangleSize); // top right
      triangle1Path.close();
      canvas.drawPath(triangle1Path, fillPaint);

      // Second triangle (further from target)
      final triangle2Path = Path();
      triangle2Path.moveTo(arrowX, animatedY + spacing); // bottom point
      triangle2Path.lineTo(arrowX - triangleSize, animatedY + spacing - triangleSize); // top left
      triangle2Path.lineTo(arrowX + triangleSize, animatedY + spacing - triangleSize); // top right
      triangle2Path.close();
      canvas.drawPath(triangle2Path, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ArrowPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
           oldDelegate.isTargetInTopHalf != isTargetInTopHalf ||
           oldDelegate.popupTopPosition != popupTopPosition ||
           oldDelegate.popupBottomPosition != popupBottomPosition ||
           oldDelegate.animationValue != animationValue;
  }
}
