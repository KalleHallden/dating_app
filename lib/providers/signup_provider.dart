import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import '../models/UserLocation.dart';
import 'dart:io';

class SignupProvider with ChangeNotifier {
  int _currentStep = 1;
  Map<String, dynamic> userData = {};

  int get currentStep => _currentStep;
  supabase.SupabaseClient get supabaseClient => SupabaseClient.instance.client;

  set currentStep(int value) {
    _currentStep = value;
    notifyListeners();
  }

  void addData(Map<String, dynamic> data) {
    userData.addAll(data);
    notifyListeners();
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final client = SupabaseClient.instance.client;
      final response = await client.auth.signUp(
        email: email,
        password: password,
      );
      if (response.user == null) {
        throw Exception('Sign-up failed: No user created');
      }
      // Force session refresh
      await client.auth.refreshSession();
    } on supabase.AuthException catch (e) {
      throw e;
    } catch (e) {
      throw Exception('Error during sign-up: $e');
    }
  }

  Future<void> saveUser() async {
    try {
      final client = SupabaseClient.instance.client;
      // Refresh session to ensure user is authenticated
      await client.auth.refreshSession();
      final user = client.auth.currentUser;
      if (user == null) {
        throw Exception('No authenticated user found');
      }

      final userId = user.id;
      final location = userData['location'] as UserLocation?;
      if (location == null) {
        throw Exception('Location is required');
      }

      // Upload profile picture to Supabase Storage
      String? profilePictureUrl;
      final profilePicturePath = userData['profile_picture'] as String?;
      if (profilePicturePath != null) {
        final file = File(profilePicturePath);
        final storagePath = 'profile_pictures/$userId.jpg';
        await client.storage.from('profile_pictures').upload(storagePath, file);
        profilePictureUrl = client.storage.from('profile_pictures').getPublicUrl(storagePath);
      }

      // Insert or update user profile in users table
      await client.from('users').upsert({
        'user_id': userId,
        'name': userData['name'] as String,
        'age': userData['age'] as int,
        'gender': userData['gender'] as String,
        'gender_preference': userData['gender_preference'] as String,
        'location': '(${location.lat},${location.long})',
        'age_preference': {'min': 18, 'max': 100}, // Default values
        'about_me': userData['aboutMe'] as String?,
        'radius': 100, // Default value in km
        'is_available': true,
        'online': true,
        'matchmaking_lock': null,
        'profile_picture': profilePictureUrl,
      }, onConflict: 'user_id');
    } on supabase.AuthException catch (e) {
      throw Exception('Authentication error: ${e.message}');
    } catch (e) {
      throw Exception('Error saving profile: $e');
    }
  }
}
