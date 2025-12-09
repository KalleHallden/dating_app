// lib/pages/matches_page.dart
import 'package:kora/widgets/match_list_item.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import '../widgets/call_restriction_button.dart';
import '../utils/age_calculator.dart';
import 'view_profile_page.dart';
import 'waiting_call_page.dart';

class MatchesPage extends StatefulWidget {
  const MatchesPage({Key? key}) : super(key: key);

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> {
  List<Map<String, dynamic>> _matches = [];
  bool _isLoading = true;
  String? _errorMessage;
  supabase.RealtimeChannel? _matchesChannel;
  supabase.RealtimeChannel? _usersUpdateChannel;
  Set<String> _matchedUserIds = {};
  
  // Add a key map to force rebuild of specific match items
  final Map<String, Key> _matchKeys = {};

  @override
  void initState() {
    super.initState();
    _loadMatches();
    _subscribeToMatchUpdates();
  }

  @override
  void dispose() {
    _matchesChannel?.unsubscribe();
    _usersUpdateChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMatches() async {
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
      final matchesResponse = await client
    .from('matches')
    .select('*')
    .or('user1_id.eq.${currentUser.id},user2_id.eq.${currentUser.id}')
    .isFilter('unmatched_at', null)  // This line ensures unmatched users don't show
    .order('created_at', ascending: false);

      // Process matches to get the other user's data
      final processedMatches = <Map<String, dynamic>>[];
      final userIds = <String>{};
      
      for (final match in matchesResponse) {
        final isUser1 = match['user1_id'] == currentUser.id;
        final otherUserId = isUser1 ? match['user2_id'] : match['user1_id'];
        userIds.add(otherUserId);
        
        // Generate a unique key for this match
        _matchKeys[match['id']] = UniqueKey();
        
        // Fetch the other user's data
        try {
          final userResponse = await client
              .from('users')
              .select('*')
              .eq('user_id', otherUserId)
              .single();
          
          // Calculate age from date of birth
          final dateOfBirthValue = userResponse['date_of_birth'];
          final birthDate = AgeCalculator.parseBirthDate(dateOfBirthValue);
          final age = birthDate != null ? AgeCalculator.calculateAge(birthDate) : 0;

          processedMatches.add({
            'match_id': match['id'],
            'created_at': match['created_at'],
            'last_message_at': match['last_message_at'],
            'user_id': userResponse['user_id'],
            'name': userResponse['name'] ?? 'Unknown',
            'age': age,
            'profile_picture_url': userResponse['profile_picture_url'] ?? userResponse['profile_picture'],
            'is_online': userResponse['online'] ?? false,
            'is_available': userResponse['is_available'] ?? false,
          });
        } catch (e) {
          print('Error fetching user data for $otherUserId: $e');
        }
      }

      setState(() {
        _matches = processedMatches;
        _matchedUserIds = userIds;
        _isLoading = false;
      });
      
      // Subscribe to user updates for all matched users
      _subscribeToUserUpdates();
    } catch (e) {
      print('Error loading matches: $e');
      setState(() {
        _errorMessage = 'Failed to load matches: $e';
        _isLoading = false;
      });
    }
  }

  void _subscribeToMatchUpdates() {
    final client = SupabaseClient.instance.client;
    final currentUser = client.auth.currentUser;
    
    if (currentUser == null) return;

    _matchesChannel = client
        .channel('matches-updates-${currentUser.id}')
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.all,
          schema: 'public',
          table: 'matches',
          callback: (payload) {
            // Reload matches when there's any change
            _loadMatches();
          },
        )
        .subscribe();
  }

  void _subscribeToUserUpdates() {
    // Unsubscribe from previous channel if exists
    _usersUpdateChannel?.unsubscribe();
    
    if (_matchedUserIds.isEmpty) return;
    
    final client = SupabaseClient.instance.client;
    
    // Create a unique channel name
    final channelName = 'users-updates-matches-${DateTime.now().millisecondsSinceEpoch}';
    
    _usersUpdateChannel = client
        .channel(channelName)
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          callback: (payload) {
            final updatedUser = payload.newRecord;
            final userId = updatedUser['user_id'];
            
            // Check if this user is in our matches
            if (_matchedUserIds.contains(userId)) {
              print('Matched user updated: $userId');
              
              setState(() {
                _matches = _matches.map((match) {
                  if (match['user_id'] == userId) {
                    // Update the match data with new user info
                    match['name'] = updatedUser['name'] ?? match['name'];

                    // Calculate age from date of birth if available
                    if (updatedUser['date_of_birth'] != null) {
                      final birthDate = AgeCalculator.parseBirthDate(updatedUser['date_of_birth']);
                      if (birthDate != null) {
                        match['age'] = AgeCalculator.calculateAge(birthDate);
                      }
                    }

                    match['is_online'] = updatedUser['online'] ?? false;
                    match['is_available'] = updatedUser['is_available'] ?? false;
                    
                    // Update profile picture URL - force refresh with timestamp
                    final newProfilePicture = updatedUser['profile_picture_url'] ?? updatedUser['profile_picture'];
                    if (newProfilePicture != null && newProfilePicture != match['profile_picture_url']) {
                      match['profile_picture_url'] = newProfilePicture;
                      // Force rebuild of this specific match item
                      _matchKeys[match['match_id']] = UniqueKey();
                    }
                  }
                  return match;
                }).toList();
              });
            }
          },
        )
        .subscribe();
    
