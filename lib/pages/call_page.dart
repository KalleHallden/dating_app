import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart' as supabase; // Import Supabase
import 'package:amplify_app/pages/home_page.dart';
import 'package:amplify_app/pages/join_call_page.dart'; // CORRECTED: This import is for JoinChannelAudio
import '../services/call_service.dart'; // Add this import
import '../components/managed_like_dislike_buttons.dart';

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

  bool _isConnecting = true; // State for initial Supabase connection/setup
  bool _isCallActive = false;
  bool _isLeavingCall = false;
  String? _currentSupabaseCallId; // The UUID from the Supabase 'calls' table
  String? _agoraChannelId;      // The channel ID to be used by Agora (from matchmaker)
  String? _matchedUserName;
  String? _matchedUserProfilePicture;
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
    
    _setupSupabaseIntegration(); // Initialize Supabase Realtime and matchmaking
  }

  @override
  void dispose() {
    _progressController.dispose();
    _progressTimer?.cancel();
    _userChannel.unsubscribe(); // Unsubscribe from Realtime channel
    super.dispose();
  }

  void safePrint(String msg) {
    if (_debug) print('${DateTime.now().toIso8601String()}: $msg');
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
  }

  /// Sets up Supabase Realtime listener and initiates the initial state clear and matchmaking join.
  Future<void> _setupSupabaseIntegration() async {
    safePrint('→ Initializing Supabase Integration');

    final currentUser = _supabaseClient.auth.currentUser;
    if (currentUser == null) {
      safePrint('Error: Supabase user not authenticated. Cannot set up Realtime.');
      // Handle scenario where user is not logged in, e.g., navigate back to AuthScreen
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()), // Or AuthScreen
          (_) => false,
        );
      }
      return;
    }

    // Subscribe to a private channel for the current user to receive messages
    // The channel name must match what your Edge Functions broadcast to: 'user:<userId>'
    _userChannel = _supabaseClient.channel('user:${currentUser.id}');
    // Use onBroadcast with a callback that receives a Map<String, dynamic>
    _userChannel.onBroadcast(
      event: '*', // Listen to all broadcast events
      callback: (payload) => _onSupabaseRealtimeMessage(payload),
    );
    _userChannel.subscribe(); // Don't forget to call subscribe on the channel
    safePrint('Supabase Realtime: Subscribed to user channel: user:${currentUser.id}');

    // Clear state and wait for completion before proceeding
    safePrint('Attempting to send clearState request from Flutter...');
    await _sendClearState();
    safePrint('clearState request sent from Flutter. Waiting for Realtime confirmation...');
  }

  /// Handles incoming broadcast messages from Supabase Realtime.
  Future<void> _onSupabaseRealtimeMessage(Map<String, dynamic> payload) async {
    safePrint('← Received raw Realtime payload: $payload'); // Access payload data
    // Extract the nested payload containing the action
    final Map<String, dynamic> message = payload['payload'] as Map<String, dynamic>;

    safePrint('← Parsed Realtime message: $message');

    switch (message['action']) {
      case 'stateCleared':
        safePrint('Supabase Realtime: State cleared confirmation received.');
        if (mounted) {
          setState(() => _isConnecting = false);
          safePrint('Calling _joinMatchmaking() after stateCleared confirmation.');
          _joinMatchmaking(); // Proceed to join matchmaking after state is cleared
        }
        return;

      case 'leftCall':
        safePrint('Supabase Realtime: Left call confirmation received.');
        if (!mounted) return;
        setState(() {
          _isCallActive = false;
          _isLeavingCall = false;
          _currentSupabaseCallId = null;
          _agoraChannelId = null;
          _matchedUserName = null;
          _matchedUserProfilePicture = null;
          _partnerId = null;
        });
        _progressController.stop();
        _progressTimer?.cancel();
        // Navigate back to HomePage after successfully leaving the call
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
          (_) => false,
        );
        return;

      case 'callInitiated':
        safePrint('Supabase Realtime: Call initiated! Details: $message');
        if (!mounted) return;

        // Extract call details from the payload
        _currentSupabaseCallId = message['callId'] as String;
        _agoraChannelId = message['channelId'] as String; // This is the Agora channel ID
        final String partnerId = message['partnerId'] as String;
        _partnerId = partnerId; // Store the partner ID
        final String role = message['role'] as String? ?? 'unknown';

        // Fetch partner's profile information from the 'users' table
        try {
          final partnerData = await _supabaseClient
              .from('users')
              .select('name, profile_picture') // Changed from profile_picture_url to profile_picture
              .eq('user_id', partnerId)
              .maybeSingle(); // Use maybeSingle as partner might not exist or data is incomplete

          if (partnerData != null) {
            setState(() {
              _matchedUserName = partnerData['name'] as String?;
              _matchedUserProfilePicture = partnerData['profile_picture'] as String?;
              _isCallActive = true; // Mark call as active
            });
            safePrint('Matched with: $_matchedUserName (ID: $partnerId) as $role');
            safePrint('Profile picture URL: $_matchedUserProfilePicture'); // Debug log
            
            // Start the progress animation when call is initiated
            _startProgressAnimation();
            
            // Update call status to active if both users have joined
            if (role == 'called') {
              await _callService.markCallAsActive(_currentSupabaseCallId!);
            }
          } else {
            safePrint('Warning: Partner data not found for ID: $partnerId');
            // Handle case where partner data is missing or incomplete
            setState(() {
              _matchedUserName = 'Unknown User';
              _matchedUserProfilePicture = null;
              _isCallActive = true; // Still activate call, but with limited info
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
        setState(() {
          _isCallActive = false;
          _currentSupabaseCallId = null;
          _agoraChannelId = null;
        });
        _progressController.stop();
        _progressTimer?.cancel();
        // Navigate back to HomePage
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
          (_) => false,
        );
        return;

      default:
        safePrint('Supabase Realtime: Unknown action received: ${message['action']}');
        break;
    }
  }

  /// Sends a request to the `user_state_handler` Edge Function.
  Future<void> _sendSupabaseFunctionAction(String action, {Map<String, dynamic>? data}) async {
    final currentUser = _supabaseClient.auth.currentUser;
    if (currentUser == null) {
      safePrint('Error: User not authenticated. Cannot send action: $action');
      return;
    }

    final Map<String, dynamic> body = {
      'action': action,
      'userId': currentUser.id, // Supabase Auth user ID (UUID)
      ...?data, // Include any additional data provided
    };

    try {
      safePrint('→ Invoking Edge Function: $action with body: $body');
      final response = await _supabaseClient.functions.invoke(
        'user_state_handler', // The name of your primary Edge Function
        body: body,
        headers: {
          'Content-Type': 'application/json',
        },
      );
      safePrint('Edge Function "$action" response status: ${response.status}');
      safePrint('Edge Function "$action" response data: ${response.data}');

      if (response.status != 200) {
        safePrint('Error invoking Edge Function "$action": ${response.data}');
        // You might want to show a Snackbar or dialog to the user
      }
    } catch (e) {
      safePrint('Exception while invoking Edge Function "$action": $e');
      // Handle network errors or other exceptions
    }
  }

  /// Clears the user's state on the backend.
  Future<void> _sendClearState() async {
    await _sendSupabaseFunctionAction('clearState');
  }

  /// Initiates matchmaking by calling the Edge Function.
  void _joinMatchmaking() {
    if (_isCallActive || _isLeavingCall) return;
    setState(() => _currentSupabaseCallId = null); // Clear any previous call ID

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

  /// Requests the backend to end the current call.
  Future<void> _leaveCall() async {
    if (_currentSupabaseCallId == null) {
      // If no call ID, just navigate back to home
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
          (_) => false,
        );
      }
      return;
    }

    setState(() => _isLeavingCall = true);

    // Update call status in database
    await _callService.endCall(_currentSupabaseCallId!);

    await _sendSupabaseFunctionAction(
      'leaveCall',
      data: {
        'callId': _currentSupabaseCallId,
      },
    );

    // The Realtime listener will handle setting _isCallActive = false and navigation
    // once the 'leftCall' message is received from the backend.
  }

  void _nextOption() => setState(() => currentIndex = (currentIndex + 1) % options.length);
  void _prevOption() => setState(() => currentIndex = (currentIndex - 1 + options.length) % options.length);

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
            padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('searching', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(height: 16),
                CircularProgressIndicator(color: Theme.of(context).primaryColor),
                const SizedBox(height: 24),
                SingleChildScrollView(
                  child: Text(
                    _currentSupabaseCallId == null // Checks if we failed to get a call ID after searching
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
                  if (_matchedUserProfilePicture != null && _matchedUserProfilePicture!.isNotEmpty)
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
                                value: loadingProgress.expectedTotalBytes != null
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
          Positioned(
            top: 40,
            left: 20,
            child: Text(
              _matchedUserName ?? '',
              style: const TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: ElevatedButton(
              onPressed: _leaveCall,
              style: ButtonStyle(
                backgroundColor: MaterialStateProperty.all(Colors.red),
              ),
              child: const Text('Leave', style: TextStyle(color: Colors.white)),
            ),
          ),
          // Pass the Agora channel ID and call ID to JoinChannelAudio
          Align(
            alignment: Alignment.center,
            child: _agoraChannelId != null 
              ? JoinChannelAudio(
                  channelID: _agoraChannelId!,
                  callId: _currentSupabaseCallId,
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
                  // Like and Dislike buttons
                  if (_partnerId != null)
                    ManagedLikeDislikeButtons(
                      targetUserId: _partnerId!,
                      onMatched: () {
                        // Handle match celebration if needed
                        print('Match celebration for call with $_partnerId');
                      },
                    ),
                  // Progress bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
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
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                              minHeight: 6,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  // Would you rather card
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 8,
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.9,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Would you rather', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(icon: const Icon(Icons.arrow_left), onPressed: _prevOption),
                              Expanded(
                                child: Text(
                                  options[currentIndex],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                              IconButton(icon: const Icon(Icons.arrow_right), onPressed: _nextOption),
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
