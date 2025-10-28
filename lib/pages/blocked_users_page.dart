import 'package:flutter/material.dart';
import '../services/supabase_client.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  List<Map<String, dynamic>> _blockedUsers = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = SupabaseClient.instance.client;
      final currentUser = client.auth.currentUser;

      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Fetch blocked user IDs first
      final blockedResponse = await client
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', currentUser.id);

      final blockedUserIds = (blockedResponse as List)
          .map((item) => item['blocked_id'] as String)
          .toList();

      if (blockedUserIds.isEmpty) {
        setState(() {
          _blockedUsers = [];
          _isLoading = false;
        });
        return;
      }

      // Fetch user details for blocked users
      final usersResponse = await client
          .from('users')
          .select('user_id, name, profile_picture_url')
          .inFilter('user_id', blockedUserIds);

      setState(() {
        _blockedUsers = (usersResponse as List).map((user) {
          return {
            'user_id': user['user_id'],
            'name': user['name'] ?? 'Unknown',
            'profile_picture_url': user['profile_picture_url'],
          };
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load blocked users: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _unblockUser(String userId, String userName) async {
    // Show confirmation dialog
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Unblock User'),
          content: Text('Are you sure you want to unblock $userName?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF985021),
              ),
              child: const Text('Unblock'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final client = SupabaseClient.instance.client;

      // Call the block-user edge function with unblock action
      final response = await client.functions.invoke(
        'block-user',
        body: {
          'action': 'unblock',
          'targetUserId': userId,
        },
      );

      if (response.data?['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$userName has been unblocked'),
              backgroundColor: Colors.green,
            ),
          );
        }
        // Reload the list
        await _loadBlockedUsers();
      } else {
        throw Exception(response.data?['error'] ?? 'Failed to unblock user');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unblock user: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Blocked Users'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadBlockedUsers,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _blockedUsers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.block,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No blocked users',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Users you block will appear here',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadBlockedUsers,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _blockedUsers.length,
                        itemBuilder: (context, index) {
                          final user = _blockedUsers[index];
                          final profilePicUrl = user['profile_picture_url'];
                          final userName = user['name'];
                          final userId = user['user_id'];

                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.grey[300],
                                backgroundImage: profilePicUrl != null &&
                                        profilePicUrl.isNotEmpty
                                    ? NetworkImage(profilePicUrl)
                                    : null,
                                child: profilePicUrl == null ||
                                        profilePicUrl.isEmpty
                                    ? const Icon(
                                        Icons.person,
                                        size: 32,
                                        color: Colors.grey,
                                      )
                                    : null,
                              ),
                              title: Text(
                                userName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'Blocked',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              trailing: TextButton(
                                onPressed: () => _unblockUser(userId, userName),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF985021),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                ),
                                child: const Text(
                                  'Unblock',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
