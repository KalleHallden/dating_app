// lib/services/tutorial_manager.dart
import 'package:flutter/material.dart';

enum TutorialStep {
  talkButton,        // Initial "Find someone to talk to" button
  searching,         // Searching for match screen
  callTimer,         // Timer at top left
  callProgressBar,   // Progress bar showing blur reduction
  callIcebreakers,   // Would you rather conversation starters
  callLikeButton,    // Like button in call
  callDislikeButton, // Dislike button in call (used for Next)
  callNextButton,    // Next button in call (used for Leave)
  callLeaveButton,   // Leave button in call (used for Menu)
  callMenuButton,    // Three-dot menu button in call
  completed,         // Tutorial finished
}

class TutorialManager extends ChangeNotifier {
  static final TutorialManager _instance = TutorialManager._internal();
  factory TutorialManager() => _instance;
  TutorialManager._internal();

  TutorialStep _currentStep = TutorialStep.talkButton;
  bool _isInTutorial = false;

  TutorialStep get currentStep => _currentStep;
  bool get isInTutorial => _isInTutorial;

  void startTutorial() {
    _isInTutorial = true;
    _currentStep = TutorialStep.talkButton;
    notifyListeners();
  }

  void nextStep() {
    switch (_currentStep) {
      case TutorialStep.talkButton:
        _currentStep = TutorialStep.searching;
        break;
      case TutorialStep.searching:
        _currentStep = TutorialStep.callTimer;
        break;
      case TutorialStep.callTimer:
        _currentStep = TutorialStep.callProgressBar;
        break;
      case TutorialStep.callProgressBar:
        _currentStep = TutorialStep.callIcebreakers;
        break;
      case TutorialStep.callIcebreakers:
        _currentStep = TutorialStep.callLikeButton;
        break;
      case TutorialStep.callLikeButton:
        _currentStep = TutorialStep.callDislikeButton;
        break;
      case TutorialStep.callDislikeButton:
        _currentStep = TutorialStep.callNextButton;
        break;
      case TutorialStep.callNextButton:
        _currentStep = TutorialStep.callLeaveButton;
        break;
      case TutorialStep.callLeaveButton:
        _currentStep = TutorialStep.callMenuButton;
        break;
      case TutorialStep.callMenuButton:
        _currentStep = TutorialStep.completed;
        _isInTutorial = false;
        break;
      case TutorialStep.completed:
        _isInTutorial = false;
        break;
    }
    notifyListeners();
  }

  void skipTutorial() {
    _isInTutorial = false;
    _currentStep = TutorialStep.completed;
    notifyListeners();
  }

  void reset() {
    _isInTutorial = false;
    _currentStep = TutorialStep.talkButton;
    notifyListeners();
  }
}
