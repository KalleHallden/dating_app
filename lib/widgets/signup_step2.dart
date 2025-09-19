import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/UserLocation.dart';
import '../widgets/location_picker.dart';
import '../providers/signup_provider.dart';

class SignupStep2 extends StatefulWidget {
  final Function(String gender, String interestedIn, UserLocation location) onDataCollected;

  const SignupStep2({required this.onDataCollected, super.key});

  @override
  State<SignupStep2> createState() => _SignupStep2State();
}

class _SignupStep2State extends State<SignupStep2> {
  String? _gender;
  String? _interestedIn;
  UserLocation? _userLocation;

  @override
  void initState() {
    super.initState();
    // Initialize with existing data if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SignupProvider>();
      if (provider.gender != null) {
        _gender = provider.gender;
      }
      if (provider.interestedIn != null) {
        _interestedIn = provider.interestedIn;
      }
      if (provider.location != null) {
        _userLocation = provider.location;
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tell us about yourself',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This helps us find better matches for you',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 32),

          // My Identity Section
          const Text(
            'My identity',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _gender,
                hint: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Select your gender',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                isExpanded: true,
                items: ['Man', 'Woman', 'Non-binary', 'Prefer not to say']
                    .map((g) => DropdownMenuItem(
                          value: g,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(g),
                          ),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _gender = value),
                icon: const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Icon(Icons.keyboard_arrow_down),
                ),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Interested In Section
          const Text(
            'Interested in',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _interestedIn,
                hint: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Who are you interested in?',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                isExpanded: true,
                items: ['Men', 'Women', 'Everyone', 'Non-binary']
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(p),
                          ),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _interestedIn = value),
                icon: const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Icon(Icons.keyboard_arrow_down),
                ),
                dropdownColor: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Location Section
          const Text(
            'Your location',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final location = await Navigator.push<UserLocation>(
                context,
                MaterialPageRoute(
                  builder: (_) => LocationPicker(
                    initialLocation: _userLocation,
                    onLocationSelected: (location) {
                      setState(() => _userLocation = location);
                    },
                  ),
                ),
              );
              if (location != null) {
                setState(() => _userLocation = location);
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _userLocation?.cityName ?? 'Set your location',
                      style: TextStyle(
                        fontSize: 16,
                        color: _userLocation?.cityName != null ? Colors.black : Colors.grey,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),

          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: () {
                if (_gender != null && _interestedIn != null && _userLocation != null) {
                  widget.onDataCollected(_gender!, _interestedIn!, _userLocation!);
                } else {
                  String missingFields = '';
                  if (_gender == null) missingFields = 'Gender';
                  if (_interestedIn == null) {
                    missingFields += missingFields.isEmpty ? 'Interest preference' : ', Interest preference';
                  }
                  if (_userLocation == null) {
                    missingFields += missingFields.isEmpty ? 'Location' : ', Location';
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please provide: $missingFields'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF985021),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Next',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}