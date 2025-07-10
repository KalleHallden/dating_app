import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_app/models/UserLocation.dart';
import 'package:amplify_app/models/user.dart';
import 'package:flutter/material.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_api/amplify_api.dart';

class TestUserButton extends StatelessWidget {
  const TestUserButton({super.key});

Future<void> _createTestUser() async {
  print('Starting _createTestUser');

  // Get the current authenticated user.
  final currentUser = await Amplify.Auth.getCurrentUser();
  print('Current user ID: ${currentUser.userId}');

  // Fetch the auth session.
  final session = await Amplify.Auth.fetchAuthSession();
  print('Auth session fetched. isSignedIn: ${session.isSignedIn}');

  // Determine authorization mode.
  final authType = session.isSignedIn
      ? APIAuthorizationType.userPools
      : APIAuthorizationType.apiKey;
  print('Using authorization mode: $authType');

  // Attempt to retrieve the user from the backend.
  final getUserRequest = ModelQueries.get(
    User.classType,
    UserModelIdentifier(userId: currentUser.userId),
  );
  print('Sending getUserRequest for userId: ${currentUser.userId}');
  final getUserResponse = await Amplify.API.query(request: getUserRequest).response;
  print('getUserResponse: ${getUserResponse.data}');
  final existingUser = getUserResponse.data;

  if (existingUser == null) {
    print('No existing user found. Creating new user.');
    final newUser = User(
      userId: currentUser.userId,
      name: "Denaerys Targaryan",
      age: 25,
      gender: "Female",
      gender_preference: "Men",
      age_preference: [18, 25],
      location: UserLocation(lat: 37.7749, long: -122.4194),
      radius: 10,
      pictures: const [],
      profile_picture: "",
      likes: [],
      likedBy: [],
      matches:[],
      dislikes: [],
      dislikedBy: [],
    );
    print('New user object: $newUser');

    final createRequest = ModelMutations.create<User>(newUser, authorizationMode: APIAuthorizationType.userPools,);
    print('Sending create request...');
    final createResponse = await Amplify.API.mutate(request: createRequest).response;
    print('Create response: ${createResponse.data}');
    if (createResponse.hasErrors) {
      print('Error creating user: ${createResponse.errors}');
    } else {
      print('User created successfully.');
    }
  } else {
    print('Existing user found. Updating user.');
    final updatedUser = existingUser.copyWith(
      name: "Test User Woman",
      age: 25,
      gender: "Female",
      gender_preference: "Male",
      age_preference: [18, 25],
      location: UserLocation(lat: 37.7749, long: -122.4194),
      radius: 10,
      pictures: const [],
      profile_picture: "",
    );
    print('Updated user object: $updatedUser');

    final updateRequest = ModelMutations.update<User>(updatedUser,  );
    print('Sending update request...');
    final updateResponse = await Amplify.API.mutate(request: updateRequest).response;
    print('Update response: ${updateResponse.data}');
    if (updateResponse.hasErrors) {
      print('Error updating user: ${updateResponse.errors}');
    } else {
      print('User updated successfully.');
    }
  }

  print('Finished _createTestUser');
}


  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
        onPressed: _createTestUser,
        tooltip: 'Add Test User',
        child: const Icon(Icons.person_add),
    );
  }
}
