// lib/pages/matched_users_call_page.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import '../services/call_service.dart';
import '../services/online_status_service.dart';
import 'home_page.dart';
import 'join_call_page.dart';
import 'call_page.dart';

class MatchedUsersCallPage extends StatefulWidget {
  final String callId;
  final String channelName;
  final Map<String, dynamic> matchedUser;
  final bool isInitiator;
  final int? assignedUid;

  const MatchedUsersCallPage({
    Key? key,
    required this.callId,
    required this.channelName,
    required this.matchedUser,
    required this.isInitiator,
    this.assignedUid,
  }) : super(key: key);

  @override
  State<MatchedUsersCallPage> createState() => _MatchedUsersCallPageState();
}

class _MatchedUsersCallPageState extends State<MatchedUsersCallPage> with TickerProviderStateMixin {
  final CallService _callService = CallService();
  supabase.RealtimeChannel? _callStatusChannel;
  bool _isCallActive = false;
  bool _isLeavingCall = false;
  String _callStatus = 'pending';
  int? _assignedUid; // Store the assigned UID from backend
  
  // Timer for call duration
  Timer? _durationTimer;
  DateTime? _callStartTime;
  Duration _callDuration = Duration.zero;
  
  // Call limits checking
  Timer? _callLimitsTimer;
  int _maxCallDurationSeconds = 300; // Default 5 minutes
  int _callerSecondsRemaining = 300;
  int _calledSecondsRemaining = 300;
  int _actualSecondsRemaining = 300;
  bool _showTimeWarning = false;
  bool _isAutoEnding = false;

  // Options for conversation starters
  final List<String> options = [
    "What's your favorite movie?",
    "What do you like to do on weekends?",
    "What's your dream vacation?",
    "Coffee or tea?",
    "What's your favorite cuisine?",
  ];
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _assignedUid = widget.assignedUid; // Use provided UID if available
    _subscribeToCallStatus();
    
