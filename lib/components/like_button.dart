// lib/widgets/like_button.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';

class LikeButton extends StatefulWidget {
  final String targetUserId;
  final VoidCallback? onLiked;
  final VoidCallback? onMatched;
  final double size;
  final Color backgroundColor;
  final Color iconColor;
  final bool enabled;

  const LikeButton({
    Key? key,
    required this.targetUserId,
    this.onLiked,
    this.onMatched,
    this.size = 60,
    this.backgroundColor = Colors.white,
    this.iconColor = Colors.green,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _isLiked = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _heartAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _heartAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleLike() async {
    if (!widget.enabled || _isLoading || _isLiked) return;

    // Animate button press
    await _animationController.forward();
    _animationController.reverse();

    setState(() {
      _isLoading = true;
    });

    try {
      final client = SupabaseClient.instance.client;
      final currentUser = client.auth.currentUser;
      
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Insert like into database
      await client.from('likes').insert({
        'liker_id': currentUser.id,
        'liked_id': widget.targetUserId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Check if it's a match (the other person already liked us)
      final matchCheck = await client
          .from('likes')
          .select()
          .eq('liker_id', widget.targetUserId)
          .eq('liked_id', currentUser.id)
          .maybeSingle();

      setState(() {
        _isLiked = true;
      });

      if (matchCheck != null) {
        // It's a match!
        widget.onMatched?.call();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('It\'s a match! 🎉'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Just a regular like
        widget.onLiked?.call();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Liked!'),
              duration: Duration(seconds: 1),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('Error creating like: $e');
      
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.backgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleLike,
            customBorder: const CircleBorder(),
            child: Center(
              child: _isLoading
                  ? SizedBox(
                      width: widget.size * 0.4,
                      height: widget.size * 0.4,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(widget.iconColor),
                      ),
                    )
                  : AnimatedBuilder(
                      animation: _heartAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _isLiked ? _heartAnimation.value : 1.0,
                          child: Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked ? widget.iconColor : widget.iconColor,
                            size: widget.size * 0.5,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
