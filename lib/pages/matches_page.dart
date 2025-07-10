// lib/pages/matches_page.dart
import 'package:amplify_app/widgets/match_list_item.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import 'view_profile_page.dart';

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

  @override
  void initState() {
    super.initState();
    _loadMatches();
    _subscribeToMatchUpdates();
  }

  @override
  void dispose() {
    _matchesChannel?.unsubscribe();
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

      // Query matches that are not unmatched (soft delete approach)
      final matchesResponse = await client
          .from('matches')
          .select('*')
          .or('user1_id.eq.${currentUser.id},user2_id.eq.${currentUser.id}')
          .isFilter('unmatched_at', null)  // Use is_ instead of isFilter for null checks
          .order('created_at', ascending: false);

      // Process matches to get the other user's data
      final processedMatches = <Map<String, dynamic>>[];
      
      for (final match in matchesResponse) {
        final isUser1 = match['user1_id'] == currentUser.id;
        final otherUserId = isUser1 ? match['user2_id'] : match['user1_id'];
        
        // Fetch the other user's data
        try {
          final userResponse = await client
              .from('users')
              .select('*')
              .eq('user_id', otherUserId)
              .single();
          
          processedMatches.add({
            'match_id': match['id'],
            'created_at': match['created_at'],
            'last_message_at': match['last_message_at'],
            'user_id': userResponse['user_id'],
            'name': userResponse['name'] ?? 'Unknown',
            'age': userResponse['age'] ?? 0,
            'profile_picture_url': userResponse['profile_picture_url'] ?? userResponse['profile_picture'],
            'is_online': userResponse['online'] ?? false,
          });
        } catch (e) {
          print('Error fetching user data for $otherUserId: $e');
        }
      }

      setState(() {
        _matches = processedMatches;
        _isLoading = false;
      });
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
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          callback: (payload) {
            // Update online status when user status changes
            final updatedUser = payload.newRecord;
            setState(() {
              _matches = _matches.map((match) {
                if (match['user_id'] == updatedUser['user_id']) {
                  match['is_online'] = updatedUser['online'] ?? false;
                }
                return match;
              }).toList();
            });
          },
        )
        .subscribe();
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
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No matches yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'When you match with someone, they\'ll appear here',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
      appBar: AppBar(
        title: const Text('Matches'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadMatches,
        child: _matches.isEmpty
            ? _buildEmptyState()
            : ListView.separated(
                itemCount: _matches.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final match = _matches[index];
                  return MatchListItem(
                    matchId: match['match_id'],
                    name: match['name'],
                    age: match['age'],
                    profilePictureUrl: match['profile_picture_url'],
                    isOnline: match['is_online'],
                    lastMessageAt: match['last_message_at'] != null
                        ? DateTime.parse(match['last_message_at'])
                        : null,
                    onTap: () => _navigateToProfile(match),
                  );
                },
              ),
      ),
    );
  }
}
