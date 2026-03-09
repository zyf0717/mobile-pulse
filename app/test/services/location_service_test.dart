import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:mobile_pulse/features/location/models/location_data.dart';
import 'package:mobile_pulse/services/location_service.dart';

// MockPlatformInterfaceMixin is required by plugin_platform_interface's strict
// mode — plain `implements` is rejected at runtime.
class MockGeolocatorPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements GeolocatorPlatform {}

Position _makePosition({double speed = 5.0}) => Position(
  latitude: 10.0,
  longitude: 20.0,
  accuracy: 3.0,
  altitude: 50.0,
  altitudeAccuracy: 1.0,
  heading: 0.0,
  headingAccuracy: 0.0,
  speed: speed,
  speedAccuracy: 0.5,
  timestamp: DateTime(2026, 3, 9),
);

void main() {
  late MockGeolocatorPlatform mockPlatform;

  setUp(() {
    mockPlatform = MockGeolocatorPlatform();
    GeolocatorPlatform.instance = mockPlatform;
  });

  group('LocationService.requestPermission', () {
    test('returns true when already whileInUse', () async {
      when(
        () => mockPlatform.checkPermission(),
      ).thenAnswer((_) async => LocationPermission.whileInUse);

      final service = LocationService();
      expect(await service.requestPermission(), isTrue);
      verifyNever(() => mockPlatform.requestPermission());
    });

    test('returns true when always granted', () async {
      when(
        () => mockPlatform.checkPermission(),
      ).thenAnswer((_) async => LocationPermission.always);

      final service = LocationService();
      expect(await service.requestPermission(), isTrue);
    });

    test('requests permission when denied and returns true on grant', () async {
      when(
        () => mockPlatform.checkPermission(),
      ).thenAnswer((_) async => LocationPermission.denied);
      when(
        () => mockPlatform.requestPermission(),
      ).thenAnswer((_) async => LocationPermission.whileInUse);

      final service = LocationService();
      expect(await service.requestPermission(), isTrue);
      verify(() => mockPlatform.requestPermission()).called(1);
    });

    test('returns false when permission permanently denied', () async {
      when(
        () => mockPlatform.checkPermission(),
      ).thenAnswer((_) async => LocationPermission.deniedForever);

      final service = LocationService();
      expect(await service.requestPermission(), isFalse);
    });
  });

  group('LocationService.locationStream', () {
    test('maps Position to LocationData correctly', () async {
      final position = _makePosition(speed: 10.0);
      when(
        () => mockPlatform.getPositionStream(
          locationSettings: any(named: 'locationSettings'),
        ),
      ).thenAnswer((_) => Stream.value(position));

      final service = LocationService();
      final data = await service.locationStream.first;

      expect(data, isA<LocationData>());
      expect(data.latitude, 10.0);
      expect(data.longitude, 20.0);
      expect(data.speed, 10.0);
      expect(data.speedKmh, closeTo(36.0, 0.001));
    });

    test('emits multiple positions in order', () async {
      final positions = [
        _makePosition(speed: 1.0),
        _makePosition(speed: 2.0),
        _makePosition(speed: 3.0),
      ];
      when(
        () => mockPlatform.getPositionStream(
          locationSettings: any(named: 'locationSettings'),
        ),
      ).thenAnswer((_) => Stream.fromIterable(positions));

      final service = LocationService();
      final speeds = await service.locationStream.map((d) => d.speed).toList();

      expect(speeds, [1.0, 2.0, 3.0]);
    });
  });
}
