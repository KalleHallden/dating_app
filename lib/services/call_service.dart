// lib/services/call_service.dart
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'supabase_client.dart';

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final _client = SupabaseClient.instance.client;

  // Get call details
  Future<Map<String, dynamic>?> getCallDetails(String callId) async {
    try {
      final response = await _client
          .from('calls')
          .select('''
            *,
            caller:users!calls_caller_id_fkey(
              user_id,
              name,
              profile_picture_url
            ),
            called:users!calls_called_id_fkey(
              user_id,
              name,
              profile_picture_url
            )
          ''')
          .eq('id', callId)
          .single();

      return response;
    } catch (e) {
      print('Error fetching call details: $e');
      return null;
    }
  }

  // Update call status
  Future<bool> updateCallStatus(String callId, String status) async {
    try {
      await _client
          .from('calls')
          .update({
            'status': status,
            // REMOVED: Don't set updated_at - let database handle it
          })
          .eq('id', callId);

      return true;
    } catch (e) {
      print('Error updating call status: $e');
      return false;
    }
  }

  // Mark call as active when both users join
  Future<bool> markCallAsActive(String callId) async {
    try {
      await _client
          .from('calls')
          .update({
            'status': 'active',
            // REMOVED: Don't set updated_at - let database handle it
          })
          .eq('id', callId)
          .eq('status', 'ringing'); // Only update if still ringing

      return true;
    } catch (e) {
      print('Error marking call as active: $e');
      return false;
    }
  }

  // End a call
  Future<bool> endCall(String callId) async {
    try {
      await _client
          .from('calls')
          .update({
            'status': 'ended',
            // CRITICAL FIX: Don't set ended_at or updated_at
            // Let the database trigger handle timestamps
          })
          .eq('id', callId);

      return true;
    } catch (e) {
      print('Error ending call: $e');
      return false;
    }
  }

  // Get active call for user
  Future<Map<String, dynamic>?> getActiveCallForUser(String userId) async {
    try {
      final response = await _client
          .from('calls')
          .select('''
            *,
            caller:users!calls_caller_id_fkey(
              user_id,
              name,
              profile_picture_url
            ),
            called:users!calls_called_id_fkey(
              user_id,
              name,
              profile_picture_url
            )
          ''')
          .or('caller_id.eq.$userId,called_id.eq.$userId')
          .inFilter('status', ['ringing', 'active'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response;
    } catch (e) {
      print('Error fetching active call: $e');
      return null;
    }
  }

  // Check if user is in a call
  Future<bool> isUserInCall(String userId) async {
    final activeCall = await getActiveCallForUser(userId);
    return activeCall != null;
  }

  // Get call history for user
  Future<List<Map<String, dynamic>>> getCallHistory(String userId,
      {int limit = 20}) async {
    try {
      final response = await _client
          .from('calls')
          .select('''
            *,
            caller:users!calls_caller_id_fkey(
              user_id,
              name,
              profile_picture_url
            ),
            called:users!calls_called_id_fkey(
              user_id,
              name,
              profile_picture_url
            )
          ''')
          .or('caller_id.eq.$userId,called_id.eq.$userId')
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching call history: $e');
      return [];
    }
  }

  supabase.RealtimeChannel subscribeToCallUpdates(
    String callId, {
    required Function(Map<String, dynamic>) onUpdate,
  }) {
    return _client
        .channel('call-updates-$callId')
        .onPostgresChanges(
          event: supabase.PostgresChangeEvent.update,
          schema: 'public',
          table: 'calls',
          filter: supabase.PostgresChangeFilter(
            type: supabase.PostgresChangeFilterType.eq,
            column: 'id',
            value: callId,
          ),
          callback: (payload) {
            onUpdate(payload.newRecord);
          },
        )
        .subscribe();
  }

  // Calculate call duration
  Duration? getCallDuration(Map<String, dynamic> call) {
    if (call['created_at'] == null) return null;

    final startTime = DateTime.parse(call['created_at']);
    final endTime = call['ended_at'] != null
        ? DateTime.parse(call['ended_at'])
        : DateTime.now();

    return endTime.difference(startTime);
  }

  // Format call status for display
  String getDisplayStatus(String status) {
    switch (status) {
      case 'pending':
        return 'Connecting...';
      case 'ringing':
        return 'Ringing...';
      case 'active':
        return 'In Call';
      case 'ended':
        return 'Call Ended';
      case 'missed':
        return 'Missed Call';
      case 'declined':
        return 'Call Declined';
      default:
        return status;
    }
  }
}