    // If not initiator, we already accepted, so start the call immediately
    if (!widget.isInitiator) {
      _startCall();
    } else {
      // For initiator, check if call is already accepted
      // This happens when navigating from WaitingCallPage after acceptance
      _checkIfCallAlreadyAccepted();
    }
  }

  @override
  void dispose() {
    _callStatusChannel?.unsubscribe();
    _durationTimer?.cancel();
    _callLimitsTimer?.cancel();
    
    // Ensure we set the user as not in call when disposing
    OnlineStatusService().setInCall(false);
    // Force refresh status to ensure it's properly updated
    OnlineStatusService().forceRefreshStatus();
    
    super.dispose();
  }

  void _subscribeToCallStatus() {
    _callStatusChannel = _callService.subscribeToCallUpdates(
      widget.callId,
      onUpdate: (callData) {
        if (!mounted) return;
        
        final previousStatus = _callStatus;
        setState(() {
          _callStatus = callData['status'] ?? 'pending';
        });
        
        // Handle different call statuses
        switch (_callStatus) {
          case 'accepted':
            if (widget.isInitiator && previousStatus == 'pending') {
              _startCall();
            }
            break;
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

  Future<void> _startCall() async {
    if (_isCallActive) return;
    
    // Fetch UID if not provided
    if (_assignedUid == null) {
      await _fetchAssignedUid();
    }
    
    setState(() {
      _isCallActive = true;
      _callStartTime = DateTime.now();
    });
    
    // Start duration timer
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration = DateTime.now().difference(_callStartTime!);
          
          // Update local remaining seconds countdown
          if (_actualSecondsRemaining > 0) {
            _actualSecondsRemaining--;
            
            // Show warning at 30 seconds
            if (_actualSecondsRemaining == 30 && !_showTimeWarning) {
              _showTimeWarning = true;
              _showCallEndingWarning();
            }
          }
        });
      }
    });
    
    // Start call limits checking timer
    _startCallLimitsChecking();
    
    // Set user as in call
    OnlineStatusService().setInCall(true);
  }

  Future<void> _fetchAssignedUid() async {
    try {
      print('MatchedUsersCallPage: Fetching assigned UID for call ${widget.callId}');
      final supabaseClient = SupabaseClient.instance.client;
      
      // Fetch call data from database to get assigned UID
      final callResponse = await supabaseClient
          .from('calls')
          .select('caller_uid, called_uid, caller_id')
          .eq('id', widget.callId)
          .maybeSingle();
      
      if (callResponse != null) {
        final currentUserId = supabaseClient.auth.currentUser?.id;
        
        // Determine which UID to use based on whether we're caller or called
        if (callResponse['caller_id'] == currentUserId) {
          _assignedUid = callResponse['caller_uid'] as int?;
          print('MatchedUsersCallPage: Using caller UID: $_assignedUid');
        } else {
          _assignedUid = callResponse['called_uid'] as int?;
          print('MatchedUsersCallPage: Using called UID: $_assignedUid');
        }
        
        if (_assignedUid == null) {
          print('MatchedUsersCallPage: Warning - No UID assigned in database for this call');
          // Generate a random UID as fallback
          _assignedUid = DateTime.now().millisecondsSinceEpoch % 100000;
          print('MatchedUsersCallPage: Using fallback UID: $_assignedUid');
        }
      } else {
        print('MatchedUsersCallPage: Call not found in database, using fallback UID');
        _assignedUid = DateTime.now().millisecondsSinceEpoch % 100000;
      }
    } catch (e) {
      print('MatchedUsersCallPage: Error fetching UID: $e');
      // Use fallback UID
      _assignedUid = DateTime.now().millisecondsSinceEpoch % 100000;
      print('MatchedUsersCallPage: Using fallback UID after error: $_assignedUid');
    }
  }

  Future<void> _checkIfCallAlreadyAccepted() async {
    try {
      print('MatchedUsersCallPage: Checking if call ${widget.callId} is already accepted');
      final supabaseClient = SupabaseClient.instance.client;
      
      // Fetch current call status from database
      final callResponse = await supabaseClient
          .from('calls')
          .select('status')
          .eq('id', widget.callId)
          .maybeSingle();
      
      if (callResponse != null && callResponse['status'] == 'accepted') {
        print('MatchedUsersCallPage: Call is already accepted, starting call for initiator');
        setState(() {
          _callStatus = 'accepted';
        });
        await _startCall();
      } else {
        print('MatchedUsersCallPage: Call not yet accepted, waiting for acceptance');
      }
    } catch (e) {
      print('MatchedUsersCallPage: Error checking call status: $e');
    }
  }

  void _handleCallDeclined() {
    // Set user as not in call and force status update
    OnlineStatusService().setInCall(false);
    OnlineStatusService().forceRefreshStatus();
    
    _showMessage('${widget.matchedUser['name']} declined the call', isError: true);
    _navigateBack();
  }

  void _handleCallEnded() {
    // Cancel timers
    _callLimitsTimer?.cancel();
    _durationTimer?.cancel();
    
    // Set user as not in call and force status update
    OnlineStatusService().setInCall(false);
    OnlineStatusService().forceRefreshStatus();
    
    if (!_isAutoEnding) {
      _showMessage('Call ended');
    }
    _navigateBack();
  }

  void _startCallLimitsChecking() {
    // Check immediately, then every 15 seconds
    _checkCallLimits();
    
    _callLimitsTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_isCallActive && !_isLeavingCall && !_isAutoEnding) {
        _checkCallLimits();
      }
    });
  }
  
  Future<void> _checkCallLimits() async {
    try {
      final supabaseClient = SupabaseClient.instance.client;
      final response = await supabaseClient.functions.invoke(
        'check-call-limits',
        body: {
          'call_id': widget.callId,
        },
      );
      
      if (response.status == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        
        if (mounted) {
          setState(() {
            _callerSecondsRemaining = data['callerSecondsRemaining'] ?? 300;
            _calledSecondsRemaining = data['calledSecondsRemaining'] ?? 300;
            _maxCallDurationSeconds = data['maxDurationSeconds'] ?? 300;
            
            // Calculate actual remaining seconds (minimum of all limits)
            final durationSeconds = data['durationSeconds'] ?? 0;
            final timeRemaining = _maxCallDurationSeconds - durationSeconds;
            _actualSecondsRemaining = [
              timeRemaining,
              _callerSecondsRemaining,
              _calledSecondsRemaining,
            ].reduce((a, b) => a < b ? a : b).toInt();
            
            // Ensure we don't go negative
            if (_actualSecondsRemaining < 0) {
              _actualSecondsRemaining = 0;
            }
          });
        }
        
        // Check if call should end
        if (data['shouldEnd'] == true) {
          _handleAutoEnd(data['reason'] ?? 'Call time limit reached');
        }
      }
    } catch (e) {
      print('Error checking call limits: $e');
      // Don't end call on error, just continue
    }
  }
  
  void _handleAutoEnd(String reason) {
    if (_isAutoEnding || _isLeavingCall) return;
    
    setState(() {
      _isAutoEnding = true;
    });
    
    // Cancel timers
    _callLimitsTimer?.cancel();
    _durationTimer?.cancel();
    
    // Show reason to user
    _showMessage(reason, duration: const Duration(seconds: 5));
    
    // Clean up and navigate back after showing message
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        OnlineStatusService().setInCall(false);
        OnlineStatusService().forceRefreshStatus();
        _navigateBack();
      }
    });
  }
  
  void _showCallEndingWarning() {
    if (!mounted) return;
    
    _showMessage('Call ending in 30 seconds...', 
      isError: false, 
      duration: const Duration(seconds: 5),
      backgroundColor: Colors.orange);
  }

  Future<void> _endCall() async {
    if (_isLeavingCall) return;
    
    setState(() {
      _isLeavingCall = true;
    });
    
    // Cancel the call limits timer when manually ending
    _callLimitsTimer?.cancel();
    
    // Don't send end call if it's auto-ending (backend already ended it)
    if (_isAutoEnding) {
      _navigateBack();
      return;
    }

    try {
      // Set user as available when leaving call
      OnlineStatusService().setInCall(false);
      
      // Call the manage-call edge function with action: 'end'
      final supabaseClient = SupabaseClient.instance.client;
      final currentUser = supabaseClient.auth.currentUser;
      
      if (currentUser != null) {
        print('Attempting to call manage-call edge function...');
        print('CallId: ${widget.callId}');
        print('UserId: ${currentUser.id}');
        
        try {
          final response = await supabaseClient.functions.invoke(
            'manage-call',
            body: {
              'call_id': widget.callId,
              'action': 'end',
            },
          );
          
          print('Edge function response status: ${response.status}');
          print('Edge function response data: ${response.data}');
          
          if (response.status != 200) {
            print('Edge function error: ${response.data}');
          } else {
            print('Successfully called manage-call edge function');
          }
        } catch (edgeFunctionError) {
          print('Error calling manage-call edge function: $edgeFunctionError');
          // Continue with fallback logic below
        }
      } else {
        print('No authenticated user found - cannot call edge function');
      }
      
      // Update call status to ended (fallback) - only if not auto-ending
      if (!_isAutoEnding) {
        await _callService.endCall(widget.callId);
      }
      
      // Force refresh online status after a short delay to ensure it's registered
      await Future.delayed(const Duration(milliseconds: 500));
      await OnlineStatusService().forceRefreshStatus();
      
      // Additional delay to ensure the other user sees the status update
      await Future.delayed(const Duration(milliseconds: 500));
      
      _navigateBack();
    } catch (e) {
      print('Error ending call: $e');
      // Even on error, ensure we update the status
      OnlineStatusService().setInCall(false);
      OnlineStatusService().forceRefreshStatus();
      _navigateBack();
    }
  }

  void _navigateBack() {
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const CallPage()),
        (route) => route.settings.name == '/home',
      );
    }
  }

  void _showMessage(String message, {
    bool isError = false, 
    Duration duration = const Duration(seconds: 3),
    Color? backgroundColor,
  }) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor ?? (isError ? Colors.red : Colors.grey),
          duration: duration,
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }
  
  String _formatRemainingTime() {
    final minutes = (_actualSecondsRemaining ~/ 60);
    final seconds = (_actualSecondsRemaining % 60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _nextOption() => setState(() => currentIndex = (currentIndex + 1) % options.length);
  void _prevOption() => setState(() => currentIndex = (currentIndex - 1 + options.length) % options.length);

  @override
  Widget build(BuildContext context) {
    // Waiting for call to be accepted
    if (!_isCallActive) {
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
                    // Profile image
                    Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey[300],
                        border: Border.all(
                          color: Colors.green.withOpacity(0.5),
                          width: 3,
                        ),
                      ),
                      child: ClipOval(
                        child: widget.matchedUser['profile_picture_url'] != null && 
                               widget.matchedUser['profile_picture_url'].isNotEmpty
                            ? Image.network(
                                widget.matchedUser['profile_picture_url'],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildPlaceholderAvatar();
                                },
                              )
                            : _buildPlaceholderAvatar(),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // User name
                    Text(
                      widget.matchedUser['name'] ?? 'Unknown',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Status text
                    Text(
                      widget.isInitiator
                          ? 'Calling...'
                          : 'Connecting...',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[400],
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Loading indicator
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
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
                    onPressed: _endCall,
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

    // Active call UI
    return WillPopScope(
      onWillPop: () async {
        // Prevent accidental back navigation during call
        return false;
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Profile picture (no blur)
            Positioned.fill(
              child: widget.matchedUser['profile_picture_url'] != null && 
                     widget.matchedUser['profile_picture_url'].isNotEmpty
                  ? Image.network(
                      widget.matchedUser['profile_picture_url'],
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
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
                    )
                  : Container(
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
            
            // Dark overlay for better text visibility
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
            
            // Top bar with name and duration
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
                        widget.matchedUser['name'] ?? '',
                        style: const TextStyle(
                          fontSize: 24,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Call duration
                      Text(
                        _formatDuration(_callDuration),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Remaining time
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _actualSecondsRemaining <= 30 
                              ? Colors.red.withOpacity(0.8)
                              : _actualSecondsRemaining <= 60
                                  ? Colors.orange.withOpacity(0.8)
                                  : Colors.green.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Time left: ${_formatRemainingTime()}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _isLeavingCall ? null : _endCall,
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.all(
                        _isLeavingCall ? Colors.grey : Colors.red
                      ),
                    ),
                    child: Text(
                      _isLeavingCall ? 'Ending...' : 'End',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            
            // Audio component
            Align(
              alignment: Alignment.center,
              child: JoinChannelAudio(
                channelID: widget.channelName,
                callId: widget.callId,
                uid: _assignedUid,
              ),
            ),
            
            // Bottom section with conversation starter
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Conversation Starter',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_left),
                              onPressed: _prevOption,
                            ),
                            Expanded(
                              child: Text(
                                options[currentIndex],
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_right),
                              onPressed: _nextOption,
                            ),
                          ],
			),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderAvatar() {
    final name = widget.matchedUser['name'] ?? 'Unknown';
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
}
