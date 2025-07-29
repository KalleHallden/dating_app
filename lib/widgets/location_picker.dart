import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import '../models/UserLocation.dart';

class LocationPicker extends StatefulWidget {
  final Function(UserLocation)? onLocationSelected; // Make optional for backward compatibility
  final UserLocation? initialLocation; // Add initial location support

  const LocationPicker({
    this.onLocationSelected, 
    this.initialLocation,
    super.key,
  });

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  GoogleMapController? _mapController;
  late LatLng _selectedPosition;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Use initial location if provided, otherwise default to New York
    if (widget.initialLocation != null) {
      _selectedPosition = LatLng(widget.initialLocation!.lat, widget.initialLocation!.long);
    } else {
      _selectedPosition = const LatLng(40.7128, -74.0060); // Default: New York
    }
  }

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
            markers: {
              Marker(
                markerId: const MarkerId('selected'),
                position: _selectedPosition,
                draggable: true,
                onDragEnd: (newPosition) {
                  setState(() => _selectedPosition = newPosition);
                },
              ),
            },
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
          Positioned(
            bottom: 16,
            right: 16,
            child: ElevatedButton(
              onPressed: () {
                final selectedLocation = UserLocation(
                  lat: _selectedPosition.latitude,
                  long: _selectedPosition.longitude,
                );
                
                // Call the callback if provided (for backward compatibility)
                widget.onLocationSelected?.call(selectedLocation);
                
                // Return the location via Navigator.pop
                Navigator.pop(context, selectedLocation);
              },
              child: const Text('Set Location'),
            ),
          ),
        ],
      ),
    );
  }
}
