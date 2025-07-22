// lib/services/online_status_service.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'supabase_client.dart';

/// Manages the user's online/availability status via heartbeat and realtime updates.
/// Removes any blocking DB calls at startup to avoid isolate crashes.
class OnlineStatusService with WidgetsBindingObserver {
  static final OnlineStatusService _instance = OnlineStatusService._internal();
  factory OnlineStatusService() => _instance;
  OnlineStatusService._internal();

  Timer? _heartbeatTimer;
  bool _isInitialized = false;
  bool _isInCall = false;
  StreamSubscription<List<Map<String, dynamic>>>? _callSubscription;
  bool _lastOnlineStatus = false; // Track last online status to avoid redundant updates

  /// Initialize: immediately mark online, start heartbeat, subscribe to call events.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    _isInCall = false; // Reset inCall on initialization

    WidgetsBinding.instance.addObserver(this);

    // Ensure user is authenticated before updating status
    final client = SupabaseClient.instance.client;
    final user = client.auth.currentUser;
    if (user != null) {
      print('DEBUG: Initializing with user ${user.id}, setting online = true');
      await _updateUserStatus(online: true, isAvailable: true);
    } else {
      print('DEBUG: No user found during initialization');
    }

    // Start periodic heartbeat to maintain online status
    _startHeartbeat();

    // Subscribe to realtime call events for this user
    _subscribeToCallStatus();
  }

  /// Heartbeat: update status every 2 minutes
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _updateUserStatus(
        online: !_isInCall,
        isAvailable: !_isInCall,
      ),
    );
  }

  /// Subscribe to active calls stream, flip in-call flag as events arrive
  void _subscribeToCallStatus() {
    _callSubscription?.cancel(); // Cancel any existing subscription
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
          _updateUserStatus(online: true, isAvailable: true);
        }
        return;
      }
      final inAnyCall = data.any((call) =>
          call['caller_id'] == user.id || call['called_id'] == user.id);
      if (inAnyCall != _isInCall) {
        _isInCall = inAnyCall;
        print('DEBUG: Call status changed, inCall=$inAnyCall, updating status');
        _updateUserStatus(
          online: !inAnyCall,
          isAvailable: !inAnyCall,
        );
      }
    });
  }

  /// Updates `online` and `is_available`, no initial DB queries to avoid crashes
  Future<void> _updateUserStatus({
    required bool online,
    required bool isAvailable,
  }) async {
    try {
      final client = SupabaseClient.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        print('DEBUG: No user found, skipping status update');
        return;
      }

      final effectiveOnline = _isInCall ? false : online;
      // Avoid redundant updates
      if (_lastOnlineStatus == effectiveOnline) {
        print('DEBUG: Skipping redundant update, online=$effectiveOnline');
        return;
      }
      _lastOnlineStatus = effectiveOnline;

      print('DEBUG: Updating status for user ${user.id}: online=$effectiveOnline, isAvailable=$isAvailable');
      await client
          .from('users')
          .update({
            'online': effectiveOnline,
            'is_available': isAvailable,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id);
      print('DEBUG: Status update completed successfully');
    } catch (e) {
      print('ERROR: Failed to update status: $e');
    }
  }

  /// Manually toggle in-call status (e.g. when starting/ending a call)
  Future<void> setInCall(bool inCall) async {
    _isInCall = inCall;
    print('DEBUG: Setting inCall=$inCall');
    await _updateUserStatus(
      online: !inCall,
      isAvailable: !inCall,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('DEBUG: AppLifecycleState changed to $state');
    if (state == AppLifecycleState.resumed) {
      // App enters foreground
      _isInCall = false; // Reset inCall on resume
      _lastOnlineStatus = false; // Force update to online
      _subscribeToCallStatus(); // Reinitialize call subscription
      _updateUserStatus(
        online: !_isInCall,
        isAvailable: !_isInCall,
      );
      _startHeartbeat();
    } else if (state == AppLifecycleState.paused) {
      // App goes to background
      _isInCall = false; // Reset inCall when exiting
      print('DEBUG: App paused, resetting inCall=false');
      _heartbeatTimer?.cancel();
      _updateUserStatus(
        online: false,
        isAvailable: false,
      );
    } else if (state == AppLifecycleState.detached) {
      // App is killed
      _isInCall = false; // Reset inCall when killed
      print('DEBUG: App detached, resetting inCall=false');
      _heartbeatTimer?.cancel();
      // No client-side status update here; handled by server-side trigger
    }
  }

  /// Dispose and mark offline
  void dispose() {
    print('DEBUG: Disposing OnlineStatusService');
    _isInCall = false; // Reset inCall on dispose
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _callSubscription?.cancel();
    _isInitialized = false;
    _lastOnlineStatus = false;
    // No client-side status update here; handled by server-side trigger
  }
}
