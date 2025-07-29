// lib/services/location_service.dart
import 'package:geocoding/geocoding.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  // Cache for location lookups to reduce API calls
  final Map<String, String> _locationCache = {};

  /// Convert coordinates to city name
  Future<String> getCityFromCoordinates(double latitude, double longitude) async {
    // Create a cache key
    final cacheKey = '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)}';
    
    // Check cache first
    if (_locationCache.containsKey(cacheKey)) {
      return _locationCache[cacheKey]!;
    }

    try {
      // Perform reverse geocoding
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      
      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        
        // Try to get the most appropriate location name
        String locationName = '';
        
        // Priority order: locality (city), subAdministrativeArea (county), administrativeArea (state)
        if (placemark.locality != null && placemark.locality!.isNotEmpty) {
          locationName = placemark.locality!;
        } else if (placemark.subAdministrativeArea != null && placemark.subAdministrativeArea!.isNotEmpty) {
          locationName = placemark.subAdministrativeArea!;
        } else if (placemark.administrativeArea != null && placemark.administrativeArea!.isNotEmpty) {
          locationName = placemark.administrativeArea!;
        } else if (placemark.name != null && placemark.name!.isNotEmpty) {
          locationName = placemark.name!;
        }
        
        // Add country if available and not USA (to distinguish international cities)
        if (placemark.country != null && 
            placemark.country!.isNotEmpty && 
            placemark.country != 'United States' &&
            placemark.country != 'USA' &&
            locationName.isNotEmpty) {
          locationName = '$locationName, ${placemark.country}';
        }
        
        // Cache the result
        if (locationName.isNotEmpty) {
          _locationCache[cacheKey] = locationName;
          return locationName;
        }
      }
      
      return 'Unknown location';
    } catch (e) {
      print('Error getting city from coordinates: $e');
      return 'Location unavailable';
    }
  }

  /// Parse PostGIS point format and get city name
  Future<String> getCityFromPostGISPoint(String? location) async {
    if (location == null || location.isEmpty) {
      return 'Location not set';
    }
    
    try {
      // Parse the PostGIS point format (lat,long)
      final coords = location.replaceAll('(', '').replaceAll(')', '').split(',');
      if (coords.length == 2) {
        final lat = double.tryParse(coords[0].trim());
        final long = double.tryParse(coords[1].trim());
        if (lat != null && long != null) {
          return await getCityFromCoordinates(lat, long);
        }
      }
    } catch (e) {
      print('Error parsing location: $e');
    }
    
    return 'Invalid location';
  }

  /// Clear the location cache (useful if memory becomes a concern)
  void clearCache() {
    _locationCache.clear();
  }
}
