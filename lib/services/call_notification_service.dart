// lib/services/call_notification_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import '../services/call_service.dart';

/// Global singleton service for managing call notifications
/// This ensures subscriptions persist across navigation
class CallNotificationService {
  static final CallNotificationService _instance = CallNotificationService._internal();
  factory CallNotificationService() => _instance;
  CallNotificationService._internal();

  final CallService _callService = CallService();
  supabase.RealtimeChannel? _callsChannel;
  Map<String, dynamic>? _incomingCall;
  Map<String, dynamic>? _callerInfo;
  String? _currentUserId;
  Timer? _subscriptionCheckTimer;
  bool _isSubscribed = false;
  StreamSubscription? _authSubscription;
  bool _isInitialized = false;
  
  // Stream controllers for UI updates
  final _notificationStateController = StreamController<CallNotificationState>.broadcast();
  Stream<CallNotificationState> get notificationState => _notificationStateController.stream;
  
  // Navigation callback
  Function(Map<String, dynamic> callData, Map<String, dynamic> callerData)? onAcceptCall;

  Future<void> initialize() async {
    if (_isInitialized) {
      print('CallNotificationService: Already initialized');
      return;
    }
    
    print('CallNotificationService: Initializing');
    _isInitialized = true;
    
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    
    if (currentUser != null) {
      _currentUserId = currentUser.id;
      print('CallNotificationService: Current user ID: $_currentUserId');
      await _setupSubscription();
      await _checkForPendingCalls();
    } else {
      print('CallNotificationService: No current user found');
    }
    
    // Listen for auth state changes
    _authSubscription = client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;
      
      print('CallNotificationService: Auth state changed: $event');
      
      if (event == supabase.AuthChangeEvent.signedIn && session != null) {
        _currentUserId = session.user.id;
        _setupSubscription();
      } else if (event == supabase.AuthChangeEvent.signedOut) {
        _unsubscribeFromCalls();
        _currentUserId = null;
      }
    });
    
    // Set up periodic subscription health check
    _subscriptionCheckTimer?.cancel();
    _subscriptionCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkSubscriptionHealth();
    });
  }

  Future<void> _checkSubscriptionHealth() async {
    print('CallNotificationService: Health check - isSubscribed: $_isSubscribed, userId: $_currentUserId');
    if (_currentUserId != null && !_isSubscribed) {
      print('CallNotificationService: Subscription health check - resubscribing');
      await _setupSubscription();
    }
  }

  Future<void> _setupSubscription() async {
    final userId = _currentUserId;
    if (userId == null) {
      print('CallNotificationService: No user ID, skipping subscription setup');
      return;
    }

    // Unsubscribe from any existing channel first
    await _unsubscribeFromCalls();
    
    print('CallNotificationService: Setting up subscription for user $userId');
    
    final client = SupabaseClient.instance.client;
    
    try {
      final channelName = 'incoming-calls-$userId';
      
      _callsChannel = client
          .channel(channelName)
          .onPostgresChanges(
            event: supabase.PostgresChangeEvent.insert,
            schema: 'public',
            table: 'calls',
            filter: supabase.PostgresChangeFilter(
              type: supabase.PostgresChangeFilterType.eq,
              column: 'called_id',
              value: userId,
            ),
            callback: (payload) async {
              print('CallNotificationService: Received INSERT call event');
              print('CallNotificationService: Payload: ${payload.newRecord}');
              await _handleIncomingCall(payload.newRecord);
            },
          )
          .onPostgresChanges(
            event: supabase.PostgresChangeEvent.update,
            schema: 'public',
            table: 'calls',
            callback: (payload) async {
              final callData = payload.newRecord;
              print('CallNotificationService: Received UPDATE call event: ${callData['status']}');
              
              // Check if this update is for a call involving the current user
              final isUserInvolved = callData['caller_id'] == userId || 
                                   callData['called_id'] == userId;
              
              if (!isUserInvolved) {
                return;
              }
              
              // If a call we're showing becomes declined or ended, hide the notification
              if (_incomingCall != null && 
                  callData['id'] == _incomingCall!['id'] &&
                  (callData['status'] == 'declined' || 
                   callData['status'] == 'ended' ||
                   callData['status'] == 'completed')) {
                print('CallNotificationService: Hiding notification for ended/declined call');
                _hideNotification();
              }
              
              // Also check for new pending calls that might have been missed
              if (callData['called_id'] == userId && 
                  callData['status'] == 'pending' &&
                  _incomingCall == null) {
                print('CallNotificationService: Found pending call in UPDATE event');
                await _handleIncomingCall(callData);
              }
            },
          )
          .subscribe((status, error) {
            if (error != null) {
              print('CallNotificationService: Subscription error: $error');
              _isSubscribed = false;
              // Retry subscription after error
              Future.delayed(const Duration(seconds: 5), () {
                if (_currentUserId != null) {
                  print('CallNotificationService: Retrying subscription after error');
                  _setupSubscription();
                }
              });
            } else {
              print('CallNotificationService: Subscription status: $status');
              _isSubscribed = status == 'SUBSCRIBED';
              if (_isSubscribed) {
                print('CallNotificationService: Successfully subscribed to channel');
              }
            }
          });
      
      // Wait a bit to ensure subscription is established
      await Future.delayed(const Duration(milliseconds: 500));
      
    } catch (e) {
      print('CallNotificationService: Error setting up subscription: $e');
      _isSubscribed = false;
      // Retry after a delay
      Future.delayed(const Duration(seconds: 3), () {
        if (_currentUserId != null) {
          print('CallNotificationService: Retrying subscription after exception');
          _setupSubscription();
        }
      });
    }
  }

  Future<void> _unsubscribeFromCalls() async {
    if (_callsChannel != null) {
      print('CallNotificationService: Unsubscribing from channel');
      try {
        await _callsChannel!.unsubscribe();
      } catch (e) {
        print('CallNotificationService: Error unsubscribing: $e');
      }
      _callsChannel = null;
      _isSubscribed = false;
    }
  }

  Future<void> _checkForPendingCalls() async {
    final client = SupabaseClient.instance.client;
    final userId = _currentUserId;
    
    if (userId == null) return;

    try {
      print('CallNotificationService: Checking for pending calls');
      final pendingCalls = await client
          .from('calls')
          .select('*')
          .eq('called_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1);

      if (pendingCalls.isNotEmpty) {
        final callData = pendingCalls.first;
        print('CallNotificationService: Found pending call on startup: ${callData['id']}');
        
        final callerResponse = await client
            .from('users')
            .select('*')
            .eq('user_id', callData['caller_id'])
            .single();
        
        _incomingCall = callData;
        _callerInfo = callerResponse;
        _showNotification();
      } else {
        print('CallNotificationService: No pending calls found');
      }
    } catch (e) {
      print('CallNotificationService: Error checking pending calls: $e');
    }
  }

  Future<void> _handleIncomingCall(Map<String, dynamic> callData) async {
    final client = SupabaseClient.instance.client;
    final userId = _currentUserId;
    
    if (userId == null) return;

    // Only show notification for pending calls where we are the called party
    if (callData['status'] != 'pending' || callData['called_id'] != userId) {
      print('CallNotificationService: Call not for us or not pending, ignoring');
      return;
    }
    
    // Don't show notification if we're already showing one
    if (_incomingCall != null) {
      print('CallNotificationService: Already showing a notification, ignoring new call');
      return;
    }
    
    print('CallNotificationService: Incoming call from ${callData['caller_id']}');
    
    try {
      final callerResponse = await client
          .from('users')
          .select('*')
          .eq('user_id', callData['caller_id'])
          .single();
      
      print('CallNotificationService: Caller info fetched: ${callerResponse['name']}');
      
      _incomingCall = callData;
      _callerInfo = callerResponse;
      _showNotification();
    } catch (e) {
      print('CallNotificationService: Error fetching caller info: $e');
    }
  }

  void _showNotification() {
    if (_callerInfo == null || _incomingCall == null) {
      print('CallNotificationService: Not showing notification - missing data');
      return;
    }
    
    print('CallNotificationService: Showing notification for ${_callerInfo!['name']}');
    
    _notificationStateController.add(CallNotificationState(
      isShowing: true,
      callData: _incomingCall!,
      callerInfo: _callerInfo!,
    ));

    // Auto-dismiss after 30 seconds if no action taken
    Future.delayed(const Duration(seconds: 30), () {
      if (_incomingCall != null) {
        print('CallNotificationService: Auto-declining after timeout');
        handleDecline();
      }
    });
  }

  void _hideNotification() {
    _incomingCall = null;
    _callerInfo = null;
    _notificationStateController.add(CallNotificationState(
      isShowing: false,
      callData: null,
      callerInfo: null,
    ));
  }

  Future<void> handleAccept() async {
    if (_incomingCall == null || _callerInfo == null) {
      print('CallNotificationService: Cannot accept - missing call or caller info');
      return;
    }

    final callId = _incomingCall!['id'] as String?;
    final channelName = _incomingCall!['channel_name'] as String?;
    
    if (callId == null || channelName == null) {
      print('CallNotificationService: Cannot accept - missing callId or channelName');
      return;
    }

    print('CallNotificationService: Accepting call $callId');

    try {
      final response = await SupabaseClient.instance.client.functions.invoke(
        'manage-call',
        body: {
          'call_id': callId,
          'action': 'accept',
        },
      );

      if (response.status != 200) {
        throw Exception(response.data['error'] ?? 'Failed to accept call');
      }
      
      // Notify UI to navigate
      onAcceptCall?.call(_incomingCall!, _callerInfo!);
      
      _hideNotification();
    } catch (e) {
      print('CallNotificationService: Error accepting call: $e');
    }
  }

  Future<void> handleDecline() async {
    if (_incomingCall == null) return;

    final callId = _incomingCall!['id'] as String?;
    if (callId == null) {
      print('CallNotificationService: Cannot decline - missing callId');
      return;
    }

    print('CallNotificationService: Declining call $callId');

    try {
      final response = await SupabaseClient.instance.client.functions.invoke(
        'manage-call',
        body: {
          'call_id': callId,
          'action': 'decline',
        },
      );

      if (response.status != 200) {
        throw Exception(response.data['error'] ?? 'Failed to decline call');
      }
      
      _hideNotification();
    } catch (e) {
      print('CallNotificationService: Error declining call: $e');
    }
  }

  void dispose() {
    print('CallNotificationService: Disposing');
    _subscriptionCheckTimer?.cancel();
    _authSubscription?.cancel();
    _unsubscribeFromCalls();
    _notificationStateController.close();
    _isInitialized = false;
  }
}

class CallNotificationState {
  final bool isShowing;
  final Map<String, dynamic>? callData;
  final Map<String, dynamic>? callerInfo;

  CallNotificationState({
    required this.isShowing,
    this.callData,
    this.callerInfo,
  });
}
