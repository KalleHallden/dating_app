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

class MatchedUsersCallPage extends StatefulWidget {
  final String callId;
  final String channelName;
  final Map<String, dynamic> matchedUser;
  final bool isInitiator;

  const MatchedUsersCallPage({
    Key? key,
    required this.callId,
    required this.channelName,
    required this.matchedUser,
    required this.isInitiator,
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
  
  // Timer for call duration
  Timer? _durationTimer;
  DateTime? _callStartTime;
  Duration _callDuration = Duration.zero;

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
    _subscribeToCallStatus();
    
    // If initiator, wait for acceptance
    // If not initiator, we already accepted, so start the call
    if (!widget.isInitiator) {
      _startCall();
    }
  }

  @override
  void dispose() {
    _callStatusChannel?.unsubscribe();
    _durationTimer?.cancel();
    OnlineStatusService().setInCall(false);
    super.dispose();
  }

  void _subscribeToCallStatus() {
    _callStatusChannel = _callService.subscribeToCallUpdates(
      widget.callId,
      onUpdate: (callData) {
        if (!mounted) return;
        
        setState(() {
          _callStatus = callData['status'] ?? 'pending';
        });
        
        // Handle different call statuses
        switch (_callStatus) {
          case 'accepted':
            if (widget.isInitiator) {
              _startCall();
            }
            break;
          case 'declined':
            _handleCallDeclined();
            break;
          case 'ended':
            _handleCallEnded();
            break;
        }
      },
    );
  }

  void _startCall() {
    if (_isCallActive) return;
    
    setState(() {
      _isCallActive = true;
      _callStartTime = DateTime.now();
    });
    
    // Start duration timer
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _callDuration = DateTime.now().difference(_callStartTime!);
        });
      }
    });
    
    // Set user as in call
    OnlineStatusService().setInCall(true);
  }

  void _handleCallDeclined() {
    _showMessage('${widget.matchedUser['name']} declined the call', isError: true);
    _navigateBack();
  }

  void _handleCallEnded() {
    _showMessage('Call ended');
    _navigateBack();
  }

  Future<void> _endCall() async {
    if (_isLeavingCall) return;
    
    setState(() {
      _isLeavingCall = true;
    });

    try {
      // Set user as available when leaving call
      OnlineStatusService().setInCall(false);
      
      // Update call status to ended
      await _callService.endCall(widget.callId);
      
      _navigateBack();
    } catch (e) {
      print('Error ending call: $e');
      _navigateBack();
    }
  }

  void _navigateBack() {
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
        (_) => false,
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
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
    return Scaffold(
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
                    Text(
                      _formatDuration(_callDuration),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: _endCall,
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.all(Colors.red),
                  ),
                  child: const Text('End', style: TextStyle(color: Colors.white)),
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
