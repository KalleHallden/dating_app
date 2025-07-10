// lib/pages/view_profile_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';

class ViewProfilePage extends StatefulWidget {
  final String userId;
  final String? userName; // Optional, for faster initial display
  
  const ViewProfilePage({
    Key? key,
    required this.userId,
    this.userName,
  }) : super(key: key);

  @override
  State<ViewProfilePage> createState() => _ViewProfilePageState();
}

class _ViewProfilePageState extends State<ViewProfilePage> {
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
      
      final response = await client
          .from('users')
          .select()
          .eq('user_id', widget.userId)
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
    final isOnline = _userData?['online'] ?? false;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name, Age, and Online Status
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '$name, $age',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Online status indicator
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isOnline ? 'Online now' : 'Offline',
            style: TextStyle(
              fontSize: 14,
              color: isOnline ? Colors.green : Colors.grey,
            ),
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
          _buildInfoRow(Icons.info_outline, _formatGenderInfo()),
          const SizedBox(height: 30),
          
          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Navigate to chat
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Chat feature coming soon!'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.message),
                  label: const Text('Message'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    _showUnmatchDialog();
                  },
                  icon: const Icon(Icons.heart_broken),
                  label: const Text('Unmatch'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
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
          return 'Location set';
        }
      }
    }
    return 'Location not set';
  }

  String _formatGenderInfo() {
    final gender = _userData?['gender'] ?? 'Not specified';
    return 'Gender: $gender';
  }

  void _showUnmatchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unmatch'),
        content: Text('Are you sure you want to unmatch with ${_userData?['name'] ?? 'this person'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _unmatchUser();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Unmatch'),
          ),
        ],
      ),
    );
  }

  Future<void> _unmatchUser() async {
    try {
      final client = SupabaseClient.instance.client;
      final currentUser = client.auth.currentUser;
      
      if (currentUser == null) return;

      // Determine the order for the match table
      final String smaller_id;
      final String larger_id;
      if (currentUser.id.compareTo(widget.userId) < 0) {
        smaller_id = currentUser.id;
        larger_id = widget.userId;
      } else {
        smaller_id = widget.userId;
        larger_id = currentUser.id;
      }

      // Update the match as unmatched
      await client
          .from('matches')
          .update({
            'unmatched_at': DateTime.now().toIso8601String(),
            'unmatched_by': currentUser.id,
          })
          .eq('user1_id', smaller_id)
          .eq('user2_id', larger_id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unmatched successfully')),
        );
        Navigator.of(context).pop(); // Go back to matches page
      }
    } catch (e) {
      print('Error unmatching: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error unmatching: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.userName ?? 'Profile'),
        ),
        body: const Center(
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

    final name = _userData?['name'] ?? 'Profile';

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
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
