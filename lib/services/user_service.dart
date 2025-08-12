import 'dart:io';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';
import '../models/User.dart';
import '../models/UserLocation.dart';

class UserService {
  Future<String> _uploadProfilePicture(File imageFile) async {
    // Get the authenticated User Pool ID
    final user = await Amplify.Auth.getCurrentUser();
    final userId = user.userId; // Cognito User Pool ID
    final storagePath = StoragePath.fromIdentityId(
        (String identityId) => 'profile-pictures/$identityId/profile.jpg');

    try {
      safePrint('User Pool ID: $userId');
      safePrint('Uploading to: profile-pictures/$userId/profile.jpg');
      // Upload the file to S3
      final uploadResult = await Amplify.Storage.uploadFile(
        localFile: AWSFile.fromPath(imageFile.path),
        path: storagePath,
      ).result;

      safePrint('Upload successful: ${uploadResult.uploadedItem.path}');
      // Get the URL of the uploaded file
      final urlResult = await Amplify.Storage.getUrl(path: storagePath).result;
      final url = urlResult.url.toString();

      safePrint('URL retrieved: $url');
      return url;
    } on StorageException catch (e) {
      safePrint('Storage error: ${e.message}');
      safePrint('Underlying exception: ${e.underlyingException}');
      throw Exception('Error uploading profile picture: ${e.message}');
    } catch (e) {
      safePrint('Unexpected error: $e');
      throw Exception('Error uploading profile picture: $e');
    }
  }

  Future<void> saveUser({
    required String name,
    required int age,
    required String gender,
    required String genderPreference,
    required File profilePicture,
    UserLocation? location,
    required String aboutMe,
  }) async {
    // Verify authentication
    final session = await Amplify.Auth.fetchAuthSession();
    if (!session.isSignedIn) {
      throw Exception('User is not signed in');
    }
    final user = await Amplify.Auth.getCurrentUser();
    final userId = user.userId; // Cognito User Pool ID
    final authType = APIAuthorizationType.userPools;

    safePrint('User Pool ID from Cognito: $userId');
    safePrint('Session signed in: ${session.isSignedIn}');

    // Upload profile picture
    final profilePictureUrl = await _uploadProfilePicture(profilePicture);

    // Check if user exists
    final getUserRequest =
        ModelQueries.get(User.classType, UserModelIdentifier(userId: userId));
    final getUserResponse =
        await Amplify.API.query(request: getUserRequest).response;
    final existingUser = getUserResponse.data;

    if (existingUser == null) {
      safePrint('Creating new user with ID: $userId');
      final newUser = User(
        userId: userId,
        name: name,
        age: age,
        gender: gender,
        gender_preference: genderPreference,
        profile_picture: profilePictureUrl,
        location: location,
        aboutMe: aboutMe,
        called: null,
      );
      final createRequest =
          ModelMutations.create<User>(newUser, authorizationMode: authType);
      final createResponse =
          await Amplify.API.mutate(request: createRequest).response;
      if (createResponse.hasErrors) {
        safePrint('Create user errors: ${createResponse.errors}');
        throw Exception('Error creating user: ${createResponse.errors}');
      } else {
        safePrint('User created successfully');
      }
    } else {
      safePrint('Updating existing user with ID: $userId');
      final updatedUser = existingUser.copyWith(
        name: name,
        age: age,
        gender: gender,
        gender_preference: genderPreference,
        profile_picture: profilePictureUrl,
        location: location,
        aboutMe: aboutMe,
        called: existingUser.called,
      );
      final updateRequest =
          ModelMutations.update<User>(updatedUser, authorizationMode: authType);
      final updateResponse =
          await Amplify.API.mutate(request: updateRequest).response;
      if (updateResponse.hasErrors) {
        safePrint('Update user errors: ${updateResponse.errors}');
        throw Exception('Error updating user: ${updateResponse.errors}');
      } else {
        safePrint('User updated successfully');
      }
    }
  }
}