    print('Subscribed to user updates for ${_matchedUserIds.length} matched users');
  }

  void _navigateToProfile(Map<String, dynamic> match) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewProfilePage(
          userId: match['user_id'],
          userName: match['name'],
        ),
      ),
    ).then((_) {
      // Reload matches when returning from profile page
      _loadMatches();
    });
  }

  Future<void> _initiateCall(Map<String, dynamic> match) async {
    // Check if user is online and available
    if (!match['is_online'] || !match['is_available']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${match['name']} is not available for calls right now'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final client = SupabaseClient.instance.client;
      final currentUser = client.auth.currentUser;
      
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Call the Supabase function to initiate the call
      final response = await client.functions.invoke(
        'initiate-call',
        body: {
          'called_id': match['user_id'],
        },
      );

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      if (response.status != 200) {
        throw Exception(response.data['error'] ?? 'Failed to initiate call');
      }

      final callData = response.data;
      
      // Navigate to waiting call page
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WaitingCallPage(
              callId: callData['id'],
              channelName: callData['channel_name'],
              matchedUser: match,
              isInitiator: true,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error initiating call: $e');
      
      // Close loading dialog if still open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start call: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF985021).withValues(alpha: 0.08),
              ),
              child: Icon(
                Icons.favorite_rounded,
                size: 40,
                color: const Color(0xFF985021).withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No matches yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.grey[900],
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'When you match with someone,\nthey\'ll appear here',
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchTile(Map<String, dynamic> match) {
    final currentUser = SupabaseClient.instance.client.auth.currentUser;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        key: _matchKeys[match['match_id']] ?? ValueKey(match['match_id']),
        onTap: () => _navigateToProfile(match),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF985021).withValues(alpha: 0.1),
                backgroundImage: match['profile_picture_url'] != null &&
                               match['profile_picture_url'].isNotEmpty
                    ? NetworkImage(match['profile_picture_url'])
                    : null,
                child: match['profile_picture_url'] == null ||
                       match['profile_picture_url'].isEmpty
                    ? Text(
                        match['name'].isNotEmpty ? match['name'][0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF985021).withValues(alpha: 0.6),
                        ),
                      )
                    : null,
              ),
            ),
            // Online status indicator
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: match['is_online']
                      ? const Color(0xFF10B981)
                      : Colors.grey.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        title: Text(
          '${match['name']}, ${match['age']}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.grey[900],
            letterSpacing: -0.2,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _getLastMessageText(match['last_message_at']),
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Call button with restriction handling
            if (currentUser != null)
              CallRestrictionButton(
                currentUserId: currentUser.id,
                matchedUserId: match['user_id'],
                isOnline: match['is_online'] ?? false,
                isAvailable: match['is_available'] ?? false,
                onCallInitiated: () => _initiateCall(match),
              ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  String _getLastMessageText(dynamic lastMessageAt) {
    if (lastMessageAt == null) {
      return 'Start a conversation';
    }
    
    DateTime messageTime;
    if (lastMessageAt is String) {
      messageTime = DateTime.parse(lastMessageAt);
    } else {
      return 'Start a conversation';
    }
    
    final now = DateTime.now();
    final difference = now.difference(messageTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
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
          title: const Text('Matches'),
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
                onPressed: _loadMatches,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(
          'Matches',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            color: Colors.grey[900],
            letterSpacing: -0.5,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: Colors.grey.withValues(alpha: 0.1),
          ),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF985021),
        onRefresh: _loadMatches,
        child: _matches.isEmpty
            ? _buildEmptyState()
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: _matches.length,
                itemBuilder: (context, index) => _buildMatchTile(_matches[index]),
              ),
      ),
    );
  }
}
