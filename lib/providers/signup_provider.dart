import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:image_picker/image_picker.dart';
import '../services/supabase_client.dart';
import '../services/image_compression.dart';
import '../models/UserLocation.dart';
import '../utils/age_calculator.dart';
import '../utils/gender_preference_converter.dart';
import 'dart:io';

class SignupProvider with ChangeNotifier {
  int _currentStep = 1;
  Map<String, dynamic> userData = {};

  // Step 1 data
  String? _name;
  DateTime? _birthdate;
  XFile? _profileImage;

  // Step 2 data
  String? _gender;
  String? _interestedIn;
  UserLocation? _location;

  // Step 3 data
  String? _aboutMe;

  int get currentStep => _currentStep;
  supabase.SupabaseClient get supabaseClient => SupabaseClient.instance.client;

  // Getters for form data
  String? get name => _name;
  DateTime? get birthdate => _birthdate;
  XFile? get profileImage => _profileImage;
  String? get gender => _gender;
  // Return frontend format for UI display
  String? get interestedIn => _interestedIn;
  UserLocation? get location => _location;
  String? get aboutMe => _aboutMe;

  set currentStep(int value) {
    _currentStep = value;
    notifyListeners();
  }

  // Individual setters for maintaining state
  void setStep1Data(String name, DateTime birthdate, XFile image) {
    _name = name;
    _birthdate = birthdate;
    _profileImage = image;
    userData.addAll({
      'name': name,
      'date_of_birth': AgeCalculator.formatBirthDate(birthdate),
      'profile_picture': image.path,
    });
    notifyListeners();
  }

  void setStep2Data(String gender, String interestedIn, UserLocation location) {
    _gender = gender;
    _interestedIn = interestedIn;
    _location = location;
    userData.addAll({
      'gender': gender,
      // Convert frontend format to backend format for storage
      'gender_preference': GenderPreferenceConverter.frontendToBackend(interestedIn),
      'location': location,
    });
    notifyListeners();
  }

  void setStep3Data(String aboutMe) {
    _aboutMe = aboutMe;
    userData.addAll({'aboutMe': aboutMe});
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
      
      // Try multiple keys for backward compatibility
      final profilePicturePath = userData['profile_picture_path'] ?? 
                                 userData['profile_picture'];
      
      if (profilePicturePath != null && profilePicturePath is String) {
        print('DEBUG: Profile picture path: $profilePicturePath');
        
        final file = File(profilePicturePath);
        
        // Check if file exists before trying to upload
        final fileExists = await file.exists();
        print('DEBUG: File exists: $fileExists');
        
        if (!fileExists) {
          throw Exception('Profile picture file not found. The temporary file may have been deleted. Please select the image again.');
        }
        
        final fileSize = await file.length();
        print('DEBUG: File size: $fileSize bytes');
        
        final storagePath = '$userId.jpg';
        print('DEBUG: Attempting to upload file to storagePath: $storagePath');
        print('DEBUG: Expected filename for RLS check: ${user.id}.jpg');

        try {
          // Upload to Supabase Storage
          await client.storage.from('profilepicture').upload(
            storagePath, 
            file,
            fileOptions: const supabase.FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
            ),
          );
          
          // Get the public URL with a timestamp to avoid caching issues
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          profilePictureUrl = '${client.storage.from('profilepicture').getPublicUrl(storagePath)}?t=$timestamp';
          
          print('DEBUG: Profile picture uploaded successfully! URL: $profilePictureUrl');
          
        } on supabase.StorageException catch (e) {
          print('ERROR: Supabase Storage Exception during upload: ${e.message} (Status: ${e.statusCode})');
          throw Exception('Failed to upload profile picture: ${e.message}');
        } catch (e) {
          print('ERROR: General file upload error: ${e.toString()}');
          throw Exception('Failed to upload profile picture: ${e.toString()}');
        }
      } else {
        print('WARNING: No profile picture path found in userData');
      }

      // Prepare data for upsert
      final Map<String, dynamic> dataToInsert = {
        'user_id': userId,
        'name': userData['name'] as String,
        'date_of_birth': userData['date_of_birth'] as String,
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
        dataToInsert['profile_picture_url'] = profilePictureUrl;
      }

      // Insert or update user profile in users table
      final response = await client.from('users').upsert(dataToInsert, onConflict: 'user_id');

      print('User profile upsert response: $response');
      
      // Clean up temporary files only after successful save
      // This ensures the files are available throughout the signup process
      try {
        await ImageCompressionUtil.cleanupTempFiles();
        print('DEBUG: Cleaned up temporary image files after successful signup');
      } catch (e) {
        print('WARNING: Failed to clean up temp files: $e');
        // Don't fail the whole operation if cleanup fails
      }

    } on supabase.AuthException catch (e) {
      throw Exception('Authentication error during profile save: ${e.message}');
    } on supabase.PostgrestException catch (e) {
      print('Supabase Postgrest Error during profile save: ${e.message} (Code: ${e.code})');
      throw Exception('Database error saving profile: ${e.message}');
    } catch (e) {
      throw Exception('Error saving profile: ${e.toString()}');
    }
  }
}
