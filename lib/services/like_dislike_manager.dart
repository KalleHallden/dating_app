// lib/services/like_dislike_manager.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'supabase_client.dart';

class LikeDislikeManager {
  static final Map<String, LikeDislikeManager> _instances = {};
  
  final String targetUserId;
  final _likeStateController = StreamController<bool>.broadcast();
  final _dislikeStateController = StreamController<bool>.broadcast();
  
  Stream<bool> get likeState => _likeStateController.stream;
  Stream<bool> get dislikeState => _dislikeStateController.stream;
  
  final _matchRemovedController = StreamController<void>.broadcast();
  Stream<void> get matchRemoved => _matchRemovedController.stream;
  
  bool _isLiked = false;
  bool _isDisliked = false;
  
  bool get isLiked => _isLiked;
  bool get isDisliked => _isDisliked;
  
  // Factory constructor to ensure single instance per target user
  factory LikeDislikeManager.forUser(String targetUserId) {
    return _instances.putIfAbsent(
      targetUserId,
      () => LikeDislikeManager._(targetUserId),
    );
  }
  
  LikeDislikeManager._(this.targetUserId) {
    _initialize();
  }
  
  Future<void> _initialize() async {
    await _checkInitialStates();
  }
  
  Future<void> _checkInitialStates() async {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    if (currentUser == null) return;
    
    // Check for existing like
    final existingLike = await client
        .from('likes')
        .select()
        .eq('liker_id', currentUser.id)
        .eq('liked_id', targetUserId)
        .maybeSingle();
    
    // Check for existing dislike
    final existingDislike = await client
        .from('dislikes')
        .select()
        .eq('disliker_id', currentUser.id)
        .eq('disliked_id', targetUserId)
        .maybeSingle();
    
    _isLiked = existingLike != null;
    _isDisliked = existingDislike != null;
    
    _likeStateController.add(_isLiked);
    _dislikeStateController.add(_isDisliked);
  }
  
  Future<bool> toggleLike() async {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    if (currentUser == null) return false;
    
    try {
      if (_isLiked) {
        // Remove like
        await client
            .from('likes')
            .delete()
            .eq('liker_id', currentUser.id)
            .eq('liked_id', targetUserId);
        
        // Check if there was a match and remove it
        final wasMatch = await _removeMatch(currentUser.id, targetUserId);
        if (wasMatch) {
          // Notify about match removal
          _notifyMatchRemoval();
        }
        
        _isLiked = false;
      } else {
        // Add like (and remove dislike if exists)
        if (_isDisliked) {
          await client
              .from('dislikes')
              .delete()
              .eq('disliker_id', currentUser.id)
              .eq('disliked_id', targetUserId);
          _isDisliked = false;
          _dislikeStateController.add(false);
        }
        
        await client.from('likes').insert({
          'liker_id': currentUser.id,
          'liked_id': targetUserId,
          'created_at': DateTime.now().toIso8601String(),
        });
        
        _isLiked = true;
      }
      
      _likeStateController.add(_isLiked);
      return _isLiked;
    } catch (e) {
      print('Error toggling like: $e');
      rethrow;
    }
  }
  
  Future<bool> toggleDislike() async {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    if (currentUser == null) return false;
    
    try {
      if (_isDisliked) {
        // Remove dislike
        await client
            .from('dislikes')
            .delete()
            .eq('disliker_id', currentUser.id)
            .eq('disliked_id', targetUserId);
        
        _isDisliked = false;
      } else {
        // Add dislike (and remove like if exists)
        if (_isLiked) {
          await client
              .from('likes')
              .delete()
              .eq('liker_id', currentUser.id)
              .eq('liked_id', targetUserId);
          
          // Check if there was a match and remove it
          final wasMatch = await _removeMatch(currentUser.id, targetUserId);
          if (wasMatch) {
            // Notify about match removal
            _notifyMatchRemoval();
          }
          
          _isLiked = false;
          _likeStateController.add(false);
        }
        
        await client.from('dislikes').insert({
          'disliker_id': currentUser.id,
          'disliked_id': targetUserId,
          'created_at': DateTime.now().toIso8601String(),
        });
        
        _isDisliked = true;
      }
      
      _dislikeStateController.add(_isDisliked);
      return _isDisliked;
    } catch (e) {
      print('Error toggling dislike: $e');
      rethrow;
    }
  }
  
  Future<bool> _removeMatch(String userId1, String userId2) async {
    final client = SupabaseClient.instance.client;
    
    // Determine the order for the match table
    final String smaller_id;
    final String larger_id;
    if (userId1.compareTo(userId2) < 0) {
      smaller_id = userId1;
      larger_id = userId2;
    } else {
      smaller_id = userId2;
      larger_id = userId1;
    }
    
    try {
      // First check if a match exists
      final existingMatch = await client
          .from('matches')
          .select()
          .eq('user1_id', smaller_id)
          .eq('user2_id', larger_id)
          .maybeSingle();
      
      if (existingMatch != null) {
        // Match exists, remove it
        await client
            .from('matches')
            .delete()
            .eq('user1_id', smaller_id)
            .eq('user2_id', larger_id);
        
        print('Match removed between $smaller_id and $larger_id');
        return true; // Match was removed
      }
      return false; // No match existed
    } catch (e) {
      print('Error removing match: $e');
      return false;
    }
  }
  
  void _notifyMatchRemoval() {
    _matchRemovedController.add(null);
  }
  
  void dispose() {
    _likeStateController.close();
    _dislikeStateController.close();
    _matchRemovedController.close();
    _instances.remove(targetUserId);
  }
}
