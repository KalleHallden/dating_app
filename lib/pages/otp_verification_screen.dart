import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'dart:async';
import '../services/supabase_client.dart';
import 'signup_screen.dart';
import 'home_page.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final bool isSignIn;

  const OtpVerificationScreen({
    required this.phoneNumber,
    required this.isSignIn,
    super.key,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );

  bool _isLoading = false;
  String? _errorMessage;
  int _resendCooldown = 0;
  Timer? _resendTimer;

  // Add a controller for the hidden text field that will capture the full OTP
  final TextEditingController _hiddenController = TextEditingController();
  final FocusNode _hiddenFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _startResendCooldown();

    // Set up listener for hidden field to detect automatic OTP input
    _hiddenController.addListener(() {
      final value = _hiddenController.text;
      if (value.length >= 6) {
        _handlePastedOTP(value);
      }
    });

    // Focus the first field initially
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _hiddenController.dispose();
    _hiddenFocusNode.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    setState(() {
      _resendCooldown = 30;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() {
          _resendCooldown--;
        });
      } else {
        timer.cancel();
      }
    });
  }

  String get _otpCode {
    return _controllers.map((c) => c.text).join();
  }

  void _onDigitChanged(String value, int index) {
    // Handle pasted OTP code (when user pastes the full code into one field)
    if (value.length > 1) {
      _handlePastedOTP(value);
      return;
    }

    if (value.isNotEmpty) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        if (_otpCode.length == 6) {
          _verifyOTP();
        }
      }
    }
  }

  void _handlePastedOTP(String pastedValue) {
    // Extract only digits from pasted value
    final digits = pastedValue.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length >= 6) {
      // Populate all 6 fields with the digits
      for (int i = 0; i < 6; i++) {
        _controllers[i].text = digits[i];
      }

      // Unfocus all fields and verify automatically
      for (var node in _focusNodes) {
        node.unfocus();
      }

      // Auto-verify if we have 6 digits
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_otpCode.length == 6) {
          _verifyOTP();
        }
      });
    }
  }

  void _handleHiddenFieldChange(String value) {
    // This handles the automatic OTP detection from iOS
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.length >= 6) {
      _handlePastedOTP(digits);
    }
  }

  void _handleBackspace(String value, int index) {
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
    }
  }

  Future<void> _verifyOTP() async {
    if (_otpCode.length != 6) {
      setState(() {
        _errorMessage = 'Please enter all 6 digits';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = SupabaseClient.instance.client;

      final response = await client.auth.verifyOTP(
        type: supabase.OtpType.sms,
        phone: widget.phoneNumber,
        token: _otpCode,
      );

      if (response.user == null) {
        throw Exception('Verification failed');
      }

      if (mounted) {
        final user = response.user!;

        // Check if user has completed profile data
        final userData = await client
            .from('users')
            .select()
            .eq('user_id', user.id)
            .maybeSingle();

        // Determine navigation based on user profile completeness and sign-in type
        if (userData == null ||
            userData['name'] == null ||
            userData['date_of_birth'] == null ||
            userData['gender'] == null ||
            userData['gender_preference'] == null ||
            userData['location'] == null ||
            userData['about_me'] == null) {

          // New user or incomplete profile - go to signup
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const SignupScreen()),
              (route) => false,
            );
          }
        } else {
          // Existing user with complete profile - go to home
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const HomePage()),
              (route) => false,
            );
          }
        }
      }
    } on supabase.AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
        for (var controller in _controllers) {
          controller.clear();
        }
        _focusNodes[0].requestFocus();
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Verification failed. Please try again.';
        for (var controller in _controllers) {
          controller.clear();
        }
        _focusNodes[0].requestFocus();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _resendOTP() async {
    if (_resendCooldown > 0) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = SupabaseClient.instance.client;

      await client.auth.signInWithOtp(
        phone: widget.phoneNumber,
      );

      _startResendCooldown();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verification code sent!'),
            backgroundColor: Color(0xFF985021),
          ),
        );
      }
    } on supabase.AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to resend code. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _formatPhoneNumber(String phoneNumber) {
    if (phoneNumber.length >= 10) {
      final lastFour = phoneNumber.substring(phoneNumber.length - 4);
      return '••••$lastFour';
    }
    return phoneNumber;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      resizeToAvoidBottomInset: true, // Handle keyboard properly
      body: SafeArea(
        child: SingleChildScrollView( // Add scroll view to handle keyboard overflow
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              height: MediaQuery.of(context).size.height -
                     MediaQuery.of(context).padding.top -
                     AppBar().preferredSize.height - 48, // Subtract padding
              child: Stack(
                children: [
                  // Hidden text field for automatic OTP detection
                  Positioned(
                    left: -1000, // Position off-screen
                    child: SizedBox(
                      width: 1,
                      height: 1,
                      child: TextField(
                        controller: _hiddenController,
                        focusNode: _hiddenFocusNode,
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        onChanged: _handleHiddenFieldChange,
                        style: const TextStyle(color: Colors.transparent),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                        ),
                      ),
                    ),
                  ),
                  // Main content
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              const Text(
                'Enter verification code',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We sent a code to ${_formatPhoneNumber(widget.phoneNumber)}',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 40),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 50,
                    height: 60,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 6, // Allow up to 6 characters for paste handling
                      enabled: !_isLoading,
                      autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFF985021),
                            width: 2,
                          ),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Colors.red,
                            width: 2,
                          ),
                        ),
                        filled: _controllers[index].text.isNotEmpty,
                        fillColor: _controllers[index].text.isNotEmpty
                            ? const Color(0xFF985021).withValues(alpha: 0.1)
                            : null,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (value) {
                        if (value.isNotEmpty) {
                          _onDigitChanged(value, index);
                        } else {
                          _handleBackspace(value, index);
                        }
                      },
                      onTap: () {
                        // Focus the hidden field to trigger iOS autofill
                        if (index == 0) {
                          _hiddenFocusNode.requestFocus();
                          Future.delayed(const Duration(milliseconds: 100), () {
                            _focusNodes[0].requestFocus();
                          });
                        }
                      },
                    ),
                  );
                }),
              ),
              const SizedBox(height: 40),
              Center(
                child: _resendCooldown > 0
                    ? Text(
                        'Resend code in $_resendCooldown seconds',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      )
                    : TextButton(
                        onPressed: _isLoading ? null : _resendOTP,
                        child: const Text(
                          'Resend Code',
                          style: TextStyle(
                            color: Color(0xFF985021),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF985021),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}