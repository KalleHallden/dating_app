import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'supabase_client.dart';

class AccountDeletionService {
  static final AccountDeletionService _instance = AccountDeletionService._internal();
  factory AccountDeletionService() => _instance;
  AccountDeletionService._internal();

  /// Delete the current user's account
  /// Returns a DeletionResult with the outcome
  Future<DeletionResult> deleteAccount({String? reason}) async {
    try {
      final client = SupabaseClient.instance.client;
      final session = client.auth.currentSession;

      if (session == null || session.accessToken == null) {
        return DeletionResult(
          success: false,
          error: 'No active session found. Please sign in again.',
        );
      }

      // Get the Supabase project URL from environment
      final supabaseUrl = dotenv.env['SUPABASE_URL'] ??
          'https://rmscsaejeoybubpgzexq.supabase.co';
      final functionUrl = '$supabaseUrl/functions/v1/delete-account';

      print('AccountDeletionService: Calling delete account function');

      // Make the HTTP request to the edge function
      final response = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'reason': reason ?? '',
        }),
      );

      print('AccountDeletionService: Response status: ${response.statusCode}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Success response
        return DeletionResult(
          success: true,
          message: responseData['message'] as String?,
          cooldownDays: responseData['cooldownDays'] as int?,
          canReregisterAfter: responseData['canReregisterAfter'] != null
              ? DateTime.parse(responseData['canReregisterAfter'] as String)
              : null,
        );
      } else if (response.statusCode == 400) {
        // Account already deleted
        return DeletionResult(
          success: false,
          error: responseData['error'] as String? ?? 'Account is already deleted',
          isAlreadyDeleted: true,
        );
      } else if (response.statusCode == 401) {
        // Unauthorized
        return DeletionResult(
          success: false,
          error: responseData['error'] as String? ?? 'Unauthorized. Please sign in again.',
        );
      } else {
        // Other errors
        return DeletionResult(
          success: false,
          error: responseData['error'] as String? ??
                 responseData['message'] as String? ??
                 'Failed to delete account. Please try again.',
        );
      }
    } catch (e) {
      print('AccountDeletionService: Error deleting account: $e');
      return DeletionResult(
        success: false,
        error: 'An error occurred while deleting your account. Please check your connection and try again.',
      );
    }
  }

  /// Sign out the user after successful deletion
  Future<void> signOutAfterDeletion() async {
    try {
      await SupabaseClient.instance.client.auth.signOut();
    } catch (e) {
      print('AccountDeletionService: Error signing out after deletion: $e');
    }
  }
}

/// Result class for account deletion
class DeletionResult {
  final bool success;
  final String? message;
  final String? error;
  final int? cooldownDays;
  final DateTime? canReregisterAfter;
  final bool isAlreadyDeleted;

  DeletionResult({
    required this.success,
    this.message,
    this.error,
    this.cooldownDays,
    this.canReregisterAfter,
    this.isAlreadyDeleted = false,
  });

  /// Get a user-friendly message about the cooldown period
  String getCooldownMessage() {
    if (cooldownDays == null) return '';

    if (cooldownDays! >= 365) {
      final years = (cooldownDays! / 365).floor();
      return 'You can create a new account after $years year${years > 1 ? 's' : ''}';
    } else if (cooldownDays! >= 30) {
      final months = (cooldownDays! / 30).floor();
      return 'You can create a new account after $months month${months > 1 ? 's' : ''}';
    } else if (cooldownDays! >= 7) {
      final weeks = (cooldownDays! / 7).floor();
      return 'You can create a new account after $weeks week${weeks > 1 ? 's' : ''}';
    } else {
      return 'You can create a new account after $cooldownDays day${cooldownDays! > 1 ? 's' : ''}';
    }
  }

  /// Get the formatted date when user can reregister
  String getReregisterDateFormatted() {
    if (canReregisterAfter == null) return '';

    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return '${months[canReregisterAfter!.month - 1]} ${canReregisterAfter!.day}, ${canReregisterAfter!.year}';
  }
}