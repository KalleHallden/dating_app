// lib/pages/call_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:amplify_app/pages/home_page.dart';
import 'package:amplify_app/pages/join_call_page.dart';
import '../services/call_service.dart';
import '../widgets/managed_like_dislike_buttons.dart';
import '../services/online_status_service.dart';
import '../services/like_dislike_manager.dart';
import '../models/User.dart';

class CallPage extends StatefulWidget {
  const CallPage({Key? key}) : super(key: key);
  @override
  _CallPageState createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> with TickerProviderStateMixin {
  // Supabase client instance
  late final supabase.SupabaseClient _supabaseClient;
  // Supabase Realtime channel for user-specific broadcasts
  late final supabase.RealtimeChannel _userChannel;

  // Add CallService instance
  final CallService _callService = CallService();

  bool _isConnecting = true;
  bool _isCallActive = false;
  bool _isLeavingCall = false;
  bool _isSkippingToNext = false;
  String? _currentSupabaseCallId;
  String? _agoraChannelId;
  String? _matchedUserName;
  String? _matchedUserProfilePicture;
  int? _assignedUid;
  final bool _debug = true;

  // Progress bar and blur animation
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;
  late Animation<double> _blurAnimation;
  Timer? _progressTimer;
  DateTime? _callStartTime;
  static const Duration _totalDuration = Duration(minutes: 5);
  static const Duration _clearImageDuration = Duration(seconds: 30);

  // Store the partner ID for like/dislike functionality
  String? _partnerId;
  String? _lastPartnerId; // Track last partner for cache clearing

  // New fields for time limits
  User? _currentUser;
  Timer? _callDurationTimer;
  int _callSecondsRemaining = 300; // 5 minutes in seconds
  bool _showTimeWarning = false;
  bool _outOfMinutes = false;

  final List<String> options = [
    "go skiing or snorkelling?",
    "eat pizza or burgers?",
    "travel to the mountains or the beach?",
    "read a book or watch a movie?",
    "stay in or go out?"
  ];
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _supabaseClient = supabase.Supabase.instance.client;

    // Initialize animation controller
    _progressController = AnimationController(
      duration: _totalDuration,
      vsync: this,
    );

    // Progress animation (0.0 to 1.0 over 5 minutes)
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.linear,
    ));

    // Blur animation (20.0 to 0.0, reaching 0 at 4:30)
    _blurAnimation = Tween<double>(
      begin: 20.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: const Interval(
        0.0,
        0.9, // 90% of the animation (4:30 out of 5:00)
        curve: Curves.easeInOut,
      ),
    ));

    _setupSupabaseIntegration();
    _loadRemainingMinutes(); // Load user's remaining minutes
  }

  @override
  void dispose() {
    _progressController.dispose();
    _progressTimer?.cancel();
    _callDurationTimer?.cancel();
    _userChannel.unsubscribe();
    OnlineStatusService().setInCall(false);

    // Clear the cache when leaving the call page
    if (_partnerId != null) {
      LikeDislikeManager.clearCacheForUser(_partnerId!);
    }
    if (_lastPartnerId != null && _lastPartnerId != _partnerId) {
      LikeDislikeManager.clearCacheForUser(_lastPartnerId!);
    }

    super.dispose();
  }

  void safePrint(String msg) {
    if (_debug) print('${DateTime.now().toIso8601String()}: $msg');
  }

  Future<void> _loadRemainingMinutes() async {
    final currentUser = _supabaseClient.auth.currentUser;
    if (currentUser == null) return;

    try {
      final response = await _supabaseClient
          .from('users')
          .select('monthly_seconds_used, monthly_second_limit, total_lifetime_seconds, name, profile_picture')
          .eq('user_id', currentUser.id)
          .maybeSingle();

      if (mounted && response != null) {
        setState(() {
          _currentUser = User(
            userId: currentUser.id,
            name: response['name'],
            profilePicture: response['profile_picture'],
            monthlySecondsUsed: response['monthly_seconds_used'] ?? 0,
            monthlySecondLimit: response['monthly_second_limit'] ?? 0,
            totalLifetimeSeconds: response['total_lifetime_seconds'] ?? 0,
          );
          _outOfMinutes = !_currentUser!.hasMinutesForCall;
        });
      }
    } catch (e) {
      safePrint('Error loading remaining minutes: $e');
    }
  }

  void _startProgressAnimation() {
    _callStartTime = DateTime.now();
    _progressController.forward();

    // Update progress every second for smooth animation
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        // Force rebuild to update blur
      });
    });

    // Start call duration countdown
    _startCallDurationTimer();
  }

  void _startCallDurationTimer() {
    _callSecondsRemaining = 300; // Reset to 5 minutes
    _showTimeWarning = false;

    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _callSecondsRemaining--;

        // Show warning at 30 seconds remaining
        if (_callSecondsRemaining == 30 && !_showTimeWarning) {
          _showTimeWarning = true;
          _showCallEndingWarning();
        }

        // Auto-end call at 0 seconds
        if (_callSecondsRemaining <= 0) {
          timer.cancel();
          _autoEndCall();
        }
      });
    });
  }

  void _showCallEndingWarning() {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Call ending in 30 seconds...'),
        duration: Duration(seconds: 5),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _autoEndCall() async {
    safePrint('Auto-ending call after 5 minutes');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Call time limit reached (5 minutes)'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.blue,
        ),
      );
    }

    await _leaveCall();
  }

  String _formatCallTime() {
    final minutes = (_callSecondsRemaining ~/ 60);
    final seconds = (_callSecondsRemaining % 60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Sets up Supabase Realtime listener and initiates the initial state clear and matchmaking join.
  Future<void> _setupSupabaseIntegration() async {
    safePrint('→ Initializing Supabase Integration');

    final currentUser = _supabaseClient.auth.currentUser;
    if (currentUser == null) {
      safePrint(
          'Error: Supabase user not authenticated. Cannot set up Realtime.');
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
          (_) => false,
        );
      }
      return;
    }

    _userChannel = _supabaseClient.channel('user:${currentUser.id}');
    _userChannel.onBroadcast(
      event: '*',
      callback: (payload) => _onSupabaseRealtimeMessage(payload),
    );
    _userChannel.subscribe();
    safePrint(
        'Supabase Realtime: Subscribed to user channel: user:${currentUser.id}');

    safePrint('Attempting to send clearState request from Flutter...');
    await _sendClearState();
    safePrint(
        'clearState request sent from Flutter. Waiting for Realtime confirmation...');
  }

  /// Handles incoming broadcast messages from Supabase Realtime.
  Future<void> _onSupabaseRealtimeMessage(Map<String, dynamic> payload) async {
    safePrint('← Received raw Realtime payload: $payload');
    final Map<String, dynamic> message =
        payload['payload'] as Map<String, dynamic>;

    safePrint('← Parsed Realtime message: $message');

    switch (message['action']) {
      case 'stateCleared':
        safePrint('Supabase Realtime: State cleared confirmation received.');
        if (mounted) {
          setState(() => _isConnecting = false);

          // Check if user has minutes before joining matchmaking
          if (_outOfMinutes) {
            _showOutOfMinutesDialog();
          } else {
            safePrint(
                'Calling _joinMatchmaking() after stateCleared confirmation.');
            _joinMatchmaking();
          }
        }
        return;

      case 'outOfMinutes':
        safePrint('Supabase Realtime: Out of minutes notification received.');
        if (!mounted) return;

        // Reload user data to get updated seconds
        await _loadRemainingMinutes();

        _showOutOfMinutesDialog();
        return;

      case 'leftCall':
        safePrint('Supabase Realtime: Left call confirmation received.');
        if (!mounted) return;

        // Clear cache when leaving call
        if (_partnerId != null) {
          LikeDislikeManager.clearCacheForUser(_partnerId!);
        }

        setState(() {
          _isCallActive = false;
          _isLeavingCall = false;
          _currentSupabaseCallId = null;
          _agoraChannelId = null;
          _matchedUserName = null;
          _matchedUserProfilePicture = null;
          _partnerId = null;
          _assignedUid = null;
        });
        _progressController.stop();
        _progressTimer?.cancel();
        _callDurationTimer?.cancel();
        OnlineStatusService().setInCall(false);

        // Reload remaining minutes after call
        await _loadRemainingMinutes();

        // Only navigate to home page if we're not skipping to next person
        if (!_isSkippingToNext) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
            (_) => false,
          );
        } else {
          // Reset the flag and stay on call page for matchmaking
          _isSkippingToNext = false;
          setState(() => _isConnecting = false);
          
          // Check if user has minutes before rejoining
          if (_outOfMinutes) {
            _showOutOfMinutesDialog();
          } else {
            _joinMatchmaking();
          }
        }
        return;

      case 'callInitiated':
        safePrint('Supabase Realtime: Call initiated! Details: $message');
        if (!mounted) return;

        _currentSupabaseCallId = message['callId'] as String;
        _agoraChannelId = message['channelId'] as String;
        final String partnerId = message['partnerId'] as String;
        _assignedUid = message['assignedUid'] as int;
        
        safePrint('Received callInitiated with assignedUid: $_assignedUid');

        // Clear cache if this is a different partner
        if (_lastPartnerId != null && _lastPartnerId != partnerId) {
          LikeDislikeManager.clearCacheForUser(_lastPartnerId!);
        }

        _partnerId = partnerId;
        _lastPartnerId = partnerId;

        // Force refresh the manager state for this partner
        final manager = LikeDislikeManager.forUser(partnerId);
        await manager.refreshState();

        final String role = message['role'] as String? ?? 'unknown';

        // Reload user data after call initiation
        await _loadRemainingMinutes();

        // Fetch partner's profile information
        try {
          final partnerData = await _supabaseClient
              .from('users')
              .select('name, profile_picture')
              .eq('user_id', partnerId)
              .maybeSingle();

          if (partnerData != null) {
            setState(() {
              _matchedUserName = partnerData['name'] as String?;
              _matchedUserProfilePicture =
                  partnerData['profile_picture'] as String?;
              _isCallActive = true;
            });
            safePrint(
                'Matched with: $_matchedUserName (ID: $partnerId) as $role');
            safePrint('Profile picture URL: $_matchedUserProfilePicture');

            _startProgressAnimation();
            OnlineStatusService().setInCall(true);

            if (role == 'called') {
              await _callService.markCallAsActive(_currentSupabaseCallId!);
            }

            // Show call info with time limit
            if (mounted && _currentUser != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      'Call started! Maximum duration: 5 minutes. Monthly minutes remaining: ${_currentUser!.remainingMonthlyMinutes}'),
                  duration: const Duration(seconds: 5),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } else {
            safePrint('Warning: Partner data not found for ID: $partnerId');
            setState(() {
              _matchedUserName = 'Unknown User';
              _matchedUserProfilePicture = null;
              _isCallActive = true;
            });
            _startProgressAnimation();
          }
        } catch (e) {
          safePrint('Error fetching partner data: $e');
          setState(() {
            _matchedUserName = 'Error User';
            _matchedUserProfilePicture = null;
            _isCallActive = true;
          });
          _startProgressAnimation();
        }
        return;

      case 'callEnded':
        safePrint('Supabase Realtime: Call ended by other party.');
        if (!mounted) return;

        // Clear cache when call ends
        if (_partnerId != null) {
          LikeDislikeManager.clearCacheForUser(_partnerId!);
        }

        setState(() {
          _isCallActive = false;
          _currentSupabaseCallId = null;
          _agoraChannelId = null;
        });
        _progressController.stop();
        _progressTimer?.cancel();
        _callDurationTimer?.cancel();
        OnlineStatusService().setInCall(false);

        await _loadRemainingMinutes();

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
          (_) => false,
        );
        return;

      case 'partnerLeftCall':
        safePrint('Supabase Realtime: Partner left the call.');
        if (!mounted) return;

        final partnerName = message['partnerName'] as String? ?? 'User';

        // Clear the cache when partner leaves
        if (_partnerId != null) {
          LikeDislikeManager.clearCacheForUser(_partnerId!);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$partnerName left the phone call'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );

        setState(() {
          _isCallActive = false;
          _isLeavingCall = false;
          _currentSupabaseCallId = null;
          _agoraChannelId = null;
          _matchedUserName = null;
          _matchedUserProfilePicture = null;
          _partnerId = null;
          _assignedUid = null;
        });

        _progressController.stop();
        _progressTimer?.cancel();
        _callDurationTimer?.cancel();

        OnlineStatusService().setInCall(false);

        await _loadRemainingMinutes();

        // Automatically rejoin matchmaking after a short delay
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() => _isConnecting = false);

            // Check if user has minutes before rejoining
            if (_outOfMinutes) {
              _showOutOfMinutesDialog();
            } else {
              safePrint('Partner left - rejoining matchmaking');
              _joinMatchmaking();
            }
          }
        });

        return;

      default:
        safePrint(
            'Supabase Realtime: Unknown action received: ${message['action']}');
        break;
    }
  }

  void _showOutOfMinutesDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Out of Minutes'),
        content: Text(
            'You have ${_currentUser?.remainingMonthlyMinutes ?? 0} minutes remaining this month.\n\n'
            'You need at least 5 minutes for a call. Your minutes will reset at the beginning of next month.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const HomePage()),
                (_) => false,
              );
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Sends a request to the `user_state_handler` Edge Function.
  Future<void> _sendSupabaseFunctionAction(String action,
      {Map<String, dynamic>? data}) async {
    final currentUser = _supabaseClient.auth.currentUser;
    if (currentUser == null) {
      safePrint('Error: User not authenticated. Cannot send action: $action');
      return;
    }

    final Map<String, dynamic> body = {
      'action': action,
      'userId': currentUser.id,
      ...?data,
    };

    try {
      safePrint('→ Invoking Edge Function: $action with body: $body');
      final response = await _supabaseClient.functions.invoke(
        'user_state_handler',
        body: body,
        headers: {
          'Content-Type': 'application/json',
        },
      );
      safePrint('Edge Function "$action" response status: ${response.status}');
      safePrint('Edge Function "$action" response data: ${response.data}');

      if (response.status != 200) {
        safePrint('Error invoking Edge Function "$action": ${response.data}');
      }
    } catch (e) {
      safePrint('Exception while invoking Edge Function "$action": $e');
    }
  }

  Future<void> _sendClearState() async {
    await _sendSupabaseFunctionAction('clearState');
  }

  void _joinMatchmaking() {
    if (_isCallActive || _isLeavingCall || _outOfMinutes) return;
    setState(() => _currentSupabaseCallId = null);

    safePrint('Attempting to send joinMatchmaking request from Flutter...');
    _sendSupabaseFunctionAction(
      'joinMatchmaking',
      data: {
        'timestamp': DateTime.now().toIso8601String(),
        'connectionId': _supabaseClient.auth.currentUser!.id,
      },
    );
    safePrint('joinMatchmaking request sent from Flutter.');
  }

  Future<void> _leaveCall({bool shouldReturnHome = true}) async {
    // Set flag to indicate if we're skipping to next person
    _isSkippingToNext = !shouldReturnHome;
    if (_currentSupabaseCallId == null) {
      if (mounted && shouldReturnHome) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
          (_) => false,
        );
      }
      return;
    }

    setState(() => _isLeavingCall = true);

    OnlineStatusService().setInCall(false);

    await _callService.endCall(_currentSupabaseCallId!);

    await _sendSupabaseFunctionAction(
      'leaveCall',
      data: {
        'callId': _currentSupabaseCallId,
      },
    );
    
    // The actual cleanup and navigation logic is handled in the 'leftCall' case
    // when we receive the confirmation from the backend
  }

  void _nextOption() =>
      setState(() => currentIndex = (currentIndex + 1) % options.length);
  void _prevOption() => setState(() =>
      currentIndex = (currentIndex - 1 + options.length) % options.length);

  @override
  Widget build(BuildContext context) {
    // Connecting / Initializing Supabase
    if (_isConnecting) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Out of minutes
    if (_outOfMinutes && !_isCallActive) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const HomePage()),
              (_) => false,
            );
          }),
          title: const Text(''),
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.timer_off,
                  size: 80,
                  color: Colors.grey,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Out of Minutes',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'You have ${_currentUser?.remainingMonthlyMinutes ?? 0} minutes remaining this month.',
                  style: const TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your minutes will reset at the beginning of next month.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const HomePage()),
                      (_) => false,
                    );
                  },
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Leaving Call
    if (_isLeavingCall) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Leaving call...',
            style: TextStyle(fontSize: 24),
          ),
        ),
      );
    }

    // Searching for match / Wu Wei quote screen
    if (!_isCallActive) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const HomePage()),
              (_) => false,
            );
          }),
          title: const Text(''),
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding:
                const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('searching',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text(
                  'Minutes remaining: ${_currentUser?.remainingMonthlyMinutes ?? 0}',
                  style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                ),
                const SizedBox(height: 16),
                CircularProgressIndicator(
                    color: Theme.of(context).primaryColor),
                const SizedBox(height: 24),
                SingleChildScrollView(
                  child: Text(
                    _currentSupabaseCallId == null
                        ? '''Wu wei (無為)
Means "effortless action". The art of not forcing anything. You are who you are and they will be who they will be. You like what you like and they will like what they will like. You might not be what they like and they might not be what you like. Some people like cats, some people like dogs. You can't be a cat and a dog. You can't be red and blue.

Look for the path of least resistance. The conversation of least resistance.
With the right person, it's easier, feels more natural, less forced.

Don't try to be someone else's match, try to find yours.'''
                        : 'Failed to join call. Try again.',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Active call UI
    return Scaffold(
      body: Stack(
        children: [
          // Profile picture with animated blur
          AnimatedBuilder(
            animation: _blurAnimation,
            builder: (context, child) {
              return Stack(
                children: [
                  if (_matchedUserProfilePicture != null &&
                      _matchedUserProfilePicture!.isNotEmpty)
                    Positioned.fill(
                      child: Image.network(
                        _matchedUserProfilePicture!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          print('Error loading profile picture: $error');
                          print('URL was: $_matchedUserProfilePicture');
                          return Container(
                            color: Colors.grey[800],
                            child: const Center(
                              child: Icon(
                                Icons.person,
                                size: 100,
                                color: Colors.white30,
                              ),
                            ),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: Colors.grey[800],
                            child: Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes !=
                                        null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                                color: Colors.white,
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else
                    Positioned.fill(
                      child: Container(
                        color: Colors.grey[800],
                        child: const Center(
                          child: Icon(
                            Icons.person,
                            size: 100,
                            color: Colors.white30,
                          ),
                        ),
                      ),
                    ),
                  // Blur overlay
                  Positioned.fill(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: _blurAnimation.value,
                        sigmaY: _blurAnimation.value,
                      ),
                      child: Container(color: Colors.black.withOpacity(0.4)),
                    ),
                  ),
                ],
              );
            },
          ),
          // Top bar with name and timer
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _matchedUserName ?? '',
                      style: const TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    // Call timer
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _callSecondsRemaining <= 30
                            ? Colors.orange.withOpacity(0.8)
                            : Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _formatCallTime(),
                        style: TextStyle(
                          fontSize: 16,
                          color: _callSecondsRemaining <= 30
                              ? Colors.white
                              : Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: _leaveCall,
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.all(Colors.red),
                  ),
                  child: const Text('Leave',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
          // Minutes remaining indicator
          Positioned(
            top: 120,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${_currentUser?.remainingMonthlyMinutes ?? 0} min/month',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Pass the Agora channel ID and call ID to JoinChannelAudio
          Align(
            alignment: Alignment.center,
            child: _agoraChannelId != null
                ? JoinChannelAudio(
                    channelID: _agoraChannelId!,
                    callId: _currentSupabaseCallId,
                    uid: _assignedUid,
                  )
                : const CircularProgressIndicator(color: Colors.white),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Like and Dislike buttons with unique key for cache busting
                  if (_partnerId != null)
                    ManagedLikeDislikeButtons(
                      key: ValueKey(
                          'buttons_${_partnerId}_${_currentSupabaseCallId}'),
                      targetUserId: _partnerId!,
                      onMatched: () {
                        print('Match celebration for call with $_partnerId');
                      },
                      onNextPressed: () async {
                        // The dislike is already handled by the button
                        // Now trigger leave call but stay on the page
                        await _leaveCall(shouldReturnHome: false);
                      },
                    ),
                  // Progress bar
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 16),
                    child: AnimatedBuilder(
                      animation: _progressAnimation,
                      builder: (context, child) {
                        return Container(
                          height: 8,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: _progressAnimation.value,
                              backgroundColor: Colors.transparent,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                              minHeight: 6,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Would you rather card
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 8,
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.9,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Would you rather',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                  icon: const Icon(Icons.arrow_left),
                                  onPressed: _prevOption),
                              Expanded(
                                child: Text(
                                  options[currentIndex],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                              IconButton(
                                  icon: const Icon(Icons.arrow_right),
                                  onPressed: _nextOption),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
