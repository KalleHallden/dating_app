// lib/widgets/call_restriction_button.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';

class CallRestrictionButton extends StatefulWidget {
  final String currentUserId;
  final String matchedUserId;
  final bool isOnline;
  final bool isAvailable;
  final VoidCallback onCallInitiated;
  
  const CallRestrictionButton({
    Key? key,
    required this.currentUserId,
    required this.matchedUserId,
    required this.isOnline,
    required this.isAvailable,
    required this.onCallInitiated,
  }) : super(key: key);

  @override
  State<CallRestrictionButton> createState() => _CallRestrictionButtonState();
}

class _CallRestrictionButtonState extends State<CallRestrictionButton> with SingleTickerProviderStateMixin {
  DateTime? _restrictedUntil;
  Timer? _updateTimer;
  bool _isLoading = true;
  supabase.RealtimeChannel? _restrictionChannel;
  
  // Animation for the pulse effect when available
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimation();
    _checkRestriction();
    _subscribeToRestrictionUpdates();
    _startUpdateTimer();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _restrictionChannel?.unsubscribe();
    _pulseController.dispose();
    super.dispose();
  }

  void _initializeAnimation() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  void _startUpdateTimer() {
    // Update every second for smooth countdown
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_restrictedUntil != null && DateTime.now().isBefore(_restrictedUntil!)) {
        setState(() {
          // Just trigger a rebuild to update the progress
        });
      } else if (_restrictedUntil != null && DateTime.now().isAfter(_restrictedUntil!)) {
        // Restriction expired
        setState(() {
          _restrictedUntil = null;
        });
        _checkRestriction(); // Re-check in case there's a new restriction
      }
    });
  }

  Future<void> _checkRestriction() async {
    try {
      final client = SupabaseClient.instance.client;
      
      // Query for active restrictions between these two users
      // Check both directions (user1->user2 and user2->user1)
      final now = DateTime.now().toIso8601String();
      
      final response = await client
          .from('call_restrictions')
          .select()
          .or('and(user1_id.eq.${widget.currentUserId},user2_id.eq.${widget.matchedUserId}),and(user1_id.eq.${widget.matchedUserId},user2_id.eq.${widget.currentUserId})')
          .gt('restricted_until', now)
          .order('restricted_until', ascending: false)
          .limit(1)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (response != null && response['restricted_until'] != null) {
            _restrictedUntil = DateTime.parse(response['restricted_until']);
            // Stop pulse animation when restricted
            _pulseController.stop();
          } else {
            _restrictedUntil = null;
            // Start pulse animation when available
            if (widget.isOnline && widget.isAvailable) {
              _pulseController.repeat(reverse: true);
            }
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error checking call restriction: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _subscribeToRestrictionUpdates() {
    final client = SupabaseClient.instance.client;
    
    // Create a unique channel name
    final channelName = 'call-restrictions-${widget.currentUserId}-${widget.matchedUserId}-${DateTime.now().millisecondsSinceEpoch}';
    
    _restrictionChannel = client
        .channel(channelName)
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.all,
          schema: 'public',
          table: 'call_restrictions',
          callback: (payload) {
            // Check if this restriction involves our users
            final data = payload.eventType == supabase.PostgresChangeEvent.delete
                ? payload.oldRecord
                : payload.newRecord;
            
            final user1Id = data['user1_id'];
            final user2Id = data['user2_id'];
            
            final involvesUsers = 
                (user1Id == widget.currentUserId && user2Id == widget.matchedUserId) ||
                (user1Id == widget.matchedUserId && user2Id == widget.currentUserId);
            
            if (involvesUsers) {
              _checkRestriction();
            }
          },
        )
        .subscribe();
  }

  double _calculateProgress() {
    if (_restrictedUntil == null) return 1.0;
    
    final now = DateTime.now();
    if (now.isAfter(_restrictedUntil!)) return 1.0;
    
    // Calculate total restriction duration (24 hours)
    final restrictionStart = _restrictedUntil!.subtract(const Duration(hours: 24));
    final totalDuration = _restrictedUntil!.difference(restrictionStart).inSeconds;
    final remainingDuration = _restrictedUntil!.difference(now).inSeconds;
    
    // Progress from 0 (fully restricted) to 1 (no restriction)
    final progress = 1.0 - (remainingDuration / totalDuration);
    return progress.clamp(0.0, 1.0);
  }

  String _formatTimeRemaining() {
    if (_restrictedUntil == null) return '';
    
    final now = DateTime.now();
    if (now.isAfter(_restrictedUntil!)) return '';
    
    final difference = _restrictedUntil!.difference(now);
    
    if (difference.inHours > 0) {
      final hours = difference.inHours;
      final minutes = difference.inMinutes % 60;
      return '${hours}h ${minutes}m';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return '${difference.inSeconds}s';
    }
  }

  bool get _isRestricted => _restrictedUntil != null && DateTime.now().isBefore(_restrictedUntil!);
  bool get _canCall => !_isRestricted && widget.isOnline && widget.isAvailable;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _canCall ? widget.onCallInitiated : null,
      child: Tooltip(
        message: _isRestricted 
            ? 'Can call again in ${_formatTimeRemaining()}'
            : !widget.isOnline 
                ? 'User is offline'
                : !widget.isAvailable
                    ? 'User is not available'
                    : 'Call user',
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Base phone icon
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _canCall ? _pulseAnimation.value : 1.0,
                    child: Icon(
                      Icons.phone,
                      size: 24,
                      color: _canCall 
                          ? Colors.green 
                          : (_isRestricted ? Colors.grey.shade400 : Colors.grey),
                    ),
                  );
                },
              ),
              
              // Restriction overlay with pizza slice effect
              if (_isRestricted)
                CustomPaint(
                  size: const Size(48, 48),
                  painter: RestrictionOverlayPainter(
                    progress: _calculateProgress(),
                    color: Colors.grey.withOpacity(0.5),
                  ),
                ),
              
              // Time remaining text (shown on hover or long press)
              if (_isRestricted && _formatTimeRemaining().isNotEmpty)
                Positioned(
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatTimeRemaining(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom painter for the pizza slice effect
class RestrictionOverlayPainter extends CustomPainter {
  final double progress;
  final Color color;

  RestrictionOverlayPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Calculate the sweep angle (full circle minus progress)
    // Progress: 0 = full overlay, 1 = no overlay
    final sweepAngle = 2 * math.pi * (1 - progress);
    
    if (sweepAngle > 0) {
      // Draw the pizza slice starting from top (-90 degrees)
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx, center.dy - radius)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          -math.pi / 2, // Start from top
          sweepAngle,
          false,
        )
        ..close();
      
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(RestrictionOverlayPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
