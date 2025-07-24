import 'dart:io';
import 'package:amplify_app/widgets/signout_button.dart';
import 'package:amplify_app/widgets/profile_picture_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _errorMessage;
  XFile? _selectedImage;
  bool _isUploadingImage = false;
  supabase.RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _setupRealtimeSubscription();
  }

  @override
  void dispose() {
    // Clean up the real-time subscription
    if (_realtimeChannel != null) {
      SupabaseClient.instance.client.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }

  Future<void> _setupRealtimeSubscription() async {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;

    if (currentUser == null) {
      print('No authenticated user for real-time subscription');
      return;
    }

    // Subscribe to changes in the users table for the current user
    _realtimeChannel = client
    .channel('public:users:user_id=eq.${currentUser.id}')
    .onPostgresChanges(
      event: supabase.PostgresChangeEvent.update,
      schema: 'public',
      table: 'users',
      filter: supabase.PostgresChangeFilter(
        type: supabase.PostgresChangeFilterType.eq,
        column: 'user_id',
        value: currentUser.id,
      ),
      callback: (payload) {
        print('Received real-time update: $payload');
        // Update the UI with the new profile data
        if (mounted) {
          setState(() {
            _userData = {
              ...?_userData,
              ...payload.newRecord,
            };
          });
        }
      },
    )
    .subscribe();
  }



  Future<void> _loadUserProfile() async {
    try {
      final client = SupabaseClient.instance.client;
      final currentUser = client.auth.currentUser;
      
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'User not authenticated';
          _isLoading = false;
        });
        return;
      }

      final response = await client
          .from('users')
          .select()
          .eq('user_id', currentUser.id)
          .single();

      setState(() {
        _userData = response;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading user profile: $e');
      setState(() {
        _errorMessage = 'Failed to load profile: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleImageSelected(XFile image) async {
    setState(() {
      _selectedImage = image;
    });

    // Upload the image immediately
    await _uploadProfilePicture(image);
  }

  Future<void> _uploadProfilePicture(XFile image) async {
    setState(() => _isUploadingImage = true);

    try {
      final client = SupabaseClient.instance.client;
      final user = client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Convert XFile to File for Supabase upload
      final file = File(image.path);

      // Upload to Supabase Storage
      final storagePath = '${user.id}.jpg';
      print('Uploading profile picture to: $storagePath');

      // Upload the compressed image
      await client.storage.from('profilepicture').upload(
        storagePath,
        file,
        fileOptions: const supabase.FileOptions(
          upsert: true, // Replace existing file
          contentType: 'image/jpeg',
        ),
      );

      // Get the public URL
      final profilePictureUrl = client.storage
          .from('profilepicture')
          .getPublicUrl(storagePath);

      print('Profile picture uploaded successfully! URL: $profilePictureUrl');

      // Update the user record with new profile picture URL
      await client
          .from('users')
          .update({
            'profile_picture': profilePictureUrl,
            'profile_picture_url': profilePictureUrl, // Update both fields if they exist
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id);

      // Update local state to reflect the new profile picture immediately
      if (mounted) {
        setState(() {
          _userData = {
            ...?_userData,
            'profile_picture': profilePictureUrl,
            'profile_picture_url': profilePictureUrl,
          };
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error uploading profile picture: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload profile picture: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
          _selectedImage = null; // Clear selected image after upload
        });
      }
    }
  }

  Widget _buildProfileImage() {
    final profilePictureUrl = _userData?['profile_picture_url'] ?? 
                             _userData?['profile_picture'];
    
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 4 / 5, // Instagram portrait format
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[300],
              image: (_selectedImage != null && _selectedImage!.path.isNotEmpty)
                  ? DecorationImage(
                      image: FileImage(File(_selectedImage!.path)),
                      fit: BoxFit.cover,
                    )
                  : (profilePictureUrl != null && profilePictureUrl.isNotEmpty)
                      ? DecorationImage(
                          image: NetworkImage(profilePictureUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
            ),
            child: (_selectedImage == null || _selectedImage!.path.isEmpty) && 
                   (profilePictureUrl == null || profilePictureUrl.isEmpty)
                ? const Center(
                    child: Icon(
                      Icons.person,
                      size: 100,
                      color: Colors.grey,
                    ),
                  )
                : null,
          ),
        ),
        // Overlay for loading state
        if (_isUploadingImage)
          Positioned.fill(
            child: Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          ),
        // Edit button overlay
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: Theme.of(context).primaryColor,
            onPressed: _isUploadingImage ? null : () {
              // Show the profile picture picker in a dialog
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Update Profile Picture',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ProfilePicturePicker(
                          currentImageUrl: profilePictureUrl,
                          selectedImage: _selectedImage,
                          onImageSelected: _handleImageSelected,
                          size: 150,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            child: const Icon(Icons.edit, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileInfo() {
    final name = _userData?['name'] ?? 'Unknown';
    final age = _userData?['age'] ?? 0;
    final aboutMe = _userData?['about_me'] ?? 'No description provided';

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name and Age
          Row(
            children: [
              Expanded(
                child: Text(
                  '$name, $age',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Edit button
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  // TODO: Navigate to edit profile page
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Edit profile coming soon!'),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // About Me Section
          const Text(
            'About Me',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            aboutMe,
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 30),
          
          // Additional Info
          _buildInfoRow(Icons.location_on, _formatLocation()),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.favorite, _formatPreferences()),
          const SizedBox(height: 30),
          
          // Sign Out Button
          Center(
            child: SignoutButton(
              text: 'Sign Out',
              showIcon: true,
              backgroundColor: Colors.red,
              textColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }

  String _formatLocation() {
    final location = _userData?['location'];
    if (location == null) return 'Location not set';
    
    // Parse the PostGIS point format (lat,long)
    if (location is String) {
      final coords = location.replaceAll('(', '').replaceAll(')', '').split(',');
      if (coords.length == 2) {
        final lat = double.tryParse(coords[0]);
        final long = double.tryParse(coords[1]);
        if (lat != null && long != null) {
          // You could use reverse geocoding here to get city name
          return 'Location set';
        }
      }
    }
    return 'Location not set';
  }

  String _formatPreferences() {
    final gender = _userData?['gender'] ?? 'Not specified';
    final genderPref = _userData?['gender_preference'] ?? 'Not specified';
    final agePref = _userData?['age_preference'];
    
    String prefString = 'Looking for: $genderPref';
    
    if (agePref != null && agePref is Map) {
      final minAge = agePref['min'] ?? 18;
      final maxAge = agePref['max'] ?? 100;
      prefString += ', Ages $minAge-$maxAge';
    }
    
    return prefString;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadUserProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileImage(),
            _buildProfileInfo(),
          ],
        ),
      ),
    );
  }
}
