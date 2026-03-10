import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_pulse/features/hr/logic/polar_provider.dart';
import 'package:mobile_pulse/features/hr/models/acc_data.dart';
import 'package:mobile_pulse/features/hr/models/ecg_data.dart';
import 'package:mobile_pulse/features/hr/models/hr_data.dart';
import 'package:mobile_pulse/services/polar_h10_service.dart';
import 'package:mobile_pulse/services/relay_push_service.dart';

class MockPolarH10Service extends Mock implements PolarH10Service {}

class MockRelayPushService extends Mock implements RelayPushService {}

void main() {
  late MockPolarH10Service mockH10;
  late MockRelayPushService mockHrRelay;
  late MockRelayPushService mockEcgRelay;
  late MockRelayPushService mockAccRelay;

  late StreamController<PolarConnectionState> connCtrl;
  late StreamController<HrData> hrCtrl;
  late StreamController<EcgData> ecgCtrl;
  late StreamController<AccData> accCtrl;
  late StreamController<RelayPushStatus> hrStatusCtrl;
  late StreamController<RelayPushStatus> ecgStatusCtrl;
  late StreamController<RelayPushStatus> accStatusCtrl;

  setUpAll(() {
    registerFallbackValue(Stream<Map<String, dynamic>>.empty());
  });

  setUp(() {
    mockH10 = MockPolarH10Service();
    mockHrRelay = MockRelayPushService();
    mockEcgRelay = MockRelayPushService();
    mockAccRelay = MockRelayPushService();

    connCtrl = StreamController<PolarConnectionState>.broadcast();
    hrCtrl = StreamController<HrData>.broadcast();
    ecgCtrl = StreamController<EcgData>.broadcast();
    accCtrl = StreamController<AccData>.broadcast();
    hrStatusCtrl = StreamController<RelayPushStatus>.broadcast();
    ecgStatusCtrl = StreamController<RelayPushStatus>.broadcast();
    accStatusCtrl = StreamController<RelayPushStatus>.broadcast();

    when(() => mockH10.connectionState).thenAnswer((_) => connCtrl.stream);
    when(() => mockH10.hrStream).thenAnswer((_) => hrCtrl.stream);
    when(() => mockH10.ecgStream).thenAnswer((_) => ecgCtrl.stream);
    when(() => mockH10.accStream).thenAnswer((_) => accCtrl.stream);
    when(() => mockH10.connect()).thenAnswer((_) async {});
    when(() => mockH10.disconnect()).thenAnswer((_) async {});
    when(() => mockH10.dispose()).thenAnswer((_) {});

    for (final r in [mockHrRelay, mockEcgRelay, mockAccRelay]) {
      when(() => r.start(any())).thenAnswer((_) {});
      when(() => r.stop()).thenAnswer((_) {});
      when(() => r.dispose()).thenAnswer((_) {});
    }
    when(() => mockHrRelay.statusStream).thenAnswer((_) => hrStatusCtrl.stream);
    when(
      () => mockEcgRelay.statusStream,
    ).thenAnswer((_) => ecgStatusCtrl.stream);
    when(
      () => mockAccRelay.statusStream,
    ).thenAnswer((_) => accStatusCtrl.stream);
  });

  tearDown(() async {
    await Future.wait([
      connCtrl.close(),
      hrCtrl.close(),
      ecgCtrl.close(),
      accCtrl.close(),
      hrStatusCtrl.close(),
      ecgStatusCtrl.close(),
      accStatusCtrl.close(),
    ]);
  });

  ProviderContainer _container() {
    final c = ProviderContainer(
      overrides: [
        polarH10ServiceProvider.overrideWithValue(mockH10),
        hrRelayPushServiceProvider.overrideWithValue(mockHrRelay),
        ecgRelayPushServiceProvider.overrideWithValue(mockEcgRelay),
        accRelayPushServiceProvider.overrideWithValue(mockAccRelay),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('PolarNotifier initial state', () {
    test('starts with disconnected / all relays off', () {
      final container = _container();
      final state = container.read(polarNotifierProvider);
      expect(state.connectionState, PolarConnectionState.disconnected);
      expect(state.latestBpm, isNull);
      expect(state.relayActive, isFalse);
      expect(state.ecgRelayActive, isFalse);
      expect(state.accRelayActive, isFalse);
    });
  });

  group('HR stream updates latestBpm', () {
    test('bpm is reflected in state after HR emission', () async {
      final container = _container();
      // trigger build
      container.read(polarNotifierProvider);

      hrCtrl.add(HrData(bpm: 72, timestamp: DateTime.now()));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(polarNotifierProvider).latestBpm, 72);
    });
  });

  group('toggleRelay (HR)', () {
    test('activates HR relay and marks relayActive = true', () {
      final container = _container();
      container.read(polarNotifierProvider.notifier).toggleRelay();
      expect(container.read(polarNotifierProvider).relayActive, isTrue);
      verify(() => mockHrRelay.start(any())).called(1);
    });

    test('deactivates HR relay and calls stop()', () {
      final container = _container();
      final notifier = container.read(polarNotifierProvider.notifier);
      notifier.toggleRelay(); // on
      notifier.toggleRelay(); // off
      expect(container.read(polarNotifierProvider).relayActive, isFalse);
      verify(() => mockHrRelay.stop()).called(1);
    });
  });

  group('toggleEcgRelay', () {
    test('activates ECG relay and marks ecgRelayActive = true', () {
      final container = _container();
      container.read(polarNotifierProvider.notifier).toggleEcgRelay();
      expect(container.read(polarNotifierProvider).ecgRelayActive, isTrue);
      verify(() => mockEcgRelay.start(any())).called(1);
    });

    test('deactivates ECG relay and calls stop()', () {
      final container = _container();
      final notifier = container.read(polarNotifierProvider.notifier);
      notifier.toggleEcgRelay(); // on
      notifier.toggleEcgRelay(); // off
      expect(container.read(polarNotifierProvider).ecgRelayActive, isFalse);
      verify(() => mockEcgRelay.stop()).called(1);
    });
  });

  group('toggleAccRelay', () {
    test('activates ACC relay and marks accRelayActive = true', () {
      final container = _container();
      container.read(polarNotifierProvider.notifier).toggleAccRelay();
      expect(container.read(polarNotifierProvider).accRelayActive, isTrue);
      verify(() => mockAccRelay.start(any())).called(1);
    });

    test('deactivates ACC relay and calls stop()', () {
      final container = _container();
      final notifier = container.read(polarNotifierProvider.notifier);
      notifier.toggleAccRelay(); // on
      notifier.toggleAccRelay(); // off
      expect(container.read(polarNotifierProvider).accRelayActive, isFalse);
      verify(() => mockAccRelay.stop()).called(1);
    });
  });

  group('connection drop auto-stops all relays', () {
    test('all relayActive flags cleared on disconnected event', () async {
      final container = _container();
      final notifier = container.read(polarNotifierProvider.notifier);

      // Start all three relays.
      notifier.toggleRelay();
      notifier.toggleEcgRelay();
      notifier.toggleAccRelay();

      expect(container.read(polarNotifierProvider).relayActive, isTrue);
      expect(container.read(polarNotifierProvider).ecgRelayActive, isTrue);
      expect(container.read(polarNotifierProvider).accRelayActive, isTrue);

      // Simulate connection drop.
      connCtrl.add(PolarConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(polarNotifierProvider);
      expect(state.relayActive, isFalse);
      expect(state.ecgRelayActive, isFalse);
      expect(state.accRelayActive, isFalse);
      expect(state.latestBpm, isNull);

      // Each relay's stop() should have been called once.
      verify(() => mockHrRelay.stop()).called(1);
      verify(() => mockEcgRelay.stop()).called(1);
      verify(() => mockAccRelay.stop()).called(1);
    });
  });

  group('disconnect()', () {
    test('stops all relays and delegates to h10.disconnect()', () async {
      final container = _container();
      final notifier = container.read(polarNotifierProvider.notifier);

      notifier.toggleRelay();
      notifier.toggleEcgRelay();

      await notifier.disconnect();

      expect(container.read(polarNotifierProvider).relayActive, isFalse);
      expect(container.read(polarNotifierProvider).ecgRelayActive, isFalse);
      verify(() => mockH10.disconnect()).called(1);
    });
  });
}
