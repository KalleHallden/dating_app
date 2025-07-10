import 'package:flutter/material.dart';
import '../models/UserLocation.dart';
import '../widgets/location_picker.dart';

class SignupStep2 extends StatefulWidget {
  final Function(String gender, String genderPreference, UserLocation location) onDataCollected;

  const SignupStep2({required this.onDataCollected, super.key});

  @override
  State<SignupStep2> createState() => _SignupStep2State();
}

class _SignupStep2State extends State<SignupStep2> {
  String? _gender;
  String? _genderPreference;
  UserLocation? _userLocation;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _gender,
            decoration: const InputDecoration(labelText: 'Gender'),
            items: ['Man', 'Woman', 'Other']
                .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                .toList(),
            onChanged: (value) => setState(() => _gender = value),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _genderPreference,
            decoration: const InputDecoration(labelText: 'Gender Preference'),
            items: ['Man', 'Woman', 'Man or Woman', 'Other']
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (value) => setState(() => _genderPreference = value),
          ),
          const SizedBox(height: 16),
          ListTile(
            title: Text(_userLocation == null
                ? 'Set Location'
                : 'Location: (${_userLocation!.lat.toStringAsFixed(2)}, ${_userLocation!.long.toStringAsFixed(2)})'),
            trailing: const Icon(Icons.map),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LocationPicker(
                    onLocationSelected: (location) {
                      setState(() => _userLocation = location);
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              if (_gender != null && _genderPreference != null && _userLocation != null) {
                widget.onDataCollected(_gender!, _genderPreference!, _userLocation!);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All fields are required')),
                );
              }
            },
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }
}
