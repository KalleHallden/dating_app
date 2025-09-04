// lib/services/agora_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' show min;
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
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
  String? _currentCallId;
  String? _currentAppId;

  // Callbacks
  Function(int uid, bool isSpeaking)? onUserSpeaking;
  Function(int uid)? onUserJoined;
  Function(int uid, UserOfflineReasonType reason)? onUserOffline;
  Function(RtcConnection connection, RtcStats stats)? onRtcStats;
  Function(String message)? onError;
  Function()? onTokenPrivilegeWillExpire;
  Function()? onCallEnded;
  Function()? onJoinChannelSuccess;

  // State management flags
  bool _isInitialized = false;
  bool _inCall = false;
  bool _isJoiningChannel = false;
  bool _isDisposing = false;
  bool _isRenewingToken = false;
  bool _isConfigured = false;

  // Retry logic
  int _retryCount = 0;
  static const int _maxRetries = 3;
  Timer? _retryTimer;

  /// Initialize the Agora engine (one-time setup)
  Future<void> initialize() async {
    if (_isInitialized || _isDisposing) {
      print(
          'AgoraService: Skipping initialize - already initialized: $_isInitialized, disposing: $_isDisposing');
      return;
    }

    try {
      print('AgoraService: Initializing engine...');

      // Create Agora engine
      _engine = createAgoraRtcEngine();
      _isInitialized = true;
      _isConfigured = false; // Engine created but not configured

      print('AgoraService: Engine created successfully');
    } catch (e) {
      print('AgoraService: Error creating engine: $e');
      _isInitialized = false;
      onError?.call('Failed to initialize audio service: $e');
      rethrow;
    }
  }

  /// Configure the engine with app ID and event handlers
  Future<void> _configureEngine(String appId) async {
    if (!_isInitialized || _engine == null || _isConfigured) {
      print(
          'AgoraService: Skipping configure - initialized: $_isInitialized, engine: ${_engine != null}, configured: $_isConfigured');
      return;
    }

    try {
      print(
          'AgoraService: Configuring engine with appId: ${appId.substring(0, 8)}...');

      // Initialize engine with app ID
      await _engine!.initialize(RtcEngineContext(
        appId: appId,
        logConfig: LogConfig(level: LogLevel.logLevelInfo),
      ));

      // Set up event handlers
      _setupEventHandlers();

      // Configure audio settings
      await _configureAudioSettings();

      _isConfigured = true;
      _currentAppId = appId;

      print('AgoraService: Engine configured successfully');
    } catch (e) {
      print('AgoraService: Error configuring engine: $e');
      _isConfigured = false;
      if (e is AgoraRtcException && e.code == -8) {
        print(
            'AgoraService: Engine already initialized error (-8), marking as configured');
        _isConfigured = true;
        _currentAppId = appId;
      } else {
        rethrow;
      }
    }
  }

  /// Configure audio settings (safe to call multiple times)
  Future<void> _configureAudioSettings() async {
    if (!_isInitialized || _engine == null) {
      print('AgoraService: Cannot configure audio - engine not ready');
      return;
    }

    try {
      print('AgoraService: Configuring audio settings');

      await _engine!
          .setChannelProfile(ChannelProfileType.channelProfileCommunication);
      await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      // Essential audio setup
      await _engine!.enableAudio();
      await _engine!.enableLocalAudio(true);

      // Configure audio routing
      await _engine!.setDefaultAudioRouteToSpeakerphone(true);

      // Audio quality settings
      await _engine!.setAudioProfile(
        profile: AudioProfileType.audioProfileSpeechStandard,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );

      // Enable volume indication
      await _engine!.enableAudioVolumeIndication(
        interval: 200,
        smooth: 3,
        reportVad: true,
      );

      // Disable video
      await _engine!.disableVideo();

      // Set volumes
      await _engine!.adjustRecordingSignalVolume(100);
      await _engine!.adjustPlaybackSignalVolume(100);

      print('AgoraService: Audio settings configured');
    } catch (e) {
      print('AgoraService: Error configuring audio settings: $e');
      if (e is AgoraRtcException && e.code == -8) {
        print('AgoraService: Audio settings already configured (error -8)');
      } else {
        rethrow;
      }
    }
  }

  void _setupEventHandlers() {
    if (!_isInitialized || _engine == null) {
      print('AgoraService: Cannot setup event handlers - engine not ready');
      return;
    }

    print('AgoraService: Setting up event handlers');
    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          print(
              'AgoraService: Successfully joined channel: ${connection.channelId}');
          _inCall = true;
          _isJoiningChannel = false;
          _retryCount = 0; // Reset retry count on success
          onJoinChannelSuccess?.call();

          // Enable speakerphone after successful join
          Future.delayed(Duration(milliseconds: 500), () {
            _engine?.setEnableSpeakerphone(true);
          });
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          print('AgoraService: User joined: $remoteUid');
          onUserJoined?.call(remoteUid);
        },
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          print('AgoraService: User offline: $remoteUid, reason: $reason');
          onUserOffline?.call(remoteUid, reason);
        },
        onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
          print('AgoraService: Token privilege will expire soon');
          onTokenPrivilegeWillExpire?.call();
          _renewTokenSafe();
        },
        onRequestToken: (RtcConnection connection) {
          print('AgoraService: Token expired, requesting new token');
          _renewTokenSafe();
        },
        onError: (ErrorCodeType err, String msg) {
          print('AgoraService: Error: $err - $msg');

          if (err == ErrorCodeType.errTokenExpired ||
              err == ErrorCodeType.errInvalidToken) {
            print('AgoraService: Token error detected, attempting renewal');
            _renewTokenSafe();
          } else if (err.name.contains('-8')) {
            print('AgoraService: Engine state error (-8), attempting recovery');
            _handleEngineStateError();
          } else {
            onError?.call('Audio error: $msg');
          }
        },
        onConnectionStateChanged: (RtcConnection connection,
            ConnectionStateType state, ConnectionChangedReasonType reason) {
          print('AgoraService: Connection state: $state, reason: $reason');

          if (state == ConnectionStateType.connectionStateFailed) {
            if (reason ==
                    ConnectionChangedReasonType.connectionChangedTokenExpired ||
                reason ==
                    ConnectionChangedReasonType.connectionChangedInvalidToken) {
              print('AgoraService: Connection failed due to token issue');
              _renewTokenSafe();
            } else {
              print('AgoraService: Connection failed, reason: $reason');
              _handleConnectionFailure();
            }
          } else if (state == ConnectionStateType.connectionStateConnected) {
            print('AgoraService: Successfully connected to channel');
            _retryCount = 0;
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
            final uid = speaker.uid ?? 0;
            final volume = speaker.volume ?? 0;
            onUserSpeaking?.call(uid, volume > 10);
          }
        },
        onLeaveChannel: (RtcConnection connection, RtcStats stats) {
          print('AgoraService: Left channel');

          // Only trigger call ended if we're not in a retry scenario
          // (retry happens when we're still joining but leave to clear state)
          if (!_isJoiningChannel) {
            print('AgoraService: Call genuinely ended, cleaning up');
            _inCall = false;
            onCallEnded?.call();
          } else {
            print(
                'AgoraService: Left channel for retry - keeping call state intact');
          }

          // Always reset joining flag when we actually leave
          // (this will be set back to true when we retry)
          if (!_isJoiningChannel) {
            _isJoiningChannel = false;
          }
        },
      ),
    );
  }

  /// Safely renew token (prevents concurrent renewals)
  Future<void> _renewTokenSafe() async {
    if (_isRenewingToken || _currentChannel == null || _currentUid == null) {
      print(
          'AgoraService: Skipping token renewal - already renewing: $_isRenewingToken, or missing channel/uid');
      return;
    }

    // Additional safety check: don't renew if we're not in a call context
    // Allow renewal if we have call context (attempting to join or already joined)
    if (!_inCall && !_isJoiningChannel) {
      print('AgoraService: Skipping token renewal - not in call context');
      return;
    }

    _isRenewingToken = true;

    try {
      print('AgoraService: === TOKEN RENEWAL ATTEMPT ===');
      print(
          'AgoraService: Renewing token for channel $_currentChannel, uid $_currentUid');
      print(
          'AgoraService: Current state - _inCall: $_inCall, _isJoiningChannel: $_isJoiningChannel');
      final tokenData = await _generateToken(_currentChannel!, _currentUid!,
          callId: _currentCallId);

      if (_engine != null && _isInitialized && !_isDisposing) {
        final newToken = tokenData['token'] as String;

        // Log token details for debugging
        print(
            'AgoraService: New token starts with: ${newToken.substring(0, min(20, newToken.length))}...');
        print('AgoraService: Token length: ${newToken.length}');

        // Only update if we got a different token
        if (newToken != _currentToken) {
          _currentToken = newToken;
          await _engine!.renewToken(_currentToken!);

          // Update expiry time
          final expiresIn = tokenData['expiresIn'] ?? 86400;
          _tokenExpiryTime = DateTime.now().add(Duration(seconds: expiresIn));

          // Setup next renewal
          _setupTokenRenewalTimer(expiresIn);

          print(
              'AgoraService: Token renewed successfully with same uid: $_currentUid');

          // If we were trying to join and failed, retry now with new token
          if (_isJoiningChannel && !_isDisposing) {
            print(
                'AgoraService: Token error recovery - leaving channel first to clear state');

            // Leave the channel to clear the bad state
            try {
              await _engine!.leaveChannel();
              print('AgoraService: Left channel successfully');
            } catch (e) {
              print('AgoraService: Error leaving channel: $e');
            }

            // Small delay to ensure clean state
            await Future.delayed(Duration(milliseconds: 500));

            print('AgoraService: Retrying channel join with fresh token');
            try {
              // Reset joining state to allow clean retry
              _isJoiningChannel = false;
              await Future.delayed(Duration(milliseconds: 100)); // Brief pause
              _isJoiningChannel = true;

              await _joinChannelInternal(
                  _currentChannel!, _currentUid!, _currentToken!);
              print('AgoraService: Retry join initiated successfully');
            } catch (retryError) {
              print('AgoraService: Retry join failed: $retryError');
              // If retry fails with -17, we might need to reset the engine
              if (retryError.toString().contains('-17') ||
                  retryError.toString().contains('17')) {
                print(
                    'AgoraService: Error -17 detected, engine still in bad state');
              }
            }
          }
        } else {
          print(
              'AgoraService: Warning - received same token as before, token generation may be failing');
        }
      }
    } catch (e) {
      print('AgoraService: Error renewing token: $e');
      onError?.call('Failed to renew authentication');

      // Reset the flag even on error to allow retry
      _isRenewingToken = false;

      // If token renewal fails, we might need to rejoin the channel
      if (_retryCount < _maxRetries) {
        _handleConnectionFailure();
      }
    } finally {
      _isRenewingToken = false;
    }
  }

  /// Handle engine state error (-8)
  void _handleEngineStateError() {
    print('AgoraService: Handling engine state error');

    // Don't restart if we're already in a good state or disposing
    if (_inCall || _isDisposing || _isJoiningChannel) {
      print(
          'AgoraService: Skipping engine recovery - inCall: $_inCall, disposing: $_isDisposing, joining: $_isJoiningChannel');
      return;
    }

    // Try to recover by rejoining
    if (_currentChannel != null && _currentUid != null) {
      print('AgoraService: Attempting to recover by rejoining channel');
      _retryJoinChannel();
    }
  }

  /// Handle connection failure with exponential backoff
  void _handleConnectionFailure() {
    if (_retryCount >= _maxRetries || _isDisposing) {
      print('AgoraService: Max retries reached or disposing, giving up');
      onError?.call('Failed to connect after multiple attempts');
      return;
    }

    _retryCount++;
    final delaySeconds =
        (2 << (_retryCount - 1)); // Exponential backoff: 2, 4, 8 seconds

    print(
        'AgoraService: Connection failed, retrying in ${delaySeconds}s (attempt $_retryCount/$_maxRetries)');

    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_isDisposing && _currentChannel != null && _currentUid != null) {
        _retryJoinChannel();
      }
    });
  }

  /// Retry joining channel
  Future<void> _retryJoinChannel() async {
    if (_isJoiningChannel || _isDisposing) {
      print('AgoraService: Skipping retry - already joining or disposing');
      return;
    }

    try {
      print('AgoraService: Retrying channel join...');

      // Leave current channel first if we're in one
      if (_inCall) {
        await _engine?.leaveChannel();
        await Future.delayed(Duration(milliseconds: 500));
      }

      // Rejoin with current parameters
      if (_currentChannel != null &&
          _currentUid != null &&
          _currentToken != null) {
        await _joinChannelInternal(
            _currentChannel!, _currentUid!, _currentToken!);
      }
    } catch (e) {
      print('AgoraService: Retry failed: $e');
      _handleConnectionFailure(); // Try again with backoff
    }
  }

  /// Generate token
  Future<Map<String, dynamic>> _generateToken(String channelName, int uid,
      {String? callId}) async {
    try {
      final Map<String, dynamic> requestBody = {
        'channelName': channelName,
        'uid': uid,
        'role': 'publisher',
      };

      // Include callId if provided (required for backend UID validation)
      if (callId != null) {
        requestBody['callId'] = callId;
      }

      print('AgoraService: === TOKEN REQUEST DEBUG ===');
      print(
          'AgoraService: Requesting token for channelName: $channelName, uid: $uid, callId: $callId');
      print(
          'AgoraService: Current stored channel: $_currentChannel, current stored callId: $_currentCallId');
      print('AgoraService: Request body: ${jsonEncode(requestBody)}');

      final response = await SupabaseClient.instance.client.functions.invoke(
        'generate-agora-token',
        body: requestBody,
      );

      if (response.data == null ||
          response.data['token'] == null ||
          response.data['appId'] == null) {
        throw Exception('Invalid token response');
      }

      print('AgoraService: Token request successful!');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('AgoraService: Error generating token: $e');
      throw Exception('Failed to generate token: $e');
    }
  }

  /// Join channel (public method)
  Future<void> joinChannel({
    required String channelName,
    required int uid,
    String? callId,
  }) async {
    if (_isJoiningChannel) {
      print('AgoraService: Already joining channel, ignoring request');
      return;
    }

    if (_isDisposing) {
      print('AgoraService: Cannot join - service is disposing');
      throw Exception('Service is being disposed');
    }

    _isJoiningChannel = true;
    _retryCount = 0;

    try {
      print('AgoraService: === JOIN CHANNEL DEBUG START ===');
      print(
          'AgoraService: Starting join channel process for $channelName with uid $uid');
      print('AgoraService: callId parameter: $callId');

      // Initialize engine if needed
      if (!_isInitialized) {
        await initialize();
      }

      // Store current parameters
      _currentChannel = channelName;
      _currentUid = uid;
      _currentCallId = callId;

      // Generate token (always get fresh token from backend)
      print('AgoraService: About to generate fresh token...');
      print('AgoraService: - channelName: $channelName');
      print('AgoraService: - uid: $uid');
      print('AgoraService: - callId: $callId');

      Map<String, dynamic> tokenData;
      try {
        tokenData = await _generateToken(channelName, uid, callId: callId);
        _currentToken = tokenData['token'];
        print(
            'AgoraService: Token generated successfully, length: ${_currentToken!.length}');
      } catch (e) {
        print('AgoraService: CRITICAL ERROR - Token generation failed: $e');
        rethrow;
      }

      final appId = tokenData['appId'];
      final expiresIn = tokenData['expiresIn'] ?? 86400;

      // Configure engine if needed
      if (!_isConfigured || _currentAppId != appId) {
        await _configureEngine(appId);
      }

      // Setup token renewal
      _tokenExpiryTime = DateTime.now().add(Duration(seconds: expiresIn));
      _setupTokenRenewalTimer(expiresIn);

      // Join channel - set inCall early to allow token renewal if needed
      print('AgoraService: Setting _inCall = true to enable token renewal');
      _inCall = true;
      await _joinChannelInternal(channelName, uid, _currentToken!);
    } catch (e) {
      print('AgoraService: Error in joinChannel: $e');
      _isJoiningChannel = false;

      // Clear state on error
      _currentChannel = null;
      _currentUid = null;
      _currentCallId = null;
      _currentToken = null;

      onError?.call('Failed to join call: $e');
      rethrow;
    }
  }

  /// Internal join channel method
  Future<void> _joinChannelInternal(
      String channelName, int uid, String token) async {
    if (!_isInitialized || !_isConfigured || _engine == null) {
      throw Exception('Engine not ready for joining channel');
    }

    print('AgoraService: Joining Agora channel with uid: $uid');
    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: uid,
      options: const ChannelMediaOptions(
        autoSubscribeAudio: true,
        publishMicrophoneTrack: true,
        publishCameraTrack: false,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );

    print('AgoraService: joinChannel call completed');
  }

  /// Setup token renewal timer
  void _setupTokenRenewalTimer(int expiresInSeconds) {
    _tokenRenewalTimer?.cancel();

    // Renew 5 minutes before expiry, or halfway through if less than 10 minutes
    final renewalSeconds =
        expiresInSeconds > 600 ? expiresInSeconds - 300 : expiresInSeconds ~/ 2;

    if (renewalSeconds > 0) {
      _tokenRenewalTimer = Timer(Duration(seconds: renewalSeconds), () {
        if (!_isDisposing && _inCall) {
          _renewTokenSafe();
        }
      });
    }
  }

  /// Leave channel
  Future<void> leaveChannel() async {
    print(
        'AgoraService: Leaving channel $_currentChannel - cleaning up state and timers');

    // Cancel timers
    _tokenRenewalTimer?.cancel();
    _retryTimer?.cancel();

    // Reset state
    _isJoiningChannel = false;
    _isRenewingToken = false;
    _retryCount = 0;

    try {
      if (_engine != null && _inCall) {
        await _engine!.leaveChannel();
      }
    } catch (e) {
      print('AgoraService: Error leaving channel: $e');
    }

    // Clear call state
    _currentChannel = null;
    _currentToken = null;
    _currentUid = null;
    _currentCallId = null;
    _tokenExpiryTime = null;
    _inCall = false;

    print('AgoraService: Channel left successfully');
  }

  /// Toggle mute
  Future<void> toggleMute(bool mute) async {
    if (_engine != null && _isInitialized) {
      try {
        await _engine!.muteLocalAudioStream(mute);
      } catch (e) {
        print('AgoraService: Error toggling mute: $e');
      }
    }
  }

  /// Toggle speaker
  Future<void> toggleSpeaker(bool speakerOn) async {
    if (_engine != null && _isInitialized) {
      try {
        await _engine!.setEnableSpeakerphone(speakerOn);
      } catch (e) {
        print('AgoraService: Error toggling speaker: $e');
      }
    }
  }

  /// Dispose service
  Future<void> dispose() async {
    if (_isDisposing) {
      print('AgoraService: Already disposing');
      return;
    }

    _isDisposing = true;
    print('AgoraService: Disposing service...');

    // Cancel all timers
    _tokenRenewalTimer?.cancel();
    _retryTimer?.cancel();

    // Leave channel first
    if (_inCall) {
      await leaveChannel();
    }

    // Release engine
    if (_engine != null) {
      try {
        await _engine!.release();
      } catch (e) {
        print('AgoraService: Error releasing engine: $e');
      }
      _engine = null;
    }

    // Reset all state
    _isInitialized = false;
    _isConfigured = false;
    _inCall = false;
    _isJoiningChannel = false;
    _isRenewingToken = false;
    _currentAppId = null;
    _retryCount = 0;

    print('AgoraService: Service disposed successfully');
    _isDisposing = false;
  }

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isInCall => _inCall;
  bool get isJoiningChannel => _isJoiningChannel;
  String? get currentChannel => _currentChannel;
  DateTime? get tokenExpiryTime => _tokenExpiryTime;
  String? get currentCallId => _currentCallId;
  int? get currentUid => _currentUid;
}
