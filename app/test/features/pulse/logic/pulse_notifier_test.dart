import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_pulse/features/pulse/logic/pulse_provider.dart';
import 'package:mobile_pulse/features/pulse/models/pulse_data.dart';
import 'package:mobile_pulse/services/pulse_service.dart';
import 'package:mobile_pulse/services/relay_push_service.dart';

class MockPulseService extends Mock implements PulseService {}

class MockRelayPushService extends Mock implements RelayPushService {}

PulseData _fix() => PulseData(
  cpuTotalPct: 30.0,
  cpuPerCorePct: const [28.0, 32.0],
  cpuFreqAvgMhz: 1800.0,
  cpuFreqPerCoreMhz: const [1700.0, 1900.0],
  memPct: 50.0,
  memUsedBytes: 4000000000,
  memAvailableBytes: 4000000000,
  socTempC: 37.0,
  netRxBpsTotal: 10000,
  netTxBpsTotal: 5000,
  timestamp: DateTime.utc(2026, 3, 10),
);

void main() {
  late MockPulseService mockPulse;
  late MockRelayPushService mockRelay;
  late StreamController<RelayPushStatus> statusCtrl;

  setUpAll(() {
    registerFallbackValue(Stream<Map<String, dynamic>>.empty());
  });

  setUp(() {
    mockPulse = MockPulseService();
    mockRelay = MockRelayPushService();
    statusCtrl = StreamController<RelayPushStatus>.broadcast();

    when(
      () => mockPulse.pulseStream,
    ).thenAnswer((_) => Stream.fromIterable([_fix()]));
    when(() => mockRelay.statusStream).thenAnswer((_) => statusCtrl.stream);
    when(() => mockRelay.start(any())).thenAnswer((_) {});
    when(() => mockRelay.stop()).thenAnswer((_) {});
    when(() => mockRelay.dispose()).thenAnswer((_) {});
  });

  tearDown(() => statusCtrl.close());

  ProviderContainer _container() {
    final c = ProviderContainer(
      overrides: [
        pulseServiceProvider.overrideWithValue(mockPulse),
        pulseRelayPushServiceProvider.overrideWithValue(mockRelay),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('PulseNotifier initial state', () {
    test('starts inactive with idle status', () {
      final container = _container();
      final state = container.read(pulseNotifierProvider);
      expect(state.active, isFalse);
      expect(state.status, RelayPushStatus.idle);
    });
  });

  group('toggle — activate', () {
    test('sets active = true and calls relay.start()', () {
      final container = _container();
      container.read(pulseNotifierProvider.notifier).toggle();
      expect(container.read(pulseNotifierProvider).active, isTrue);
      verify(() => mockRelay.start(any())).called(1);
    });
  });

  group('toggle — deactivate', () {
    test('sets active = false and calls relay.stop()', () {
      final container = _container();
      final notifier = container.read(pulseNotifierProvider.notifier);
      notifier.toggle(); // on
      notifier.toggle(); // off
      expect(container.read(pulseNotifierProvider).active, isFalse);
      verify(() => mockRelay.stop()).called(1);
    });

    test('status resets to idle after stop', () {
      final container = _container();
      final notifier = container.read(pulseNotifierProvider.notifier);
      notifier.toggle();
      notifier.toggle();
      expect(
        container.read(pulseNotifierProvider).status,
        RelayPushStatus.idle,
      );
    });
  });

  group('relay status stream updates state', () {
    test('ok status from relay is reflected in PulseState', () async {
      final container = _container();
      container.read(pulseNotifierProvider.notifier).toggle();

      statusCtrl.add(RelayPushStatus.ok);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(pulseNotifierProvider).status, RelayPushStatus.ok);
    });

    test('error status from relay is reflected in PulseState', () async {
      final container = _container();
      container.read(pulseNotifierProvider.notifier).toggle();

      statusCtrl.add(RelayPushStatus.error);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(pulseNotifierProvider).status,
        RelayPushStatus.error,
      );
    });
  });

  group('PulseState.copyWith', () {
    test('updates supplied fields and preserves others', () {
      const base = PulseState();
      final next = base.copyWith(active: true, status: RelayPushStatus.ok);
      expect(next.active, isTrue);
      expect(next.status, RelayPushStatus.ok);
    });

    test('omitting a field preserves its current value', () {
      const base = PulseState(active: true, status: RelayPushStatus.ok);
      final next = base.copyWith(active: false);
      expect(next.status, RelayPushStatus.ok);
    });
  });

  group('startIfInactive()', () {
    test('activates when currently inactive', () {
      final container = _container();
      container.read(pulseNotifierProvider.notifier).startIfInactive();
      expect(container.read(pulseNotifierProvider).active, isTrue);
      verify(() => mockRelay.start(any())).called(1);
    });

    test('is a no-op when already active', () {
      final container = _container();
      final notifier = container.read(pulseNotifierProvider.notifier);
      notifier.startIfInactive(); // first call — activates
      notifier.startIfInactive(); // second call — should do nothing
      verify(() => mockRelay.start(any())).called(1); // still just once
    });
  });

  group('stopIfActive()', () {
    test('deactivates when currently active', () {
      final container = _container();
      final notifier = container.read(pulseNotifierProvider.notifier);
      notifier.toggle(); // activate
      notifier.stopIfActive();
      expect(container.read(pulseNotifierProvider).active, isFalse);
      verify(() => mockRelay.stop()).called(1);
    });

    test('is a no-op when already inactive', () {
      final container = _container();
      container.read(pulseNotifierProvider.notifier).stopIfActive();
      expect(container.read(pulseNotifierProvider).active, isFalse);
      verifyNever(() => mockRelay.stop());
    });
  });
}
