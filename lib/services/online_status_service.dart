// lib/services/online_status_service.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'supabase_client.dart';

class OnlineStatusService with WidgetsBindingObserver {
  static final OnlineStatusService _instance = OnlineStatusService._internal();
  factory OnlineStatusService() => _instance;
  OnlineStatusService._internal();

  Timer? _heartbeatTimer;
  bool _isInitialized = false;
  bool _isInCall = false;
  StreamSubscription? _callSubscription;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _isInitialized = true;
    WidgetsBinding.instance.addObserver(this);
    
    // Set user as online and available
    await _updateUserStatus(online: true, isAvailable: true);
    
    // Start heartbeat timer to keep online status active
    _startHeartbeat();
    
    // Subscribe to call status changes
    _subscribeToCallStatus();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _updateUserStatus(online: true, isAvailable: !_isInCall),
    );
  }

  void _subscribeToCallStatus() {
    final client = SupabaseClient.instance.client;
    final user = client.auth.currentUser;
    
    if (user == null) return;

    // Subscribe to changes in the calls table to detect when user enters/leaves a call
    _callSubscription = client
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('status', 'active')
        .listen((data) {
          // Check if current user is in any active call
          final isInActiveCall = data.any((call) => 
            (call['caller_id'] == user.id || call['called_id'] == user.id) &&
            call['status'] == 'active'
          );
          
          if (isInActiveCall != _isInCall) {
            _isInCall = isInActiveCall;
            _updateUserStatus(online: true, isAvailable: !_isInCall);
          }
        });
  }

  Future<void> _updateUserStatus({required bool online, required bool isAvailable}) async {
    try {
      final client = SupabaseClient.instance.client;
      final user = client.auth.currentUser;
      
      if (user == null) return;

      await client
          .from('users')
          .update({
            'online': online,
            'is_available': isAvailable,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id);
      
      print('User status updated - Online: $online, Available: $isAvailable');
    } catch (e) {
      print('Error updating user status: $e');
    }
  }

  // Call this when user enters a call
  Future<void> setInCall(bool inCall) async {
    _isInCall = inCall;
    await _updateUserStatus(online: true, isAvailable: !inCall);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App is in foreground - user is online and available (unless in call)
        _updateUserStatus(online: true, isAvailable: !_isInCall);
        _startHeartbeat();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // App is in background or closing - user is offline and not available
        _heartbeatTimer?.cancel();
        _updateUserStatus(online: false, isAvailable: false);
        break;
      case AppLifecycleState.hidden:
        // Handle hidden state if needed
        break;
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _callSubscription?.cancel();
    _updateUserStatus(online: false, isAvailable: false);
    _isInitialized = false;
  }
}
