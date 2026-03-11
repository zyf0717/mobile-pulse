import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_pulse/features/polar/common/models/acc_data.dart';
import 'package:mobile_pulse/features/polar/common/models/hr_data.dart';
import 'package:mobile_pulse/features/polar/common/models/polar_connection_state.dart';
import 'package:mobile_pulse/features/polar/common/models/ppi_data.dart';
import 'package:mobile_pulse/features/polar/pacer/logic/pacer_provider.dart';
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
  late StreamController<String> errorCtrl;
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
    errorCtrl = StreamController<String>.broadcast();
    hrStatusCtrl = StreamController<RelayPushStatus>.broadcast();
    accStatusCtrl = StreamController<RelayPushStatus>.broadcast();
    ppiStatusCtrl = StreamController<RelayPushStatus>.broadcast();

    when(() => mockPacer.isConfigured).thenReturn(true);
    when(() => mockPacer.connectionState).thenAnswer((_) => connCtrl.stream);
    when(() => mockPacer.hrStream).thenAnswer((_) => hrCtrl.stream);
    when(() => mockPacer.accStream).thenAnswer((_) => accCtrl.stream);
    when(() => mockPacer.ppiStream).thenAnswer((_) => ppiCtrl.stream);
    when(() => mockPacer.errorStream).thenAnswer((_) => errorCtrl.stream);
    when(() => mockPacer.connect()).thenAnswer((_) async {});
    when(() => mockPacer.disconnect()).thenAnswer((_) async {});
    when(() => mockPacer.startRelayStreams()).thenAnswer((_) async {});
    when(() => mockPacer.stopRelayStreams()).thenAnswer((_) async {});
    when(() => mockPacer.dispose()).thenAnswer((_) {});

    for (final relay in [mockHrRelay, mockAccRelay, mockPpiRelay]) {
      when(() => relay.start(any())).thenAnswer((_) {});
      when(() => relay.stop()).thenAnswer((_) {});
      when(() => relay.dispose()).thenAnswer((_) {});
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
      errorCtrl.close(),
      hrStatusCtrl.close(),
      accStatusCtrl.close(),
      ppiStatusCtrl.close(),
    ]);
  });

  ProviderContainer container() {
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

  test('starts configured and disconnected', () {
    final state = container().read(pacerNotifierProvider);
    expect(state.isConfigured, isTrue);
    expect(state.connectionState, PolarConnectionState.disconnected);
    expect(state.pacerRelayActive, isFalse);
  });

  test('HR and PPI update latest bpm', () async {
    final c = container();
    c.read(pacerNotifierProvider);

    hrCtrl.add(HrData(bpm: 65, timestamp: DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(pacerNotifierProvider).latestBpm, 65);

    ppiCtrl.add(
      PpiData(
        timestamp: DateTime.now(),
        samples: const [
          PpiSample(
            ppiMs: 950,
            errorEstimateMs: 4,
            hr: 63,
            blockerBit: false,
            skinContactStatus: true,
            skinContactSupported: true,
            timestampNs: 1,
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(c.read(pacerNotifierProvider).latestBpm, 63);
  });

  test('ignores zero bpm updates from HR and PPI streams', () async {
    final c = container();
    c.read(pacerNotifierProvider);

    hrCtrl.add(HrData(bpm: 68, timestamp: DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(pacerNotifierProvider).latestBpm, 68);

    hrCtrl.add(HrData(bpm: 0, timestamp: DateTime.now()));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(pacerNotifierProvider).latestBpm, 68);

    ppiCtrl.add(
      PpiData(
        timestamp: DateTime.now(),
        samples: const [
          PpiSample(
            ppiMs: 950,
            errorEstimateMs: 4,
            hr: 0,
            blockerBit: false,
            skinContactStatus: true,
            skinContactSupported: true,
            timestampNs: 1,
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(c.read(pacerNotifierProvider).latestBpm, 68);
  });

  test('togglePacerRelay starts relay streams and all relays', () async {
    final c = container();

    await c.read(pacerNotifierProvider.notifier).togglePacerRelay();

    expect(c.read(pacerNotifierProvider).pacerRelayActive, isTrue);
    verify(() => mockPacer.startRelayStreams()).called(1);
    verify(() => mockHrRelay.start(any())).called(1);
    verify(() => mockAccRelay.start(any())).called(1);
    verify(() => mockPpiRelay.start(any())).called(1);
  });

  test('disconnect stops relay streams and disconnects service', () async {
    final c = container();
    final notifier = c.read(pacerNotifierProvider.notifier);

    await notifier.togglePacerRelay();
    await notifier.disconnect();

    expect(c.read(pacerNotifierProvider).pacerRelayActive, isFalse);
    verify(() => mockPacer.stopRelayStreams()).called(1);
    verify(() => mockPacer.disconnect()).called(1);
  });

  test(
    'native error updates lastError and transitions to error state',
    () async {
      final c = container();
      c.read(pacerNotifierProvider);

      errorCtrl.add('PPI stream failed');
      await Future<void>.delayed(Duration.zero);
      connCtrl.add(PolarConnectionState.error);
      await Future<void>.delayed(Duration.zero);

      final state = c.read(pacerNotifierProvider);
      expect(state.lastError, 'PPI stream failed');
      expect(state.connectionState, PolarConnectionState.error);
    },
  );
}
