class UserLocation {
  final double lat;
  final double long;
  final String? cityName;

  UserLocation({
    required this.lat,
    required this.long,
    this.cityName,
  });
}
