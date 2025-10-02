// lib/widgets/managed_dislike_button.dart
import 'package:flutter/material.dart';
import '../services/like_dislike_manager.dart';

class ManagedDislikeButton extends StatefulWidget {
  final LikeDislikeManager manager;
  final VoidCallback? onDisliked;
  final VoidCallback? onUndisliked;
  final VoidCallback? onNextPressed;
  final bool showConfirmDialog;
  final double size;
  final Color backgroundColor;
  final Color iconColor;

  const ManagedDislikeButton({
    Key? key,
    required this.manager,
    this.onDisliked,
    this.onUndisliked,
    this.onNextPressed,
    this.showConfirmDialog = true,
    this.size = 56,
    this.backgroundColor = Colors.white,
    this.iconColor = Colors.red,
  }) : super(key: key);

  @override
  State<ManagedDislikeButton> createState() => _ManagedDislikeButtonState();
}

class _ManagedDislikeButtonState extends State<ManagedDislikeButton> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isLoading = false;

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
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_isLoading) return;

    // If confirmation dialog is enabled, show it first
    if (widget.showConfirmDialog && widget.onNextPressed != null) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Skip Conversation?'),
            content: const Text('Are you sure you want to skip this conversation?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
                child: const Text('Skip'),
              ),
            ],
          );
        },
      );

      if (shouldProceed != true) return;
    }

    await _animationController.forward();
    _animationController.reverse();

    setState(() => _isLoading = true);

    try {
      // Only add dislike if there's no existing like
      // When skipping, preserve existing likes
      if (!widget.manager.isDisliked && !widget.manager.isLiked) {
        await widget.manager.toggleDislike();
        widget.onDisliked?.call();
      }

      // Call the next handler if provided (skip to next person)
      if (widget.onNextPressed != null) {
        widget.onNextPressed!();
      }
    } catch (e) {
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
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: widget.manager.dislikeState,
      initialData: widget.manager.isDisliked,
      builder: (context, snapshot) {
        final isDisliked = snapshot.data ?? false;
        
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
                onTap: _handleTap,
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
                          Icons.fast_forward,
                          color: widget.iconColor.withOpacity(0.8),
                          size: widget.size * 0.5,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
