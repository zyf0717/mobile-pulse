import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/polar_connection_state.dart';
import '../../../services/polar_pacer_service.dart';
import '../../../services/relay_push_service.dart';

class PolarPacerState {
  final PolarConnectionState connectionState;
  final int? latestBpm;
  final bool pacerRelayActive;
  final RelayPushStatus hrRelayStatus;
  final RelayPushStatus accRelayStatus;
  final RelayPushStatus ppiRelayStatus;

  const PolarPacerState({
    this.connectionState = PolarConnectionState.disconnected,
    this.latestBpm,
    this.pacerRelayActive = false,
    this.hrRelayStatus = RelayPushStatus.idle,
    this.accRelayStatus = RelayPushStatus.idle,
    this.ppiRelayStatus = RelayPushStatus.idle,
  });

  /// Aggregate relay status for the UI chip.
  RelayPushStatus get pacerRelayStatus {
    if (!pacerRelayActive) return RelayPushStatus.idle;
    if (hrRelayStatus == RelayPushStatus.error ||
        accRelayStatus == RelayPushStatus.error ||
        ppiRelayStatus == RelayPushStatus.error) {
      return RelayPushStatus.error;
    }
    if (hrRelayStatus == RelayPushStatus.ok &&
        accRelayStatus == RelayPushStatus.ok &&
        ppiRelayStatus == RelayPushStatus.ok) {
      return RelayPushStatus.ok;
    }
    return RelayPushStatus.idle;
  }

  PolarPacerState copyWith({
    PolarConnectionState? connectionState,
    int? latestBpm,
    bool? latestBpmSet,
    bool? pacerRelayActive,
    RelayPushStatus? hrRelayStatus,
    RelayPushStatus? accRelayStatus,
    RelayPushStatus? ppiRelayStatus,
  }) => PolarPacerState(
    connectionState: connectionState ?? this.connectionState,
    latestBpm: latestBpmSet == true ? null : (latestBpm ?? this.latestBpm),
    pacerRelayActive: pacerRelayActive ?? this.pacerRelayActive,
    hrRelayStatus: hrRelayStatus ?? this.hrRelayStatus,
    accRelayStatus: accRelayStatus ?? this.accRelayStatus,
    ppiRelayStatus: ppiRelayStatus ?? this.ppiRelayStatus,
  );
}

class PolarPacerNotifier extends Notifier<PolarPacerState> {
  bool _startAllPending = false;

  @override
  PolarPacerState build() {
    final pacer = ref.watch(polarPacerServiceProvider);
    final hrRelay = ref.watch(pacerHrRelayPushServiceProvider);
    final accRelay = ref.watch(pacerAccRelayPushServiceProvider);
    final ppiRelay = ref.watch(pacerPpiRelayPushServiceProvider);

    final connSub = pacer.connectionState.listen((s) {
      if (s == PolarConnectionState.disconnected ||
          s == PolarConnectionState.error) {
        _startAllPending = false;
        hrRelay.stop();
        accRelay.stop();
        ppiRelay.stop();
        state = state.copyWith(
          connectionState: s,
          latestBpmSet: true,
          pacerRelayActive: false,
          hrRelayStatus: RelayPushStatus.idle,
          accRelayStatus: RelayPushStatus.idle,
          ppiRelayStatus: RelayPushStatus.idle,
        );
      } else {
        state = state.copyWith(connectionState: s);
        if (s == PolarConnectionState.connected && _startAllPending) {
          _startAllPending = false;
          _startPacerRelay();
        }
      }
    });

    final hrSub = pacer.hrStream.listen(
      (hr) => state = state.copyWith(latestBpm: hr.bpm),
    );
    final hrRelaySub = hrRelay.statusStream.listen(
      (s) => state = state.copyWith(hrRelayStatus: s),
    );
    final accRelaySub = accRelay.statusStream.listen(
      (s) => state = state.copyWith(accRelayStatus: s),
    );
    final ppiRelaySub = ppiRelay.statusStream.listen(
      (s) => state = state.copyWith(ppiRelayStatus: s),
    );

    ref.onDispose(() {
      connSub.cancel();
      hrSub.cancel();
      hrRelaySub.cancel();
      accRelaySub.cancel();
      ppiRelaySub.cancel();
      pacer.dispose();
      hrRelay.dispose();
      accRelay.dispose();
      ppiRelay.dispose();
    });

    return const PolarPacerState();
  }

  Future<void> connect() => ref.read(polarPacerServiceProvider).connect();

  /// Connects and auto-starts the relay once the device is connected.
  Future<void> connectAndStartRelay() {
    if (state.connectionState == PolarConnectionState.connected) {
      if (!state.pacerRelayActive) _startPacerRelay();
      return Future.value();
    }
    _startAllPending = true;
    return ref.read(polarPacerServiceProvider).connect();
  }

  /// Stops the relay and disconnects.
  Future<void> stopAll() async {
    _startAllPending = false;
    await disconnect();
  }

  void _startPacerRelay() {
    final hrRelay = ref.read(pacerHrRelayPushServiceProvider);
    final accRelay = ref.read(pacerAccRelayPushServiceProvider);
    final ppiRelay = ref.read(pacerPpiRelayPushServiceProvider);
    final pacer = ref.read(polarPacerServiceProvider);
    hrRelay.start(pacer.hrStream.map((hr) => hr.toJson()));
    accRelay.start(pacer.accStream.map((acc) => acc.toJson()));
    ppiRelay.start(pacer.ppiStream.map((ppi) => ppi.toJson()));
    state = state.copyWith(pacerRelayActive: true);
  }

  Future<void> disconnect() async {
    ref.read(pacerHrRelayPushServiceProvider).stop();
    ref.read(pacerAccRelayPushServiceProvider).stop();
    ref.read(pacerPpiRelayPushServiceProvider).stop();
    state = state.copyWith(
      pacerRelayActive: false,
      hrRelayStatus: RelayPushStatus.idle,
      accRelayStatus: RelayPushStatus.idle,
      ppiRelayStatus: RelayPushStatus.idle,
    );
    await ref.read(polarPacerServiceProvider).disconnect();
  }

  void togglePacerRelay() {
    if (state.pacerRelayActive) {
      ref.read(pacerHrRelayPushServiceProvider).stop();
      ref.read(pacerAccRelayPushServiceProvider).stop();
      ref.read(pacerPpiRelayPushServiceProvider).stop();
      state = state.copyWith(
        pacerRelayActive: false,
        hrRelayStatus: RelayPushStatus.idle,
        accRelayStatus: RelayPushStatus.idle,
        ppiRelayStatus: RelayPushStatus.idle,
      );
    } else {
      _startPacerRelay();
    }
  }
}

final polarPacerServiceProvider = Provider<PolarPacerService>((ref) {
  const deviceId = String.fromEnvironment(
    'POLAR_PACER_DEVICE_ID',
    defaultValue: 'DA2E2324',
  );
  return PolarPacerService(deviceId: deviceId);
});

final pacerHrRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  const url = String.fromEnvironment('RELAY_PACER_HR_URL');
  return RelayPushService(relayUrl: url);
});

final pacerAccRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  const url = String.fromEnvironment('RELAY_PACER_ACC_URL');
  return RelayPushService(relayUrl: url);
});

final pacerPpiRelayPushServiceProvider = Provider<RelayPushService>((ref) {
  const url = String.fromEnvironment('RELAY_PACER_PPI_URL');
  return RelayPushService(relayUrl: url);
});

final polarPacerNotifierProvider =
    NotifierProvider<PolarPacerNotifier, PolarPacerState>(
      PolarPacerNotifier.new,
    );
