import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_pulse/features/location/logic/location_provider.dart';
import 'package:mobile_pulse/features/location/logic/relay_provider.dart';
import 'package:mobile_pulse/features/location/models/location_data.dart';
import 'package:mobile_pulse/services/location_service.dart';
import 'package:mobile_pulse/services/relay_push_service.dart';

class MockLocationService extends Mock implements LocationService {}

class MockRelayPushService extends Mock implements RelayPushService {}

LocationData _fix() => LocationData(
  latitude: 1.0,
  longitude: 2.0,
  accuracy: 5.0,
  altitude: 10.0,
  speed: 0.0,
  timestamp: DateTime.utc(2026, 3, 10),
);

void main() {
  late MockLocationService mockLocation;
  late MockRelayPushService mockRelay;
  late StreamController<RelayPushStatus> statusCtrl;

  setUpAll(() {
    registerFallbackValue(Stream<Map<String, dynamic>>.empty());
  });

  setUp(() {
    mockLocation = MockLocationService();
    mockRelay = MockRelayPushService();
    statusCtrl = StreamController<RelayPushStatus>.broadcast();

    when(
      () => mockLocation.locationStream,
    ).thenAnswer((_) => Stream.value(_fix()));
    when(() => mockLocation.requestPermission()).thenAnswer((_) async => true);
    when(() => mockRelay.statusStream).thenAnswer((_) => statusCtrl.stream);
    when(() => mockRelay.start(any())).thenAnswer((_) {});
    when(() => mockRelay.stop()).thenAnswer((_) {});
    when(() => mockRelay.dispose()).thenAnswer((_) {});
  });

  tearDown(() => statusCtrl.close());

  ProviderContainer makeContainer() {
    final c = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(mockLocation),
        relayPushServiceProvider.overrideWithValue(mockRelay),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('RelayNotifier initial state', () {
    test('starts inactive with idle status', () {
      final container = makeContainer();
      final state = container.read(relayNotifierProvider);
      expect(state.active, isFalse);
      expect(state.status, RelayPushStatus.idle);
    });
  });

  group('toggle — activate', () {
    test('sets active = true and calls relay.start()', () {
      final container = makeContainer();
      container.read(relayNotifierProvider.notifier).toggle();
      expect(container.read(relayNotifierProvider).active, isTrue);
      verify(() => mockRelay.start(any())).called(1);
    });
  });

  group('toggle — deactivate', () {
    test('sets active = false and calls relay.stop()', () {
      final container = makeContainer();
      final notifier = container.read(relayNotifierProvider.notifier);
      notifier.toggle(); // on
      notifier.toggle(); // off
      expect(container.read(relayNotifierProvider).active, isFalse);
      verify(() => mockRelay.stop()).called(1);
    });

    test('status resets to idle after stop', () {
      final container = makeContainer();
      final notifier = container.read(relayNotifierProvider.notifier);
      notifier.toggle();
      notifier.toggle();
      expect(
        container.read(relayNotifierProvider).status,
        RelayPushStatus.idle,
      );
    });
  });

  group('relay status stream updates state', () {
    test('ok status from relay is reflected in RelayState', () async {
      final container = makeContainer();
      container.read(relayNotifierProvider.notifier).toggle();

      statusCtrl.add(RelayPushStatus.ok);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(relayNotifierProvider).status, RelayPushStatus.ok);
    });

    test('error status from relay is reflected in RelayState', () async {
      final container = makeContainer();
      container.read(relayNotifierProvider.notifier).toggle();

      statusCtrl.add(RelayPushStatus.error);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(relayNotifierProvider).status,
        RelayPushStatus.error,
      );
    });
  });

  group('RelayState.copyWith', () {
    test('updates supplied fields and preserves others', () {
      const base = RelayState();
      final next = base.copyWith(active: true, status: RelayPushStatus.ok);
      expect(next.active, isTrue);
      expect(next.status, RelayPushStatus.ok);
    });

    test('omitting a field preserves its current value', () {
      const base = RelayState(active: true, status: RelayPushStatus.ok);
      final next = base.copyWith(active: false);
      expect(next.status, RelayPushStatus.ok);
    });
  });

  group('startIfInactive()', () {
    test('activates when currently inactive', () {
      final container = makeContainer();
      container.read(relayNotifierProvider.notifier).startIfInactive();
      expect(container.read(relayNotifierProvider).active, isTrue);
      verify(() => mockRelay.start(any())).called(1);
    });

    test('is a no-op when already active', () {
      final container = makeContainer();
      final notifier = container.read(relayNotifierProvider.notifier);
      notifier.startIfInactive(); // activates
      notifier.startIfInactive(); // should do nothing
      verify(() => mockRelay.start(any())).called(1); // only once
    });
  });

  group('stopIfActive()', () {
    test('deactivates when currently active', () {
      final container = makeContainer();
      final notifier = container.read(relayNotifierProvider.notifier);
      notifier.toggle(); // activate
      notifier.stopIfActive();
      expect(container.read(relayNotifierProvider).active, isFalse);
      verify(() => mockRelay.stop()).called(1);
    });

    test('is a no-op when already inactive', () {
      final container = makeContainer();
      container.read(relayNotifierProvider.notifier).stopIfActive();
      expect(container.read(relayNotifierProvider).active, isFalse);
      verifyNever(() => mockRelay.stop());
    });
  });
}
