// lib/services/online_status_service.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'supabase_client.dart';

/// Manages the user's online/availability status via heartbeat and realtime updates.
/// Uses heartbeat mechanism to handle app crashes and force-quit scenarios.
class OnlineStatusService with WidgetsBindingObserver {
  static final OnlineStatusService _instance = OnlineStatusService._internal();
  factory OnlineStatusService() => _instance;
  OnlineStatusService._internal();

  Timer? _heartbeatTimer;
  bool _isInitialized = false;
  bool _isInCall = false;
  supabase.RealtimeChannel? _callStatusChannel;
  bool _lastOnlineStatus = false;
  DateTime? _lastHeartbeat;
  static const Duration _heartbeatInterval = Duration(seconds: 30); // Send heartbeat every 30 seconds
  static const Duration _staleThreshold = Duration(minutes: 2); // Consider stale after 2 minutes

  /// Initialize: immediately mark online, start heartbeat, subscribe to call events.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    _isInCall = false;

    WidgetsBinding.instance.addObserver(this);

    // Ensure user is authenticated before updating status
    final client = SupabaseClient.instance.client;
    final user = client.auth.currentUser;
    if (user != null) {
      print('DEBUG: Initializing with user ${user.id}, setting online = true with heartbeat');
      await _sendHeartbeat();
    } else {
      print('DEBUG: No user found during initialization');
    }

    // Start periodic heartbeat
    _startHeartbeat();

    // Subscribe to realtime call events for this user
    _subscribeToCallStatus();
  }

  /// Send heartbeat to server
  Future<void> _sendHeartbeat() async {
    try {
      final client = SupabaseClient.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        print('DEBUG: No user found, skipping heartbeat');
        return;
      }

      final now = DateTime.now();
      final effectiveOnline = !_isInCall;
      
      print('DEBUG: Sending heartbeat for user ${user.id}: online=$effectiveOnline');
      
      await client
          .from('users')
          .update({
            'online': effectiveOnline,
            'is_available': !_isInCall,
            'last_heartbeat': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          })
          .eq('user_id', user.id);
      
      _lastHeartbeat = now;
      _lastOnlineStatus = effectiveOnline;
      print('DEBUG: Heartbeat sent successfully at ${now.toIso8601String()}');
    } catch (e) {
      print('ERROR: Failed to send heartbeat: $e');
    }
  }

  /// Start periodic heartbeat
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // Send initial heartbeat immediately
    _sendHeartbeat();
    
    // Then send periodic heartbeats
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeat());
  }

  /// Subscribe to call status changes using Realtime
  void _subscribeToCallStatus() {
    _callStatusChannel?.unsubscribe();
    final client = SupabaseClient.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      print('DEBUG: No user found, skipping call subscription');
      return;
    }

    print('DEBUG: Subscribing to call status for user ${user.id}');
    
    // Create a unique channel name
    final channelName = 'call-status-${user.id}-${DateTime.now().millisecondsSinceEpoch}';
    
    // Subscribe to call changes where user is either caller or called
    _callStatusChannel = client
        .channel(channelName)
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.all,
          schema: 'public',
          table: 'calls',
          callback: (payload) {
            final callData = payload.eventType == supabase.PostgresChangeEvent.delete
                ? payload.oldRecord
                : payload.newRecord;
            
            // Check if this call involves the current user
            if (callData['caller_id'] != user.id && callData['called_id'] != user.id) {
              return;
            }
            
            print('DEBUG: Call event for user - type: ${payload.eventType}, status: ${callData['status']}');
            
            // Determine if user should be in call based on the event
            bool shouldBeInCall = false;
            
            if (payload.eventType != supabase.PostgresChangeEvent.delete) {
              final status = callData['status'];
              shouldBeInCall = (status == 'active' || status == 'accepted' || status == 'pending');
            }
            
            if (shouldBeInCall != _isInCall) {
              _isInCall = shouldBeInCall;
              print('DEBUG: Call status changed, inCall=$shouldBeInCall, updating status');
              _sendHeartbeat(); // Send immediate heartbeat on status change
            }
            
            // Also handle recently ended calls
            if (payload.eventType == supabase.PostgresChangeEvent.update) {
              final status = callData['status'];
              if ((status == 'ended' || status == 'completed' || status == 'declined') && _isInCall) {
                print('DEBUG: Call ended, forcing status update');
                _isInCall = false;
                _sendHeartbeat();
                
                // Send another heartbeat after a delay to ensure it's registered
                Future.delayed(const Duration(seconds: 2), () {
                  if (!_isInCall) {
                    print('DEBUG: Sending follow-up heartbeat after call ended');
                    _sendHeartbeat();
                  }
                });
              }
            }
          },
        )
        .subscribe();
    
    print('DEBUG: Subscribed to call status changes on channel: $channelName');
  }

  /// Updates online status (now integrated with heartbeat)
  Future<void> _updateUserStatus({
    required bool online,
    required bool isAvailable,
  }) async {
    // This method is now primarily used for immediate status changes
    // The heartbeat mechanism handles regular updates
    await _sendHeartbeat();
  }

  /// Manually toggle in-call status (e.g. when starting/ending a call)
  Future<void> setInCall(bool inCall) async {
    if (_isInCall == inCall) {
      print('DEBUG: setInCall($inCall) called but status unchanged, forcing update anyway');
    }
    _isInCall = inCall;
    print('DEBUG: Setting inCall=$inCall');
    
    // Always send heartbeat immediately when call status changes
    await _sendHeartbeat();
    
    // If ending a call, send another heartbeat after a short delay to ensure it's registered
    if (!inCall) {
      Future.delayed(const Duration(seconds: 2), () {
        if (!_isInCall) { // Only if still not in a call
          print('DEBUG: Sending follow-up heartbeat after call ended');
          _sendHeartbeat();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('DEBUG: AppLifecycleState changed to $state');
    if (state == AppLifecycleState.resumed) {
      // App enters foreground
      _subscribeToCallStatus();
      _startHeartbeat(); // Restart heartbeat
      // Force a status update when resuming
      _sendHeartbeat();
    } else if (state == AppLifecycleState.paused) {
      // App goes to background
      print('DEBUG: App paused, sending final offline status');
      _heartbeatTimer?.cancel();
      
      // Send one final status update before going to background
      final client = SupabaseClient.instance.client;
      final user = client.auth.currentUser;
      if (user != null) {
        // Use synchronous-style update for better reliability
        client
            .from('users')
            .update({
              'online': false,
              'is_available': false,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('user_id', user.id)
            .then((_) => print('DEBUG: Final offline status sent'))
            .catchError((e) => print('ERROR: Failed to send final offline status: $e'));
      }
    } else if (state == AppLifecycleState.detached) {
      // App is being terminated - this may not always be called
      print('DEBUG: App detached');
      _heartbeatTimer?.cancel();
      // Note: We can't reliably send network requests here
      // The server-side cleanup will handle this case
    }
  }

  /// Check if heartbeat is stale (for debugging)
  bool isHeartbeatStale() {
    if (_lastHeartbeat == null) return true;
    return DateTime.now().difference(_lastHeartbeat!) > _staleThreshold;
  }

  /// Force refresh status - useful after call ends
  Future<void> forceRefreshStatus() async {
    print('DEBUG: Force refreshing online status');
    _isInCall = false;
    await _sendHeartbeat();
  }

  /// Dispose and cleanup
  void dispose() {
    print('DEBUG: Disposing OnlineStatusService');
    _isInCall = false;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _callStatusChannel?.unsubscribe();
    _isInitialized = false;
    _lastOnlineStatus = false;
    _lastHeartbeat = null;
  }
}
