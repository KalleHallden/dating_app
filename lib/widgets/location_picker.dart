import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import '../models/UserLocation.dart';

class LocationPicker extends StatefulWidget {
  final Function(UserLocation) onLocationSelected;

  const LocationPicker({required this.onLocationSelected, super.key});

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  GoogleMapController? _mapController;
  LatLng _selectedPosition = const LatLng(40.7128, -74.0060); // Default: New York
  final _searchController = TextEditingController();

  Future<void> _searchLocation() async {
    try {
      final locations = await locationFromAddress(_searchController.text);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        final newPosition = LatLng(loc.latitude, loc.longitude);
        setState(() => _selectedPosition = newPosition);
        _mapController?.animateCamera(CameraUpdate.newLatLng(newPosition));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location not found')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error searching location')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Your Location'),
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selectedPosition,
              zoom: 12,
            ),
            onMapCreated: (controller) => _mapController = controller,
            onTap: (position) {
              setState(() => _selectedPosition = position);
            },
            myLocationEnabled: false, // No permissions needed
            myLocationButtonEnabled: false,
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search (e.g., city, street)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _searchLocation,
                ),
              ),
              onSubmitted: (_) => _searchLocation(),
            ),
          ),
          Center(
            child: Icon(
              Icons.location_pin,
              color: Colors.red,
              size: 40,
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: ElevatedButton(
              onPressed: () {
                final selectedLocation = UserLocation(
                  lat: _selectedPosition.latitude,
                  long: _selectedPosition.longitude,
                );
                widget.onLocationSelected(selectedLocation);
                Navigator.pop(context);
              },
              child: const Text('Set Location'),
            ),
          ),
        ],
      ),
    );
  }
}
