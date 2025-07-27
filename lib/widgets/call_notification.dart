// lib/widgets/call_notification.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import '../services/call_service.dart';
import '../pages/waiting_call_page.dart';

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
  }

  @override
  void dispose() {
    _callsChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToIncomingCalls() {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    
    if (currentUser == null) {
      print('CallNotification: No current user, skipping subscription');
      return;
    }

    print('CallNotification: Setting up subscription for user ${currentUser.id}');

    // Subscribe to new calls where current user is the called party
    _callsChannel = client
        .channel('incoming-calls-${currentUser.id}')
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
            print('CallNotification: Received call event: $payload');
            final callData = payload.newRecord;
            
            // Only show notification for pending calls
            if (callData['status'] != 'pending') {
              print('CallNotification: Call status is not pending, ignoring');
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

  void _showCallNotification() {
    if (_isShowingNotification || _callerInfo == null || _incomingCall == null) return;
    
    setState(() {
      _isShowingNotification = true;
    });

    // Auto-dismiss after 30 seconds if no action taken
    Future.delayed(const Duration(seconds: 30), () {
      if (_isShowingNotification && mounted) {
        _handleDecline();
      }
    });
  }

  Future<void> _handleAccept() async {
    if (_incomingCall == null) return;

    try {
      // Update call status to accepted
      await _callService.updateCallStatus(_incomingCall!['id'], 'accepted');
      
      // Navigate to waiting call page
      if (mounted) {
        setState(() {
          _isShowingNotification = false;
        });
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WaitingCallPage(
              callId: _incomingCall!['id'],
              channelName: _incomingCall!['channel_name'],
              matchedUser: _callerInfo!,
              isInitiator: false,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error accepting call: $e');
      _showError('Failed to accept call');
    }
  }

  Future<void> _handleDecline() async {
    if (_incomingCall == null) return;

    try {
      // Update call status to declined
      await _callService.updateCallStatus(_incomingCall!['id'], 'declined');
      
      if (mounted) {
        setState(() {
          _isShowingNotification = false;
          _incomingCall = null;
          _callerInfo = null;
        });
      }
    } catch (e) {
      print('Error declining call: $e');
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
                                           _callerInfo!['profile_picture_url'].isNotEmpty
                                ? NetworkImage(_callerInfo!['profile_picture_url'])
                                : null,
                            child: _callerInfo!['profile_picture_url'] == null ||
                                   _callerInfo!['profile_picture_url'].isEmpty
                                ? Text(
                                    _callerInfo!['name'][0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
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
                                  '${_callerInfo!['name']} is calling...',
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
