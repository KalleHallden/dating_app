// lib/widgets/like_dislike_buttons.dart
import 'package:flutter/material.dart';
import 'like_button.dart';
import 'dislike_button.dart';

class LikeDislikeButtons extends StatefulWidget {
  final String targetUserId;
  final VoidCallback? onMatched;
  final double buttonSize;
  final double spacing;

  const LikeDislikeButtons({
    Key? key,
    required this.targetUserId,
    this.onMatched,
    this.buttonSize = 56,
    this.spacing = 60,
  }) : super(key: key);

  @override
  State<LikeDislikeButtons> createState() => _LikeDislikeButtonsState();
}

class _LikeDislikeButtonsState extends State<LikeDislikeButtons> {
  // State tracking is handled internally by each button
  // They will automatically sync through the database

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.spacing, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          DislikeButton(
            targetUserId: widget.targetUserId,
            size: widget.buttonSize,
            backgroundColor: Colors.white.withOpacity(0.9),
            iconColor: Colors.red,
            onDisliked: () {
              print('Disliked user: ${widget.targetUserId}');
              // The dislike button already handles removing likes internally
            },
            onUndisliked: () {
              print('Undisliked user: ${widget.targetUserId}');
            },
          ),
          LikeButton(
            targetUserId: widget.targetUserId,
            size: widget.buttonSize,
            backgroundColor: Colors.white.withOpacity(0.9),
            iconColor: Colors.green,
            onLiked: () {
              print('Liked user: ${widget.targetUserId}');
              // The like button already handles removing dislikes internally
            },
            onUnliked: () {
              print('Unliked user: ${widget.targetUserId}');
            },
            onMatched: () {
              print('Matched with user: ${widget.targetUserId}');
              widget.onMatched?.call();
            },
          ),
        ],
      ),
    );
  }
}
