import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/location/logic/relay_provider.dart';
import 'features/location/presentation/location_screen.dart';
import 'features/polar/h10/logic/polar_provider.dart';
import 'features/pulse/logic/pulse_provider.dart';
import 'services/polar_h10_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    final polar = ref.read(polarNotifierProvider);

    return _SuspendedSession(
      gpsRelayActive: relay.active,
      pulseRelayActive: pulse.active,
      h10ShouldReconnect:
          polar.connectionState == PolarConnectionState.connected ||
          polar.connectionState == PolarConnectionState.connecting ||
          polar.connectionState == PolarConnectionState.scanning,
      h10RelayActive: polar.h10RelayActive,
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
      return;
    }
    if (session.h10ShouldReconnect) {
      await ref.read(polarNotifierProvider.notifier).connect();
    }
  }

  Future<void> _stopAndResetSession() async {
    ref.read(relayNotifierProvider.notifier).stopIfActive();
    ref.read(pulseNotifierProvider.notifier).stopIfActive();
    await ref.read(polarNotifierProvider.notifier).stopAll();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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

  const _SuspendedSession({
    required this.gpsRelayActive,
    required this.pulseRelayActive,
    required this.h10ShouldReconnect,
    required this.h10RelayActive,
  });
}
