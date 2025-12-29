// lib/services/tutorial_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class TutorialService {
  static const String _tutorialCompletedKey = 'tutorial_completed';

  // Singleton pattern
  static final TutorialService _instance = TutorialService._internal();
  factory TutorialService() => _instance;
  TutorialService._internal();

  // Check if user has completed the tutorial
  Future<bool> hasCompletedTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_tutorialCompletedKey) ?? false;
  }

  // Mark tutorial as completed
  Future<void> setTutorialCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tutorialCompletedKey, true);
  }

  // Reset tutorial (for settings button)
  Future<void> resetTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tutorialCompletedKey, false);
  }
}
