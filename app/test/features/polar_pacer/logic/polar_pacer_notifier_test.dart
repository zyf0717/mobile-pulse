import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_pulse/features/polar_pacer/logic/polar_pacer_provider.dart';
import 'package:mobile_pulse/features/polar_pacer/models/ppi_data.dart';
import 'package:mobile_pulse/features/polar/models/acc_data.dart';
import 'package:mobile_pulse/features/polar/models/hr_data.dart';
import 'package:mobile_pulse/services/polar_connection_state.dart';
import 'package:mobile_pulse/services/polar_pacer_service.dart';
import 'package:mobile_pulse/services/relay_push_service.dart';

class MockPolarPacerService extends Mock implements PolarPacerService {}

class MockRelayPushService extends Mock implements RelayPushService {}

void main() {
  late MockPolarPacerService mockPacer;
  late MockRelayPushService mockHrRelay;
  late MockRelayPushService mockAccRelay;
  late MockRelayPushService mockPpiRelay;

  late StreamController<PolarConnectionState> connCtrl;
  late StreamController<HrData> hrCtrl;
  late StreamController<AccData> accCtrl;
  late StreamController<PpiData> ppiCtrl;
  late StreamController<RelayPushStatus> hrStatusCtrl;
  late StreamController<RelayPushStatus> accStatusCtrl;
  late StreamController<RelayPushStatus> ppiStatusCtrl;

  setUpAll(() {
    registerFallbackValue(Stream<Map<String, dynamic>>.empty());
  });

  setUp(() {
    mockPacer = MockPolarPacerService();
    mockHrRelay = MockRelayPushService();
    mockAccRelay = MockRelayPushService();
    mockPpiRelay = MockRelayPushService();

    connCtrl = StreamController<PolarConnectionState>.broadcast();
    hrCtrl = StreamController<HrData>.broadcast();
    accCtrl = StreamController<AccData>.broadcast();
    ppiCtrl = StreamController<PpiData>.broadcast();
    hrStatusCtrl = StreamController<RelayPushStatus>.broadcast();
    accStatusCtrl = StreamController<RelayPushStatus>.broadcast();
    ppiStatusCtrl = StreamController<RelayPushStatus>.broadcast();

    when(() => mockPacer.connectionState).thenAnswer((_) => connCtrl.stream);
    when(() => mockPacer.hrStream).thenAnswer((_) => hrCtrl.stream);
    when(() => mockPacer.accStream).thenAnswer((_) => accCtrl.stream);
    when(() => mockPacer.ppiStream).thenAnswer((_) => ppiCtrl.stream);
    when(() => mockPacer.connect()).thenAnswer((_) async {});
    when(() => mockPacer.disconnect()).thenAnswer((_) async {});
    when(() => mockPacer.dispose()).thenAnswer((_) {});

    for (final r in [mockHrRelay, mockAccRelay, mockPpiRelay]) {
      when(() => r.start(any())).thenAnswer((_) {});
      when(() => r.stop()).thenAnswer((_) {});
      when(() => r.dispose()).thenAnswer((_) {});
    }
    when(() => mockHrRelay.statusStream).thenAnswer((_) => hrStatusCtrl.stream);
    when(
      () => mockAccRelay.statusStream,
    ).thenAnswer((_) => accStatusCtrl.stream);
    when(
      () => mockPpiRelay.statusStream,
    ).thenAnswer((_) => ppiStatusCtrl.stream);
  });

  tearDown(() async {
    await Future.wait([
      connCtrl.close(),
      hrCtrl.close(),
      accCtrl.close(),
      ppiCtrl.close(),
      hrStatusCtrl.close(),
      accStatusCtrl.close(),
      ppiStatusCtrl.close(),
    ]);
  });

  ProviderContainer container0() {
    final c = ProviderContainer(
      overrides: [
        polarPacerServiceProvider.overrideWithValue(mockPacer),
        pacerHrRelayPushServiceProvider.overrideWithValue(mockHrRelay),
        pacerAccRelayPushServiceProvider.overrideWithValue(mockAccRelay),
        pacerPpiRelayPushServiceProvider.overrideWithValue(mockPpiRelay),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('PolarPacerNotifier initial state', () {
    test('starts with disconnected / relay off', () {
      final container = container0();
      final state = container.read(polarPacerNotifierProvider);
      expect(state.connectionState, PolarConnectionState.disconnected);
      expect(state.latestBpm, isNull);
      expect(state.pacerRelayActive, isFalse);
    });
  });

  group('HR stream updates latestBpm', () {
    test('bpm is reflected in state after HR emission', () async {
      final container = container0();
      container.read(polarPacerNotifierProvider);

      hrCtrl.add(HrData(bpm: 58, timestamp: DateTime.now()));
      await Future<void>.delayed(Duration.zero);

      expect(container.read(polarPacerNotifierProvider).latestBpm, 58);
    });
  });

  group('togglePacerRelay', () {
    test('activates all three relays and marks pacerRelayActive = true', () {
      final container = container0();
      container.read(polarPacerNotifierProvider.notifier).togglePacerRelay();
      expect(
        container.read(polarPacerNotifierProvider).pacerRelayActive,
        isTrue,
      );
      verify(() => mockHrRelay.start(any())).called(1);
      verify(() => mockAccRelay.start(any())).called(1);
      verify(() => mockPpiRelay.start(any())).called(1);
    });

    test('deactivates all three relays and calls stop() on each', () {
      final container = container0();
      final notifier = container.read(polarPacerNotifierProvider.notifier);
      notifier.togglePacerRelay(); // on
      notifier.togglePacerRelay(); // off
      expect(
        container.read(polarPacerNotifierProvider).pacerRelayActive,
        isFalse,
      );
      verify(() => mockHrRelay.stop()).called(1);
      verify(() => mockAccRelay.stop()).called(1);
      verify(() => mockPpiRelay.stop()).called(1);
    });
  });

  group('connection drop auto-stops all relays', () {
    test(
      'pacerRelayActive cleared and all relays stopped on disconnected event',
      () async {
        final container = container0();
        final notifier = container.read(polarPacerNotifierProvider.notifier);

        notifier.togglePacerRelay();
        expect(
          container.read(polarPacerNotifierProvider).pacerRelayActive,
          isTrue,
        );

        connCtrl.add(PolarConnectionState.disconnected);
        await Future<void>.delayed(Duration.zero);

        final state = container.read(polarPacerNotifierProvider);
        expect(state.pacerRelayActive, isFalse);
        expect(state.latestBpm, isNull);

        verify(() => mockHrRelay.stop()).called(1);
        verify(() => mockAccRelay.stop()).called(1);
        verify(() => mockPpiRelay.stop()).called(1);
      },
    );
  });

  group('disconnect()', () {
    test('stops all relays and delegates to pacer.disconnect()', () async {
      final container = container0();
      final notifier = container.read(polarPacerNotifierProvider.notifier);

      notifier.togglePacerRelay();

      await notifier.disconnect();

      expect(
        container.read(polarPacerNotifierProvider).pacerRelayActive,
        isFalse,
      );
      verify(() => mockHrRelay.stop()).called(1);
      verify(() => mockAccRelay.stop()).called(1);
      verify(() => mockPpiRelay.stop()).called(1);
      verify(() => mockPacer.disconnect()).called(1);
    });
  });

  group('connectAndStartRelay()', () {
    test('starts relay immediately when already connected', () async {
      final container = container0();
      final notifier = container.read(polarPacerNotifierProvider.notifier);

      connCtrl.add(PolarConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      await notifier.connectAndStartRelay();

      expect(
        container.read(polarPacerNotifierProvider).pacerRelayActive,
        isTrue,
      );
      verify(() => mockHrRelay.start(any())).called(1);
      verify(() => mockAccRelay.start(any())).called(1);
      verify(() => mockPpiRelay.start(any())).called(1);
      verifyNever(() => mockPacer.connect());
    });

    test(
      'does not double-start relay if already active and connected',
      () async {
        final container = container0();
        final notifier = container.read(polarPacerNotifierProvider.notifier);

        connCtrl.add(PolarConnectionState.connected);
        await Future<void>.delayed(Duration.zero);

        await notifier.connectAndStartRelay(); // starts relay
        await notifier.connectAndStartRelay(); // should be a no-op

        verify(() => mockHrRelay.start(any())).called(1); // only once
      },
    );

    test(
      'auto-starts relay when connected event arrives after pending connect',
      () async {
        final container = container0();
        final notifier = container.read(polarPacerNotifierProvider.notifier);

        await notifier.connectAndStartRelay();
        verify(() => mockPacer.connect()).called(1);
        expect(
          container.read(polarPacerNotifierProvider).pacerRelayActive,
          isFalse,
        );

        connCtrl.add(PolarConnectionState.connected);
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(polarPacerNotifierProvider).pacerRelayActive,
          isTrue,
        );
        verify(() => mockHrRelay.start(any())).called(1);
        verify(() => mockAccRelay.start(any())).called(1);
        verify(() => mockPpiRelay.start(any())).called(1);
      },
    );

    test(
      'pending flag cleared on disconnect — relay does not auto-start',
      () async {
        final container = container0();
        final notifier = container.read(polarPacerNotifierProvider.notifier);

        await notifier.connectAndStartRelay(); // sets pending
        connCtrl.add(PolarConnectionState.disconnected);
        await Future<void>.delayed(Duration.zero);

        expect(
          container.read(polarPacerNotifierProvider).pacerRelayActive,
          isFalse,
        );
        verifyNever(() => mockHrRelay.start(any()));
      },
    );
  });

  group('stopAll()', () {
    test('disconnects and stops all relays', () async {
      final container = container0();
      final notifier = container.read(polarPacerNotifierProvider.notifier);

      notifier.togglePacerRelay();
      await notifier.stopAll();

      expect(
        container.read(polarPacerNotifierProvider).pacerRelayActive,
        isFalse,
      );
      verify(() => mockPacer.disconnect()).called(1);
    });

    test(
      'cancels pending auto-start so relay does not start after disconnect',
      () async {
        final container = container0();
        final notifier = container.read(polarPacerNotifierProvider.notifier);

        await notifier.connectAndStartRelay(); // pending = true
        await notifier.stopAll(); // should clear pending

        connCtrl.add(PolarConnectionState.connected);
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => mockHrRelay.start(any()));
      },
    );
  });
}
