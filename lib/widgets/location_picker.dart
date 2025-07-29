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
  bool _isMapReady = false;

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
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(newPosition, 15),
        );
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

  void _onCameraMove(CameraPosition position) {
    setState(() {
      _selectedPosition = position.target;
    });
  }

  void _onCameraIdle() {
    // This is called when the camera stops moving
    // You could add additional logic here if needed
    print('Camera stopped at: ${_selectedPosition.latitude}, ${_selectedPosition.longitude}');
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
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _selectedPosition,
              zoom: 15,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              setState(() {
                _isMapReady = true;
              });
            },
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
            // No markers needed since we're using a static center pin
            markers: const {},
          ),
          
          // Search bar at the top
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search (e.g., city, street)',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                    },
                  ),
                ),
                onSubmitted: (_) => _searchLocation(),
              ),
            ),
          ),
          
          // Static pin in the center
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pin icon
                Icon(
                  Icons.location_pin,
                  color: Colors.red[700],
                  size: 50,
                ),
                // Small dot at the exact center point
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.red[700],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Current position display (optional - shows coordinates)
          if (_isMapReady)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.grey[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lat: ${_selectedPosition.latitude.toStringAsFixed(6)}, '
                        'Lng: ${_selectedPosition.longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Set Location button
          Positioned(
            bottom: 24,
            left: 16,
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
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                backgroundColor: Theme.of(context).primaryColor,
              ),
              child: const Text(
                'Set Location',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
		  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
