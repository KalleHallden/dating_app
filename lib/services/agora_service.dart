// lib/services/agora_service.dart
import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'supabase_client.dart';

class AgoraService {
  static final AgoraService _instance = AgoraService._internal();
  factory AgoraService() => _instance;
  AgoraService._internal();

  RtcEngine? _engine;
  String? _currentToken;
  String? _currentChannel;
  int? _currentUid;
  DateTime? _tokenExpiryTime;
  Timer? _tokenRenewalTimer;
  String? _currentCallId; // Add this to track the database call ID

  // Callbacks
  Function(int uid, bool isSpeaking)? onUserSpeaking;
  Function(int uid)? onUserJoined;
  Function(int uid, UserOfflineReasonType reason)? onUserOffline;
  Function(RtcConnection connection, RtcStats stats)? onRtcStats;
  Function(String message)? onError;
  Function()? onTokenExpiring;
  Function()? onCallEnded;

  bool _isInitialized = false;
  bool _inCall = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Request permissions
      await _requestPermissions();

      // Create Agora engine
      _engine = createAgoraRtcEngine();
      
      // Don't initialize yet - we'll do it when we get the app ID from server

      // Set up event handlers
      _setupEventHandlers();

      _isInitialized = true;
      print('Agora service initialized successfully');
    } catch (e) {
      print('Error initializing Agora service: $e');
      onError?.call('Failed to initialize audio service: $e');
      rethrow;
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.microphone,
    ].request();
  }

  void _setupEventHandlers() {
    _engine?.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          print('Successfully joined channel: ${connection.channelId}');
          _inCall = true;
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          print('User joined: $remoteUid');
          onUserJoined?.call(remoteUid);
        },
        onUserOffline: (RtcConnection connection, int remoteUid, UserOfflineReasonType reason) {
          print('User offline: $remoteUid, reason: $reason');
          onUserOffline?.call(remoteUid, reason);
        },
        onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
          print('Token will expire soon, renewing...');
          onTokenExpiring?.call();
          _renewToken();
        },
        onRequestToken: (RtcConnection connection) {
          print('Token expired, renewing...');
          _renewToken();
        },
        onError: (ErrorCodeType err, String msg) {
          print('Agora error: $err - $msg');
          onError?.call('Audio error: $msg');
          
          if (err == ErrorCodeType.errTokenExpired) {
            _renewToken();
          }
        },
        onRtcStats: (RtcConnection connection, RtcStats stats) {
          onRtcStats?.call(connection, stats);
        },
        onAudioVolumeIndication: (
          RtcConnection connection,
          List<AudioVolumeInfo> speakers,
          int speakerNumber,
          int totalVolume,
        ) {
          for (final speaker in speakers) {
            if (speaker.uid != null && speaker.uid != 0) {
              onUserSpeaking?.call(speaker.uid!, speaker.volume! > 0);
            }
          }
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          print('Left channel');
          _inCall = false;
          onCallEnded?.call();
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _generateToken(String channelName, int uid) async {
    try {
      print('Generating token for channel: $channelName, uid: $uid');
      
      final response = await SupabaseClient.instance.client.functions.invoke(
        'generate-agora-token',
        body: {
          'channelName': channelName,
          'uid': uid,
          'role': 'publisher',
        },
      );

      print('Token generation response status: ${response.status}');
      print('Token generation response data: ${response.data}');

      if (response.data == null) {
        throw Exception('Failed to generate token: No data returned');
      }

      final data = response.data as Map<String, dynamic>;
      
      // Validate response data
      if (data['token'] == null || data['appId'] == null) {
        throw Exception('Invalid token response: missing token or appId');
      }

      return data;
    } catch (e) {
      print('Error generating token: $e');
      throw Exception('Failed to generate token: $e');
    }
  }

  Future<void> joinChannel({
    required String channelName,
    required int uid,
    String? initialToken,
    String? callId, // Add this parameter
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      print('AgoraService: Joining channel $channelName with uid $uid');
      
      _currentChannel = channelName;
      _currentUid = uid;
      _currentCallId = callId; // Store the call ID

      // Generate or use provided token
      Map<String, dynamic> tokenData;
      if (initialToken != null) {
        print('AgoraService: Using provided token');
        // If token is provided, use it but still fetch app ID from server
        tokenData = await _generateToken(channelName, uid);
        _currentToken = initialToken;
      } else {
        print('AgoraService: Generating new token');
        tokenData = await _generateToken(channelName, uid);
        _currentToken = tokenData['token'];
      }

      final appId = tokenData['appId'];
      final expiresIn = tokenData['expiresIn'] ?? 86400;

      print('AgoraService: Got appId: $appId, token length: ${_currentToken?.length}');

      // Calculate token expiry time
      _tokenExpiryTime = DateTime.now().add(Duration(seconds: expiresIn));

      // Set up token renewal timer (renew 5 minutes before expiry)
      _setupTokenRenewalTimer(expiresIn - 300);

      // Update app ID if needed
      if (_engine != null) {
        print('AgoraService: Initializing engine with appId');
        await _engine!.initialize(RtcEngineContext(
          appId: appId,
        ));
      }

      // Configure audio settings
      print('AgoraService: Configuring audio settings');
      await _engine!.setChannelProfile(ChannelProfileType.channelProfileCommunication);
      await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await _engine!.enableAudio();
      await _engine!.enableLocalAudio(true);
      await _engine!.setDefaultAudioRouteToSpeakerphone(false);
      
      // Enable volume indication
      await _engine!.enableAudioVolumeIndication(
        interval: 200,
        smooth: 3,
        reportVad: true,
      );

      // Join channel
      print('AgoraService: Attempting to join channel with token');
      await _engine!.joinChannel(
        token: _currentToken!,
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          autoSubscribeAudio: true,
          publishMicrophoneTrack: true,
        ),
      );

      print('AgoraService: joinChannel called successfully');
    } catch (e) {
      print('AgoraService: Error joining channel: $e');
      print('AgoraService: Error type: ${e.runtimeType}');
      if (e is AgoraRtcException) {
        print('AgoraService: Agora error code: ${e.code}');
      }
      onError?.call('Failed to join call: $e');
      rethrow;
    }
  }

  void _setupTokenRenewalTimer(int secondsUntilRenewal) {
    _tokenRenewalTimer?.cancel();
    
    if (secondsUntilRenewal > 0) {
      _tokenRenewalTimer = Timer(
        Duration(seconds: secondsUntilRenewal),
        () => _renewToken(),
      );
    }
  }

  Future<void> _renewToken() async {
    if (_currentChannel == null || _currentUid == null) return;

    try {
      print('Renewing Agora token...');
      final tokenData = await _generateToken(_currentChannel!, _currentUid!);
      _currentToken = tokenData['token'];
      final expiresIn = tokenData['expiresIn'] ?? 86400;

      // Update token expiry time
      _tokenExpiryTime = DateTime.now().add(Duration(seconds: expiresIn));

      // Renew token in the engine
      await _engine?.renewToken(_currentToken!);

      // Set up next renewal
      _setupTokenRenewalTimer(expiresIn - 300);

      print('Token renewed successfully');
    } catch (e) {
      print('Error renewing token: $e');
      onError?.call('Failed to renew call token: $e');
    }
  }

  Future<void> leaveChannel() async {
    try {
      _tokenRenewalTimer?.cancel();
      await _engine?.leaveChannel();
      _currentChannel = null;
      _currentToken = null;
      _currentUid = null;
      _currentCallId = null;
      _tokenExpiryTime = null;
      _inCall = false;
    } catch (e) {
      print('Error leaving channel: $e');
    }
  }

  Future<void> toggleMute(bool mute) async {
    try {
      await _engine?.muteLocalAudioStream(mute);
    } catch (e) {
      print('Error toggling mute: $e');
      onError?.call('Failed to toggle mute: $e');
    }
  }

  Future<void> toggleSpeaker(bool speakerOn) async {
    try {
      await _engine?.setEnableSpeakerphone(speakerOn);
    } catch (e) {
      print('Error toggling speaker: $e');
      onError?.call('Failed to toggle speaker: $e');
    }
  }

  Future<void> dispose() async {
    try {
      _tokenRenewalTimer?.cancel();
      await leaveChannel();
      await _engine?.release();
      _engine = null;
      _isInitialized = false;
    } catch (e) {
      print('Error disposing Agora service: $e');
    }
  }

  bool get isInCall => _inCall;
  String? get currentChannel => _currentChannel;
  DateTime? get tokenExpiryTime => _tokenExpiryTime;
}
