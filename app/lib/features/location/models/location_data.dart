import 'package:geolocator/geolocator.dart';

class LocationData {
  final double latitude;
  final double longitude;
  final double accuracy; // metres
  final double altitude; // metres
  final double speed; // m/s
  final DateTime timestamp;

  const LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.speed,
    required this.timestamp,
  });

  factory LocationData.fromPosition(Position position) => LocationData(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracy: position.accuracy,
    altitude: position.altitude,
    speed: position.speed,
    timestamp: position.timestamp,
  );

  /// Speed in km/h.
  double get speedKmh => speed * 3.6;

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'altitude': altitude,
    'speed': speed,
    'timestamp': timestamp.toUtc().toIso8601String(),
  };

  @override
  String toString() =>
      'LocationData(lat=$latitude, lng=$longitude, accuracy=${accuracy.toStringAsFixed(1)}m, '
      'speed=${speedKmh.toStringAsFixed(1)}km/h, alt=${altitude.toStringAsFixed(1)}m)';
}
