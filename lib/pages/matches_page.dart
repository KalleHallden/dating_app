// lib/pages/matches_list_page.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class MatchesListPage extends StatefulWidget {
  const MatchesListPage({Key? key}) : super(key: key);

  @override
  _MatchesListPageState createState() => _MatchesListPageState();
}

class _MatchesListPageState extends State<MatchesListPage> {
  final _client = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _matches = [];

  @override
  void initState() {
    super.initState();
    _fetchMatches();
  }

  Future<void> _fetchMatches() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    try {
      // Query the user_matches view/table which is row-level restricted to the current user
      final response = await _client
          .from('user_matches')
          .select('''
            matched_user_id,
            matched_user_name,
            matched_user_picture,
            created_at
          ''')
          .order('created_at', ascending: false);

      final data = response as List<dynamic>;
      final parsed = data.map((row) {
        final item = row as Map<String, dynamic>;
        return {
          'id': item['matched_user_id'] as String,
          'name': item['matched_user_name'] as String,
          'avatarUrl': item['matched_user_picture'] as String?,
          'created_at': DateTime.parse(item['created_at'] as String),
        };
      }).toList();

      setState(() => _matches = parsed);
    } on PostgrestException catch (e) {
      debugPrint('Error fetching matches: ${e.message}');
    } catch (e) {
      debugPrint('Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_matches.isEmpty) {
      return const Center(child: Text('No matches yet.'));
    }

    return ListView.separated(
      itemCount: _matches.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = _matches[i];
        final dateStr = DateFormat.yMMMd().format(m['created_at'] as DateTime);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            radius: 24,
            backgroundImage:
                m['avatarUrl'] != null ? NetworkImage(m['avatarUrl']!) : null,
            child: m['avatarUrl'] == null
                ? const Icon(Icons.person, size: 24)
                : null,
          ),
          title: Text(
            m['name'] as String,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            dateStr,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          onTap: () {
            // TODO: navigate to chat or profile
          },
        );
      },
    );
  }
}

