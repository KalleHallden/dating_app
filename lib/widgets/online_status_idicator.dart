// lib/widgets/online_status_indicator.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';

class OnlineStatusIndicator extends StatefulWidget {
  final String userId;
  final double size;
  final bool showBorder;
  
  const OnlineStatusIndicator({
    Key? key,
    required this.userId,
    this.size = 12,
    this.showBorder = true,
  }) : super(key: key);

  @override
  State<OnlineStatusIndicator> createState() => _OnlineStatusIndicatorState();
}

class _OnlineStatusIndicatorState extends State<OnlineStatusIndicator> {
  bool _isOnline = false;
  supabase.RealtimeChannel? _statusChannel;

  @override
  void initState() {
    super.initState();
    _loadInitialStatus();
    _subscribeToStatus();
  }

  @override
  void dispose() {
    _statusChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadInitialStatus() async {
    try {
      final client = SupabaseClient.instance.client;
      final response = await client
          .from('users')
          .select('online')
          .eq('user_id', widget.userId)
          .single();
      
      if (mounted) {
        setState(() {
          _isOnline = response['online'] ?? false;
        });
      }
    } catch (e) {
      print('Error loading initial status for ${widget.userId}: $e');
    }
  }

  void _subscribeToStatus() {
    final client = SupabaseClient.instance.client;
    
    _statusChannel = client
        .channel('user-online-${widget.userId}')
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: supabase.PostgresChangeFilter(
            type: supabase.PostgresChangeFilterType.eq,
            column: 'user_id',
            value: widget.userId,
          ),
          callback: (payload) {
            final updatedData = payload.newRecord;
            if (mounted) {
              setState(() {
                _isOnline = updatedData['online'] ?? false;
              });
            }
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: _isOnline ? Colors.green : Colors.grey,
        shape: BoxShape.circle,
        border: widget.showBorder
            ? Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
                width: 2,
              )
            : null,
      ),
    );
  }
}
