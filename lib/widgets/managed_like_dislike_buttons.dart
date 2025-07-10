// lib/widgets/managed_like_dislike_buttons.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import '../services/like_dislike_manager.dart';
import 'managed_like_button.dart';
import 'managed_dislike_button.dart';

class ManagedLikeDislikeButtons extends StatefulWidget {
  final String targetUserId;
  final VoidCallback? onMatched;
  final double buttonSize;
  final double spacing;

  const ManagedLikeDislikeButtons({
    Key? key,
    required this.targetUserId,
    this.onMatched,
    this.buttonSize = 56,
    this.spacing = 60,
  }) : super(key: key);

  @override
  State<ManagedLikeDislikeButtons> createState() => _ManagedLikeDislikeButtonsState();
}

class _ManagedLikeDislikeButtonsState extends State<ManagedLikeDislikeButtons> {
  late final LikeDislikeManager _manager;
  supabase.RealtimeChannel? _matchChannel;
  supabase.RealtimeChannel? _matchDeleteChannel;

  @override
  void initState() {
    super.initState();
    _manager = LikeDislikeManager.forUser(widget.targetUserId);
    _subscribeToMatches();
    _subscribeToMatchRemovals();
    
    // Listen to match removal from the manager
    _manager.matchRemoved.listen((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Match removed'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _matchChannel?.unsubscribe();
    _matchDeleteChannel?.unsubscribe();
    // Don't dispose the manager here as it might be used elsewhere
    super.dispose();
  }

  void _subscribeToMatches() {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    
    if (currentUser == null) return;

    print('Setting up match subscription for user: ${currentUser.id}');

    // Subscribe to match notifications
    _matchChannel = client
        .channel('match-notifications-${currentUser.id}-${widget.targetUserId}')
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'matches',
          callback: (payload) {
            print('Match insert detected: ${payload.newRecord}');
            final match = payload.newRecord;
            final user1Id = match['user1_id'] as String?;
            final user2Id = match['user2_id'] as String?;
            
            if (user1Id == null || user2Id == null) return;
            
            // Check if this match is between current user and target user
            final involvesCurrentUser = (user1Id == currentUser.id || user2Id == currentUser.id);
            final involvesTargetUser = (user1Id == widget.targetUserId || user2Id == widget.targetUserId);
            
            if (involvesCurrentUser && involvesTargetUser) {
              print('Match confirmed! Notifying user.');
              widget.onMatched?.call();
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('It\'s a match! 🎉'),
                    duration: Duration(seconds: 3),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            }
          },
        )
        .subscribe();
  }

  void _subscribeToMatchRemovals() {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    
    if (currentUser == null) return;

    print('Setting up match removal subscription for user: ${currentUser.id}');

    // Subscribe to match deletion notifications
    _matchDeleteChannel = client
        .channel('match-delete-${currentUser.id}-${widget.targetUserId}')
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.delete,
          schema: 'public',
          table: 'matches',
          callback: (payload) {
            print('Match delete detected: ${payload.oldRecord}');
            final match = payload.oldRecord;
            final user1Id = match['user1_id'] as String?;
            final user2Id = match['user2_id'] as String?;
            
            if (user1Id == null || user2Id == null) return;
            
            // Check if this match was between current user and target user
            final involvesCurrentUser = (user1Id == currentUser.id || user2Id == currentUser.id);
            final involvesTargetUser = (user1Id == widget.targetUserId || user2Id == widget.targetUserId);
            
            if (involvesCurrentUser && involvesTargetUser) {
              print('Match removed! Notifying user.');
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Match removed'),
                    duration: Duration(seconds: 2),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.spacing, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ManagedDislikeButton(
            manager: _manager,
            size: widget.buttonSize,
            backgroundColor: Colors.white.withOpacity(0.9),
            iconColor: Colors.red,
            onDisliked: () {
              print('Disliked user: ${widget.targetUserId}');
            },
            onUndisliked: () {
              print('Undisliked user: ${widget.targetUserId}');
            },
          ),
          ManagedLikeButton(
            manager: _manager,
            size: widget.buttonSize,
            backgroundColor: Colors.white.withOpacity(0.9),
            iconColor: Colors.green,
            onLiked: () {
              print('Liked user: ${widget.targetUserId}');
            },
            onUnliked: () {
              print('Unliked user: ${widget.targetUserId}');
            },
          ),
        ],
      ),
    );
  }
}
