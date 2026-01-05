// lib/pages/waiting_call_page.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import '../services/call_service.dart';
import 'join_call_page.dart';
import 'home_page.dart';
import 'matched_users_call_page.dart';

class WaitingCallPage extends StatefulWidget {
  final String callId;
  final String channelName;
  final Map<String, dynamic> matchedUser;
  final bool isInitiator;

  const WaitingCallPage({
    Key? key,
    required this.callId,
    required this.channelName,
    required this.matchedUser,
    required this.isInitiator,
  }) : super(key: key);

  @override
  State<WaitingCallPage> createState() => _WaitingCallPageState();
}

class _WaitingCallPageState extends State<WaitingCallPage> with TickerProviderStateMixin {
  final CallService _callService = CallService();
  supabase.RealtimeChannel? _callStatusChannel;
  bool _isCallActive = false;
  bool _isLeavingCall = false;
  bool _hasNavigated = false; // Add flag to prevent multiple navigations
  String _callStatus = 'pending';
  
  // Animation controller for pulsing effect
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Timer for call timeout
  Timer? _timeoutTimer;
  static const Duration _callTimeout = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _subscribeToCallStatus();
    _startTimeoutTimer();

    // Mark this user as ready immediately when they land on the waiting page
    _markUserReady().then((_) {
      // After marking ready, check if call_started_at is already set
      _checkIfBothUsersReady();
    });
  }

  @override
  void dispose() {
    _callStatusChannel?.unsubscribe();
    _pulseController.dispose();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
  }

  void _startTimeoutTimer() {
    _timeoutTimer = Timer(_callTimeout, () {
      if (!_isCallActive && mounted && !_hasNavigated) {
        _handleCallTimeout();
      }
    });
  }

  // Mark this user as ready on the database
  Future<void> _markUserReady() async {
    try {
      final currentUserId = SupabaseClient.instance.client.auth.currentUser?.id;
      if (currentUserId == null) {
        print('WaitingCallPage: ERROR - Current user ID is null');
        return;
      }

      print('WaitingCallPage: Marking user ready for call ${widget.callId}, isInitiator: ${widget.isInitiator}');

      // Fetch call to determine if we're caller or called
      final callData = await SupabaseClient.instance.client
          .from('calls')
          .select('caller_id')
          .eq('id', widget.callId)
          .maybeSingle();

      if (callData != null) {
        final isCaller = callData['caller_id'] == currentUserId;
        final fieldToUpdate = isCaller ? 'caller_ready' : 'called_ready';

        print('WaitingCallPage: Updating ${fieldToUpdate} = true for call ${widget.callId}');

        await SupabaseClient.instance.client
            .from('calls')
            .update({fieldToUpdate: true})
            .eq('id', widget.callId);

        print('WaitingCallPage: Successfully marked ${isCaller ? "caller" : "called"} as ready');
      } else {
        print('WaitingCallPage: ERROR - Call data is null for call ${widget.callId}');
      }
    } catch (e) {
      print('WaitingCallPage: ERROR marking user ready: $e');
    }
  }

  // Check if both users are ready by checking call_started_at
  Future<void> _checkIfBothUsersReady() async {
    try {
      final callData = await SupabaseClient.instance.client
          .from('calls')
          .select('call_started_at')
          .eq('id', widget.callId)
          .maybeSingle();

      if (callData != null && callData['call_started_at'] != null && !_hasNavigated) {
        print('WaitingCallPage: call_started_at already set! Both users ready, navigating to call page');
        _handleCallStarted();
      }
    } catch (e) {
      print('WaitingCallPage: Error checking if both users ready: $e');
    }
  }

  void _subscribeToCallStatus() {
    _callStatusChannel = _callService.subscribeToCallUpdates(
      widget.callId,
      onUpdate: (callData) {
        if (!mounted || _hasNavigated) return;

        final newStatus = callData['status'] ?? 'pending';
        print('WaitingCallPage: Call status updated to: $newStatus');

        setState(() {
          _callStatus = newStatus;
        });

        // Check if call_started_at was set by the trigger (both users ready)
        if (callData['call_started_at'] != null && !_hasNavigated) {
          print('WaitingCallPage: call_started_at detected! Both users ready, navigating to call page');
          _handleCallStarted();
          return;
        }

        // Handle different call statuses
        switch (_callStatus) {
          case 'declined':
            _handleCallDeclined();
            break;
          case 'ended':
          case 'completed':
            _handleCallEnded();
            break;
        }
      },
    );
  }

  void _handleCallStarted() {
    print('WaitingCallPage: Both users ready, navigating to call page');
    if (_hasNavigated) return;

    setState(() {
      _isCallActive = true;
    });

    _timeoutTimer?.cancel();

    // Navigate to the matched users call page
    _navigateToCallPage();
  }

  void _navigateToCallPage() {
    if (_hasNavigated) return;
    
    _hasNavigated = true;
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => MatchedUsersCallPage(
          callId: widget.callId,
          channelName: widget.channelName,
          matchedUser: widget.matchedUser,
          isInitiator: widget.isInitiator,
          assignedUid: null, // Will be handled by the backend/call system
        ),
      ),
    );
  }

  void _handleCallDeclined() {
    _showMessage('${widget.matchedUser['name']} declined the call', isError: true);
    _navigateBack();
  }

  void _handleCallEnded() {
    _showMessage('Call ended');
    _navigateBack();
  }

  void _handleCallTimeout() {
    _showMessage('Call timed out - ${widget.matchedUser['name']} didn\'t answer', isError: true);
    _cancelCall();
  }

  Future<void> _cancelCall() async {
    if (_isLeavingCall || _hasNavigated) return;
    
    setState(() {
      _isLeavingCall = true;
    });

    try {
      // Update call status to ended using the manage-call function
      final response = await SupabaseClient.instance.client.functions.invoke(
        'manage-call',
        body: {
          'call_id': widget.callId,
          'action': 'end',
        },
      );

      if (response.status != 200) {
        print('Error ending call: ${response.data}');
      }
      
      // Navigate back
      _navigateBack();
    } catch (e) {
      print('Error canceling call: $e');
      _navigateBack();
    }
  }

  void _navigateBack() {
    if (mounted && !_hasNavigated) {
      _hasNavigated = true;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false, // Remove all routes
      );
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.grey,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildProfileImage() {
    final profilePictureUrl = widget.matchedUser['profile_picture_url'];
    
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[300],
              border: Border.all(
                color: Colors.green.withOpacity(0.5),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipOval(
              child: profilePictureUrl != null && profilePictureUrl.toString().isNotEmpty
                  ? Image.network(
                      profilePictureUrl.toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildPlaceholderAvatar();
                      },
                    )
                  : _buildPlaceholderAvatar(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderAvatar() {
    final name = widget.matchedUser['name']?.toString() ?? 'Unknown';
    return Container(
      color: Colors.grey[400],
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 50,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLeavingCall) {
      return const Scaffold(
        backgroundColor: Colors.grey,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    // For accepted user, show a brief loading state before navigation
    if (!widget.isInitiator && _callStatus == 'pending') {
      return Scaffold(
        backgroundColor: Colors.grey[900],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
              ),
              const SizedBox(height: 20),
              Text(
                'Connecting to ${widget.matchedUser['name']}...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: SafeArea(
        child: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.grey[900]!,
                    Colors.black,
                  ],
                ),
              ),
            ),
            
            // Main content
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Profile image with pulse animation
                  _buildProfileImage(),
                  
                  const SizedBox(height: 40),
                  
                  // User name
                  Text(
                    widget.matchedUser['name']?.toString() ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Status text - only show for initiator
                  if (widget.isInitiator)
                    Text(
                      'Calling...',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[400],
                      ),
                    ),
                  
                  const SizedBox(height: 40),
                  
                  // Loading indicator - only show for initiator
                  if (widget.isInitiator)
                    Column(
                      children: [
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Waiting for ${widget.matchedUser['name']} to answer...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[400],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            
            // Bottom action button
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton.extended(
                  onPressed: _cancelCall,
                  backgroundColor: Colors.red,
                  icon: const Icon(Icons.call_end),
                  label: Text(widget.isInitiator ? 'Cancel' : 'End Call'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
