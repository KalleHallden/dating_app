import 'package:flutter/material.dart';
import '../services/agora_service.dart';
import '../services/supabase_client.dart';
import 'waveform.dart';

class JoinChannelAudio extends StatefulWidget {
  final String channelID;
  final String? callId; // Add this to track the database call ID
  
  const JoinChannelAudio({
    Key? key, 
    required this.channelID,
    this.callId,
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
    await _agoraService.leaveChannel();
    await _agoraService.dispose();
  }

  Future<void> _initEngine() async {
    try {
      setState(() {
        _isInitializing = true;
        _errorMessage = null;
      });

      print('JoinChannelAudio: Initializing engine for channel ${widget.channelID}');

      // Set up callbacks
      _agoraService.onUserSpeaking = (uid, isSpeaking) {
        if (!_isDisposed) {
          if (isSpeaking) {
            _updateWaveform(0.7); // Show activity when someone is speaking
          } else {
            _updateWaveform(0.0);
          }
        }
      };

      _agoraService.onError = (message) {
        print('JoinChannelAudio: Error from AgoraService: $message');
        if (!_isDisposed && mounted) {
          setState(() {
            _errorMessage = message;
          });
        }
      };

      _agoraService.onUserJoined = (uid) {
        print('JoinChannelAudio: User joined with uid: $uid');
      };

      _agoraService.onCallEnded = () {
        if (!_isDisposed && mounted) {
          setState(() {
            isJoined = false;
          });
        }
      };

      // Initialize the service
      await _agoraService.initialize();

      // Get current user for UID generation
      final currentUser = SupabaseClient.instance.client.auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Generate a consistent UID from user ID
      // Use hashCode and ensure it fits in 32-bit integer range
      final uid = currentUser.id.hashCode.abs() % 2147483647;
      
      print('JoinChannelAudio: Generated UID $uid for user ${currentUser.id}');
      print('JoinChannelAudio: Joining channel ${widget.channelID} with callId ${widget.callId}');

      // Join the channel with the call ID if provided
      await _agoraService.joinChannel(
        channelName: widget.channelID,
        uid: uid,
        callId: widget.callId,
      );

      if (!_isDisposed && mounted) {
        setState(() {
          isJoined = true;
          _isInitializing = false;
        });
      }
    } catch (e) {
      print('JoinChannelAudio: Error initializing audio: $e');
      if (!_isDisposed && mounted) {
        setState(() {
          _errorMessage = 'Failed to connect to audio: $e';
          _isInitializing = false;
        });
      }
    }
  }

  void _updateWaveform(double newVolume) {
    if (newVolume > _maxVolumeSeen) {
      _maxVolumeSeen = newVolume;
    }
    
    if (shouldUpdate && !_isDisposed) {
      shouldUpdate = !shouldUpdate;
      if (mounted) {
        setState(() {
          if (_maxVolumeSeen == 0) volume = 0; // avoid divide by zero
          volume = (newVolume / _maxVolumeSeen).clamp(0.0, 1.0);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    shouldUpdate = true;

    if (_isInitializing) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Connecting audio...',
            style: TextStyle(color: Colors.white),
          ),
        ],
      );
    }

    if (_errorMessage != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initEngine,
            child: const Text('Retry'),
          ),
        ],
      );
    }

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
        if (!isJoined)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Connecting...',
              style: TextStyle(color: Colors.white70),
            ),
          ),
      ],
    );
  }
}
