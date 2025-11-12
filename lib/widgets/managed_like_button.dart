// lib/widgets/managed_like_button.dart
import 'package:flutter/material.dart';
import '../services/like_dislike_manager.dart';

class ManagedLikeButton extends StatefulWidget {
  final LikeDislikeManager manager;
  final VoidCallback? onLiked;
  final VoidCallback? onUnliked;
  final double size;
  final Color backgroundColor;
  final Color iconColor;

  const ManagedLikeButton({
    Key? key,
    required this.manager,
    this.onLiked,
    this.onUnliked,
    this.size = 56,
    this.backgroundColor = Colors.white,
    this.iconColor = Colors.green,
  }) : super(key: key);

  @override
  State<ManagedLikeButton> createState() => _ManagedLikeButtonState();
}

class _ManagedLikeButtonState extends State<ManagedLikeButton> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isLoading = false;

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
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_isLoading) return;

    await _animationController.forward();
    _animationController.reverse();

    setState(() => _isLoading = true);

    try {
      final wasLiked = widget.manager.isLiked;
      final isNowLiked = await widget.manager.toggleLike();
      
      if (isNowLiked && !wasLiked) {
        widget.onLiked?.call();
      } else if (!isNowLiked && wasLiked) {
        widget.onUnliked?.call();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Like removed'),
              duration: Duration(seconds: 1),
              backgroundColor: Colors.grey,
            ),
          );
        }
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
      stream: widget.manager.likeState,
      initialData: widget.manager.isLiked,
      builder: (context, snapshot) {
        final isLiked = snapshot.data ?? false;
        
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
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          color: widget.iconColor,
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
