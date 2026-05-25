import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/location/logic/relay_provider.dart';
import 'features/location/presentation/location_screen.dart';
import 'features/polar/h10/logic/polar_provider.dart';
import 'features/polar/pacer/logic/pacer_provider.dart';
import 'features/pulse/logic/pulse_provider.dart';
import 'features/polar/common/models/polar_connection_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterBluePlus.setLogLevel(LogLevel.warning, color: false);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: MobilePulseApp()));
}

class MobilePulseApp extends ConsumerStatefulWidget {
  const MobilePulseApp({super.key});

  @override
  ConsumerState<MobilePulseApp> createState() => _MobilePulseAppState();
}

class _MobilePulseAppState extends ConsumerState<MobilePulseApp>
    with WidgetsBindingObserver {
  Future<void> _lifecycleSync = Future.value();
  bool _isSuspended = false;
  _SuspendedSession? _suspendedSession;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queueResume();
      return;
    }

    _queueSuspend();
  }

  void _queueResume() {
    _lifecycleSync = _lifecycleSync.then((_) async {
      if (!_isSuspended) return;

      final session = _suspendedSession;
      _suspendedSession = null;
      _isSuspended = false;
      if (session != null) {
        await _restoreSession(session);
      }
    });
  }

  void _queueSuspend() {
    _lifecycleSync = _lifecycleSync.then((_) async {
      if (_isSuspended) return;

      _suspendedSession = _captureSession();
      _isSuspended = true;
      await _stopAndResetSession();
    });
  }

  _SuspendedSession _captureSession() {
    final relay = ref.read(relayNotifierProvider);
    final pulse = ref.read(pulseNotifierProvider);
    final h10 = ref.read(polarNotifierProvider);
    final pacer = ref.read(pacerNotifierProvider);

    return _SuspendedSession(
      gpsRelayActive: relay.active,
      pulseRelayActive: pulse.active,
      h10ShouldReconnect:
          h10.connectionState == PolarConnectionState.connected ||
          h10.connectionState == PolarConnectionState.connecting ||
          h10.connectionState == PolarConnectionState.scanning,
      h10RelayActive: h10.h10RelayActive,
      pacerShouldReconnect:
          pacer.connectionState == PolarConnectionState.connected ||
          pacer.connectionState == PolarConnectionState.connecting ||
          pacer.connectionState == PolarConnectionState.scanning,
      pacerRelayActive: pacer.pacerRelayActive,
    );
  }

  Future<void> _restoreSession(_SuspendedSession session) async {
    if (session.gpsRelayActive) {
      ref.read(relayNotifierProvider.notifier).startIfInactive();
    }
    if (session.pulseRelayActive) {
      ref.read(pulseNotifierProvider.notifier).startIfInactive();
    }
    if (session.h10RelayActive) {
      await ref.read(polarNotifierProvider.notifier).connectAndStartRelay();
    } else if (session.h10ShouldReconnect) {
      await ref.read(polarNotifierProvider.notifier).connect();
    }
    if (session.pacerRelayActive) {
      await ref.read(pacerNotifierProvider.notifier).connectAndStartRelay();
    } else if (session.pacerShouldReconnect) {
      await ref.read(pacerNotifierProvider.notifier).connect();
    }
  }

  Future<void> _stopAndResetSession() async {
    ref.read(relayNotifierProvider.notifier).stopIfActive();
    ref.read(pulseNotifierProvider.notifier).stopIfActive();
    await ref.read(polarNotifierProvider.notifier).stopAll();
    await ref.read(pacerNotifierProvider.notifier).stopAll();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Polar Streams',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const LocationScreen(),
    );
  }
}

class _SuspendedSession {
  final bool gpsRelayActive;
  final bool pulseRelayActive;
  final bool h10ShouldReconnect;
  final bool h10RelayActive;
  final bool pacerShouldReconnect;
  final bool pacerRelayActive;

  const _SuspendedSession({
    required this.gpsRelayActive,
    required this.pulseRelayActive,
    required this.h10ShouldReconnect,
    required this.h10RelayActive,
    required this.pacerShouldReconnect,
    required this.pacerRelayActive,
  });
}
