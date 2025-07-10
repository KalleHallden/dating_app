// lib/widgets/dislike_button.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';

class DislikeButton extends StatefulWidget {
  final String targetUserId;
  final VoidCallback? onDisliked;
  final VoidCallback? onUndisliked;
  final double size;
  final Color backgroundColor;
  final Color iconColor;
  final bool enabled;

  const DislikeButton({
    Key? key,
    required this.targetUserId,
    this.onDisliked,
    this.onUndisliked,
    this.size = 60,
    this.backgroundColor = Colors.white,
    this.iconColor = Colors.red,
    this.enabled = true,
  }) : super(key: key);

  @override
  State<DislikeButton> createState() => _DislikeButtonState();
}

class _DislikeButtonState extends State<DislikeButton> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _isDisliked = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  supabase.RealtimeChannel? _dislikesChannel;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.9,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _checkExistingDislike();
    _subscribeToDislikesChanges();
  }

  @override
  void dispose() {
    _dislikesChannel?.unsubscribe();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingDislike() async {
    try {
      final client = SupabaseClient.instance.client;
      final currentUser = client.auth.currentUser;
      
      if (currentUser == null) return;

      final existingDislike = await client
          .from('dislikes')
          .select()
          .eq('disliker_id', currentUser.id)
          .eq('disliked_id', widget.targetUserId)
          .maybeSingle();

      if (mounted && existingDislike != null) {
        setState(() {
          _isDisliked = true;
        });
      }
    } catch (e) {
      print('Error checking existing dislike: $e');
    }
  }

  void _subscribeToDislikesChanges() {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    
    if (currentUser == null) return;

    // Subscribe to changes in dislikes table for this user-target pair
    _dislikesChannel = client
        .channel('dislikes-changes-${currentUser.id}-${widget.targetUserId}')
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.delete,
          schema: 'public',
          table: 'dislikes',
          callback: (payload) {
            // When a dislike is deleted, check if it was ours
            final oldRecord = payload.oldRecord;
            if (oldRecord['disliker_id'] == currentUser.id && 
                oldRecord['disliked_id'] == widget.targetUserId) {
              if (mounted) {
                setState(() {
                  _isDisliked = false;
                });
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _handleDislike() async {
    if (!widget.enabled || _isLoading) return;

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

      if (_isDisliked) {
        // Un-dislike - remove the dislike
        await client
            .from('dislikes')
            .delete()
            .eq('disliker_id', currentUser.id)
            .eq('disliked_id', widget.targetUserId);

        setState(() {
          _isDisliked = false;
        });

        widget.onUndisliked?.call();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Dislike removed'),
              duration: Duration(seconds: 1),
              backgroundColor: Colors.grey,
            ),
          );
        }
      } else {
        // Dislike - first remove any existing like
        await client
            .from('likes')
            .delete()
            .eq('liker_id', currentUser.id)
            .eq('liked_id', widget.targetUserId);

        // Then insert the dislike
        await client.from('dislikes').insert({
          'disliker_id': currentUser.id,
          'disliked_id': widget.targetUserId,
          'created_at': DateTime.now().toIso8601String(),
        });

        setState(() {
          _isDisliked = true;
        });

        widget.onDisliked?.call();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Disliked'),
              duration: Duration(seconds: 1),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Error handling dislike: $e');
      
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
            onTap: _handleDislike,
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
                  : Icon(
                      Icons.close,
                      color: _isDisliked ? widget.iconColor : widget.iconColor.withOpacity(0.6),
                      size: widget.size * 0.5,
                      weight: _isDisliked ? 700 : 400,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
