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
        emailRedirectTo: 'io.supabase.flutterquickstart://login-callback/',
      );
      if (response.user == null) {
        throw Exception('Sign-up failed: No user created or email already exists.');
      }
    } on supabase.AuthException catch (e) {
      throw e;
    } catch (e) {
      throw Exception('Error during sign-up: ${e.toString()}');
    }
  }

  Future<void> saveUser() async {
    try {
      final client = SupabaseClient.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        throw Exception('No authenticated user found before saving profile.');
      }

      final userId = user.id;
      final location = userData['location'] as UserLocation?;
      if (location == null) {
        throw Exception('Location is required. Please go back and select a location.');
      }

      // Upload profile picture to Supabase Storage
      String? profilePictureUrl;
      final profilePicturePath = userData['profile_picture'] as String?;
      if (profilePicturePath != null) {
        final file = File(profilePicturePath);
        // CRITICAL FIX: Removed 'profilepicture/' prefix from storagePath
        // The .from('profilepicture') already specifies the bucket.
        final storagePath = '$userId.jpg';
        print('DEBUG: Attempting to upload file to storagePath: $storagePath');
        print('DEBUG: Expected filename for RLS check (should match storagePath): ${user.id}.jpg');

        try {
          // The bucket name is specified here: .from('profilepicture')
          await client.storage.from('profilepicture').upload(storagePath, file,
              fileOptions: const supabase.FileOptions(upsert: true));
          profilePictureUrl = client.storage.from('profilepicture').getPublicUrl(storagePath);
          print('DEBUG: Profile picture uploaded successfully! URL: $profilePictureUrl');
        } on supabase.StorageException catch (e) {
          print('ERROR: Supabase Storage Exception during upload: ${e.message} (Status: ${e.statusCode})');
          throw Exception('Failed to upload profile picture: ${e.message}');
        } catch (e) {
          print('ERROR: General file upload error: ${e.toString()}');
          throw Exception('Failed to upload profile picture: ${e.toString()}');
        }
      }

      // Prepare data for upsert
      final Map<String, dynamic> dataToInsert = {
        'user_id': userId,
        'name': userData['name'] as String,
        'age': userData['age'] as int,
        'gender': userData['gender'] as String,
        'gender_preference': userData['gender_preference'] as String,
        'location': '(${location.lat},${location.long})',
        'age_preference': {'min': 18, 'max': 100},
        'about_me': userData['aboutMe'] as String?,
        'radius': 100,
        'is_available': true,
        'online': true,
        'matchmaking_lock': null,
      };

      if (profilePictureUrl != null) {
        dataToInsert['profile_picture'] = profilePictureUrl;
      }

      // Insert or update user profile in users table
      final response = await client.from('users').upsert(dataToInsert, onConflict: 'user_id');

      print('User profile upsert response: $response');

    } on supabase.AuthException catch (e) {
      throw Exception('Authentication error during profile save: ${e.message}');
    } on supabase.PostgrestException catch (e) {
      print('Supabase Postgrest Error during profile save: ${e.message} (Code: ${e.code})');
      throw Exception('Database error saving profile: ${e.message}');
    } catch (e) {
      throw Exception('General error saving profile: ${e.toString()}');
    }
  }
}

