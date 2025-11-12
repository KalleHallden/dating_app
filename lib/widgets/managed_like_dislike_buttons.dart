// lib/widgets/managed_like_dislike_buttons.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import '../services/like_dislike_manager.dart';
import 'managed_like_button.dart';
import 'managed_dislike_button.dart';
import 'match_celebration_popup.dart';

class ManagedLikeDislikeButtons extends StatefulWidget {
  final String targetUserId;
  final VoidCallback? onMatched;
  final VoidCallback? onNextPressed;
  final double buttonSize;
  final double spacing;

  const ManagedLikeDislikeButtons({
    Key? key,
    required this.targetUserId,
    this.onMatched,
    this.onNextPressed,
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
  bool _isInitialized = false;
  String? _currentUserName;
  String? _currentUserProfilePicture;
  String? _matchedUserName;
  String? _matchedUserProfilePicture;

  @override
  void initState() {
    super.initState();
    _initializeManager();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final client = SupabaseClient.instance.client;
      final currentUser = client.auth.currentUser;

      if (currentUser == null) return;

      // Load current user data
      final currentUserData = await client
          .from('users')
          .select('name, profile_picture_url')
          .eq('user_id', currentUser.id)
          .single();

      // Load matched user data
      final matchedUserData = await client
          .from('users')
          .select('name, profile_picture_url')
          .eq('user_id', widget.targetUserId)
          .single();

      if (mounted) {
        setState(() {
          _currentUserName = currentUserData['name'];
          _currentUserProfilePicture = currentUserData['profile_picture_url'];
          _matchedUserName = matchedUserData['name'];
          _matchedUserProfilePicture = matchedUserData['profile_picture_url'];
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }
  
  Future<void> _initializeManager() async {
    // Clear any existing cache for this user first
    LikeDislikeManager.clearCacheForUser(widget.targetUserId);
    
    // Create a fresh manager instance
    _manager = LikeDislikeManager.forUser(widget.targetUserId);
    
    // Force refresh the state to ensure we have the latest data
    await _manager.refreshState();
    
    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
    
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
  void didUpdateWidget(ManagedLikeDislikeButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the target user changed, reinitialize
    if (oldWidget.targetUserId != widget.targetUserId) {
      _reinitialize();
    }
  }
  
  Future<void> _reinitialize() async {
    // Unsubscribe from old channels
    _matchChannel?.unsubscribe();
    _matchDeleteChannel?.unsubscribe();
    
    // Clear old manager cache
    LikeDislikeManager.clearCacheForUser(widget.targetUserId);
    
    // Reinitialize with new user
    setState(() {
      _isInitialized = false;
    });
    
    await _initializeManager();
  }

  @override
  void dispose() {
    _matchChannel?.unsubscribe();
    _matchDeleteChannel?.unsubscribe();
    // Clear the cache when disposing
    LikeDislikeManager.clearCacheForUser(widget.targetUserId);
    super.dispose();
  }

  void _subscribeToMatches() {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    
    if (currentUser == null) return;

    print('Setting up match subscription for user: ${currentUser.id}');

    // Subscribe to match notifications with unique channel name
    _matchChannel = client
        .channel('match-notifications-${currentUser.id}-${widget.targetUserId}-${DateTime.now().millisecondsSinceEpoch}')
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
                _showMatchCelebration();
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

    // Subscribe to match deletion notifications with unique channel name
    _matchDeleteChannel = client
        .channel('match-delete-${currentUser.id}-${widget.targetUserId}-${DateTime.now().millisecondsSinceEpoch}')
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
              
              // Refresh the manager state
              _manager.refreshState();
              
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

  Future<void> _showMatchCelebration() async {
    // Ensure we have user data
    if (_currentUserName == null || _matchedUserName == null) {
      return;
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: '',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {
        return MatchCelebrationPopup(
          currentUserName: _currentUserName!,
          matchedUserName: _matchedUserName!,
          currentUserProfilePicture: _currentUserProfilePicture,
          matchedUserProfilePicture: _matchedUserProfilePicture,
          onDismiss: () => Navigator.of(context).pop(),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      // Show loading state while initializing
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.spacing, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: widget.buttonSize,
              height: widget.buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.9),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            Container(
              width: widget.buttonSize,
              height: widget.buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.9),
              ),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.spacing, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
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
            onNextPressed: widget.onNextPressed,
            showConfirmDialog: true,
          ),
        ],
      ),
    );
  }
}
