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
  StreamSubscription<List<Map<String, dynamic>>>? _callSubscription;
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

  /// Subscribe to active calls stream, flip in-call flag as events arrive
  void _subscribeToCallStatus() {
    _callSubscription?.cancel();
    final client = SupabaseClient.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      print('DEBUG: No user found, skipping call subscription');
      return;
    }

    print('DEBUG: Subscribing to call status for user ${user.id}');
    _callSubscription = client
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('status', 'active')
        .listen((data) {
      print('DEBUG: Call stream data: $data');
      if (data.isEmpty) {
        if (_isInCall) {
          _isInCall = false;
          print('DEBUG: No active calls, resetting inCall=false');
          _sendHeartbeat(); // Send immediate heartbeat on status change
        }
        return;
      }
      final inAnyCall = data.any((call) =>
          call['caller_id'] == user.id || call['called_id'] == user.id);
      if (inAnyCall != _isInCall) {
        _isInCall = inAnyCall;
        print('DEBUG: Call status changed, inCall=$inAnyCall, updating status');
        _sendHeartbeat(); // Send immediate heartbeat on status change
      }
    });
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
    _isInCall = inCall;
    print('DEBUG: Setting inCall=$inCall');
    await _sendHeartbeat();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('DEBUG: AppLifecycleState changed to $state');
    if (state == AppLifecycleState.resumed) {
      // App enters foreground
      _isInCall = false;
      _lastOnlineStatus = false;
      _subscribeToCallStatus();
      _startHeartbeat(); // Restart heartbeat
    } else if (state == AppLifecycleState.paused) {
      // App goes to background
      _isInCall = false;
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
      _isInCall = false;
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

  /// Dispose and cleanup
  void dispose() {
    print('DEBUG: Disposing OnlineStatusService');
    _isInCall = false;
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _callSubscription?.cancel();
    _isInitialized = false;
    _lastOnlineStatus = false;
    _lastHeartbeat = null;
  }
}
