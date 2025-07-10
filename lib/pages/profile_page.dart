// lib/pages/profile_page.dart
import 'package:amplify_app/widgets/signout_button.dart';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
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

  Widget _buildProfileImage() {
    final profilePictureUrl = _userData?['profile_picture_url'] ?? 
                             _userData?['profile_picture'];
    
    return AspectRatio(
      aspectRatio: 4 / 5, // Instagram portrait format
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[300],
          image: profilePictureUrl != null && profilePictureUrl.isNotEmpty
              ? DecorationImage(
                  image: NetworkImage(profilePictureUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: profilePictureUrl == null || profilePictureUrl.isEmpty
            ? const Center(
                child: Icon(
                  Icons.person,
                  size: 100,
                  color: Colors.grey,
                ),
              )
            : null,
      ),
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
