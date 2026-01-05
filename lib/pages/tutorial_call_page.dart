// lib/pages/tutorial_call_page.dart
import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import '../services/tutorial_manager.dart';
import '../widgets/tutorial_spotlight.dart';
import 'waveform.dart';

class TutorialCallPage extends StatefulWidget {
  const TutorialCallPage({super.key});

  @override
  State<TutorialCallPage> createState() => _TutorialCallPageState();
}

class _TutorialCallPageState extends State<TutorialCallPage>
    with TickerProviderStateMixin {
  bool _showSearching = true;
  bool _showTutorialOverlay = false;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  // Timer for 5-minute countdown
  Timer? _callTimer;
  int _callSecondsRemaining = 300; // 5 minutes

  // Global keys for tutorial targeting - one for each button
  final GlobalKey _searchingTargetKey = GlobalKey();
  final GlobalKey _timerKey = GlobalKey();
  final GlobalKey _progressBarKey = GlobalKey();
  final GlobalKey _icebreakersKey = GlobalKey();
  final GlobalKey _likeButtonKey = GlobalKey();
  final GlobalKey _nextButtonKey = GlobalKey();
  final GlobalKey _leaveButtonKey = GlobalKey();
  final GlobalKey _menuButtonKey = GlobalKey();

  int currentQuestionIndex = 0;
  final List<String> questions = [
    "go skiing or snorkeling?",
    "eat pizza or burgers?",
    "travel to the mountains or the beach?",
  ];

  // Voice animation waveform data
  List<double> _spectrumData = List.generate(13, (index) => 0.0);
  Timer? _waveformTimer;
  bool _shouldUpdateWaveform = true;

  // Audio player for tutorial voice
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlayingAudio = false;

  // Microphone recorder for real audio input
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecordingMic = false;
  String? _recordingPath;

  // Like button state
  bool _isLiked = false;

  @override
  void initState() {
    super.initState();

    _progressController = AnimationController(
      duration: const Duration(minutes: 5),
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.linear),
    );

    // Listen for tutorial state changes
    TutorialManager().addListener(_handleTutorialStateChange);

    // Show tutorial overlay after delay
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _showTutorialOverlay = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _callTimer?.cancel();
    _waveformTimer?.cancel();
    _stopMicrophoneMonitoring();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    TutorialManager().removeListener(_handleTutorialStateChange);
    super.dispose();
  }

  void _startCallTimer() {
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_callSecondsRemaining > 0) {
            _callSecondsRemaining--;
          }
          // Don't end call when timer hits 0 - this is just a tutorial
        });
      }
    });
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _startMicrophoneMonitoring() async {
    if (_isRecordingMic) {
      print('Tutorial: Mic already recording, skipping');
      return;
    }

    print('Tutorial: Starting microphone monitoring...');

    try {
      // Check and request microphone permission
      final hasPermission = await _audioRecorder.hasPermission();
      print('Tutorial: Microphone permission: $hasPermission');

      if (hasPermission) {
        // Start recording to monitor microphone input
        // We provide a temporary path - the file will be discarded
        final tempDir = Directory.systemTemp;
        _recordingPath = '${tempDir.path}/tutorial_mic_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: _recordingPath!,
        );

        _isRecordingMic = true;
        print('Tutorial: Microphone recording started at: $_recordingPath');

        // Monitor amplitude levels from microphone
        _waveformTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
          if (!_isRecordingMic || !mounted) return;

          // Toggle update flag to skip every other update (like real call)
          if (!_shouldUpdateWaveform) {
            _shouldUpdateWaveform = true;
            return;
          }
          _shouldUpdateWaveform = false;

          try {
            final amplitude = await _audioRecorder.getAmplitude();
            print('Tutorial: Amplitude: ${amplitude.current} dB, max: ${amplitude.max}');

            // Adjusted audio levels based on actual measurements:
            // -45dB or lower = silence/background noise (your actual silent level is ~-48 to -50dB)
            // -35dB = very quiet speech
            // -20dB = normal speech
            // -10dB = loud speech
            // 0dB = very loud/clipping

            // Map -45dB to 0.0 and -10dB to 1.0 for realistic range
            final double silenceThreshold = -45.0;
            final double loudThreshold = -10.0;
            final normalizedValue = ((amplitude.current - silenceThreshold) / (loudThreshold - silenceThreshold)).clamp(0.0, 1.0);
            print('Tutorial: Normalized value: $normalizedValue');

            if (normalizedValue > 0.1) {
              // Only show waveform if above 10% (actual sound detected)
              setState(() {
                // Generate spectrum data exactly like AgoraService does
                final random = math.Random();
                _spectrumData = List.generate(13, (index) {
                  double barValue;

                  if (normalizedValue < 0.1) {
                    // Very quiet - minimal activity
                    barValue = random.nextDouble() * 0.1;
                  } else {
                    // Lower frequency bands (bass) tend to be stronger
                    final frequencyWeight = index < 4 ? 1.0 : (index < 8 ? 0.8 : 0.6);
                    final baseValue = normalizedValue * frequencyWeight;

                    // Add randomness for natural variation (±30%)
                    final randomFactor = 0.7 + (random.nextDouble() * 0.6);
                    barValue = (baseValue * randomFactor).clamp(0.0, 1.0);

                    // Add some occasional peaks for visual interest
                    if (random.nextDouble() < 0.2) {
                      barValue = math.min(barValue * 1.5, 1.0);
                    }
                  }

                  return barValue;
                });
              });
              print('Tutorial: Updated spectrum data: $_spectrumData');
            } else {
              // Silence - set all bars to zero
              setState(() {
                _spectrumData = List.generate(13, (index) => 0.0);
              });
            }
          } catch (e) {
            print('Tutorial: Error getting amplitude: $e');
          }
        });
      } else {
        print('Tutorial: No microphone permission!');
      }
    } catch (e) {
      print('Tutorial: Error starting microphone monitoring: $e');
    }
  }

  Future<void> _stopMicrophoneMonitoring() async {
    if (!_isRecordingMic) return;

    _waveformTimer?.cancel();
    _isRecordingMic = false;

    try {
      await _audioRecorder.stop();

      // Delete the temporary recording file
      if (_recordingPath != null) {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
          print('Tutorial: Deleted temp recording file');
        }
        _recordingPath = null;
      }
    } catch (e) {
      print('Tutorial: Error stopping microphone: $e');
    }

    if (mounted) {
      setState(() {
        _spectrumData = List.generate(13, (index) => 0.0);
      });
    }
  }

  Future<void> _playTutorialAudio() async {
    if (_isPlayingAudio) return;

    setState(() {
      _isPlayingAudio = true;
    });

    try {
      // Play first audio file
      await _audioPlayer.play(AssetSource('KORA_INTRO_1.mp3'));
      await _audioPlayer.onPlayerComplete.first;

      // Wait 8 seconds
      await Future.delayed(const Duration(seconds: 8));

      // Play second audio file
      await _audioPlayer.play(AssetSource('KORA_INTRO_2.mp3'));
      await _audioPlayer.onPlayerComplete.first;

      // Wait 3 seconds
      await Future.delayed(const Duration(seconds: 3));

      // Play third audio file
      await _audioPlayer.play(AssetSource('KORA_INTRO_3.mp3'));
      await _audioPlayer.onPlayerComplete.first;

      // Wait 3 seconds
      await Future.delayed(const Duration(seconds: 3));

      // Play fourth audio file
      await _audioPlayer.play(AssetSource('KORA_INTRO_4.mp3'));
      await _audioPlayer.onPlayerComplete.first;

      setState(() {
        _isPlayingAudio = false;
      });
    } catch (e) {
      print('Error playing tutorial audio: $e');
      setState(() {
        _isPlayingAudio = false;
      });
    }
  }

  void _handleTutorialStateChange() {
    if (!mounted) return;

    final currentStep = TutorialManager().currentStep;

    // Transition from searching to call when user taps "Got it!" on searching tutorial
    if (currentStep == TutorialStep.callTimer && _showSearching) {
      setState(() {
        _showSearching = false;
        _showTutorialOverlay = false;
      });
      _progressController.forward();
      _startCallTimer(); // Start the 5-minute countdown timer
      _startMicrophoneMonitoring(); // Start monitoring microphone for real waveform

      // Show next tutorial after delay
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) {
          setState(() {
            _showTutorialOverlay = true;
          });
        }
      });
    } else {
      // For other transitions, briefly hide then show overlay
      setState(() {
        _showTutorialOverlay = false;
      });
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _showTutorialOverlay = true;
          });
        }
      });
    }
  }

  Widget _buildSearchingScreen() {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () {
          TutorialManager().skipTutorial();
          Navigator.pop(context);
        }),
        title: const Text(''),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding:
                  const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('searching',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  Text(
                    'Minutes remaining: 60',
                    style: TextStyle(fontSize: 12, color: Colors.blue[600]),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    key: _searchingTargetKey,
                    child: const CircularProgressIndicator(
                        color: Color(0xFF985021)),
                  ),
                  const SizedBox(height: 24),
                  const SingleChildScrollView(
                    child: Text(
                      '''Wu wei (無為)
Means "effortless action". The art of not forcing anything. You are who you are and they will be who they will be. You like what you like and they will like what they will like. You might not be what they like and they might not be what you like. Some people like cats, some people like dogs. You can't be a cat and a dog. You can't be red and blue.

Look for the path of least resistance. The conversation of least resistance.
With the right person, it's easier, feels more natural, less forced.

Don't try to be someone else's match, try to find yours.''',
                      style: TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tutorial overlay for searching step
          if (_showTutorialOverlay &&
              TutorialManager().currentStep == TutorialStep.searching)
            TutorialSpotlight(
              targetKey: _searchingTargetKey,
              title: 'Finding Your Match',
              description:
                  'The app is searching for someone available to talk. In a real call, this usually takes just a few seconds!',
              currentStep: 2,
              totalSteps: 9,
              onNext: () {
                TutorialManager().nextStep();
              },
              onSkip: () {
                TutorialManager().skipTutorial();
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildCallInterface() {
    return Scaffold(
      body: Stack(
        children: [
          // Background with profile picture and blur
          Positioned.fill(
            child: Stack(
              children: [
                // Profile picture
                Image.asset(
                  'assets/profile_pic.jpg',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (context, error, stackTrace) {
                    print('Error loading tutorial profile pic: $error');
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
                ),
                // Blur overlay that decreases as progress bar fills
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _progressAnimation,
                    builder: (context, child) {
                      // Calculate blur amount: starts at 20.0, ends at 0.0
                      final blurAmount = 20.0 * (1.0 - _progressAnimation.value);

                      return BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: blurAmount,
                          sigmaY: blurAmount,
                        ),
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.4 * (1.0 - _progressAnimation.value)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Top bar with name and timer
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
                    const Text(
                      'Alex',
                      style: TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      key: _timerKey,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _formatTime(_callSecondsRemaining),
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      key: _leaveButtonKey,
                      onPressed: () {
                        TutorialManager().skipTutorial();
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text(
                        'Leave',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      key: _menuButtonKey,
                      enabled: false,
                      icon: const Icon(
                        Icons.more_vert,
                        color: Colors.white,
                        size: 24,
                      ),
                      itemBuilder: (BuildContext context) => const [
                        PopupMenuItem<String>(
                          value: 'block',
                          child: Row(
                            children: [
                              Icon(Icons.block, color: Colors.orange),
                              SizedBox(width: 8),
                              Text('Block User'),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'report',
                          child: Row(
                            children: [
                              Icon(Icons.flag, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Report User'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Voice animation waveform in center
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 200,
              height: 200,
              decoration: const BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: CustomPaint(
                key: ValueKey(_spectrumData.hashCode),
                painter: WaveformWidget(_spectrumData),
              ),
            ),
          ),

          // Bottom section with buttons and progress
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Like and Next buttons - matching real call page
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 60, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Like button (heart icon, green color to match real UI)
                        Container(
                          key: _likeButtonKey,
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: Icon(
                              _isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 28,
                            ),
                            color: Colors.green,
                            onPressed: () {
                              setState(() {
                                _isLiked = !_isLiked;
                              });
                            },
                          ),
                        ),
                        // Next button (fast_forward icon, red color to match real UI)
                        Container(
                          key: _nextButtonKey,
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.fast_forward, size: 28),
                            color: Colors.red.withValues(alpha: 0.8),
                            onPressed: () {},
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Progress bar
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 16),
                    child: AnimatedBuilder(
                      animation: _progressAnimation,
                      builder: (context, child) {
                        return Container(
                          key: _progressBarKey,
                          height: 8,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white, width: 1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: _progressAnimation.value,
                              backgroundColor: Colors.transparent,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white),
                              minHeight: 6,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // "Would you rather" card
                  Card(
                    key: _icebreakersKey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 8,
                    child: Container(
                      width: MediaQuery.of(context).size.width * 0.9,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Would you rather',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_left),
                                onPressed: () {
                                  setState(() {
                                    currentQuestionIndex =
                                        (currentQuestionIndex - 1) %
                                            questions.length;
                                  });
                                },
                              ),
                              Expanded(
                                child: Text(
                                  questions[currentQuestionIndex],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_right),
                                onPressed: () {
                                  setState(() {
                                    currentQuestionIndex =
                                        (currentQuestionIndex + 1) %
                                            questions.length;
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tutorial overlays for each button - INDIVIDUAL HIGHLIGHTS
          if (_showTutorialOverlay &&
              TutorialManager().currentStep == TutorialStep.callTimer)
            TutorialSpotlight(
              targetKey: _timerKey,
              title: 'Call Timer',
              description:
                  'Here is a timer for the phone call, each call lasts 5 minutes',
              currentStep: 3,
              totalSteps: 9,
              onNext: () {
                TutorialManager().nextStep();
              },
              onSkip: () {
                TutorialManager().skipTutorial();
                Navigator.pop(context);
              },
            ),

          if (_showTutorialOverlay &&
              TutorialManager().currentStep == TutorialStep.callProgressBar)
            TutorialSpotlight(
              targetKey: _progressBarKey,
              title: 'Profile Reveal Progress',
              description:
                  'As the call continues, the profile picture becomes clearer. The progress bar shows how much of the picture has been revealed - at the end of the call you\'ll see the full image!',
              currentStep: 4,
              totalSteps: 9,
              onNext: () {
                TutorialManager().nextStep();
              },
              onSkip: () {
                TutorialManager().skipTutorial();
                Navigator.pop(context);
              },
            ),

          if (_showTutorialOverlay &&
              TutorialManager().currentStep == TutorialStep.callIcebreakers)
            TutorialSpotlight(
              targetKey: _icebreakersKey,
              title: 'Conversation Starters',
              description:
                  'These are some easy conversation starters that you can flip through to get the conversation going',
              currentStep: 5,
              totalSteps: 9,
              onNext: () {
                TutorialManager().nextStep();
              },
              onSkip: () {
                TutorialManager().skipTutorial();
                Navigator.pop(context);
              },
            ),

          if (_showTutorialOverlay &&
              TutorialManager().currentStep == TutorialStep.callLikeButton)
            TutorialSpotlight(
              targetKey: _likeButtonKey,
              title: 'Like Button',
              description:
                  'Tap the heart if you enjoyed talking with this person. If they like you back, you\'ll match and can continue talking!',
              currentStep: 6,
              totalSteps: 9,
              onNext: () {
                TutorialManager().nextStep();
              },
              onSkip: () {
                TutorialManager().skipTutorial();
                Navigator.pop(context);
              },
            ),

          if (_showTutorialOverlay &&
              TutorialManager().currentStep == TutorialStep.callDislikeButton)
            TutorialSpotlight(
              targetKey: _nextButtonKey,
              title: 'Next Button',
              description:
                  'If this person wasn\'t for you, tap next to move on to someone new.',
              currentStep: 7,
              totalSteps: 9,
              onNext: () {
                TutorialManager().nextStep();
              },
              onSkip: () {
                TutorialManager().skipTutorial();
                Navigator.pop(context);
              },
            ),

          if (_showTutorialOverlay &&
              TutorialManager().currentStep == TutorialStep.callNextButton)
            TutorialSpotlight(
              targetKey: _leaveButtonKey,
              title: 'Leave Button',
              description:
                  'Need to go? Tap Leave to exit the call and return to the home screen.',
              currentStep: 8,
              totalSteps: 9,
              onNext: () {
                TutorialManager().nextStep();
              },
              onSkip: () {
                TutorialManager().skipTutorial();
                Navigator.pop(context);
              },
            ),

          if (_showTutorialOverlay &&
              TutorialManager().currentStep == TutorialStep.callLeaveButton)
            TutorialSpotlight(
              targetKey: _menuButtonKey,
              title: 'Menu Button',
              description:
                  'Use this menu to block or report users if needed. We take safety seriously!',
              currentStep: 9,
              totalSteps: 9,
              onNext: () async {
                TutorialManager().nextStep(); // This will complete the tutorial

                // Hide the tutorial overlay to show the voice animation
                setState(() {
                  _showTutorialOverlay = false;
                });

                // Play the tutorial audio with voice animation
                await _playTutorialAudio();

                // Navigate back after audio completes
                if (mounted) {
                  Navigator.pop(context);
                }
              },
              onSkip: () {
                TutorialManager().skipTutorial();
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showSearching) {
      return _buildSearchingScreen();
    } else {
      return _buildCallInterface();
    }
  }
}
