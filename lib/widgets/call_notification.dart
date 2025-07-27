// lib/widgets/call_notification.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import '../services/call_service.dart';
import '../pages/waiting_call_page.dart';
import '../pages/matched_users_call_page.dart';

class CallNotificationOverlay extends StatefulWidget {
  final Widget child;
  
  const CallNotificationOverlay({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<CallNotificationOverlay> createState() => _CallNotificationOverlayState();
}

class _CallNotificationOverlayState extends State<CallNotificationOverlay> {
  final CallService _callService = CallService();
  supabase.RealtimeChannel? _callsChannel;
  Map<String, dynamic>? _incomingCall;
  Map<String, dynamic>? _callerInfo;
  bool _isShowingNotification = false;

  @override
  void initState() {
    super.initState();
    _subscribeToIncomingCalls();
    _checkForPendingCalls(); // Add this to check for any pending calls on startup
  }

  @override
  void dispose() {
    _callsChannel?.unsubscribe();
    super.dispose();
  }

  // Check for any pending calls when the widget initializes
  Future<void> _checkForPendingCalls() async {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    
    if (currentUser == null) return;

    try {
      // Check for any pending calls where current user is the called party
      final pendingCalls = await client
          .from('calls')
          .select('*')
          .eq('called_id', currentUser.id)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1);

      if (pendingCalls.isNotEmpty) {
        final callData = pendingCalls.first;
        print('CallNotification: Found pending call on startup: ${callData['id']}');
        
        // Fetch caller information
        final callerResponse = await client
            .from('users')
            .select('*')
            .eq('user_id', callData['caller_id'])
            .single();
        
        if (mounted) {
          setState(() {
            _incomingCall = callData;
            _callerInfo = callerResponse;
          });
          
          _showCallNotification();
        }
      }
    } catch (e) {
      print('CallNotification: Error checking pending calls: $e');
    }
  }

  void _subscribeToIncomingCalls() {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    
    if (currentUser == null) {
      print('CallNotification: No current user, skipping subscription');
      return;
    }

    print('CallNotification: Setting up subscription for user ${currentUser.id}');

    // Create a unique channel name to avoid conflicts
    final channelName = 'incoming-calls-${currentUser.id}-${DateTime.now().millisecondsSinceEpoch}';

    // Subscribe to both INSERT and UPDATE events
    _callsChannel = client
        .channel(channelName)
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.insert,
          schema: 'public',
          table: 'calls',
          filter: supabase.PostgresChangeFilter(
            type: supabase.PostgresChangeFilterType.eq,
            column: 'called_id',
            value: currentUser.id,
          ),
          callback: (payload) async {
            print('CallNotification: Received INSERT call event');
            print('CallNotification: Payload: ${payload.newRecord}');
            await _handleIncomingCall(payload.newRecord);
          },
        )
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.update,
          schema: 'public',
          table: 'calls',
          callback: (payload) async {
            final callData = payload.newRecord;
            print('CallNotification: Received UPDATE call event: ${callData['status']}');
            
            // If a call we're showing becomes declined or ended, hide the notification
            if (_incomingCall != null && 
                callData['id'] == _incomingCall!['id'] &&
                (callData['status'] == 'declined' || 
                 callData['status'] == 'ended' ||
                 callData['status'] == 'completed')) {
              if (mounted) {
                setState(() {
                  _isShowingNotification = false;
                  _incomingCall = null;
                  _callerInfo = null;
                });
              }
            }
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            print('CallNotification: Subscription error: $error');
          } else {
            print('CallNotification: Subscription status: $status');
          }
        });
  }

  Future<void> _handleIncomingCall(Map<String, dynamic> callData) async {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    
    if (currentUser == null) return;

    // Only show notification for pending calls where we are the called party
    if (callData['status'] != 'pending' || callData['called_id'] != currentUser.id) {
      print('CallNotification: Call not for us or not pending, ignoring');
      return;
    }
    
    print('CallNotification: Incoming call from ${callData['caller_id']}');
    
    // Fetch caller information
    try {
      final callerResponse = await client
          .from('users')
          .select('*')
          .eq('user_id', callData['caller_id'])
          .single();
      
      print('CallNotification: Caller info fetched: ${callerResponse['name']}');
      
      if (mounted) {
        setState(() {
          _incomingCall = callData;
          _callerInfo = callerResponse;
        });
        
        _showCallNotification();
      }
    } catch (e) {
      print('CallNotification: Error fetching caller info: $e');
    }
  }

  void _showCallNotification() {
    if (_isShowingNotification || _callerInfo == null || _incomingCall == null) {
      print('CallNotification: Not showing notification - already showing: $_isShowingNotification, caller: ${_callerInfo != null}, call: ${_incomingCall != null}');
      return;
    }
    
    print('CallNotification: Showing notification for ${_callerInfo!['name']}');
    
    setState(() {
      _isShowingNotification = true;
    });

    // Auto-dismiss after 30 seconds if no action taken
    Future.delayed(const Duration(seconds: 30), () {
      if (_isShowingNotification && mounted) {
        print('CallNotification: Auto-declining after timeout');
        _handleDecline();
      }
    });
  }

  Future<void> _handleAccept() async {
    if (_incomingCall == null || _callerInfo == null) {
      print('CallNotification: Cannot accept - missing call or caller info');
      return;
    }

    final callId = _incomingCall!['id'] as String?;
    final channelName = _incomingCall!['channel_name'] as String?;
    
    if (callId == null || channelName == null) {
      print('CallNotification: Cannot accept - missing callId or channelName');
      _showError('Invalid call data');
      return;
    }

    print('CallNotification: Accepting call $callId');

    try {
      // Update call status to accepted using the manage-call function
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
      
      // Navigate to waiting call page for matched users
      if (mounted) {
        setState(() {
          _isShowingNotification = false;
        });
        
        // Create a proper matched user map with all required fields
        final matchedUser = <String, dynamic>{
          'user_id': _callerInfo!['user_id'] ?? '',
          'name': _callerInfo!['name'] ?? 'Unknown',
          'age': _callerInfo!['age'] ?? 0,
          'profile_picture_url': _callerInfo!['profile_picture_url'] ?? _callerInfo!['profile_picture'] ?? '',
          'is_online': _callerInfo!['online'] ?? false,
          'is_available': _callerInfo!['is_available'] ?? false,
        };
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WaitingCallPage(
              callId: callId,
              channelName: channelName,
              matchedUser: matchedUser,
              isInitiator: false,
            ),
          ),
        );
        
        // Clear the notification state
        setState(() {
          _incomingCall = null;
          _callerInfo = null;
        });
      }
    } catch (e) {
      print('CallNotification: Error accepting call: $e');
      _showError('Failed to accept call');
    }
  }

  Future<void> _handleDecline() async {
    if (_incomingCall == null) return;

    final callId = _incomingCall!['id'] as String?;
    if (callId == null) {
      print('CallNotification: Cannot decline - missing callId');
      return;
    }

    print('CallNotification: Declining call $callId');

    try {
      // Update call status to declined using the manage-call function
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
      
      if (mounted) {
        setState(() {
          _isShowingNotification = false;
          _incomingCall = null;
          _callerInfo = null;
        });
      }
    } catch (e) {
      print('CallNotification: Error declining call: $e');
      _showError('Failed to decline call');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isShowingNotification && _callerInfo != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 10,
                  left: 10,
                  right: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          // Caller avatar
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: _callerInfo!['profile_picture_url'] != null &&
                                           _callerInfo!['profile_picture_url'].toString().isNotEmpty
                                ? NetworkImage(_callerInfo!['profile_picture_url'])
                                : null,
                            child: _callerInfo!['profile_picture_url'] == null ||
                                   _callerInfo!['profile_picture_url'].toString().isEmpty
                                ? Text(
                                    _callerInfo!['name'] != null && _callerInfo!['name'].toString().isNotEmpty 
                                        ? _callerInfo!['name'][0].toUpperCase() 
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 15),
                          // Caller info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Incoming Call',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_callerInfo!['name'] ?? 'Unknown'} is calling...',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Action buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Decline button
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _handleDecline,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ),
                              icon: const Icon(Icons.call_end),
                              label: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Accept button
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _handleAccept,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ),
                              icon: const Icon(Icons.call),
                              label: const Text('Accept'),
                            ),
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
    );
  }
}
