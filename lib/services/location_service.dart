// lib/services/location_service.dart
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'supabase_client.dart';

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

  /// Update user location and automatically detect timezone
  Future<Map<String, dynamic>?> updateUserLocationWithTimezone({
    required double latitude,
    required double longitude,
    String? userId,
  }) async {
    try {
      final client = SupabaseClient.instance.client;
      
      // Get current user ID if not provided
      final targetUserId = userId ?? client.auth.currentUser?.id;
      if (targetUserId == null) {
        throw Exception('No user ID available');
      }
      
      // First, update the location in the database
      // The database trigger will handle the timezone update
      await client
          .from('users')
          .update({
            'location': '($latitude,$longitude)',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', targetUserId);
      
      print('Location updated to: ($latitude, $longitude)');
      
      // Also call the Edge Function to ensure timezone is updated
      // This provides redundancy in case the trigger fails
      final timezoneResponse = await _detectTimezoneFromCoordinates(
        latitude: latitude,
        longitude: longitude,
        userId: targetUserId,
      );
      
      return {
        'location': '($latitude,$longitude)',
        'timezone': timezoneResponse?['timezone'] ?? 'UTC',
        'city': await getCityFromCoordinates(latitude, longitude),
      };
    } catch (e) {
      print('Error updating location with timezone: $e');
      return null;
    }
  }

  /// Call Edge Function to detect timezone from coordinates
  Future<Map<String, dynamic>?> _detectTimezoneFromCoordinates({
    required double latitude,
    required double longitude,
    String? userId,
  }) async {
    try {
      final client = SupabaseClient.instance.client;
      
      final response = await client.functions.invoke(
        'get-timezone-from-location',
        body: {
          'lat': latitude,
          'lon': longitude,
          'userId': userId,
        },
      );

      if (response.status == 200 && response.data != null) {
        print('Timezone detected: ${response.data['timezone']}');
        return response.data as Map<String, dynamic>;
      } else {
        print('Error detecting timezone: ${response.data}');
        return null;
      }
    } catch (e) {
      print('Exception detecting timezone: $e');
      return null;
    }
  }

  /// Get user's current timezone
  Future<String> getUserTimezone(String? userId) async {
    try {
      final client = SupabaseClient.instance.client;
      final targetUserId = userId ?? client.auth.currentUser?.id;
      
      if (targetUserId == null) {
        return 'UTC';
      }
      
      final response = await client
          .from('users')
          .select('timezone')
          .eq('user_id', targetUserId)
          .single();
      
      return response['timezone'] ?? 'UTC';
    } catch (e) {
      print('Error getting user timezone: $e');
      return 'UTC';
    }
  }

  /// Clear the location cache (useful if memory becomes a concern)
  void clearCache() {
    _locationCache.clear();
  }
}
