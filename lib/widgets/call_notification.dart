// lib/widgets/call_notification.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/call_notification_service.dart';
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
  final CallNotificationService _notificationService = CallNotificationService();
  StreamSubscription<CallNotificationState>? _notificationSubscription;
  CallNotificationState? _currentState;

  @override
  void initState() {
    super.initState();
    print('CallNotificationOverlay: initState called');
    
    // Set up navigation callback
    _notificationService.onAcceptCall = _handleAcceptedCall;
    
    // Listen to notification state changes
    _notificationSubscription = _notificationService.notificationState.listen((state) {
      print('CallNotificationOverlay: Notification state changed - showing: ${state.isShowing}');
      if (mounted) {
        setState(() {
          _currentState = state;
        });
      }
    });
  }

  @override
  void dispose() {
    print('CallNotificationOverlay: dispose called');
    _notificationSubscription?.cancel();
    super.dispose();
  }

  void _handleAcceptedCall(Map<String, dynamic> callData, Map<String, dynamic> callerInfo) {
    print('CallNotificationOverlay: Handling accepted call');
    
    final callId = callData['id'] as String;
    final channelName = callData['channel_name'] as String;
    
    // Create a proper matched user map with all required fields
    final matchedUser = <String, dynamic>{
      'user_id': callerInfo['user_id'] ?? '',
      'name': callerInfo['name'] ?? 'Unknown',
      'age': callerInfo['age'] ?? 0,
      'profile_picture_url': callerInfo['profile_picture_url'] ?? callerInfo['profile_picture'] ?? '',
      'is_online': callerInfo['online'] ?? false,
      'is_available': callerInfo['is_available'] ?? false,
    };
    
    if (mounted) {
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
        if (_currentState != null && _currentState!.isShowing && _currentState!.callerInfo != null)
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
                            backgroundImage: _currentState!.callerInfo!['profile_picture_url'] != null &&
                                           _currentState!.callerInfo!['profile_picture_url'].toString().isNotEmpty
                                ? NetworkImage(_currentState!.callerInfo!['profile_picture_url'])
                                : null,
                            child: _currentState!.callerInfo!['profile_picture_url'] == null ||
                                   _currentState!.callerInfo!['profile_picture_url'].toString().isEmpty
                                ? Text(
                                    _currentState!.callerInfo!['name'] != null && _currentState!.callerInfo!['name'].toString().isNotEmpty 
                                        ? _currentState!.callerInfo!['name'][0].toUpperCase() 
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
                                  '${_currentState!.callerInfo!['name'] ?? 'Unknown'} is calling...',
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
                              onPressed: () {
                                _notificationService.handleDecline();
                              },
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
                              onPressed: () {
                                _notificationService.handleAccept();
                              },
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
