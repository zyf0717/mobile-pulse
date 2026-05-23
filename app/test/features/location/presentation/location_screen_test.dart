import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_pulse/features/location/logic/location_provider.dart';
import 'package:mobile_pulse/features/location/logic/relay_provider.dart';
import 'package:mobile_pulse/features/location/models/location_data.dart';
import 'package:mobile_pulse/features/location/presentation/location_screen.dart';
import 'package:mobile_pulse/features/polar/common/models/polar_connection_state.dart';
import 'package:mobile_pulse/features/polar/h10/logic/polar_provider.dart';
import 'package:mobile_pulse/features/polar/loop/logic/loop_provider.dart';
import 'package:mobile_pulse/features/polar/loop/logic/loop_service.dart';
import 'package:mobile_pulse/features/polar/loop/models/loop_models.dart';
import 'package:mobile_pulse/features/polar/pacer/logic/pacer_provider.dart';
import 'package:mobile_pulse/features/pulse/logic/pulse_provider.dart';

class MockPolarLoopService extends Mock implements PolarLoopService {}

class _TestRelayNotifier extends RelayNotifier {
  @override
  RelayState build() => const RelayState();

  @override
  void toggle() {}
}

class _TestPulseNotifier extends PulseNotifier {
  @override
  PulseState build() => const PulseState();

  @override
  void toggle() {}
}

class _TestPolarNotifier extends PolarNotifier {
  @override
  PolarState build() => const PolarState();

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}
}

class _TestPacerNotifier extends PacerNotifier {
  @override
  PacerState build() => const PacerState(isConfigured: false);

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPolarLoopService mockLoop;
  late StreamController<PolarConnectionState> connCtrl;
  late StreamController<PolarLoopError> errorCtrl;
  late StreamController<LoopDownloadProgress> progressCtrl;

  final location = LocationData(
    latitude: 1.3000,
    longitude: 103.8000,
    accuracy: 3,
    altitude: 12,
    speed: 0,
    timestamp: DateTime.utc(2026, 5, 24, 8, 30),
  );

  setUp(() {
    mockLoop = MockPolarLoopService();
    connCtrl = StreamController<PolarConnectionState>.broadcast();
    errorCtrl = StreamController<PolarLoopError>.broadcast();
    progressCtrl = StreamController<LoopDownloadProgress>.broadcast();

    when(() => mockLoop.isConfigured).thenReturn(false);
    when(() => mockLoop.connectionState).thenAnswer((_) => connCtrl.stream);
    when(() => mockLoop.errorStream).thenAnswer((_) => errorCtrl.stream);
    when(
      () => mockLoop.downloadProgressStream,
    ).thenAnswer((_) => progressCtrl.stream);
    when(() => mockLoop.dispose()).thenAnswer((_) {});
  });

  tearDown(() async {
    await Future.wait([
      connCtrl.close(),
      errorCtrl.close(),
      progressCtrl.close(),
    ]);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required bool showLoopDevEntry,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationStreamProvider.overrideWith((ref) => Stream.value(location)),
          relayNotifierProvider.overrideWith(_TestRelayNotifier.new),
          pulseNotifierProvider.overrideWith(_TestPulseNotifier.new),
          polarNotifierProvider.overrideWith(_TestPolarNotifier.new),
          pacerNotifierProvider.overrideWith(_TestPacerNotifier.new),
          polarLoopServiceProvider.overrideWithValue(mockLoop),
        ],
        child: MaterialApp(
          home: LocationScreen(showLoopDevEntry: showLoopDevEntry),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hides the Loop dev entry when disabled', (tester) async {
    await pumpScreen(tester, showLoopDevEntry: false);

    expect(find.byKey(const ValueKey('open-loop-dev-page')), findsNothing);
  });

  testWidgets('shows the Loop dev entry and opens the dev screen', (
    tester,
  ) async {
    await pumpScreen(tester, showLoopDevEntry: true);

    final button = find.byKey(const ValueKey('open-loop-dev-page'));
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Loop Dev'), findsOneWidget);
    expect(find.text('Capabilities & Settings'), findsOneWidget);
  });
}
