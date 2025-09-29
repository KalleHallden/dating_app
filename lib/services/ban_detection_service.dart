import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'supabase_client.dart';
import 'online_status_service.dart';

class BanDetectionService {
  static final BanDetectionService _instance = BanDetectionService._internal();
  factory BanDetectionService() => _instance;
  BanDetectionService._internal();

  supabase.RealtimeChannel? _banChannel;
  bool _isInitialized = false;
  String? _currentUserId;
  VoidCallback? _onBanned;
  Timer? _periodicCheckTimer;

  /// Initialize the ban detection service
  Future<void> initialize({VoidCallback? onBanned}) async {
    final client = SupabaseClient.instance.client;
    final user = client.auth.currentUser;

    if (user == null) {
      print('BanDetectionService: No authenticated user found');
      return;
    }

    _currentUserId = user.id;
    _onBanned = onBanned;

    // First check if user is already banned
    final isBanned = await checkCurrentUserBanStatus();
    if (isBanned) {
      print('BanDetectionService: User is already banned, handling logout');
      await _handleUserBanned();
      return;
    }

    await _setupRealtimeListener();
    _isInitialized = true;
    print('BanDetectionService: Initialized for user ${user.id}');

    // Start periodic ban check as a fallback
    _startPeriodicBanCheck();
  }

  /// Set up real-time listener for user ban status changes
  Future<void> _setupRealtimeListener() async {
    if (_currentUserId == null) return;

    await _banChannel?.unsubscribe();

    final client = SupabaseClient.instance.client;

    _banChannel = client
        .channel('user-ban-detection-${_currentUserId}')
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: supabase.PostgresChangeFilter(
            type: supabase.PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _currentUserId,
          ),
          callback: (payload) async {
            final updatedUser = payload.newRecord;
            final banned = updatedUser['banned'] as bool?;

            if (banned == true) {
              print('BanDetectionService: User has been banned, handling logout');
              await _handleUserBanned();
            }
          },
        )
        .onBroadcast(
          event: '*',  // Listen to all broadcast events
          callback: (payload) async {
            print('BanDetectionService: Received broadcast: ${payload.toString()}');
            // Check if it's an account banned message
            if (payload['payload']?['action'] == 'accountBanned') {
              print('BanDetectionService: Received accountBanned broadcast');
              await _handleUserBanned();
            }
          },
        )
        .subscribe();

    // Also subscribe to the user-specific channel that the Edge Function might use
    final userChannel = client.channel('user:$_currentUserId')
        .onBroadcast(
          event: '*',
          callback: (payload) async {
            print('BanDetectionService: Received user channel broadcast: ${payload.toString()}');
            if (payload['payload']?['action'] == 'accountBanned') {
              print('BanDetectionService: User banned via channel broadcast');
              await _handleUserBanned();
            }
          },
        )
        .subscribe();

    print('BanDetectionService: Real-time ban detection active for user $_currentUserId');
  }

  /// Start periodic ban check as a fallback (checks every 30 seconds)
  void _startPeriodicBanCheck() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final isBanned = await checkCurrentUserBanStatus();
      if (isBanned) {
        print('BanDetectionService: Periodic check detected ban, handling logout');
        await _handleUserBanned();
      }
    });
  }

  /// Handle when user gets banned
  Future<void> _handleUserBanned() async {
    try {
      print('BanDetectionService: Handling banned user');

      // Cancel periodic timer first to prevent multiple calls
      _periodicCheckTimer?.cancel();

      // Clear services
      OnlineStatusService().dispose();

      // Sign out the user
      await SupabaseClient.instance.client.auth.signOut();

      // Use a post-frame callback to ensure navigation happens after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Call the callback if provided
        _onBanned?.call();
      });

      // Clean up
      await dispose();

    } catch (e) {
      print('BanDetectionService: Error handling banned user: $e');
    }
  }

  /// Check if current user is banned (one-time check)
  Future<bool> checkCurrentUserBanStatus() async {
    final client = SupabaseClient.instance.client;
    final user = client.auth.currentUser;

    if (user == null) return false;

    try {
      final userData = await client
          .from('users')
          .select('banned')
          .eq('user_id', user.id)
          .maybeSingle();

      return userData?['banned'] == true;
    } catch (e) {
      print('BanDetectionService: Error checking ban status: $e');
      return false;
    }
  }

  /// Reinitialize the service (useful after auth state changes)
  Future<void> reinitialize({VoidCallback? onBanned}) async {
    await dispose();
    await initialize(onBanned: onBanned);
  }

  /// Dispose of the service and clean up resources
  Future<void> dispose() async {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
    await _banChannel?.unsubscribe();
    _banChannel = null;
    _isInitialized = false;
    _currentUserId = null;
    _onBanned = null;
    print('BanDetectionService: Disposed');
  }

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;
}