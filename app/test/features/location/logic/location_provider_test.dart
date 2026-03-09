import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_pulse/features/location/data/location_repository.dart';
import 'package:mobile_pulse/features/location/logic/location_provider.dart';
import 'package:mobile_pulse/features/location/models/location_data.dart';
import 'package:mobile_pulse/services/location_service.dart';

class MockLocationService extends Mock implements LocationService {}

LocationData _fix({double lat = 1.0, double lng = 2.0}) => LocationData(
  latitude: lat,
  longitude: lng,
  accuracy: 5.0,
  altitude: 10.0,
  speed: 0.0,
  timestamp: DateTime(2026, 3, 9),
);

void main() {
  late MockLocationService mockService;

  setUp(() {
    mockService = MockLocationService();
  });

  ProviderContainer _container() => ProviderContainer(
    overrides: [locationServiceProvider.overrideWithValue(mockService)],
  );

  group('locationStreamProvider', () {
    test('emits data when permission granted and stream active', () async {
      when(() => mockService.requestPermission()).thenAnswer((_) async => true);
      when(() => mockService.locationStream).thenAnswer(
        (_) => Stream.fromIterable([_fix(lat: 3.0), _fix(lat: 4.0)]),
      );

      final container = _container();
      addTearDown(container.dispose);

      // Advance past loading state
      final sub = container.listen(locationStreamProvider, (_, __) {});
      addTearDown(sub.close);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(locationStreamProvider);
      expect(state, isA<AsyncData<LocationData>>());
      expect(state.value?.latitude, 4.0); // last emission
    });

    test('emits error when permission denied', () async {
      when(
        () => mockService.requestPermission(),
      ).thenAnswer((_) async => false);
      when(
        () => mockService.locationStream,
      ).thenAnswer((_) => const Stream.empty());

      final container = _container();
      addTearDown(container.dispose);

      // Riverpod 3 StreamProvider retries on error, cycling through
      // AsyncLoading → AsyncError → AsyncLoading … Use a completer to
      // capture the first AsyncError emission via the listener.
      final completer = Completer<AsyncValue<LocationData>>();
      final sub = container.listen(locationStreamProvider, (_, next) {
        if (next.hasError && !completer.isCompleted) completer.complete(next);
      });
      addTearDown(sub.close);

      final state = await completer.future.timeout(const Duration(seconds: 2));
      expect(state.error.toString(), contains('permission denied'));
    });
  });

  group('locationRepositoryProvider', () {
    test('delegates requestPermission to service', () async {
      when(() => mockService.requestPermission()).thenAnswer((_) async => true);

      final container = _container();
      addTearDown(container.dispose);

      final repo = container.read(locationRepositoryProvider);
      final result = await repo.requestPermission();
      expect(result, isTrue);
      verify(() => mockService.requestPermission()).called(1);
    });

    test('delegates locationStream to service', () {
      final fix = _fix();
      when(
        () => mockService.locationStream,
      ).thenAnswer((_) => Stream.value(fix));

      final container = _container();
      addTearDown(container.dispose);

      final repo = container.read(locationRepositoryProvider);
      expect(repo.locationStream, emits(fix));
    });
  });
}
