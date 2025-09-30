import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';

class PhoneBanService {
  static final PhoneBanService _instance = PhoneBanService._internal();
  factory PhoneBanService() => _instance;
  PhoneBanService._internal();

  /// Check if a phone number is banned
  /// Returns a PhoneBanResult with the check status
  Future<PhoneBanResult> checkPhoneBan(String phoneNumber) async {
    try {
      final client = SupabaseClient.instance.client;

      // Format phone number consistently (ensure it starts with +)
      final formattedPhone = _formatPhoneNumber(phoneNumber);

      print('PhoneBanService: Checking phone ban status');

      final response = await client.functions.invoke(
        'check-phone-ban',
        body: {
          'phoneNumber': formattedPhone,
        },
        headers: {
          'Content-Type': 'application/json',
        },
      );

      print('PhoneBanService: Response status: ${response.status}');
      print('PhoneBanService: Response data: ${response.data}');

      // Handle success response (200)
      if (response.status == 200) {
        final data = response.data as Map<String, dynamic>;
        final allowed = data['allowed'] as bool? ?? false;
        final message = data['message'] as String? ?? 'Phone check completed';

        return PhoneBanResult(
          allowed: allowed,
          banned: false,
          message: message,
        );
      }

      // Handle banned phone (403)
      if (response.status == 403) {
        final data = response.data as Map<String, dynamic>;
        final message = data['message'] as String? ?? 'This phone number has been suspended';

        return PhoneBanResult(
          allowed: false,
          banned: true,
          message: message,
        );
      }

      // Handle other error statuses
      final data = response.data as Map<String, dynamic>? ?? {};
      final errorMessage = data['error'] as String? ??
                          data['message'] as String? ??
                          'Unable to verify phone number';

      return PhoneBanResult(
        allowed: false,
        banned: false,
        message: errorMessage,
      );

    } on supabase.FunctionException catch (e) {
      print('PhoneBanService: Function exception: status=${e.status}');
      print('PhoneBanService: Complete exception details: ${e.details}');

      // Handle banned phone or cooldown (403 status)
      if (e.status == 403) {
        final details = e.details as Map<String, dynamic>? ?? {};
        final message = details['message'] as String? ?? 'This phone number has been suspended';
        final banned = details['banned'] as bool? ?? false;
        final inCooldown = details['inCooldown'] as bool? ?? false;
        final canReregisterAfter = details['canReregisterAfter'] as String?;
        final daysRemaining = details['daysRemaining'] as int?;

        return PhoneBanResult(
          allowed: false,
          banned: banned,
          inCooldown: inCooldown,
          message: message,
          canReregisterAfter: canReregisterAfter,
          daysRemaining: daysRemaining,
        );
      }

      // Handle server errors (500, etc.) - allow user to proceed
      if (e.status >= 500) {
        print('PhoneBanService: Server error during ban check, allowing user to proceed');
        return PhoneBanResult(
          allowed: true,
          banned: false,
          message: 'Phone verification completed',
        );
      }

      // Handle other function errors
      final details = e.details as Map<String, dynamic>? ?? {};
      final errorMessage = details['error'] as String? ??
                          details['message'] as String? ??
                          'Unable to verify phone number';

      return PhoneBanResult(
        allowed: false,
        banned: false,
        message: errorMessage,
      );
    } catch (e) {
      print('PhoneBanService: Unexpected error: $e');

      // Return a generic error for network/connection issues
      return PhoneBanResult(
        allowed: false,
        banned: false,
        message: 'Unable to verify phone number. Please check your connection and try again.',
      );
    }
  }

  /// Format phone number to ensure consistent format with country code
  String _formatPhoneNumber(String phoneNumber) {
    // Remove any non-digit characters except +
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

    // Ensure it starts with +
    if (!cleaned.startsWith('+')) {
      // If it doesn't start with +, assume it needs a + prefix
      cleaned = '+$cleaned';
    }

    return cleaned;
  }
}

/// Result class for phone ban check
class PhoneBanResult {
  final bool allowed;
  final bool banned;
  final bool inCooldown;
  final String message;
  final String? canReregisterAfter;
  final int? daysRemaining;

  PhoneBanResult({
    required this.allowed,
    required this.banned,
    required this.message,
    this.inCooldown = false,
    this.canReregisterAfter,
    this.daysRemaining,
  });

  /// Returns true if the phone number check failed due to an error (not a ban or cooldown)
  bool get hasError => !allowed && !banned && !inCooldown;

  /// Returns true if the phone number is explicitly banned
  bool get isBanned => banned;

  /// Returns true if the phone number is in cooldown period
  bool get isInCooldown => inCooldown;

  /// Returns true if the phone number is blocked (banned or in cooldown)
  bool get isBlocked => banned || inCooldown;

  /// Returns true if the phone number is allowed to proceed
  bool get isAllowed => allowed;

  @override
  String toString() {
    return 'PhoneBanResult(allowed: $allowed, banned: $banned, inCooldown: $inCooldown, message: $message)';
  }
}