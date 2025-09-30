import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/supabase_client.dart';
import '../services/phone_ban_service.dart';
import 'otp_verification_screen.dart';

class PhoneEntryScreen extends StatefulWidget {
  final bool isSignIn;

  const PhoneEntryScreen({required this.isSignIn, super.key});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  bool _isCheckingBan = false;
  String? _errorMessage;
  bool _isErrorDueToBan = false;

  String _selectedCountryCode = '+1';
  final Map<String, String> _countryCodes = {
    '+1': '🇺🇸 United States',
    '+44': '🇬🇧 United Kingdom',
    '+33': '🇫🇷 France',
    '+49': '🇩🇪 Germany',
    '+39': '🇮🇹 Italy',
    '+34': '🇪🇸 Spain',
    '+31': '🇳🇱 Netherlands',
    '+46': '🇸🇪 Sweden',
    '+47': '🇳🇴 Norway',
    '+45': '🇩🇰 Denmark',
    '+358': '🇫🇮 Finland',
    '+48': '🇵🇱 Poland',
    '+41': '🇨🇭 Switzerland',
    '+43': '🇦🇹 Austria',
    '+32': '🇧🇪 Belgium',
    '+353': '🇮🇪 Ireland',
    '+351': '🇵🇹 Portugal',
    '+30': '🇬🇷 Greece',
    '+420': '🇨🇿 Czech Republic',
    '+36': '🇭🇺 Hungary',
    '+40': '🇷🇴 Romania',
    '+7': '🇷🇺 Russia',
    '+380': '🇺🇦 Ukraine',
    '+86': '🇨🇳 China',
    '+81': '🇯🇵 Japan',
    '+82': '🇰🇷 South Korea',
    '+91': '🇮🇳 India',
    '+62': '🇮🇩 Indonesia',
    '+60': '🇲🇾 Malaysia',
    '+65': '🇸🇬 Singapore',
    '+66': '🇹🇭 Thailand',
    '+84': '🇻🇳 Vietnam',
    '+63': '🇵🇭 Philippines',
    '+61': '🇦🇺 Australia',
    '+64': '🇳🇿 New Zealand',
    '+20': '🇪🇬 Egypt',
    '+27': '🇿🇦 South Africa',
    '+234': '🇳🇬 Nigeria',
    '+254': '🇰🇪 Kenya',
    '+212': '🇲🇦 Morocco',
    '+216': '🇹🇳 Tunisia',
    '+213': '🇩🇿 Algeria',
    '+966': '🇸🇦 Saudi Arabia',
    '+971': '🇦🇪 United Arab Emirates',
    '+972': '🇮🇱 Israel',
    '+90': '🇹🇷 Turkey',
    '+98': '🇮🇷 Iran',
    '+92': '🇵🇰 Pakistan',
    '+880': '🇧🇩 Bangladesh',
    '+94': '🇱🇰 Sri Lanka',
    '+52': '🇲🇽 Mexico',
    '+55': '🇧🇷 Brazil',
    '+54': '🇦🇷 Argentina',
    '+57': '🇨🇴 Colombia',
    '+58': '🇻🇪 Venezuela',
    '+51': '🇵🇪 Peru',
    '+56': '🇨🇱 Chile',
    '+593': '🇪🇨 Ecuador',
  };

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String get _countryFlag {
    final countryInfo = _countryCodes[_selectedCountryCode] ?? '';
    return countryInfo.split(' ')[0];
  }


  Future<void> _sendOTP() async {
    if (_phoneController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your phone number';
        _isErrorDueToBan = false;
      });
      return;
    }

    final phoneNumber = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (phoneNumber.length < 7) {
      setState(() {
        _errorMessage = 'Please enter a valid phone number';
        _isErrorDueToBan = false;
      });
      return;
    }

    setState(() {
      _isCheckingBan = true;
      _errorMessage = null;
      _isErrorDueToBan = false;
    });

    try {
      final fullPhoneNumber = '$_selectedCountryCode$phoneNumber';

      // Step 1: Check if phone number is banned BEFORE sending OTP
      final banCheckResult = await PhoneBanService().checkPhoneBan(fullPhoneNumber);

      if (!banCheckResult.isAllowed) {
        // Phone is banned, in cooldown, or there was an error
        setState(() {
          _errorMessage = banCheckResult.message;
          // Show red error ONLY for banned users, gray for cooldown and other errors
          _isErrorDueToBan = banCheckResult.isBanned; // Only banned users get red
        });
        return;
      }

      // Step 2: Phone is allowed, proceed with OTP sending
      setState(() {
        _isCheckingBan = false;
        _isLoading = true;
      });

      final client = SupabaseClient.instance.client;

      await client.auth.signInWithOtp(
        phone: fullPhoneNumber,
      );

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtpVerificationScreen(
              phoneNumber: fullPhoneNumber,
              isSignIn: widget.isSignIn,
            ),
          ),
        );
      }
    } on supabase.AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isErrorDueToBan = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to send verification code. Please try again.';
        _isErrorDueToBan = false;
      });
    } finally {
      setState(() {
        _isLoading = false;
        _isCheckingBan = false;
      });
    }
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey, width: 0.5),
                    ),
                  ),
                  child: const Text(
                    'Select Country',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _countryCodes.length,
                    itemBuilder: (context, index) {
                      final code = _countryCodes.keys.elementAt(index);
                      final countryInfo = _countryCodes[code]!;
                      final parts = countryInfo.split(' ');
                      final flag = parts[0];
                      final name = parts.sublist(1).join(' ');

                      return ListTile(
                        leading: Text(flag, style: const TextStyle(fontSize: 24)),
                        title: Text(name),
                        trailing: Text(
                          code,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        selected: code == _selectedCountryCode,
                        selectedTileColor: const Color(0xFF985021).withValues(alpha: 0.1),
                        onTap: () {
                          setState(() {
                            _selectedCountryCode = code;
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your phone number',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We\'ll send you a code to verify your number',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 32),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: _isErrorDueToBan ? Colors.red : Colors.grey[600],
                    ),
                  ),
                ),
              Row(
                children: [
                  GestureDetector(
                    onTap: _showCountryPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(_countryFlag, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Text(
                            _selectedCountryCode,
                            style: const TextStyle(fontSize: 16),
                          ),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        hintText: 'Phone number',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF985021)),
                        ),
                      ),
                      onSubmitted: (_) => _sendOTP(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_isLoading || _isCheckingBan) ? null : _sendOTP,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF985021),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                  child: (_isLoading || _isCheckingBan)
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _isCheckingBan ? 'Verifying...' : 'Sending...',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'Send Code',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}