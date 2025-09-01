import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/agora_service.dart';
import '../services/supabase_client.dart';
import 'waveform.dart';
import 'dart:async';

class JoinChannelAudio extends StatefulWidget {
  final String channelID;
  final String? callId;
  final int? uid;

  const JoinChannelAudio({
    Key? key,
    required this.channelID,
    this.callId,
    this.uid,
  }) : super(key: key);

  @override
  _JoinChannelAudioState createState() => _JoinChannelAudioState();
}

class _JoinChannelAudioState extends State<JoinChannelAudio> {
  final AgoraService _agoraService = AgoraService();
  bool isJoined = false;
  double volume = 0.0;
  bool shouldUpdate = true;
  double _maxVolumeSeen = 1.0;
  bool _isInitializing = true;
  String? _errorMessage;
  bool _isDisposed = false;
  int? _currentUid;
  String _connectionStatus = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _dispose();
    super.dispose();
  }

  Future<void> _dispose() async {
    // Clear the callbacks to prevent memory leaks
    _agoraService.onUserSpeaking = null;
    _agoraService.onError = null;
    _agoraService.onUserJoined = null;
    _agoraService.onCallEnded = null;
    _agoraService.onJoinChannelSuccess = null;
    _agoraService.onTokenPrivilegeWillExpire = null;
    
    // CRITICAL FIX: Always call leaveChannel to clean up state and timers
    // This prevents old token renewal timers from running with stale channel data
    print('JoinChannelAudio: Cleaning up - leaving channel to prevent token renewal issues');
    await _agoraService.leaveChannel();
  }


  Future<void> _initEngine() async {
    if (_isDisposed) return;

    try {
      setState(() {
        _isInitializing = true;
        _errorMessage = null;
        _connectionStatus = 'Connecting to audio service...';
      });

      print('JoinChannelAudio: Initializing for channel ${widget.channelID}');

      // Set up callbacks before joining
      _setupAgoraCallbacks();

      // Use the provided UID from the backend (required for token validation)
      if (widget.uid == null) {
        throw Exception('No UID provided - backend must assign UID before calling this widget');
      }

      _currentUid = widget.uid!;
      print('JoinChannelAudio: Using pre-assigned UID $_currentUid');
      print('JoinChannelAudio: Joining channel ${widget.channelID}');

      // Update status
      setState(() {
        _connectionStatus = 'Joining channel...';
      });

      // Join the channel
      await _agoraService.joinChannel(
        channelName: widget.channelID,
        uid: _currentUid!,
        callId: widget.callId,
      );

      // Success will be handled by the onJoinChannelSuccess callback
    } catch (e) {
      print('JoinChannelAudio: Error initializing: $e');
      if (!_isDisposed && mounted) {
        setState(() {
          _errorMessage = 'Failed to connect to audio: ${e.toString()}';
          _isInitializing = false;
          _connectionStatus = 'Connection failed';
        });
      }
    }
  }

  void _setupAgoraCallbacks() {
    // User speaking callback for waveform animation
    _agoraService.onUserSpeaking = (uid, isSpeaking) {
      if (!_isDisposed && mounted) {
        if (isSpeaking) {
          _updateWaveform(0.7);
        } else {
          _updateWaveform(0.0);
        }
      }
    };

    // Error callback
    _agoraService.onError = (message) {
      print('JoinChannelAudio: Error from AgoraService: $message');
      if (!_isDisposed && mounted) {
        setState(() {
          _errorMessage = message;
          _connectionStatus = 'Error: $message';
        });
      }
    };

    // User joined callback
    _agoraService.onUserJoined = (uid) {
      print('JoinChannelAudio: User joined with uid: $uid');
      if (!_isDisposed && mounted) {
        setState(() {
          _connectionStatus = 'User joined the call';
        });
      }
    };

    // Call ended callback
    _agoraService.onCallEnded = () {
      if (!_isDisposed && mounted) {
        setState(() {
          isJoined = false;
          _connectionStatus = 'Call ended';
        });
      }
    };

    // Join channel success callback
    _agoraService.onJoinChannelSuccess = () {
      print('JoinChannelAudio: Successfully joined channel');
      if (!_isDisposed && mounted) {
        setState(() {
          isJoined = true;
          _isInitializing = false;
          _errorMessage = null;
          _connectionStatus = 'Connected to voice call';
        });
      }
    };

    // Token expiring callback
    _agoraService.onTokenPrivilegeWillExpire = () {
      print('JoinChannelAudio: Token expiring, renewal in progress...');
      if (!_isDisposed && mounted) {
        setState(() {
          _connectionStatus = 'Refreshing connection...';
        });
      }
    };
  }

  void _updateWaveform(double newVolume) {
    if (newVolume > _maxVolumeSeen) {
      _maxVolumeSeen = newVolume;
    }

    if (shouldUpdate && !_isDisposed && mounted) {
      shouldUpdate = !shouldUpdate;
      setState(() {
        if (_maxVolumeSeen == 0) {
          volume = 0; // avoid divide by zero
        } else {
          volume = (newVolume / _maxVolumeSeen).clamp(0.0, 1.0);
        }
      });
    }
  }

  Future<void> _retryConnection() async {
    if (_isDisposed) return;

    setState(() {
      _errorMessage = null;
      _isInitializing = true;
      _connectionStatus = 'Retrying connection...';
    });

    // Wait a bit before retrying
    await Future.delayed(const Duration(seconds: 1));

    if (!_isDisposed && mounted) {
      await _initEngine();
    }
  }

  @override
  Widget build(BuildContext context) {
    shouldUpdate = true;

    if (_isInitializing) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(
            _connectionStatus,
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    if (_errorMessage != null) {
      // Check error type for appropriate UI
      final isPermissionError = _errorMessage!.toLowerCase().contains('permission') ||
          _errorMessage!.toLowerCase().contains('microphone');
      
      final isTokenError = _errorMessage!.toLowerCase().contains('token') ||
          _errorMessage!.toLowerCase().contains('authentication');
      
      final isConnectionError = _errorMessage!.toLowerCase().contains('connect') ||
          _errorMessage!.toLowerCase().contains('network') ||
          _errorMessage!.toLowerCase().contains('timeout');

      IconData errorIcon;
      String errorTitle;
      String errorDescription;

      if (isPermissionError) {
        errorIcon = Icons.mic_off;
        errorTitle = 'Microphone Access Required';
        errorDescription = 'Please allow microphone access in your device settings to join the call.';
      } else if (isTokenError) {
        errorIcon = Icons.lock_outline;
        errorTitle = 'Authentication Error';
        errorDescription = 'There was an issue with call authentication. Please try again.';
      } else if (isConnectionError) {
        errorIcon = Icons.wifi_off;
        errorTitle = 'Connection Error';
        errorDescription = 'Unable to connect to the call. Please check your internet connection.';
      } else {
        errorIcon = Icons.error_outline;
        errorTitle = 'Connection Error';
        errorDescription = _errorMessage!;
      }

      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            errorIcon,
            color: Colors.red,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            errorTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              errorDescription,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          if (isPermissionError) ...[
            ElevatedButton.icon(
              onPressed: () async {
                final opened = await openAppSettings();
                if (opened) {
                  // Wait a moment and retry
                  Future.delayed(const Duration(seconds: 1), () {
                    if (mounted) {
                      _retryConnection();
                    }
                  });
                }
              },
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Enable microphone permission in Settings',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ] else ...[
            ElevatedButton.icon(
              onPressed: _retryConnection,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      );
    }

    // Successfully connected UI
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Waveform visualization
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8.0,
                offset: const Offset(2, 4),
              ),
            ],
          ),
          child: CustomPaint(
            painter: WaveformWidget(volume),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Connection status
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isJoined ? Icons.fiber_manual_record : Icons.hourglass_empty,
              color: isJoined ? Colors.green : Colors.orange,
              size: 12,
            ),
            const SizedBox(width: 8),
            Text(
              _connectionStatus,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        
        if (isJoined) ...[
          const SizedBox(height: 8),
          Text(
            'Channel: ${widget.channelID}',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          if (_currentUid != null) ...[
            Text(
              'UID: $_currentUid',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ],
        ],
      ],
    );
  }
}