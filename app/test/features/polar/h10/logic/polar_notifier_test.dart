import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_pulse/features/polar/common/models/acc_data.dart';
import 'package:mobile_pulse/features/polar/common/models/hr_data.dart';
import 'package:mobile_pulse/features/polar/common/models/polar_connection_state.dart';
import 'package:mobile_pulse/features/polar/h10/logic/polar_provider.dart';
import 'package:mobile_pulse/features/polar/h10/models/ecg_data.dart';
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
    test('starts with disconnected / relay off', () {
      final container = _container();
      final state = container.read(polarNotifierProvider);
      expect(state.connectionState, PolarConnectionState.disconnected);
      expect(state.latestBpm, isNull);
      expect(state.h10RelayActive, isFalse);
    });
  });

  group('HR stream updates latestBpm', () {
    test('bpm is reflected in state after HR emission', () async {
      final container = _container();
      container.read(polarNotifierProvider);

      hrCtrl.add(HrData(bpm: 72, timestamp: DateTime.now()));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(polarNotifierProvider).latestBpm, 72);
    });
  });

  group('toggleH10Relay', () {
    test('activates all three relays and marks h10RelayActive = true', () {
      final container = _container();
      container.read(polarNotifierProvider.notifier).toggleH10Relay();
      expect(container.read(polarNotifierProvider).h10RelayActive, isTrue);
      verify(() => mockHrRelay.start(any())).called(1);
      verify(() => mockEcgRelay.start(any())).called(1);
      verify(() => mockAccRelay.start(any())).called(1);
    });

    test('deactivates all three relays and calls stop() on each', () {
      final container = _container();
      final notifier = container.read(polarNotifierProvider.notifier);
      notifier.toggleH10Relay();
      notifier.toggleH10Relay();
      expect(container.read(polarNotifierProvider).h10RelayActive, isFalse);
      verify(() => mockHrRelay.stop()).called(1);
      verify(() => mockEcgRelay.stop()).called(1);
      verify(() => mockAccRelay.stop()).called(1);
    });
  });

  group('connection drop auto-stops all relays', () {
    test(
      'h10RelayActive cleared and all relays stopped on disconnected event',
      () async {
        final container = _container();
        final notifier = container.read(polarNotifierProvider.notifier);

        notifier.toggleH10Relay();
        expect(container.read(polarNotifierProvider).h10RelayActive, isTrue);

        connCtrl.add(PolarConnectionState.disconnected);
        await Future<void>.delayed(Duration.zero);

        final state = container.read(polarNotifierProvider);
        expect(state.h10RelayActive, isFalse);
        expect(state.latestBpm, isNull);

        verify(() => mockHrRelay.stop()).called(1);
        verify(() => mockEcgRelay.stop()).called(1);
        verify(() => mockAccRelay.stop()).called(1);
      },
    );
  });

  group('partial H10 relay success', () {
    test(
      'aggregate relay status stays ok when one stream errors but another is ok',
      () async {
        final container = _container();
        container.read(polarNotifierProvider.notifier).toggleH10Relay();

        hrStatusCtrl.add(RelayPushStatus.ok);
        ecgStatusCtrl.add(RelayPushStatus.error);
        await Future<void>.delayed(Duration.zero);

        final state = container.read(polarNotifierProvider);
        expect(state.h10RelayActive, isTrue);
        expect(state.hrRelayStatus, RelayPushStatus.ok);
        expect(state.ecgRelayStatus, RelayPushStatus.error);
        expect(state.h10RelayStatus, RelayPushStatus.ok);
      },
    );

    test(
      'aggregate relay status is error when no H10 stream is healthy',
      () async {
        final container = _container();
        container.read(polarNotifierProvider.notifier).toggleH10Relay();

        ecgStatusCtrl.add(RelayPushStatus.error);
        accStatusCtrl.add(RelayPushStatus.idle);
        hrStatusCtrl.add(RelayPushStatus.idle);
        await Future<void>.delayed(Duration.zero);

        final state = container.read(polarNotifierProvider);
        expect(state.h10RelayActive, isTrue);
        expect(state.h10RelayStatus, RelayPushStatus.error);
      },
    );
  });

  group('disconnect()', () {
    test('stops all relays and delegates to h10.disconnect()', () async {
      final container = _container();
      final notifier = container.read(polarNotifierProvider.notifier);

      notifier.toggleH10Relay();

      await notifier.disconnect();

      expect(container.read(polarNotifierProvider).h10RelayActive, isFalse);
      verify(() => mockHrRelay.stop()).called(1);
      verify(() => mockEcgRelay.stop()).called(1);
      verify(() => mockAccRelay.stop()).called(1);
      verify(() => mockH10.disconnect()).called(1);
    });
  });

  group('connectAndStartRelay()', () {
    test('starts relay immediately when already connected', () async {
      final container = _container();
      final notifier = container.read(polarNotifierProvider.notifier);

      connCtrl.add(PolarConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      await notifier.connectAndStartRelay();

      expect(container.read(polarNotifierProvider).h10RelayActive, isTrue);
      verify(() => mockHrRelay.start(any())).called(1);
      verify(() => mockEcgRelay.start(any())).called(1);
      verify(() => mockAccRelay.start(any())).called(1);
      verifyNever(() => mockH10.connect());
    });

    test(
      'does not double-start relay if already active and connected',
      () async {
        final container = _container();
        final notifier = container.read(polarNotifierProvider.notifier);

        connCtrl.add(PolarConnectionState.connected);
        await Future<void>.delayed(Duration.zero);

        await notifier.connectAndStartRelay();
        await notifier.connectAndStartRelay();

        verify(() => mockHrRelay.start(any())).called(1);
      },
    );

    test(
      'auto-starts relay when connected event arrives after pending connect',
      () async {
        final container = _container();
        final notifier = container.read(polarNotifierProvider.notifier);

        await notifier.connectAndStartRelay();
        verify(() => mockH10.connect()).called(1);
        expect(container.read(polarNotifierProvider).h10RelayActive, isFalse);

        connCtrl.add(PolarConnectionState.connected);
        await Future<void>.delayed(Duration.zero);

        expect(container.read(polarNotifierProvider).h10RelayActive, isTrue);
        verify(() => mockHrRelay.start(any())).called(1);
        verify(() => mockEcgRelay.start(any())).called(1);
        verify(() => mockAccRelay.start(any())).called(1);
      },
    );

    test(
      'pending flag cleared on disconnect — relay does not auto-start',
      () async {
        final container = _container();
        final notifier = container.read(polarNotifierProvider.notifier);

        await notifier.connectAndStartRelay();
        connCtrl.add(PolarConnectionState.disconnected);
        await Future<void>.delayed(Duration.zero);

        expect(container.read(polarNotifierProvider).h10RelayActive, isFalse);
        verifyNever(() => mockHrRelay.start(any()));
      },
    );
  });

  group('stopAll()', () {
    test('disconnects and stops all relays', () async {
      final container = _container();
      final notifier = container.read(polarNotifierProvider.notifier);

      notifier.toggleH10Relay();
      await notifier.stopAll();

      expect(container.read(polarNotifierProvider).h10RelayActive, isFalse);
      verify(() => mockH10.disconnect()).called(1);
    });

    test(
      'cancels pending auto-start so relay does not start after disconnect',
      () async {
        final container = _container();
        final notifier = container.read(polarNotifierProvider.notifier);

        await notifier.connectAndStartRelay();
        await notifier.stopAll();

        connCtrl.add(PolarConnectionState.connected);
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => mockHrRelay.start(any()));
      },
    );
  });
}
