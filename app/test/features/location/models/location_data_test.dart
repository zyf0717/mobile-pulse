import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:mobile_pulse/features/location/models/location_data.dart';

Position _makePosition({
  double latitude = 1.23456,
  double longitude = 6.54321,
  double accuracy = 5.0,
  double altitude = 42.0,
  double speed = 10.0,
  DateTime? timestamp,
}) => Position(
  latitude: latitude,
  longitude: longitude,
  accuracy: accuracy,
  altitude: altitude,
  altitudeAccuracy: 1.0,
  heading: 0.0,
  headingAccuracy: 0.0,
  speed: speed,
  speedAccuracy: 0.5,
  timestamp: timestamp ?? DateTime(2026, 3, 9, 12, 0, 0),
);

void main() {
  group('LocationData.fromPosition', () {
    test('maps all fields correctly', () {
      final ts = DateTime(2026, 3, 9, 12, 0, 0);
      final position = _makePosition(
        latitude: 1.23456,
        longitude: 6.54321,
        accuracy: 5.0,
        altitude: 42.0,
        speed: 10.0,
        timestamp: ts,
      );

      final data = LocationData.fromPosition(position);

      expect(data.latitude, 1.23456);
      expect(data.longitude, 6.54321);
      expect(data.accuracy, 5.0);
      expect(data.altitude, 42.0);
      expect(data.speed, 10.0);
      expect(data.timestamp, ts);
    });

    test('speedKmh converts m/s to km/h', () {
      final data = LocationData.fromPosition(_makePosition(speed: 10.0));
      expect(data.speedKmh, closeTo(36.0, 0.001));
    });

    test('speedKmh is zero when speed is zero', () {
      final data = LocationData.fromPosition(_makePosition(speed: 0.0));
      expect(data.speedKmh, 0.0);
    });

    test('toString includes key fields', () {
      final data = LocationData.fromPosition(_makePosition());
      final s = data.toString();
      expect(s, contains('lat='));
      expect(s, contains('lng='));
      expect(s, contains('accuracy='));
      expect(s, contains('speed='));
      expect(s, contains('alt='));
    });
  });
}
